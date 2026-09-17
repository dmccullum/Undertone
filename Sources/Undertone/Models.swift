import AppKit
import SwiftUI

struct ColorStop: Codable, Identifiable, Equatable, Sendable {
    var id = UUID()
    var hex: String
    var x: Double
    var y: Double
    var color: Color { Color(nsColor: nsColor) }
    var nsColor: NSColor {
        let value = UInt32(hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")), radix: 16) ?? 0
        return NSColor(srgbRed: Double((value >> 16) & 255) / 255, green: Double((value >> 8) & 255) / 255, blue: Double(value & 255) / 255, alpha: 1)
    }
}

enum GradientMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case organic
    case linear
    case magicLinear
    case magicSingle
    case radial
    case aurora

    var id: String { rawValue }
    var title: String {
        switch self {
        case .organic: "Organic"
        case .linear: "Linear"
        case .magicLinear: "Magic Linear"
        case .magicSingle: "Magic Single"
        case .radial: "Radial Glow"
        case .aurora: "Aurora"
        }
    }
}

struct GradientRecipe: Codable, Equatable, Sendable {
    var stops: [ColorStop] = [.init(hex: "F3AC91", x: 0.18, y: 0.20), .init(hex: "7655A3", x: 0.78, y: 0.24), .init(hex: "F3CC91", x: 0.34, y: 0.82), .init(hex: "3B526E", x: 0.92, y: 0.85)]
    var mode: GradientMode = .organic
    var flow: Double = 0.55
    var softness: Double = 0.55
    var angleDegrees: Double = 0
    var gradientPosition: Double = 0.5
    var fadeWidth: Double = 1
    var easing: Double = 0.55
    var colorArc: Double = 0.35
    var centerX: Double = 0.5
    var centerY: Double = 0.5
    var grain: Double = 0.20
    var grainSize: Double = 1.0
    var seed: UInt64 = 42
    var width: Int = 2160
    var height: Int = 2880

    enum CodingKeys: String, CodingKey {
        case stops, mode, flow, softness, angleDegrees, gradientPosition, fadeWidth
        case easing, colorArc, centerX, centerY, grain, grainSize, seed, width, height
    }

    init(
        stops: [ColorStop] = [.init(hex: "F3AC91", x: 0.18, y: 0.20), .init(hex: "7655A3", x: 0.78, y: 0.24), .init(hex: "F3CC91", x: 0.34, y: 0.82), .init(hex: "3B526E", x: 0.92, y: 0.85)],
        mode: GradientMode = .organic,
        flow: Double = 0.55,
        softness: Double = 0.55,
        angleDegrees: Double = 0,
        gradientPosition: Double = 0.5,
        fadeWidth: Double = 1,
        easing: Double = 0.55,
        colorArc: Double = 0.35,
        centerX: Double = 0.5,
        centerY: Double = 0.5,
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
        self.angleDegrees = angleDegrees
        self.gradientPosition = gradientPosition
        self.fadeWidth = fadeWidth
        self.easing = easing
        self.colorArc = colorArc
        self.centerX = centerX
        self.centerY = centerY
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
        angleDegrees = try values.decodeIfPresent(Double.self, forKey: .angleDegrees) ?? angleDegrees
        gradientPosition = try values.decodeIfPresent(Double.self, forKey: .gradientPosition) ?? gradientPosition
        fadeWidth = try values.decodeIfPresent(Double.self, forKey: .fadeWidth) ?? fadeWidth
        easing = try values.decodeIfPresent(Double.self, forKey: .easing) ?? easing
        colorArc = try values.decodeIfPresent(Double.self, forKey: .colorArc) ?? colorArc
        centerX = try values.decodeIfPresent(Double.self, forKey: .centerX) ?? centerX
        centerY = try values.decodeIfPresent(Double.self, forKey: .centerY) ?? centerY
        grain = try values.decodeIfPresent(Double.self, forKey: .grain) ?? grain
        grainSize = try values.decodeIfPresent(Double.self, forKey: .grainSize) ?? grainSize
        seed = try values.decodeIfPresent(UInt64.self, forKey: .seed) ?? seed
        width = try values.decodeIfPresent(Int.self, forKey: .width) ?? width
        height = try values.decodeIfPresent(Int.self, forKey: .height) ?? height
    }
}
struct BrandPalette: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var colors: [String]
}

struct LibraryColor: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var hex: String

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

struct ColorLibrary: Codable, Identifiable, Equatable {
    static let coldwellBankerID = UUID(uuidString: "CB000001-0000-4000-8000-000000000001")!
    static let coldwellBanker = ColorLibrary(
        id: coldwellBankerID,
        name: "Coldwell Banker",
        colors: LibraryColor.coldwellBanker,
        isBuiltIn: true
    )

    var id = UUID()
    var name: String
    var colors: [LibraryColor]
    var isBuiltIn = false
}
