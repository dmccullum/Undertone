import AppKit
import DMKit
import SwiftUI

/// The About window's live gradient: an Organic recipe drawn by `RenderEngine`, the renderer the
/// canvas uses, at a third of the window's size and scaled up. Its color points swirl around the
/// pointer and drift toward it, and ease back to rest when it leaves. The backdrop and the palette
/// capsule share one instance.
///
/// Nothing renders on a loop: a pointer move sets a target, and one frame task eases the points
/// toward it at about 30 fps, rendering each step, then ends once they settle.
@Observable final class AboutGradient {
    /// Pixels the gradient renders across; the height follows the window's aspect.
    static let renderWidth = 132
    static let frameInterval = Duration.milliseconds(33)

    /// The palette at rest, laid out by `StudioModel.randomized`.
    private(set) var recipe: GradientRecipe
    private(set) var name: String
    private(set) var image: CGImage?
    /// Changes on every shuffle, so the backdrop crossfades to the new palette.
    private(set) var generation = 0
    /// Whether the window's text should be light, from the rest image under the text.
    private(set) var prefersDarkText = true
    /// Mean luminance (0...1, sRGB-weighted) of the rest image under the text.
    private(set) var luminance = 0.6

    private var size = CGSize.zero
    private var pointer: CGPoint?
    /// Each stop's position as drawn, easing toward its target.
    private var current: [CGPoint] = []
    /// Extra turn around the pointer that builds with pointer travel and unwinds when it stops.
    private var spin = 0.0
    private var lastPointer: CGPoint?
    private var frameTask: Task<Void, Never>?
    private var paletteIndex = 0

    init() {
        recipe = Self.restRecipe(GradientRecipe().stops.map(\.hex), randomized: false)
        name = "Dusk"
        current = recipe.stops.map { CGPoint(x: $0.x, y: $0.y) }
    }

    var hexes: [String] { recipe.stops.map(\.hex) }

    // MARK: Palettes

    /// The library's starter gradients first (Dusk, Tidal, Ember), then palettes built from the
    /// color tray's suggestions around a random hue and its complement.
    private static let starters: [(name: String, colors: [String])] = [
        ("Dusk", GradientRecipe().stops.map(\.hex)),
        ("Tidal", ["164E63", "67B8AC", "E8DFC7", "2B7A86"]),
        ("Ember", ["842D43", "E57E55", "F4D8AB", "B9504A"])
    ]

    static func generatedPalette() -> [String] {
        let hue = Double.random(in: 0..<1)
        func hex(hue: Double, saturation: Double, brightness: Double) -> String {
            let color = NSColor(hue: hue.truncatingRemainder(dividingBy: 1), saturation: saturation, brightness: brightness, alpha: 1)
            return Hex.string(from: Color(nsColor: color))
        }
        let base = hex(hue: hue, saturation: .random(in: 0.45...0.7), brightness: .random(in: 0.8...0.95))
        let complement = hex(hue: hue + .random(in: 0.42...0.58), saturation: .random(in: 0.35...0.6), brightness: .random(in: 0.45...0.7))
        let near = StudioModel.suggestedColors(near: base)
        let far = StudioModel.suggestedColors(near: complement)
        return [base, near[0], complement, far[3]]
    }

    static func restRecipe(_ colors: [String], randomized: Bool) -> GradientRecipe {
        var recipe = GradientRecipe()
        if colors != recipe.stops.map(\.hex) {
            recipe.stops = colors.enumerated().map { index, hex in
                let angle = Double(index) / Double(max(colors.count, 1)) * .pi * 2 + .pi / 4
                return ColorStop(hex: hex, x: 0.5 + cos(angle) * 0.34, y: 0.5 + sin(angle) * 0.34)
            }
        }
        if randomized {
            recipe = StudioModel.randomized(recipe)
            recipe.organicFlow = OrganicFlow.allCases.randomElement() ?? .still
        }
        // The window adds its own grain at screen resolution; see `AboutGrain`.
        recipe.textureEnabled = false
        return recipe
    }

    /// Moves to the next palette with a new layout and seed.
    func shuffle() {
        paletteIndex += 1
        let colors: [String]
        if paletteIndex < Self.starters.count {
            colors = Self.starters[paletteIndex].colors
            recipe = Self.restRecipe(colors, randomized: true)
            name = Self.starters[paletteIndex].name
        } else {
            colors = Self.generatedPalette()
            recipe = Self.restRecipe(colors, randomized: true)
            name = NameGenerator.name(for: recipe, seed: .random(in: 0...9_999))
        }
        spin = 0
        current = targets()
        generation += 1
        render(updatingLegibility: true)
    }

    // MARK: Pointer

    /// The backdrop's size in points; renders the first frame once it's known.
    func resize(to newSize: CGSize) {
        guard newSize.width > 1, newSize.height > 1, newSize != size else { return }
        size = newSize
        render(updatingLegibility: true)
    }

