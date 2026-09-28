import AppKit
import SwiftUI

struct ColorStop: Codable, Identifiable, Equatable, Sendable {
    var id = UUID()
    var hex: String
    var x: Double
    var y: Double
    /// How strongly this point pulls in the point-based styles (Organic, Mesh, Tonal). 1 is neutral.
    var weight: Double = 1.0
    var color: Color { Hex.color(hex) }
    var nsColor: NSColor { Hex.nsColor(hex) }

    enum CodingKeys: String, CodingKey { case id, hex, x, y, weight }

    init(id: UUID = UUID(), hex: String, x: Double, y: Double, weight: Double = 1.0) {
        self.id = id
        self.hex = hex
        self.x = x
        self.y = y
        self.weight = weight
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        hex = try container.decode(String.self, forKey: .hex)
        x = try container.decode(Double.self, forKey: .x)
        y = try container.decode(Double.self, forKey: .y)
        weight = try container.decodeIfPresent(Double.self, forKey: .weight) ?? 1.0
    }
}

enum GradientMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case organic
    case mesh
    case linear
    case tonal = "magicSingle"
    case radial
    case aurora

    var id: String { rawValue }
    var title: String {
        switch self {
        case .organic: "Organic"
        case .mesh: "Mesh"
        case .linear: "Linear"
        case .tonal: "Tonal"
        case .radial: "Glow"
        case .aurora: "Aurora"
        }
    }

    /// Magic Linear merged into Linear; retired styles fall back to Organic so old files still open.
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        if raw == "magicLinear" {
            self = .linear
        } else {
            self = GradientMode(rawValue: raw) ?? .organic
        }
    }
}

struct GradientRecipe: Codable, Equatable, Sendable {
    static let currentVersion = 3

    var stops: [ColorStop] = [.init(hex: "F3AC91", x: 0.18, y: 0.20), .init(hex: "7655A3", x: 0.78, y: 0.24), .init(hex: "F3CC91", x: 0.34, y: 0.82), .init(hex: "3B526E", x: 0.92, y: 0.85)]
    var mode: GradientMode = .organic
    var flow: Double = 0.55
    var softness: Double = 0.55
    /// Organic/Tonal: a vortex domain-warp that twirls the mesh. Its center and spin come from `seed`.
    var swirl: Double = 0
    var angleDegrees: Double = 0
    var gradientPosition: Double = 0.5
    var fadeWidth: Double = 1
    /// Linear runs the gradient from `start` to `end` (fractions of the canvas). Both points are
    /// draggable; the angle is whatever line they describe.
    var startX: Double = 0.0
    var startY: Double = 0.5
    var endX: Double = 1.0
    var endY: Double = 0.5
    /// Linear only: a rounded, kink-free blend through the colors instead of straight segments.
    /// On by default — Linear reads best smooth.
    var smoothBlend: Bool = true
    var easing: Double = 0.55
    var colorArc: Double = 0.35
    var centerX: Double = 0.5
    var centerY: Double = 0.5
    var textureEnabled: Bool = true
    var grain: Double = 0.20
    var grainSize: Double = 1.0
    var seed: UInt64 = 42
    var width: Int = 2160
    var height: Int = 2880
    var version: Int = GradientRecipe.currentVersion

    enum CodingKeys: String, CodingKey {
        case stops, mode, flow, softness, swirl, angleDegrees, gradientPosition, fadeWidth
        case startX, startY, endX, endY, smoothBlend
        case easing, colorArc, centerX, centerY, textureEnabled, grain, grainSize, seed, width, height, version
    }

