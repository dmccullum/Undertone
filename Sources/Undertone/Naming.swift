import Foundation
import FoundationModels
import UndertoneKit

/// Plain-language descriptions of colors, used for names and for the Apple Intelligence brief.
nonisolated enum ColorNamer {
    enum Family: CaseIterable {
        case red, orange, amber, yellow, green, teal, cyan, blue, indigo, violet, pink
        case neutralLight, neutralMid, neutralDark

        var isNeutral: Bool { self == .neutralLight || self == .neutralMid || self == .neutralDark }
        var isWarm: Bool { [.red, .orange, .amber, .yellow, .pink].contains(self) }

        var baseName: String {
            switch self {
            case .red: "Red"
            case .orange: "Coral"
            case .amber: "Amber"
            case .yellow: "Yellow"
            case .green: "Green"
            case .teal: "Teal"
            case .cyan: "Aqua"
            case .blue: "Blue"
            case .indigo: "Indigo"
            case .violet: "Violet"
            case .pink: "Pink"
            case .neutralLight: "Light Gray"
            case .neutralMid: "Gray"
            case .neutralDark: "Charcoal"
            }
        }

        var nouns: [String] {
            switch self {
            case .red: ["Ember", "Cinder", "Poppy", "Garnet", "Flare", "Cherry"]
            case .orange: ["Apricot", "Marmalade", "Terracotta", "Sunset", "Tangerine", "Clay"]
            case .amber: ["Honey", "Saffron", "Brass", "Wheat", "Marigold", "Amber"]
            case .yellow: ["Lemon", "Buttercup", "Citron", "Sunbeam", "Daylight"]
            case .green: ["Fern", "Moss", "Meadow", "Sage", "Pine", "Clover"]
            case .teal: ["Lagoon", "Jade", "Seaglass", "Tidepool", "Eucalyptus"]
            case .cyan: ["Glacier", "Surf", "Skylight", "Rain", "Spray"]
            case .blue: ["Harbor", "Tide", "Cobalt", "Denim", "Current", "Marine"]
            case .indigo: ["Midnight", "Ink", "Nightfall", "Abyss", "Sapphire"]
            case .violet: ["Lilac", "Iris", "Wisteria", "Twilight", "Amethyst"]
            case .pink: ["Peony", "Blush", "Orchid", "Flamingo", "Petal", "Rosewater"]
            case .neutralLight: ["Linen", "Porcelain", "Fog", "Pearl", "Chalk"]
            case .neutralMid: ["Slate", "Stone", "Pewter", "Driftwood", "Flint"]
            case .neutralDark: ["Graphite", "Obsidian", "Onyx", "Charcoal", "Soot"]
            }
        }
    }

    struct HSB { let hue: Double; let saturation: Double; let brightness: Double }

    static func hsb(_ hex: String) -> HSB {
        let rgb = Hex.components(hex)
        let high = max(rgb.red, rgb.green, rgb.blue), low = min(rgb.red, rgb.green, rgb.blue)
        let delta = high - low
        var hue = 0.0
        if delta > 0 {
            if high == rgb.red { hue = 60 * ((rgb.green - rgb.blue) / delta).truncatingRemainder(dividingBy: 6) }
            else if high == rgb.green { hue = 60 * ((rgb.blue - rgb.red) / delta + 2) }
            else { hue = 60 * ((rgb.red - rgb.green) / delta + 4) }
        }
        if hue < 0 { hue += 360 }
        return HSB(hue: hue, saturation: high == 0 ? 0 : delta / high, brightness: high)
    }

    static func family(_ hex: String) -> Family {
        let color = hsb(hex)
        if color.saturation < 0.12 || color.brightness < 0.14 {
            if color.brightness >= 0.75 { return .neutralLight }
            return color.brightness >= 0.3 ? .neutralMid : .neutralDark
        }
        switch color.hue {
        case ..<12: return .red
        case ..<40: return .orange
        case ..<58: return .amber
        case ..<72: return .yellow
        case ..<160: return .green
        case ..<190: return .teal
        case ..<205: return .cyan
        case ..<240: return .blue
        case ..<262: return .indigo
        case ..<295: return .violet
        case ..<345: return .pink
        default: return .red
        }
    }

    /// A readable name such as "Deep Blue" or "Pale Coral".
    static func name(_ hex: String) -> String {
        let color = hsb(hex)
        let family = Self.family(hex)
        if family.isNeutral {
            switch color.brightness {
            case 0.95...: return "White"
            case 0.75...: return "Light Gray"
            case 0.35...: return "Gray"
            case 0.1...: return "Charcoal"
            default: return "Black"
            }
        }
        let modifier: String
        if color.brightness < 0.45 { modifier = "Deep " }
        else if color.brightness > 0.85 && color.saturation < 0.35 { modifier = "Pale " }
        else if color.saturation < 0.35 { modifier = "Dusty " }
        else if color.saturation > 0.75 && color.brightness > 0.7 { modifier = "Bright " }
        else { modifier = "" }
        return modifier + family.baseName
    }
}