    /// The pointer over the window in points, or nil when it left. Under Reduce Motion it's ignored.
    func pointerMoved(to location: CGPoint?, reduceMotion: Bool) {
        let normalized = reduceMotion || size.width <= 0 ? nil : location.map {
            CGPoint(x: $0.x / size.width, y: $0.y / size.height)
        }
        if let normalized, let lastPointer {
            spin = min(2.4, spin + hypot(normalized.x - lastPointer.x, normalized.y - lastPointer.y) * 2.2)
        }
        lastPointer = normalized
        pointer = normalized
        startFrames()
    }

    func stop() {
        frameTask?.cancel()
        frameTask = nil
        pointer = nil
        lastPointer = nil
        spin = 0
        current = targets()
        render(updatingLegibility: false)
    }

    private func startFrames() {
        guard frameTask == nil else { return }
        frameTask = Task { [weak self] in
            while let self, !Task.isCancelled {
                let settled = self.step()
                self.render(updatingLegibility: false)
                if settled { break }
                try? await Task.sleep(for: Self.frameInterval)
            }
            self?.frameTask = nil
        }
    }

    /// Eases every point a step toward its target. True once they've all arrived.
    private func step() -> Bool {
        spin *= 0.9
        if spin < 0.002 { spin = 0 }
        let goals = targets()
        var settled = spin == 0
        for index in current.indices where index < goals.count {
            let dx = goals[index].x - current[index].x, dy = goals[index].y - current[index].y
            if abs(dx) < 0.0008 && abs(dy) < 0.0008 {
                current[index] = goals[index]
            } else {
                current[index].x += dx * 0.2
                current[index].y += dy * 0.2
                settled = false
            }
        }
        return settled
    }

    /// Where each point is headed: its rest position, turned around the pointer and drawn toward
    /// it by an amount that falls off with distance.
    private func targets() -> [CGPoint] {
        recipe.stops.map { stop in
            Self.displaced(CGPoint(x: stop.x, y: stop.y), around: pointer, spin: spin, aspect: size.width > 0 ? size.height / size.width : 1)
        }
    }

    static func displaced(_ rest: CGPoint, around pointer: CGPoint?, spin: Double, aspect: Double) -> CGPoint {
        guard let pointer else { return rest }
        let dx = rest.x - pointer.x, dy = (rest.y - pointer.y) * aspect
        let influence = exp(-(dx * dx + dy * dy) / 0.22)
        let angle = influence * (0.85 + spin)
        let reach = 1 - 0.38 * influence
        let turnedX = (dx * cos(angle) - dy * sin(angle)) * reach
        let turnedY = (dx * sin(angle) + dy * cos(angle)) * reach
        return CGPoint(x: pointer.x + turnedX, y: pointer.y + turnedY / aspect)
    }

    // MARK: Rendering

    private func render(updatingLegibility: Bool) {
        guard size.width > 1, size.height > 1 else { return }
        let width = Self.renderWidth
        let height = max(1, Int((Double(width) * size.height / size.width).rounded()))
        var frame = recipe
        frame.width = width
        frame.height = height
        for index in frame.stops.indices where index < current.count {
            frame.stops[index].x = current[index].x
            frame.stops[index].y = current[index].y
        }
        guard let rendered = try? RenderEngine.render(frame, width: width, height: height) else { return }
        image = rendered
        if updatingLegibility, let measured = Self.textLuminance(rendered) {
            luminance = measured
            prefersDarkText = measured > 0.5
        }
    }

    /// Mean luminance of the middle band below the icon, where the name, version and links sit.
    static func textLuminance(_ image: CGImage) -> Double? {
        guard let data = image.dataProvider?.data as Data?, image.bitsPerPixel == 32 else { return nil }
        let bytes = [UInt8](data)
        var total = 0.0, count = 0
        for row in (image.height / 5)..<image.height {
            for column in (image.width * 3 / 20)..<(image.width * 17 / 20) {
                let offset = row * image.bytesPerRow + column * 4
                total += (0.2126 * Double(bytes[offset]) + 0.7152 * Double(bytes[offset + 1]) + 0.0722 * Double(bytes[offset + 2])) / 255
                count += 1
            }
        }
        return count > 0 ? total / Double(count) : nil
    }
}