    init(
        stops: [ColorStop] = [.init(hex: "F3AC91", x: 0.18, y: 0.20), .init(hex: "7655A3", x: 0.78, y: 0.24), .init(hex: "F3CC91", x: 0.34, y: 0.82), .init(hex: "3B526E", x: 0.92, y: 0.85)],
        mode: GradientMode = .organic,
        flow: Double = 0.55,
        softness: Double = 0.55,
        swirl: Double = 0,
        angleDegrees: Double = 0,
        gradientPosition: Double = 0.5,
        fadeWidth: Double = 1,
        startX: Double = 0.0,
        startY: Double = 0.5,
        endX: Double = 1.0,
        endY: Double = 0.5,
        smoothBlend: Bool = true,
        easing: Double = 0.55,
        colorArc: Double = 0.35,
        centerX: Double = 0.5,
        centerY: Double = 0.5,
        textureEnabled: Bool = true,
        grain: Double = 0.20,
        grainSize: Double = 1,
        seed: UInt64 = 42,
        width: Int = 2160,
        height: Int = 2880
    ) {
        self.stops = stops
        self.mode = mode
        self.flow = flow
        self.softness = softness
        self.swirl = swirl
        self.angleDegrees = angleDegrees
        self.gradientPosition = gradientPosition
        self.fadeWidth = fadeWidth
        self.startX = startX
        self.startY = startY
        self.endX = endX
        self.endY = endY
        self.smoothBlend = smoothBlend
        self.easing = easing
        self.colorArc = colorArc
        self.centerX = centerX
        self.centerY = centerY
        self.textureEnabled = textureEnabled
        self.grain = grain
        self.grainSize = grainSize
        self.seed = seed
        self.width = width
        self.height = height
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        stops = try values.decodeIfPresent([ColorStop].self, forKey: .stops) ?? stops
        mode = try values.decodeIfPresent(GradientMode.self, forKey: .mode) ?? mode
        flow = try values.decodeIfPresent(Double.self, forKey: .flow) ?? flow
        softness = try values.decodeIfPresent(Double.self, forKey: .softness) ?? softness
        swirl = try values.decodeIfPresent(Double.self, forKey: .swirl) ?? swirl
        angleDegrees = try values.decodeIfPresent(Double.self, forKey: .angleDegrees) ?? angleDegrees
        gradientPosition = try values.decodeIfPresent(Double.self, forKey: .gradientPosition) ?? gradientPosition
        fadeWidth = try values.decodeIfPresent(Double.self, forKey: .fadeWidth) ?? fadeWidth
        smoothBlend = try values.decodeIfPresent(Bool.self, forKey: .smoothBlend) ?? smoothBlend
        easing = try values.decodeIfPresent(Double.self, forKey: .easing) ?? easing
        colorArc = try values.decodeIfPresent(Double.self, forKey: .colorArc) ?? colorArc
        centerX = try values.decodeIfPresent(Double.self, forKey: .centerX) ?? centerX
        centerY = try values.decodeIfPresent(Double.self, forKey: .centerY) ?? centerY
        textureEnabled = try values.decodeIfPresent(Bool.self, forKey: .textureEnabled) ?? textureEnabled
        grain = try values.decodeIfPresent(Double.self, forKey: .grain) ?? grain
        grainSize = try values.decodeIfPresent(Double.self, forKey: .grainSize) ?? grainSize
        seed = try values.decodeIfPresent(UInt64.self, forKey: .seed) ?? seed
        width = try values.decodeIfPresent(Int.self, forKey: .width) ?? width
        height = try values.decodeIfPresent(Int.self, forKey: .height) ?? height
        let savedVersion = try values.decodeIfPresent(Int.self, forKey: .version) ?? 1
        // Before version 2, plain Linear had no color arc. Keep those files looking straight.
        if savedVersion < 2, try values.decodeIfPresent(String.self, forKey: .mode) == "linear" {
            colorArc = 0
        }
        // Version 3 moved Linear to draggable start/end points. Older files describe the line with
        // angle + position + fade width, so rebuild the endpoints from those to look identical.
        if let sx = try values.decodeIfPresent(Double.self, forKey: .startX),
           let sy = try values.decodeIfPresent(Double.self, forKey: .startY),
           let ex = try values.decodeIfPresent(Double.self, forKey: .endX),
           let ey = try values.decodeIfPresent(Double.self, forKey: .endY) {
            startX = sx; startY = sy; endX = ex; endY = ey
        } else {
            let radians = angleDegrees * .pi / 180
            let axisX = cos(radians), axisY = sin(radians)
            let near = gradientPosition - 0.5 * fadeWidth - 0.5
            let far = gradientPosition + 0.5 * fadeWidth - 0.5
            startX = 0.5 + near * axisX; startY = 0.5 + near * axisY
            endX = 0.5 + far * axisX; endY = 0.5 + far * axisY
        }
        version = Self.currentVersion
    }
}

