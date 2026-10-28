import SwiftUI

/// The default recipe's colors, for the About signature's symbols.
private enum AboutPalette {
    static let peach = Color(red: 0.95, green: 0.67, blue: 0.57)
    static let violet = Color(red: 0.58, green: 0.45, blue: 0.80)
    static let gold = Color(red: 0.95, green: 0.80, blue: 0.57)
    static let slate = Color(red: 0.45, green: 0.58, blue: 0.76)
}

/// The About window's signature: Undertone's four steps (colors, flow, grain, image) in one glass
/// capsule. DMKit's AboutScene places it under the app name.
struct StudioSignature: View {
    private let stages: [(symbol: String, tint: Color)] = [
        ("swatchpalette", AboutPalette.peach),
        ("scribble.variable", AboutPalette.violet),
        ("aqi.medium", AboutPalette.gold),
        ("photo", AboutPalette.slate)
    ]

    var body: some View {
        HStack(spacing: 10) {
            ForEach(Array(stages.enumerated()), id: \.offset) { index, stage in
                Image(systemName: stage.symbol)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(stage.tint)
                    .frame(width: 24, height: 24)

                if index < stages.count - 1 {
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 8)
        .glassEffect(.regular, in: Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Pick colors, shape the flow, add grain, and export an image")
    }
}