/// Deterministic word-picker names. The same colors and seed always give the same name.
nonisolated enum NameGenerator {
    static let untitled = "Untitled Gradient"

    static func name(for recipe: GradientRecipe, seed: Int) -> String {
        let hexes = recipe.mode == .tonal ? Array(recipe.stops.prefix(1).map(\.hex)) : recipe.stops.map(\.hex)
        guard !hexes.isEmpty else { return untitled }

        var families: [ColorNamer.Family] = []
        for hex in hexes {
            let family = ColorNamer.family(hex)
            if !families.contains(family) { families.append(family) }
        }
        families = families.filter { !$0.isNeutral } + families.filter(\.isNeutral)

        var state = fnv(hexes.joined() + recipe.mode.rawValue) &+ UInt64(bitPattern: Int64(seed)) &* 0x9E37_79B9_7F4A_7C15
        func pick<T>(_ options: [T]) -> T {
            state = mix(state)
            return options[Int(state % UInt64(options.count))]
        }

        let noun = pick(families[0].nouns)
        let otherNouns = families.dropFirst().flatMap(\.nouns).filter { $0 != noun }
        let adjective = pick(adjectives(for: hexes).filter { $0 != noun })
        let pattern = pick([0, 1, 2, 3])
        switch pattern {
        case 1 where !otherNouns.isEmpty: return "\(noun) \(pick(otherNouns))"
        case 2 where !otherNouns.isEmpty: return "\(pick(otherNouns)) \(noun)"
        case 3: return "\(noun) \(pick(suffixes(for: recipe.mode)))"
        default: return "\(adjective) \(noun)"
        }
    }

    static func suggestions(for recipe: GradientRecipe, startingAt seed: Int, count: Int = 5) -> [String] {
        var names: [String] = []
        var offset = 0
        while names.count < count && offset < count * 6 {
            let candidate = name(for: recipe, seed: seed + offset)
            if !names.contains(candidate) { names.append(candidate) }
            offset += 1
        }
        return names
    }

    enum Mood: String { case light, dark, vivid, muted, warm, cool }

    static func mood(for hexes: [String]) -> Mood {
        let colors = hexes.map(ColorNamer.hsb)
        guard !colors.isEmpty else { return .muted }
        let brightness = colors.map(\.brightness).reduce(0, +) / Double(colors.count)
        let saturation = colors.map(\.saturation).reduce(0, +) / Double(colors.count)
        let warmCount = hexes.filter { ColorNamer.family($0).isWarm }.count
        if brightness > 0.78 { return .light }
        if brightness < 0.38 { return .dark }
        if saturation > 0.62 { return .vivid }
        if saturation < 0.3 { return .muted }
        return warmCount * 2 >= hexes.count ? .warm : .cool
    }

    private static func adjectives(for hexes: [String]) -> [String] {
        switch mood(for: hexes) {
        case .light: ["Hushed", "Airy", "Morning", "Quiet", "Powder", "Soft"]
        case .dark: ["Velvet", "Smoky", "Late", "Moonlit", "Midnight"]
        case .vivid: ["Electric", "Radiant", "Bright", "Candied", "Juicy"]
        case .muted: ["Dusty", "Faded", "Weathered", "Gentle", "Muted"]
        case .warm: ["Sunlit", "Golden", "Glowing", "Toasted", "Balmy"]
        case .cool: ["Frosted", "Still", "Tidal", "Crisp", "Breezy"]
        }
    }

    private static func suffixes(for mode: GradientMode) -> [String] {
        switch mode {
        case .organic: ["Haze", "Bloom", "Drift", "Cloud"]
        case .mesh: ["Weave", "Field", "Panel", "Mesh"]
        case .linear: ["Horizon", "Hour", "Fade", "Line"]
        case .tonal: ["Study", "Tones", "Echo", "Shade"]
        case .radial: ["Glow", "Bloom", "Halo", "Flare"]
        case .aurora: ["Drift", "Ribbon", "Veil", "Lights"]
        }
    }

    private static func fnv(_ text: String) -> UInt64 {
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325
        for byte in text.utf8 { hash = (hash ^ UInt64(byte)) &* 0x0000_0100_0000_01B3 }
        return hash
    }

    private static func mix(_ value: UInt64) -> UInt64 {
        var value = value &+ 0x9E37_79B9_7F4A_7C15
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        return value ^ (value >> 31)
    }
}

/// On-device Apple Intelligence names. Falls back to nothing when the model isn't available,
/// so callers always keep the word-picker names as a baseline.
nonisolated enum NameIntelligence {
    static var isAvailable: Bool { FoundationNamer.isAvailable }

    static func suggestions(for brief: String) async -> [String] {
        await FoundationNamer.suggestions(for: brief)
    }

    static func cleaned(_ names: [String]) -> [String] {
        var result: [String] = []
        for name in names {
            let trimmed = name
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'“”‘’.!-•*0123456789) ").union(.whitespacesAndNewlines))
            let words = trimmed.split(separator: " ")
            guard !trimmed.isEmpty, trimmed.count <= 32, (1...3).contains(words.count),
                  !trimmed.lowercased().contains("gradient"),
                  !result.contains(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) else { continue }
            result.append(trimmed)
        }
        return Array(result.prefix(5))
    }
}

@Generable
nonisolated struct GradientNameIdeas {
    @Guide(description: "Five distinct names for the artwork, each one to three words in title case")
    var names: [String]
}

nonisolated enum FoundationNamer {
    static var isAvailable: Bool {
        if case .available = SystemLanguageModel.default.availability { return true }
        return false
    }

    static func suggestions(for brief: String) async -> [String] {
        guard isAvailable else { return [] }
        let session = LanguageModelSession(instructions: """
            You name gradient artworks for a designer's color studio. Suggest short, evocative names \
            of one to three words in title case. Draw on nature, places, weather, times of day, \
            materials and moods that match the colors. Never use the words gradient or color, \
            hex codes, quotation marks, emoji or punctuation.
            """)
        do {
            let response = try await session.respond(to: brief, generating: GradientNameIdeas.self)
            return NameIntelligence.cleaned(response.content.names)
        } catch {
            return []
        }
    }
}
