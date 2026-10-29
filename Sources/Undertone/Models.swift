import AppKit
import SwiftUI
import UndertoneKit
import UniformTypeIdentifiers

/// Colors for the views. The recipe types themselves live in UndertoneKit, which has no AppKit or SwiftUI.
nonisolated extension ColorStop {
    var color: Color { Hex.color(hex) }
    var nsColor: NSColor { Hex.nsColor(hex) }
}

nonisolated extension Hex {
    static func nsColor(_ hex: String) -> NSColor {
        let rgb = components(hex)
        return NSColor(srgbRed: rgb.red, green: rgb.green, blue: rgb.blue, alpha: 1)
    }

    static func color(_ hex: String) -> Color { Color(nsColor: nsColor(hex)) }

    static func string(from color: Color) -> String {
        let converted = NSColor(color).usingColorSpace(.sRGB) ?? .black
        return String(format: "%02X%02X%02X", Int((converted.redComponent * 255).rounded()), Int((converted.greenComponent * 255).rounded()), Int((converted.blueComponent * 255).rounded()))
    }
}

/// A complete, named composition in the gradient library.
nonisolated struct SavedGradient: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    /// False while the name is still generated from the colors.
    var hasCustomName = false
    var nameSeed = 0
    var recipe: GradientRecipe
    var modified = Date()
    /// An unsaved gradient: a scratch copy that edits go into instead of overwriting a saved one.
    /// It stays in the library until it's saved, used to update its source, or discarded.
    var isUnsaved = false
    /// The saved gradient an unsaved one was edited from, which Update writes back to.
    var sourceID: UUID?
}

nonisolated extension SavedGradient {
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        name = try values.decode(String.self, forKey: .name)
        hasCustomName = try values.decodeIfPresent(Bool.self, forKey: .hasCustomName) ?? false
        nameSeed = try values.decodeIfPresent(Int.self, forKey: .nameSeed) ?? 0
        recipe = try values.decode(GradientRecipe.self, forKey: .recipe)
        modified = try values.decodeIfPresent(Date.self, forKey: .modified) ?? Date()
        isUnsaved = try values.decodeIfPresent(Bool.self, forKey: .isUnsaved) ?? false
        sourceID = try values.decodeIfPresent(UUID.self, forKey: .sourceID)
    }
}

/// Legacy "gradient preset" format, which stored only colors. Read once for migration.
nonisolated struct BrandPalette: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var colors: [String]
}

nonisolated struct LibraryColor: Codable, Identifiable, Equatable {
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
nonisolated struct ColorLibrary: Codable, Identifiable, Equatable {
    static let coldwellBankerID = UUID(uuidString: "CB000001-0000-4000-8000-000000000001")!
    static let coldwellBanker = ColorLibrary(
        id: coldwellBankerID,
        name: "Coldwell Banker",
        colors: LibraryColor.coldwellBanker
    )

    var id = UUID()
    var name: String
    var colors: [LibraryColor]
}

nonisolated enum CanvasPreset: String, CaseIterable, Identifiable {
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

/// The image formats Export Image writes. Settings picks the one its save panel starts on.
nonisolated enum ExportFormat: String, CaseIterable, Identifiable {
    case png, jpeg

    static let preference = "exportFormat"
    static let jpegQualityPreference = "jpegQuality"
    static let defaultJPEGQuality = 0.95

    var id: String { rawValue }
    var title: String {
        switch self {
        case .png: "PNG"
        case .jpeg: "JPEG"
        }
    }
    var contentType: UTType { self == .png ? .png : .jpeg }
    var fileExtension: String { self == .png ? "png" : "jpg" }
}