/// A complete, named composition in the gradient library.
struct SavedGradient: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    /// False while the name is still generated from the colors.
    var hasCustomName = false
    var nameSeed = 0
    var recipe: GradientRecipe
    var modified = Date()
}

/// Legacy "gradient preset" format, which stored only colors. Read once for migration.
struct BrandPalette: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var colors: [String]
}

struct LibraryColor: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var hex: String

    /// Names are optional; fall back to the hex where a label is needed.
    var displayName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "#\(hex)" : name
    }

    static let coldwellBanker: [LibraryColor] = [
        .init(name: "Coldwell Banker Blue", hex: "012169"),
        .init(name: "Smoky Gray", hex: "58718D"),
        .init(name: "Mist", hex: "BECAD7"),
        .init(name: "Tide", hex: "B8CFEA"),
        .init(name: "Bright Blue", hex: "2068FF"),
        .init(name: "Midnight", hex: "0A1730"),
        .init(name: "Slate", hex: "1B3C55"),
        .init(name: "Glacier", hex: "DAE1E8"),
        .init(name: "Icy Blue", hex: "F0F5FB"),
        .init(name: "Celestial", hex: "418FDE"),
        .init(name: "Black", hex: "000000"),
        .init(name: "White", hex: "FFFFFF")
    ]
}

/// A named collection of named colors. Brand libraries and small palettes are both collections.
struct ColorLibrary: Codable, Identifiable, Equatable {
    static let coldwellBankerID = UUID(uuidString: "CB000001-0000-4000-8000-000000000001")!
    static let coldwellBanker = ColorLibrary(
        id: coldwellBankerID,
        name: "Coldwell Banker",
        colors: LibraryColor.coldwellBanker,
        isBuiltIn: false
    )

    var id = UUID()
    var name: String
    var colors: [LibraryColor]
    var isBuiltIn = false
}

enum CanvasPreset: String, CaseIterable, Identifiable {
    case instagram = "2160x2880"
    case uhd = "3840x2160"
    case desktop = "2560x1440"
    case square = "2048x2048"
    case story = "1440x2560"

    var id: String { rawValue }
    var size: (width: Int, height: Int) {
        switch self {
        case .instagram: (2160, 2880)
        case .uhd: (3840, 2160)
        case .desktop: (2560, 1440)
        case .square: (2048, 2048)
        case .story: (1440, 2560)
        }
    }
    var title: String {
        switch self {
        case .instagram: "Instagram · 2160 × 2880"
        case .uhd: "4K · 3840 × 2160"
        case .desktop: "Desktop · 2560 × 1440"
        case .square: "Square · 2048 × 2048"
        case .story: "Story · 1440 × 2560"
        }
    }
    static func matching(width: Int, height: Int) -> CanvasPreset? {
        allCases.first { $0.size.width == width && $0.size.height == height }
    }
}

enum Hex {
    /// Uppercased six-digit hex without "#", or nil when the input isn't a color.
    static func normalized(_ input: String) -> String? {
        let cleaned = input.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "#", with: "").uppercased()
        return cleaned.range(of: "^[0-9A-F]{6}$", options: .regularExpression) == nil ? nil : cleaned
    }

    static func components(_ hex: String) -> (red: Double, green: Double, blue: Double) {
        let value = UInt32(hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")), radix: 16) ?? 0
        return (Double((value >> 16) & 255) / 255, Double((value >> 8) & 255) / 255, Double(value & 255) / 255)
    }

    static func nsColor(_ hex: String) -> NSColor {
        let rgb = components(hex)
        return NSColor(srgbRed: rgb.red, green: rgb.green, blue: rgb.blue, alpha: 1)
    }

    static func color(_ hex: String) -> Color { Color(nsColor: nsColor(hex)) }

    static func string(from color: Color) -> String {
        let converted = NSColor(color).usingColorSpace(.sRGB) ?? .black
        return String(format: "%02X%02X%02X", Int((converted.redComponent * 255).rounded()), Int((converted.greenComponent * 255).rounded()), Int((converted.blueComponent * 255).rounded()))
    }

    /// Relative luminance, used to pick a legible checkmark over a swatch.
    static func luminance(_ hex: String) -> Double {
        let rgb = components(hex)
        return 0.2126 * rgb.red + 0.7152 * rgb.green + 0.0722 * rgb.blue
    }
}