/// Fills the About window with the live gradient, film grain and a wash that keeps the text legible.
struct AboutGradientBackdrop: View {
    let gradient: AboutGradient
    @Environment(\.aboutPointerLocation) private var pointer
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                if let image = gradient.image {
                    Image(decorative: image, scale: 1)
                        .resizable()
                        .interpolation(.high)
                        .id(gradient.generation)
                        .transition(.opacity)
                }
                AboutGrain(size: proxy.size, scale: displayScale)
                wash
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .onAppear { gradient.resize(to: proxy.size) }
            .onChange(of: proxy.size) { _, size in gradient.resize(to: size) }
        }
        // The pointer comes from AboutView's content frame, which this backdrop covers.
        .onChange(of: pointer) { _, location in gradient.pointerMoved(to: location, reduceMotion: reduceMotion) }
        .onDisappear { gradient.stop() }
        // The window's text follows the gradient: dark text over a light palette, light over a dark one.
        .preferredColorScheme(gradient.prefersDarkText ? .light : .dark)
    }

    /// A flat, opaque-color wash toward white or black, just enough to bring the gradient under the
    /// text to a set luminance. Increase Contrast pushes it further.
    private var wash: some View {
        let strong = contrast == .increased
        let lum = gradient.luminance
        let opacity: Double
        if gradient.prefersDarkText {
            let target = strong ? 0.86 : 0.74
            opacity = min(0.6, max(0.1, (target - lum) / max(0.01, 1 - lum)))
        } else {
            let target = strong ? 0.16 : 0.28
            opacity = min(0.65, max(0.12, 1 - target / max(0.01, lum)))
        }
        return (gradient.prefersDarkText ? Color.white : Color.black)
            .opacity(opacity)
            .dmAnimation(.smooth, value: gradient.generation)
    }
}

/// Undertone's film grain at screen resolution: the renderer's per-cell hash, added to and taken
/// from the gradient the way the renderer adds it (`.plusLighter` for the bright half,
/// `.plusDarker` for the dark half). One 256-pixel tile, built once and repeated across the window.
struct AboutGrain: View {
    static let amount = 0.32 * 0.105
    static let tileSize = 256
    let size: CGSize
    let scale: CGFloat

    var body: some View {
        if let images = Self.images(width: Self.tileSize, height: Self.tileSize) {
            ZStack {
                Image(decorative: images.light, scale: scale)
                    .resizable(resizingMode: .tile)
                    .interpolation(.none)
                    .blendMode(.plusLighter)
                Image(decorative: images.dark, scale: scale)
                    .resizable(resizingMode: .tile)
                    .interpolation(.none)
                    .blendMode(.plusDarker)
            }
            .frame(width: size.width, height: size.height)
        }
    }

    @MainActor private static var cache: (width: Int, height: Int, light: CGImage, dark: CGImage)?

    static func images(width: Int, height: Int) -> (light: CGImage, dark: CGImage)? {
        guard width > 0, height > 0, width * height <= 4_000_000 else { return nil }
        if let cache, cache.width == width, cache.height == height { return (cache.light, cache.dark) }
        var light = [UInt8](repeating: 0, count: width * height)
        var dark = [UInt8](repeating: 255, count: width * height)
        for row in 0..<height {
            for column in 0..<width {
                let noise = GradientRenderer.hashNoise(x: column, y: row, seed: 0x00A8_0057) * amount
                if noise > 0 {
                    light[row * width + column] = GradientRenderer.byte(noise)
                } else {
                    dark[row * width + column] = GradientRenderer.byte(1 + noise)
                }
            }
        }
        guard let lightImage = grayImage(light, width: width, height: height),
              let darkImage = grayImage(dark, width: width, height: height) else { return nil }
        cache = (width, height, lightImage, darkImage)
        return (lightImage, darkImage)
    }

    private static func grayImage(_ bytes: [UInt8], width: Int, height: Int) -> CGImage? {
        guard let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
        return CGImage(
            width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: width,
            space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
        )
    }
}

/// The About window's signature: the backdrop's palette as swatches with its name. Clicking it
/// shuffles to the next palette, laid out fresh by Undertone's Randomize.
struct PaletteSignature: View {
    let gradient: AboutGradient
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    @State private var isHovering = false

    var body: some View {
        Button {
            withDMAnimation(.smooth) { gradient.shuffle() }
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        } label: {
            HStack(spacing: 10) {
                HStack(spacing: -5) {
                    ForEach(Array(gradient.hexes.enumerated()), id: \.offset) { _, hex in
                        ColorDot(hex: hex, size: 20)
                    }
                }
                Text(gradient.name)
                    .font(.callout.weight(.medium))
                    .contentTransition(.opacity)
                    .lineLimit(1)
                Image(systemName: "shuffle")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(isHovering ? .primary : .secondary)
            }
            .padding(.leading, 10)
            .padding(.trailing, 14)
            .padding(.vertical, 7)
            .background {
                Capsule()
                    .fill(Color(nsColor: .windowBackgroundColor).opacity(reduceTransparency ? 1 : (isHovering ? 0.82 : 0.66)))
                    .overlay { Capsule().strokeBorder(Color.primary.opacity(contrast.hairline(0.12)), lineWidth: 1) }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .dmAnimation(.snappy, value: isHovering)
        .help("Shuffle the palette")
        .accessibilityLabel("Shuffle Palette")
        .accessibilityValue("\(gradient.name): \(gradient.hexes.map { ColorNamer.family($0).baseName }.joined(separator: ", "))")
    }
}

#Preview("Palette signature") {
    let gradient = AboutGradient()
    ZStack {
        AboutGradientBackdrop(gradient: gradient)
        PaletteSignature(gradient: gradient)
    }
    .frame(width: 400, height: 300)
}
