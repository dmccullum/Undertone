import AppKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor final class StudioModel: ObservableObject {
    @Published var recipe = GradientRecipe()
    @Published var palettes: [BrandPalette] = []
    @Published var colorLibraries: [ColorLibrary] = [.coldwellBanker]
    @Published var preview: NSImage?
    @Published var isRendering = false
    @Published var status = "Ready"
    @Published var errorMessage: String?
    private var previewTask: Task<Void, Never>?
    private var generation = 0
    private let libraryURL: URL
    private let colorLibrariesURL: URL
    private let legacyColorsURL: URL

    init(directory: URL? = nil) {
        let directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Undertone", isDirectory: true)
        libraryURL = directory.appendingPathComponent("palettes.json")
        colorLibrariesURL = directory.appendingPathComponent("color-libraries.json")
        legacyColorsURL = directory.appendingPathComponent("colors.json")
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: libraryURL.path) {
                palettes = try JSONDecoder().decode([BrandPalette].self, from: Data(contentsOf: libraryURL))
            } else {
                palettes = [.init(name: "Dusk", colors: ["F3AC91", "7655A3", "F3CC91", "3B526E"]), .init(name: "Tidal", colors: ["164E63", "67B8AC", "E8DFC7"]), .init(name: "Ember", colors: ["842D43", "E57E55", "F4D8AB"])]
            }
        } catch { errorMessage = "Could not load your palette library: \(error.localizedDescription)" }
        loadColorLibraries()
        refreshPreview()
    }

    private func loadColorLibraries() {
        do {
            if FileManager.default.fileExists(atPath: colorLibrariesURL.path) {
                let saved = try JSONDecoder().decode([ColorLibrary].self, from: Data(contentsOf: colorLibrariesURL))
                colorLibraries = [.coldwellBanker] + saved.map {
                    ColorLibrary(id: $0.id, name: $0.name, colors: $0.colors, isBuiltIn: false)
                }
            } else if FileManager.default.fileExists(atPath: legacyColorsURL.path) {
                let colors = try JSONDecoder().decode([LibraryColor].self, from: Data(contentsOf: legacyColorsURL))
                if !colors.isEmpty {
                    colorLibraries.append(.init(name: "My Colors", colors: colors))
                    try persistColorLibraries()
                }
            }
        } catch { errorMessage = "Could not load color libraries: \(error.localizedDescription)" }
    }

    private func persistColorLibraries() throws {
        let custom = colorLibraries.filter { !$0.isBuiltIn }
        try JSONEncoder().encode(custom).write(to: colorLibrariesURL, options: .atomic)
    }

    @discardableResult func createColorLibrary(name: String) -> UUID? {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        let library = ColorLibrary(name: name, colors: [])
        colorLibraries.append(library)
        do {
            try persistColorLibraries()
            status = "Created \(name)"
            return library.id
        } catch {
            colorLibraries.removeAll { $0.id == library.id }
            errorMessage = error.localizedDescription
            return nil
        }
    }

    @discardableResult func saveColor(name: String, hex: String, libraryID: UUID? = nil) -> UUID? {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let hex = hex.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "#", with: "").uppercased()
        guard !name.isEmpty, hex.range(of: "^[0-9A-F]{6}$", options: .regularExpression) != nil else { return nil }
        var target = colorLibraries.firstIndex { $0.id == libraryID && !$0.isBuiltIn }
        if target == nil {
            target = colorLibraries.firstIndex { $0.name == "My Colors" && !$0.isBuiltIn }
        }
        if target == nil {
            colorLibraries.append(.init(name: "My Colors", colors: []))
            target = colorLibraries.indices.last
        }
        guard let target else { return nil }
        colorLibraries[target].colors.append(.init(name: name, hex: hex))
        do {
            try persistColorLibraries()
            status = "Saved \(name) to \(colorLibraries[target].name)"
            return colorLibraries[target].id
        } catch {
            colorLibraries[target].colors.removeLast()
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func encodedColorLibrary(id: UUID) throws -> Data {
        guard let library = colorLibraries.first(where: { $0.id == id }) else { throw CocoaError(.fileNoSuchFile) }
        let exported = ColorLibrary(id: library.id, name: library.name, colors: library.colors, isBuiltIn: false)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(exported)
    }

    @discardableResult func importColorLibrary(data: Data) throws -> UUID {
        let decoder = JSONDecoder()
        let decoded: ColorLibrary
        if let library = try? decoder.decode(ColorLibrary.self, from: data) {
            decoded = library
        } else if let colors = try? decoder.decode([LibraryColor].self, from: data) {
            decoded = .init(name: "Imported Colors", colors: colors)
        } else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let name = decoded.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, decoded.colors.allSatisfy({
            !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            $0.hex.range(of: "^[0-9A-Fa-f]{6}$", options: .regularExpression) != nil
        }) else { throw CocoaError(.fileReadCorruptFile) }
        let imported = ColorLibrary(name: name, colors: decoded.colors.map {
            LibraryColor(name: $0.name, hex: $0.hex.uppercased())
        })
        colorLibraries.append(imported)
        do { try persistColorLibraries() }
        catch { colorLibraries.removeAll { $0.id == imported.id }; throw error }
        status = "Imported \(imported.name)"
        return imported.id
    }

    func importColorLibraryFromPanel() -> UUID? {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.json]; panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        do { return try importColorLibrary(data: Data(contentsOf: url)) }
        catch { errorMessage = "Could not import color library: \(error.localizedDescription)"; return nil }
    }

    func exportColorLibrary(id: UUID) {
        guard let library = colorLibraries.first(where: { $0.id == id }) else { return }
        let panel = NSSavePanel(); panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = library.name.replacingOccurrences(of: "/", with: "-") + ".undertone-colors.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try encodedColorLibrary(id: id).write(to: url, options: .atomic); status = "Exported \(library.name)" }
        catch { errorMessage = "Could not export color library: \(error.localizedDescription)" }
    }

    func containsColor(hex: String) -> Bool {
        if recipe.mode == .magicSingle {
            return recipe.stops.first?.hex.caseInsensitiveCompare(hex) == .orderedSame
        }
        return recipe.stops.contains { $0.hex.caseInsensitiveCompare(hex) == .orderedSame }
    }

    func toggleLibraryColor(_ color: LibraryColor) {
        if recipe.mode == .magicSingle {
            setBaseColor(hex: color.hex)
            status = "Using \(color.name) as the base color"
            return
        }
        if let match = recipe.stops.first(where: { $0.hex.caseInsensitiveCompare(color.hex) == .orderedSame }) {
            guard recipe.stops.count > 2 else {
                status = "A gradient needs at least two colors"
                return
            }
            recipe.stops.removeAll { $0.id == match.id }
            status = "Removed \(color.name)"
        } else {
            guard recipe.stops.count < 8 else {
                status = "A gradient can use up to eight colors"
                return
            }
            let positions: [(Double, Double)] = [(0.18, 0.18), (0.82, 0.20), (0.22, 0.80), (0.78, 0.82), (0.50, 0.15), (0.50, 0.85), (0.15, 0.50), (0.85, 0.50)]
            let position = positions[recipe.stops.count]
            recipe.stops.append(.init(hex: color.hex, x: position.0, y: position.1))
            status = "Added \(color.name)"
        }
    }

    func refreshPreview() {
        generation += 1
        let token = generation
        previewTask?.cancel()
        let snapshot = recipe
        previewTask = Task {
            try? await Task.sleep(nanoseconds: 90_000_000)
            guard !Task.isCancelled else { return }
            let scale = 900.0 / Double(max(1, max(snapshot.width, snapshot.height)))
            let width = max(1, Int(Double(snapshot.width) * scale))
            let height = max(1, Int(Double(snapshot.height) * scale))
            do {
                let image = try await Task.detached(priority: .userInitiated) { try GradientRenderer.render(snapshot, width: width, height: height) }.value
                guard token == self.generation, !Task.isCancelled else { return }
                self.preview = NSImage(cgImage: image, size: NSSize(width: width, height: height))
            } catch { if token == self.generation { self.errorMessage = error.localizedDescription } }
        }
    }

    func randomize() {
        recipe.seed = UInt64.random(in: 1...UInt64.max)
        switch recipe.mode {
        case .organic, .magicSingle:
            for index in recipe.stops.indices {
                recipe.stops[index].x = Double.random(in: 0.05...0.95)
                recipe.stops[index].y = Double.random(in: 0.05...0.95)
            }
        case .linear, .magicLinear, .aurora:
            recipe.angleDegrees = Double.random(in: 0...360)
            recipe.gradientPosition = Double.random(in: 0.35...0.65)
        case .radial:
            recipe.centerX = Double.random(in: 0.15...0.85)
            recipe.centerY = Double.random(in: 0.15...0.85)
        }
    }
    func savePalette(name: String) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        palettes.append(.init(name: name, colors: recipe.stops.map(\.hex)))
        do { try JSONEncoder().encode(palettes).write(to: libraryURL, options: .atomic); status = "Palette saved" }
        catch { errorMessage = error.localizedDescription }
    }
    func applyPalette(_ palette: BrandPalette) {
        recipe.stops = palette.colors.enumerated().map { index, hex in
            let angle = Double(index) / Double(palette.colors.count) * .pi * 2
            return ColorStop(hex: hex, x: 0.5 + cos(angle) * 0.35, y: 0.5 + sin(angle) * 0.35)
        }
    }
    func suggestedColors() -> [String] {
        guard let color = recipe.stops.first?.nsColor.usingColorSpace(.sRGB) else { return [] }
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        return [-0.055, -0.025, 0.025, 0.055].enumerated().map { index, offset in
            let tone = NSColor(hue: (h + offset + 1).truncatingRemainder(dividingBy: 1), saturation: min(1, s * (index % 2 == 0 ? 0.72 : 0.92)), brightness: min(1, b * (index < 2 ? 1.13 : 0.86)), alpha: 1).usingColorSpace(.sRGB)!
            return String(format: "%02X%02X%02X", Int(tone.redComponent * 255), Int(tone.greenComponent * 255), Int(tone.blueComponent * 255))
        }
    }
    func setBaseColor(hex: String) {
        if recipe.stops.isEmpty { recipe.stops = [.init(hex: hex, x: 0.5, y: 0.5)] }
        else { recipe.stops[0].hex = hex }
    }
    func addColor(hex: String) {
        if recipe.mode == .magicSingle { setBaseColor(hex: hex) }
        else if recipe.stops.count < 8 { recipe.stops.append(.init(hex: hex, x: Double.random(in: 0.1...0.9), y: Double.random(in: 0.1...0.9))) }
    }
    func removeColor(id: UUID) { if recipe.stops.count > 2 { recipe.stops.removeAll { $0.id == id } } }

    private func renderExport(completion: @escaping (CGImage, GradientRecipe) throws -> Void) {
        guard !isRendering else { return }
        isRendering = true; status = "Rendering full resolution…"
        let snapshot = recipe
        Task {
            defer { isRendering = false }
            do {
                let image = try await Task.detached(priority: .userInitiated) { try GradientRenderer.render(snapshot, width: snapshot.width, height: snapshot.height) }.value
                try completion(image, snapshot)
            } catch { status = "Export failed"; errorMessage = error.localizedDescription }
        }
    }
    static func encoded(_ image: CGImage, jpeg: Bool = false) throws -> Data {
        let bitmap = NSBitmapImageRep(cgImage: image)
        guard let data = bitmap.representation(using: jpeg ? .jpeg : .png, properties: jpeg ? [.compressionFactor: 0.95] : [:]) else { throw CocoaError(.fileWriteUnknown) }
        return data
    }
    func copyImage() {
        renderExport { image, _ in
            let item = NSPasteboardItem()
            item.setData(try Self.encoded(image), forType: .png)
            if let tiff = NSBitmapImageRep(cgImage: image).tiffRepresentation { item.setData(tiff, forType: .tiff) }
            NSPasteboard.general.clearContents()
            guard NSPasteboard.general.writeObjects([item]) else { throw CocoaError(.fileWriteUnknown) }
            self.status = "Full-resolution image copied"
        }
    }
    func exportImage() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png, .jpeg]; panel.nameFieldStringValue = "Undertone.png"
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        renderExport { image, _ in
            try Self.encoded(image, jpeg: ["jpg", "jpeg"].contains(url.pathExtension.lowercased())).write(to: url, options: .atomic)
            self.status = "Saved \(url.lastPathComponent)"
        }
    }
    func saveRecipe() {
        let panel = NSSavePanel(); panel.allowedContentTypes = [.json]; panel.nameFieldStringValue = "Untitled.undertone.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; try encoder.encode(recipe).write(to: url, options: .atomic); status = "Composition saved" }
        catch { errorMessage = error.localizedDescription }
    }
    func openRecipe() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.json]; panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let candidate = try JSONDecoder().decode(GradientRecipe.self, from: Data(contentsOf: url))
            let validStopCount = candidate.mode == .magicSingle
                ? (1...8).contains(candidate.stops.count)
                : (2...8).contains(candidate.stops.count)
            let unitValues = [candidate.flow, candidate.softness, candidate.grain, candidate.gradientPosition, candidate.easing, candidate.colorArc, candidate.centerX, candidate.centerY]
            guard validStopCount,
                  (1...8192).contains(candidate.width), (1...8192).contains(candidate.height),
                  unitValues.allSatisfy({ $0.isFinite && (0...1).contains($0) }),
                  candidate.angleDegrees.isFinite,
                  candidate.fadeWidth.isFinite, (0.05...2).contains(candidate.fadeWidth),
                  candidate.grainSize.isFinite, (0.25...10).contains(candidate.grainSize),
                  candidate.stops.allSatisfy({ $0.x.isFinite && $0.y.isFinite && (0...1).contains($0.x) && (0...1).contains($0.y) && $0.hex.range(of: "^[0-9A-Fa-f]{6}$", options: .regularExpression) != nil })
            else { throw CocoaError(.fileReadCorruptFile) }
            recipe = candidate; status = "Composition opened"
        } catch { errorMessage = "Could not open composition: \(error.localizedDescription)" }
    }
}
