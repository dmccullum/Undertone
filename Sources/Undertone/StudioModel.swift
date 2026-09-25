import AppKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor final class StudioModel: ObservableObject {
    private static let canvasWidthPreference = "canvasWidth"
    private static let canvasHeightPreference = "canvasHeight"
    private static let currentGradientPreference = "currentGradientID"
    static let maximumStops = 8

    @Published var recipe = GradientRecipe() {
        didSet { recipeDidChange(from: oldValue) }
    }
    @Published private(set) var gradients: [SavedGradient] = []
    @Published private(set) var currentGradientID: UUID?
    @Published var colorLibraries: [ColorLibrary] = [.coldwellBanker]
    @Published private(set) var preview: NSImage?
    @Published private(set) var previewVersion = 0
    @Published private(set) var styleThumbnails: [GradientMode: NSImage] = [:]
    @Published private(set) var isRendering = false
    @Published private(set) var toast: String?
    @Published private(set) var nameSuggestions: [String] = []
    @Published private(set) var isThinkingOfNames = false
    @Published var errorMessage: String?

    weak var undoManager: UndoManager?

    private let gradientsURL: URL
    private let legacyPalettesURL: URL
    private let colorLibrariesURL: URL
    private let legacyColorsURL: URL
    private var previewTask: Task<Void, Never>?
    private var saveTask: Task<Void, Never>?
    private var toastTask: Task<Void, Never>?
    private var undoBurstTask: Task<Void, Never>?
    private var intelligentNameTask: Task<Void, Never>?
    private var generation = 0
    private var suggestionSeed = 0
    private var isLoadingGradient = false
    private var isApplyingUndo = false
    private var undoBurstOpen = false
    private var animateNextPreview = false
    private var thumbnailCache: [UUID: (recipe: GradientRecipe, image: NSImage)] = [:]
    private var terminationObserver: NSObjectProtocol?

    init(directory: URL? = nil) {
        let directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Undertone", isDirectory: true)
        gradientsURL = directory.appendingPathComponent("gradients.json")
        legacyPalettesURL = directory.appendingPathComponent("palettes.json")
        colorLibrariesURL = directory.appendingPathComponent("color-libraries.json")
        legacyColorsURL = directory.appendingPathComponent("colors.json")
        do { try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true) }
        catch { errorMessage = "Could not open your library folder: \(error.localizedDescription)" }
        loadColorLibraries()
        loadGradients()
        let savedID = UserDefaults.standard.string(forKey: Self.currentGradientPreference).flatMap(UUID.init(uuidString:))
        let initial = gradients.first { $0.id == savedID } ?? gradients[0]
        currentGradientID = initial.id
        load(initial.recipe, animated: false)
        terminationObserver = NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.saveNow() }
        }
    }

    // MARK: - Gradient library

    var currentGradient: SavedGradient? { gradients.first { $0.id == currentGradientID } }
    var currentName: String { currentGradient?.name ?? NameGenerator.untitled }
    private var currentIndex: Int? { gradients.firstIndex { $0.id == currentGradientID } }

    private static var defaultCanvasSize: (width: Int, height: Int) {
        let width = UserDefaults.standard.integer(forKey: canvasWidthPreference)
        let height = UserDefaults.standard.integer(forKey: canvasHeightPreference)
        if (128...8192).contains(width), (128...8192).contains(height) { return (width, height) }
        return (2160, 2880)
    }

    private func loadGradients() {
        do {
            if FileManager.default.fileExists(atPath: gradientsURL.path) {
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                gradients = try decoder.decode([SavedGradient].self, from: Data(contentsOf: gradientsURL))
            } else if FileManager.default.fileExists(atPath: legacyPalettesURL.path) {
                let palettes = try JSONDecoder().decode([BrandPalette].self, from: Data(contentsOf: legacyPalettesURL))
                gradients = palettes.map { SavedGradient(name: $0.name, hasCustomName: true, recipe: Self.laidOutRecipe($0.colors)) }
                try persistGradients()
                try? FileManager.default.moveItem(at: legacyPalettesURL, to: legacyPalettesURL.deletingLastPathComponent().appendingPathComponent("palettes-migrated.json"))
            } else {
                gradients = Self.starterGradients()
                try persistGradients()
            }
        } catch { errorMessage = "Could not load your gradients: \(error.localizedDescription)" }
        if gradients.isEmpty { gradients = Self.starterGradients() }
    }

    /// Spreads colors evenly around the canvas, the layout older palettes used.
    static func laidOutRecipe(_ colors: [String]) -> GradientRecipe {
        var recipe = GradientRecipe()
        let size = defaultCanvasSize
        recipe.width = size.width
        recipe.height = size.height
        recipe.stops = colors.enumerated().map { index, hex in
            let angle = Double(index) / Double(max(colors.count, 1)) * .pi * 2
            return ColorStop(hex: hex, x: 0.5 + cos(angle) * 0.35, y: 0.5 + sin(angle) * 0.35)
        }
        return recipe
    }

    private static func starterGradients() -> [SavedGradient] {
        var dusk = GradientRecipe()
        let size = defaultCanvasSize
        dusk.width = size.width
        dusk.height = size.height
        var tidal = laidOutRecipe(["164E63", "67B8AC", "E8DFC7"])
        tidal.mode = .linear
        tidal.angleDegrees = 115
        var ember = laidOutRecipe(["842D43", "E57E55", "F4D8AB"])
        ember.mode = .aurora
        ember.angleDegrees = 70
        ember.seed = 7
        return [
            SavedGradient(name: "Dusk", hasCustomName: true, recipe: dusk),
            SavedGradient(name: "Tidal", hasCustomName: true, recipe: tidal),
            SavedGradient(name: "Ember", hasCustomName: true, recipe: ember)
        ]
    }

    private func persistGradients() throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(gradients).write(to: gradientsURL, options: .atomic)
    }

    /// Writes any pending edits immediately.
    func saveNow(confirm: Bool = false) {
        saveTask?.cancel()
        do {
            try persistGradients()
            if confirm { flash("Saved") }
        } catch { errorMessage = "Could not save your gradients: \(error.localizedDescription)" }
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 600_000_000)
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
    }

    func selectGradient(id: UUID?) {
        guard let id, id != currentGradientID, let gradient = gradients.first(where: { $0.id == id }) else { return }
        currentGradientID = id
        UserDefaults.standard.set(id.uuidString, forKey: Self.currentGradientPreference)
        nameSuggestions = []
        load(gradient.recipe, animated: true)
        undoManager?.removeAllActions()
    }

    private func load(_ recipe: GradientRecipe, animated: Bool) {
        isLoadingGradient = true
        animateNextPreview = animated
        if self.recipe == recipe { refreshPreview() } else { self.recipe = recipe }
        isLoadingGradient = false
    }

    private func insertAndSelect(_ gradient: SavedGradient) {
        gradients.insert(gradient, at: 0)
        saveNow()
        selectGradient(id: gradient.id)
    }

    /// Starts a fresh composition with the current colors, style and canvas size.
    @discardableResult func newGradient() -> UUID {
        var fresh = Self.randomized(recipe)
        fresh.seed = UInt64.random(in: 1...UInt64.max)
        let nameSeed = Int.random(in: 0...9_999)
        let gradient = SavedGradient(name: NameGenerator.name(for: fresh, seed: nameSeed), nameSeed: nameSeed, recipe: fresh)
        insertAndSelect(gradient)
        return gradient.id
    }

    @discardableResult func duplicateCurrentGradient() -> UUID? {
        guard let current = currentGradient else { return nil }
        let copy = SavedGradient(name: "\(current.name) Copy", hasCustomName: true, nameSeed: current.nameSeed, recipe: recipe)
        insertAndSelect(copy)
        return copy.id
    }

    func deleteGradient(id: UUID) {
        guard let index = gradients.firstIndex(where: { $0.id == id }) else { return }
        let wasCurrent = id == currentGradientID
        let removed = gradients[index]
        let name = removed.name
        gradients.remove(at: index)
        thumbnailCache[id] = nil
        if gradients.isEmpty {
            var blank = GradientRecipe()
            let size = Self.defaultCanvasSize
            blank.width = size.width
            blank.height = size.height
            gradients = [SavedGradient(name: NameGenerator.name(for: blank, seed: 0), recipe: blank)]
        }
        if wasCurrent {
            currentGradientID = nil
            selectGradient(id: gradients[min(index, gradients.count - 1)].id)
        }
        saveNow()
        undoManager?.registerUndo(withTarget: self) { model in
            MainActor.assumeIsolated { model.restoreDeletedGradient(removed, at: index) }
        }
        undoManager?.setActionName("Delete Gradient")
        flash("Deleted \(name)")
    }

    private func restoreDeletedGradient(_ gradient: SavedGradient, at index: Int) {
        gradients.insert(gradient, at: min(index, gradients.count))
        saveNow()
        selectGradient(id: gradient.id)
    }

    func renameCurrentGradient(_ name: String) {
        guard let id = currentGradientID else { return }
        renameGradient(id: id, to: name)
    }

    /// An empty name hands naming back to the generator.
    func renameGradient(id: UUID, to name: String) {
        guard let index = gradients.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            gradients[index].hasCustomName = false
            gradients[index].name = NameGenerator.name(for: gradients[index].recipe, seed: gradients[index].nameSeed)
        } else {
            gradients[index].name = String(trimmed.prefix(60))
            gradients[index].hasCustomName = true
        }
        intelligentNameTask?.cancel()
        scheduleSave()
    }

    /// Lets the name follow the colors again.
    func useAutomaticName() {
        renameCurrentGradient("")
        requestIntelligentName(after: 0)
    }

    private func updateCurrentGradient() {
        guard let index = currentIndex else { return }
        gradients[index].recipe = recipe
        gradients[index].modified = Date()
    }

    func thumbnail(for gradient: SavedGradient) -> NSImage? {
        if let cached = thumbnailCache[gradient.id], cached.recipe == gradient.recipe { return cached.image }
        var small = gradient.recipe
        small.grain = 0
        let scale = 120.0 / Double(max(1, max(small.width, small.height)))
        let width = max(1, Int(Double(small.width) * scale)), height = max(1, Int(Double(small.height) * scale))
        guard let image = try? GradientRenderer.render(small, width: width, height: height) else { return nil }
        let result = NSImage(cgImage: image, size: NSSize(width: width, height: height))
        thumbnailCache[gradient.id] = (gradient.recipe, result)
        return result
    }

    // MARK: - Editing, undo and autosave

    private func recipeDidChange(from old: GradientRecipe) {
        guard recipe != old else { return }
        if !isLoadingGradient {
            if !isApplyingUndo { registerUndo(returningTo: old) }
            updateCurrentGradient()
            scheduleSave()
            if old.stops.map(\.hex) != recipe.stops.map(\.hex) || old.mode != recipe.mode {
                refreshAutomaticName()
            }
        }
        refreshPreview()
    }

    /// One undo step per burst of edits, so a slider drag undoes in one go.
    private func registerUndo(returningTo old: GradientRecipe) {
        guard let undoManager else { return }
        if !undoBurstOpen {
            undoBurstOpen = true
            undoManager.registerUndo(withTarget: self) { model in
                MainActor.assumeIsolated { model.restore(old) }
            }
            undoManager.setActionName("Gradient Change")
        }
        undoBurstTask?.cancel()
        undoBurstTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 700_000_000)
            guard !Task.isCancelled else { return }
            self?.undoBurstOpen = false
        }
    }

    private func restore(_ target: GradientRecipe) {
        let current = recipe
        undoManager?.registerUndo(withTarget: self) { model in
            MainActor.assumeIsolated { model.restore(current) }
        }
        undoBurstOpen = false
        isApplyingUndo = true
        animateNextPreview = true
        recipe = target
        isApplyingUndo = false
    }

    // MARK: - Names

    var canUseIntelligence: Bool { NameIntelligence.isAvailable }

    private func refreshAutomaticName() {
        guard let index = currentIndex, !gradients[index].hasCustomName else { return }
        gradients[index].name = NameGenerator.name(for: recipe, seed: gradients[index].nameSeed)
        requestIntelligentName(after: 1_200_000_000)
    }

    /// While a gradient still has an automatic name, Apple Intelligence gets a chance to improve it.
    private func requestIntelligentName(after delay: UInt64) {
        intelligentNameTask?.cancel()
        guard NameIntelligence.isAvailable, let id = currentGradientID else { return }
        let colors = recipe.stops.map(\.hex)
        let brief = nameBrief()
        intelligentNameTask = Task { [weak self] in
            if delay > 0 { try? await Task.sleep(nanoseconds: delay) }
            guard !Task.isCancelled else { return }
            let names = await NameIntelligence.suggestions(for: brief)
            guard let self, !Task.isCancelled, let first = names.first,
                  let index = self.gradients.firstIndex(where: { $0.id == id }),
                  !self.gradients[index].hasCustomName,
                  self.gradients[index].recipe.stops.map(\.hex) == colors else { return }
            self.gradients[index].name = first
            self.scheduleSave()
        }
    }

    func suggestNames() {
        suggestionSeed += 5
        let seed = (currentGradient?.nameSeed ?? 0) + suggestionSeed
        nameSuggestions = NameGenerator.suggestions(for: recipe, startingAt: seed)
        guard NameIntelligence.isAvailable else { return }
        isThinkingOfNames = true
        let brief = nameBrief()
        Task { [weak self] in
            let names = await NameIntelligence.suggestions(for: brief)
            guard let self else { return }
            if !names.isEmpty { self.nameSuggestions = names }
            self.isThinkingOfNames = false
        }
    }

    /// A plain-language description of the gradient for the on-device model.
    func nameBrief() -> String {
        let stops = recipe.mode == .tonal ? Array(recipe.stops.prefix(1)) : recipe.stops
        let colors = stops.map { stop -> String in
            let description = ColorNamer.name(stop.hex).lowercased()
            if let named = libraryName(for: stop.hex) { return "\(named) (\(description))" }
            return description
        }
        let style: String
        switch recipe.mode {
        case .organic: style = "soft organic blend of drifting color fields"
        case .linear: style = "smooth linear fade"
        case .tonal: style = "tonal study built from lighter and deeper shades of one color"
        case .radial: style = "radial glow spreading from a bright center"
        case .aurora: style = "sweeping aurora ribbons"
        }
        let mood = NameGenerator.mood(for: stops.map(\.hex)).rawValue
        return """
            Colors, in order: \(colors.isEmpty ? "none yet" : colors.joined(separator: "; ")).
            Style: \(style).
            Overall mood: \(mood).
            Suggest five names.
            """
    }

    func libraryName(for hex: String) -> String? {
        for library in colorLibraries {
            if let match = library.colors.first(where: { $0.hex.caseInsensitiveCompare(hex) == .orderedSame }) { return match.name }
        }
        return nil
    }

    // MARK: - Color libraries

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
        } catch { errorMessage = "Could not load color collections: \(error.localizedDescription)" }
    }

    private func persistColorLibraries() throws {
        let custom = colorLibraries.filter { !$0.isBuiltIn }
        try JSONEncoder().encode(custom).write(to: colorLibrariesURL, options: .atomic)
    }

    @discardableResult func createColorLibrary(name: String, colors: [LibraryColor] = []) -> UUID? {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        let library = ColorLibrary(name: name, colors: colors)
        colorLibraries.append(library)
        do {
            try persistColorLibraries()
            flash("Created \(name)")
            return library.id
        } catch {
            colorLibraries.removeAll { $0.id == library.id }
            errorMessage = error.localizedDescription
            return nil
        }
    }

    /// Saves the gradient's colors as a collection, named after the gradient.
    @discardableResult func createColorLibraryFromCurrentColors() -> UUID? {
        guard !recipe.stops.isEmpty else { return nil }
        var seen: Set<String> = []
        let colors = recipe.stops.compactMap { stop -> LibraryColor? in
            guard seen.insert(stop.hex.uppercased()).inserted else { return nil }
            return LibraryColor(name: libraryName(for: stop.hex) ?? ColorNamer.name(stop.hex), hex: stop.hex.uppercased())
        }
        return createColorLibrary(name: currentName, colors: colors)
    }

    func deleteColorLibrary(id: UUID) {
        guard let library = colorLibraries.first(where: { $0.id == id }), !library.isBuiltIn else { return }
        colorLibraries.removeAll { $0.id == id }
        do { try persistColorLibraries(); flash("Deleted \(library.name)") }
        catch { errorMessage = error.localizedDescription }
    }

    func deleteLibraryColor(_ colorID: UUID, from libraryID: UUID) {
        guard let index = colorLibraries.firstIndex(where: { $0.id == libraryID }), !colorLibraries[index].isBuiltIn else { return }
        colorLibraries[index].colors.removeAll { $0.id == colorID }
        do { try persistColorLibraries() } catch { errorMessage = error.localizedDescription }
    }

    @discardableResult func saveColor(name: String, hex: String, libraryID: UUID? = nil) -> UUID? {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, let hex = Hex.normalized(hex) else { return nil }
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
            flash("Saved \(name) to \(colorLibraries[target].name)")
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
            !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && Hex.normalized($0.hex) != nil
        }) else { throw CocoaError(.fileReadCorruptFile) }
        let imported = ColorLibrary(name: name, colors: decoded.colors.map {
            LibraryColor(name: $0.name, hex: $0.hex.uppercased())
        })
        colorLibraries.append(imported)
        do { try persistColorLibraries() }
        catch { colorLibraries.removeAll { $0.id == imported.id }; throw error }
        flash("Imported \(imported.name)")
        return imported.id
    }

    func importColorLibraryFromPanel() -> UUID? {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.json]; panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        do { return try importColorLibrary(data: Data(contentsOf: url)) }
        catch { errorMessage = "Could not import that collection: \(error.localizedDescription)"; return nil }
    }

    func exportColorLibrary(id: UUID) {
        guard let library = colorLibraries.first(where: { $0.id == id }) else { return }
        let panel = NSSavePanel(); panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = Self.fileSafe(library.name) + ".undertone-colors.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try encodedColorLibrary(id: id).write(to: url, options: .atomic); flash("Exported \(library.name)") }
        catch { errorMessage = "Could not export that collection: \(error.localizedDescription)" }
    }

    // MARK: - Color stops

    func containsColor(hex: String) -> Bool {
        if recipe.mode == .tonal {
            return recipe.stops.first?.hex.caseInsensitiveCompare(hex) == .orderedSame
        }
        return recipe.stops.contains { $0.hex.caseInsensitiveCompare(hex) == .orderedSame }
    }

    var canAddStop: Bool { recipe.mode == .tonal ? recipe.stops.isEmpty : recipe.stops.count < Self.maximumStops }

    func toggleLibraryColor(_ color: LibraryColor) {
        if recipe.mode == .tonal {
            if recipe.stops.first?.hex.caseInsensitiveCompare(color.hex) == .orderedSame {
                recipe.stops.removeAll()
            } else {
                setBaseColor(hex: color.hex)
            }
            return
        }
        if let match = recipe.stops.first(where: { $0.hex.caseInsensitiveCompare(color.hex) == .orderedSame }) {
            recipe.stops.removeAll { $0.id == match.id }
        } else {
            guard recipe.stops.count < Self.maximumStops else {
                flash("A gradient can use up to eight colors")
                return
            }
            let positions: [(Double, Double)] = [(0.18, 0.18), (0.82, 0.20), (0.22, 0.80), (0.78, 0.82), (0.50, 0.15), (0.50, 0.85), (0.15, 0.50), (0.85, 0.50)]
            let position = positions[recipe.stops.count]
            recipe.stops.append(.init(hex: color.hex, x: position.0, y: position.1))
        }
    }

    func setBaseColor(hex: String) {
        if recipe.stops.isEmpty { recipe.stops = [.init(hex: hex, x: 0.5, y: 0.5)] }
        else { recipe.stops[0].hex = hex }
    }

    func addColor(hex: String) {
        if recipe.mode == .tonal { setBaseColor(hex: hex) }
        else if recipe.stops.count < Self.maximumStops {
            recipe.stops.append(.init(hex: hex, x: Double.random(in: 0.1...0.9), y: Double.random(in: 0.1...0.9)))
        }
    }

    func setColor(hex: String, for id: UUID) {
        guard let hex = Hex.normalized(hex), let index = recipe.stops.firstIndex(where: { $0.id == id }) else { return }
        recipe.stops[index].hex = hex
    }

    func removeColor(id: UUID) { recipe.stops.removeAll { $0.id == id } }

    func removeAllColors() { recipe.stops.removeAll() }

    /// Moves a color so it sits where `target` is now; order drives Linear, Glow and Aurora.
    func moveColor(id: UUID, to target: UUID) {
        guard id != target,
              let from = recipe.stops.firstIndex(where: { $0.id == id }),
              let to = recipe.stops.firstIndex(where: { $0.id == target }) else { return }
        var stops = recipe.stops
        let moving = stops.remove(at: from)
        stops.insert(moving, at: to)
        recipe.stops = stops
    }

    func suggestedColors() -> [String] {
        guard let color = recipe.stops.first?.nsColor.usingColorSpace(.sRGB) else {
            return ["F3AC91", "7655A3", "67B8AC", "E57E55"]
        }
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        return [-0.055, -0.025, 0.025, 0.055].enumerated().map { index, offset in
            let tone = NSColor(hue: (h + offset + 1).truncatingRemainder(dividingBy: 1), saturation: min(1, s * (index % 2 == 0 ? 0.72 : 0.92)), brightness: min(1, b * (index < 2 ? 1.13 : 0.86)), alpha: 1).usingColorSpace(.sRGB)!
            return String(format: "%02X%02X%02X", Int(tone.redComponent * 255), Int(tone.greenComponent * 255), Int(tone.blueComponent * 255))
        }
    }

    // MARK: - Style and canvas

    func setMode(_ mode: GradientMode) {
        guard mode != recipe.mode else { return }
        animateNextPreview = true
        recipe.mode = mode
    }

    func setCanvasSize(width: Int, height: Int) {
        guard (128...8192).contains(width), (128...8192).contains(height), width * height <= 33_554_432 else { return }
        UserDefaults.standard.set(width, forKey: Self.canvasWidthPreference)
        UserDefaults.standard.set(height, forKey: Self.canvasHeightPreference)
        animateNextPreview = true
        recipe.width = width
        recipe.height = height
    }

    func randomize() {
        animateNextPreview = true
        recipe = Self.randomized(recipe)
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
    }

    static func randomized(_ source: GradientRecipe) -> GradientRecipe {
        var recipe = source
        recipe.seed = UInt64.random(in: 1...UInt64.max)
        switch recipe.mode {
        case .organic:
            for index in recipe.stops.indices {
                recipe.stops[index].x = Double.random(in: 0.05...0.95)
                recipe.stops[index].y = Double.random(in: 0.05...0.95)
            }
        case .tonal:
            recipe.flow = Double.random(in: 0.25...0.95)
            recipe.softness = Double.random(in: 0.2...0.9)
            recipe.colorArc = Double.random(in: 0.2...0.95)
        case .linear, .aurora:
            recipe.angleDegrees = Double.random(in: 0...360)
            recipe.gradientPosition = Double.random(in: 0.35...0.65)
        case .radial:
            recipe.centerX = Double.random(in: -0.25...1.25)
            recipe.centerY = Double.random(in: -0.25...1.25)
        }
        return recipe
    }

    // MARK: - Rendering

    func refreshPreview() {
        generation += 1
        let token = generation
        let animated = animateNextPreview
        animateNextPreview = false
        previewTask?.cancel()
        let snapshot = recipe
        previewTask = Task {
            try? await Task.sleep(nanoseconds: animated ? 0 : 40_000_000)
            guard !Task.isCancelled else { return }
            let scale = 900.0 / Double(max(1, max(snapshot.width, snapshot.height)))
            let width = max(1, Int(Double(snapshot.width) * scale))
            let height = max(1, Int(Double(snapshot.height) * scale))
            do {
                let image = try await Task.detached(priority: .userInitiated) { try GradientRenderer.render(snapshot, width: width, height: height) }.value
                guard token == self.generation, !Task.isCancelled else { return }
                let rendered = NSImage(cgImage: image, size: NSSize(width: width, height: height))
                if animated {
                    withAnimation(.easeInOut(duration: 0.28)) { self.preview = rendered; self.previewVersion += 1 }
                } else {
                    self.preview = rendered
                    self.previewVersion += 1
                }
                let thumbnails = await Task.detached(priority: .utility) { Self.renderStyleThumbnails(for: snapshot) }.value
                guard token == self.generation, !Task.isCancelled else { return }
                self.styleThumbnails = thumbnails.mapValues { NSImage(cgImage: $0, size: NSSize(width: $0.width, height: $0.height)) }
            } catch { if token == self.generation { self.errorMessage = error.localizedDescription } }
        }
    }

    nonisolated private static func renderStyleThumbnails(for recipe: GradientRecipe) -> [GradientMode: CGImage] {
        var result: [GradientMode: CGImage] = [:]
        for mode in GradientMode.allCases {
            var variant = recipe
            variant.mode = mode
            variant.grain = 0
            if let image = try? GradientRenderer.render(variant, width: 120, height: 90) { result[mode] = image }
        }
        return result
    }

    // MARK: - Messages

    func flash(_ message: String) {
        toastTask?.cancel()
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { toast = message }
        toastTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_200_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.25)) { self?.toast = nil }
        }
    }

    // MARK: - Export

    static func fileSafe(_ name: String) -> String {
        let cleaned = name.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-").trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "Undertone" : cleaned
    }

    func exportFileName(extension ext: String) -> String {
        "\(Self.fileSafe(currentName)) \(recipe.width)x\(recipe.height).\(ext)"
    }

    private func renderExport(completion: @escaping (CGImage, GradientRecipe) throws -> Void) {
        guard !isRendering else { return }
        isRendering = true
        let snapshot = recipe
        Task {
            defer { isRendering = false }
            do {
                let image = try await Task.detached(priority: .userInitiated) { try GradientRenderer.render(snapshot, width: snapshot.width, height: snapshot.height) }.value
                try completion(image, snapshot)
            } catch { errorMessage = "Export failed: \(error.localizedDescription)" }
        }
    }

    nonisolated static func encoded(_ image: CGImage, jpeg: Bool = false) throws -> Data {
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
            self.flash("Copied \(self.recipe.width) × \(self.recipe.height) image")
        }
    }

    /// Synchronous PNG for Edit > Copy while the canvas has focus.
    func copyItemProvider() -> NSItemProvider? {
        guard let image = try? GradientRenderer.render(recipe, width: recipe.width, height: recipe.height),
              let data = try? Self.encoded(image) else { return nil }
        flash("Copied \(recipe.width) × \(recipe.height) image")
        return NSItemProvider(item: data as NSData, typeIdentifier: UTType.png.identifier)
    }

    /// Renders the full-size PNG only when the drop target asks for it.
    func dragItemProvider() -> NSItemProvider {
        let snapshot = recipe
        let fileName = exportFileName(extension: "png")
        let provider = NSItemProvider()
        provider.suggestedName = fileName
        provider.registerFileRepresentation(forTypeIdentifier: UTType.png.identifier, fileOptions: [], visibility: .all) { completion in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let image = try GradientRenderer.render(snapshot, width: snapshot.width, height: snapshot.height)
                    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
                    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                    let url = folder.appendingPathComponent(fileName)
                    try StudioModel.encoded(image).write(to: url, options: .atomic)
                    completion(url, false, nil)
                } catch {
                    completion(nil, false, error)
                }
            }
            return nil
        }
        return provider
    }

    func exportImage() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png, .jpeg]
        panel.nameFieldStringValue = exportFileName(extension: "png")
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        renderExport { image, _ in
            try Self.encoded(image, jpeg: ["jpg", "jpeg"].contains(url.pathExtension.lowercased())).write(to: url, options: .atomic)
            self.flash("Saved \(url.lastPathComponent)")
        }
    }

    func exportRecipe() {
        let panel = NSSavePanel(); panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = Self.fileSafe(currentName) + ".undertone.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(recipe).write(to: url, options: .atomic)
            flash("Exported \(url.lastPathComponent)")
        } catch { errorMessage = error.localizedDescription }
    }

    func importRecipe() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.json]; panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let recipe = try Self.validatedRecipe(from: Data(contentsOf: url))
            var name = url.lastPathComponent
            for suffix in [".json", ".undertone"] where name.lowercased().hasSuffix(suffix) { name = String(name.dropLast(suffix.count)) }
            insertAndSelect(SavedGradient(name: name.isEmpty ? NameGenerator.name(for: recipe, seed: 0) : name, hasCustomName: !name.isEmpty, recipe: recipe))
        } catch { errorMessage = "Could not open that recipe: \(error.localizedDescription)" }
    }

    static func validatedRecipe(from data: Data) throws -> GradientRecipe {
        let candidate = try JSONDecoder().decode(GradientRecipe.self, from: data)
        let unitValues = [candidate.flow, candidate.softness, candidate.grain, candidate.gradientPosition, candidate.easing, candidate.colorArc]
        guard (0...maximumStops).contains(candidate.stops.count),
              (1...8192).contains(candidate.width), (1...8192).contains(candidate.height),
              unitValues.allSatisfy({ $0.isFinite && (0...1).contains($0) }),
              candidate.angleDegrees.isFinite,
              candidate.centerX.isFinite, candidate.centerY.isFinite,
              (-1...2).contains(candidate.centerX), (-1...2).contains(candidate.centerY),
              candidate.fadeWidth.isFinite, (0.05...2).contains(candidate.fadeWidth),
              candidate.grainSize.isFinite, (0.25...10).contains(candidate.grainSize),
              candidate.stops.allSatisfy({ $0.x.isFinite && $0.y.isFinite && (0...1).contains($0.x) && (0...1).contains($0.y) && Hex.normalized($0.hex) != nil })
        else { throw CocoaError(.fileReadCorruptFile) }
        return candidate
    }
}
