import Foundation

public nonisolated struct ColorStop: Codable, Identifiable, Equatable, Sendable {
    public var id = UUID()
    public var hex: String
    public var x: Double
    public var y: Double
    /// How strongly this point pulls in the point-based styles (Organic, Mesh, Tonal). 1 is neutral.
    public var weight: Double = 1.0

    enum CodingKeys: String, CodingKey { case id, hex, x, y, weight }

    public init(id: UUID = UUID(), hex: String, x: Double, y: Double, weight: Double = 1.0) {
        self.id = id
        self.hex = hex
        self.x = x
        self.y = y
        self.weight = weight
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        hex = try container.decode(String.self, forKey: .hex)
        x = try container.decode(Double.self, forKey: .x)
        y = try container.decode(Double.self, forKey: .y)
        weight = try container.decodeIfPresent(Double.self, forKey: .weight) ?? 1.0
    }
}

/// How Organic's colors move: melt in place, stretch like dragged paint, ripple in long waves, or
/// bend with the original Organic's broad warp.
public nonisolated enum OrganicFlow: String, Codable, CaseIterable, Identifiable, Sendable {
    case still, pull, wave, classic

    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .still: "Still"
        case .pull: "Pull"
        case .wave: "Wave"
        case .classic: "Classic"
        }
    }

    /// Unknown values (from newer files) open as Still.
    public init(from decoder: Decoder) throws {
        self = OrganicFlow(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .still
    }
}

public nonisolated enum GradientMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case organic
    case mesh
    case linear
    case tonal = "magicSingle"
    case radial
    case aurora

    public var id: String { rawValue }
    public var title: String {
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
    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        if raw == "magicLinear" {
            self = .linear
        } else {
            self = GradientMode(rawValue: raw) ?? .organic
        }
    }
}

public nonisolated struct GradientRecipe: Codable, Equatable, Sendable {
    public static let currentVersion = 5

    public var stops: [ColorStop] = [.init(hex: "F3AC91", x: 0.18, y: 0.20), .init(hex: "7655A3", x: 0.78, y: 0.24), .init(hex: "F3CC91", x: 0.34, y: 0.82), .init(hex: "3B526E", x: 0.92, y: 0.85)]
    public var mode: GradientMode = .organic
    public var organicFlow: OrganicFlow = .still
    public var flow: Double = 0.55
    public var softness: Double = 0.55
    /// Organic/Tonal: a vortex domain-warp that twirls the mesh. Its center and spin come from `seed`.
    public var swirl: Double = 0
    public var angleDegrees: Double = 0
    public var gradientPosition: Double = 0.5
    public var fadeWidth: Double = 1
    /// Linear runs the gradient from `start` to `end` (fractions of the canvas). Both points are
    /// draggable; the angle is whatever line they describe.
    public var startX: Double = 0.0
    public var startY: Double = 0.5
    public var endX: Double = 1.0
    public var endY: Double = 0.5
    /// Linear only: a rounded, kink-free blend through the colors instead of straight segments.
    /// On by default — Linear reads best smooth.
    public var smoothBlend: Bool = true
    public var easing: Double = 0.55
    public var colorArc: Double = 0.35
    public var centerX: Double = 0.5
    public var centerY: Double = 0.5
    public var textureEnabled: Bool = true
    public var grain: Double = 0.20
    public var grainSize: Double = 1.0
    public var seed: UInt64 = 42
    /// Mesh: the grid is `meshSize` × `meshSize` points, each with its own color. `meshVertices` holds
    /// them row by row; empty means an even grid not yet edited, seeded from `stops`.
    public var meshSize: Int = 3
    public var meshVertices: [MeshVertex] = []
    public var width: Int = 2160
    public var height: Int = 2880
    public var version: Int = GradientRecipe.currentVersion

    enum CodingKeys: String, CodingKey {
        case stops, mode, organicFlow, flow, softness, swirl, angleDegrees, gradientPosition, fadeWidth
        case startX, startY, endX, endY, smoothBlend
        case easing, colorArc, centerX, centerY, textureEnabled, grain, grainSize, seed, meshSize, meshVertices
        case width, height, version
    }

    public init(
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
        meshSize: Int = 3,
        meshVertices: [MeshVertex] = [],
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
        self.meshSize = meshSize
        self.meshVertices = meshVertices
        self.width = width
        self.height = height
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        stops = try values.decodeIfPresent([ColorStop].self, forKey: .stops) ?? stops
        mode = try values.decodeIfPresent(GradientMode.self, forKey: .mode) ?? mode
        organicFlow = try values.decodeIfPresent(OrganicFlow.self, forKey: .organicFlow) ?? organicFlow
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
        meshSize = try values.decodeIfPresent(Int.self, forKey: .meshSize) ?? meshSize
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
        // Version 5 points own their colors; version 4 points named a tray color or followed the
        // automatic fill. Before version 4, Mesh blended free-floating points: open those as the
        // nearest grid layout.
        if let legacy = try values.decodeIfPresent([LegacyMeshVertex].self, forKey: .meshVertices) {
            meshVertices = MeshGrid.resolved(legacy, size: MeshGrid.clampedSize(meshSize), stops: stops)
        } else if savedVersion < 4, mode == .mesh {
            meshVertices = MeshGrid.migrated(from: stops, size: meshSize)
        }
        version = Self.currentVersion
    }
}

public nonisolated enum Hex {
    /// Uppercased six-digit hex without "#", or nil when the input isn't a color.
    public static func normalized(_ input: String) -> String? {
        let cleaned = input.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "#", with: "").uppercased()
        return cleaned.range(of: "^[0-9A-F]{6}$", options: .regularExpression) == nil ? nil : cleaned
    }

    public static func components(_ hex: String) -> (red: Double, green: Double, blue: Double) {
        let value = UInt32(hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")), radix: 16) ?? 0
        return (Double((value >> 16) & 255) / 255, Double((value >> 8) & 255) / 255, Double(value & 255) / 255)
    }

    /// Relative luminance, used to pick a legible checkmark over a swatch.
    public static func luminance(_ hex: String) -> Double {
        let rgb = components(hex)
        return 0.2126 * rgb.red + 0.7152 * rgb.green + 0.0722 * rgb.blue
    }
}
