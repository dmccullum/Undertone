import AppKit
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: StudioModel
    @Environment(\.undoManager) private var undoManager

    var body: some View {
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 230, ideal: 260, max: 340)
        } detail: {
            HStack(spacing: 0) {
                StudioCanvas()
                Divider().opacity(0.5)
                InspectorView()
                    .frame(width: 292)
            }
            .background { AmbientBackdrop() }
        }
        .toolbar(.hidden, for: .windowToolbar)
        .onAppear { model.undoManager = undoManager }
        .onChange(of: undoManager) { _, manager in model.undoManager = manager }
        .alert("Couldn’t complete that action", isPresented: errorIsPresented) {
            Button("OK", role: .cancel) { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "Unknown error")
        }
    }

    private var errorIsPresented: Binding<Bool> {
        Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )
    }
}

/// Randomize, Copy and Export, at the top of the inspector.
private struct InspectorActions: View {
    @EnvironmentObject private var model: StudioModel

    var body: some View {
        HStack(spacing: 8) {
            InspectorActionButton(title: "Randomize", systemImage: "shuffle", help: "Randomize the layout (⌘R)") { model.randomize() }
            InspectorActionButton(title: "Copy", systemImage: "doc.on.doc", help: "Copy the full-size image (⇧⌘C)") { model.copyImage() }
                .disabled(model.isRendering)
            InspectorActionButton(title: "Export", systemImage: "square.and.arrow.up", help: "Export a PNG or JPEG (⌘E)") { model.exportImage() }
                .disabled(model.isRendering)
        }
    }
}

private struct InspectorActionButton: View {
    let title: String
    let systemImage: String
    let help: String
    let action: () -> Void
    @State private var hovering = false
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.system(size: 15, weight: .medium))
                    .frame(height: 18)
                Text(title)
                    .font(.caption)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .background(Color.primary.opacity(hovering && isEnabled ? 0.12 : 0.06), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Color.primary.opacity(0.1), lineWidth: 1) }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(isEnabled ? 1 : 0.5)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
        .help(help)
    }
}

struct InspectorView: View {
    @EnvironmentObject private var model: StudioModel

    var body: some View {
        VStack(spacing: 0) {
            InspectorActions()
                .padding(.horizontal, 20)
                .padding(.top, 10)
                .padding(.bottom, 2)
            form
        }
    }

    private var form: some View {
        Form {
            Section("Style") {
                StylePicker()
            }
            Section(model.recipe.mode.title) {
                styleControls
            }
            Section("Texture") {
                SliderControl(title: "Grain", value: $model.recipe.grain, range: 0...0.5, valueText: percent(model.recipe.grain))
                SliderControl(title: "Grain size", value: $model.recipe.grainSize, range: 0.5...3, valueText: String(format: "%.1f×", model.recipe.grainSize))
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }

    @ViewBuilder private var styleControls: some View {
        switch model.recipe.mode {
        case .organic:
            SliderControl(title: "Flow", value: $model.recipe.flow, range: 0...1, valueText: percent(model.recipe.flow))
            SliderControl(title: "Softness", value: $model.recipe.softness, range: 0...1, valueText: percent(model.recipe.softness))
        case .linear:
            directionControls
            SliderControl(title: "Fade width", value: $model.recipe.fadeWidth, range: 0.15...1.5, valueText: percent(model.recipe.fadeWidth))
            SliderControl(title: "Ease", value: $model.recipe.easing, range: 0...1, valueText: percent(model.recipe.easing))
            SliderControl(title: "Color arc", value: $model.recipe.colorArc, range: 0...1, valueText: percent(model.recipe.colorArc))
        case .tonal:
            SliderControl(title: "Flow", value: $model.recipe.flow, range: 0...1, valueText: percent(model.recipe.flow))
            SliderControl(title: "Softness", value: $model.recipe.softness, range: 0...1, valueText: percent(model.recipe.softness))
            SliderControl(title: "Variation", value: $model.recipe.colorArc, range: 0...1, valueText: percent(model.recipe.colorArc))
        case .radial:
            SliderControl(title: "Center X", value: $model.recipe.centerX, range: -1...2, valueText: percent(model.recipe.centerX))
            SliderControl(title: "Center Y", value: $model.recipe.centerY, range: -1...2, valueText: percent(model.recipe.centerY))
            SliderControl(title: "Spread", value: $model.recipe.fadeWidth, range: 0.15...1.5, valueText: percent(model.recipe.fadeWidth))
            SliderControl(title: "Ease", value: $model.recipe.easing, range: 0...1, valueText: percent(model.recipe.easing))
        case .aurora:
            directionControls
            SliderControl(title: "Flow", value: $model.recipe.flow, range: 0...1, valueText: percent(model.recipe.flow))
            SliderControl(title: "Fade width", value: $model.recipe.fadeWidth, range: 0.15...1.5, valueText: percent(model.recipe.fadeWidth))
            SliderControl(title: "Ease", value: $model.recipe.easing, range: 0...1, valueText: percent(model.recipe.easing))
            SliderControl(title: "Color arc", value: $model.recipe.colorArc, range: 0...1, valueText: percent(model.recipe.colorArc))
        }
    }

    @ViewBuilder private var directionControls: some View {
        SliderControl(title: "Angle", value: $model.recipe.angleDegrees, range: 0...360, valueText: "\(Int(model.recipe.angleDegrees.rounded()))°")
        SliderControl(title: "Position", value: $model.recipe.gradientPosition, range: 0...1, valueText: percent(model.recipe.gradientPosition))
    }

    private func percent(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
    }
}

/// Live previews of the current colors in every style.
struct StylePicker: View {
    @EnvironmentObject private var model: StudioModel
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 3)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 10) {
            ForEach(GradientMode.allCases) { mode in
                StyleTile(mode: mode, image: model.styleThumbnails[mode], isSelected: model.recipe.mode == mode) {
                    model.setMode(mode)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

private struct StyleTile: View {
    let mode: GradientMode
    let image: NSImage?
    let isSelected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 9, style: .continuous)
        Button(action: action) {
            VStack(spacing: 5) {
                ZStack {
                    shape.fill(.quaternary)
                    if let image {
                        Image(nsImage: image)
                            .resizable()
                            .scaledToFill()
                    }
                }
                .frame(height: 50)
                .frame(maxWidth: .infinity)
                .clipShape(shape)
                .overlay {
                    shape.strokeBorder(isSelected ? Color.accentColor : Color.primary.opacity(0.1), lineWidth: isSelected ? 2.5 : 1)
                }
                .shadow(color: .black.opacity(hovering ? 0.22 : 0.08), radius: hovering ? 6 : 2, y: 2)
                .scaleEffect(hovering ? 1.04 : 1)
                Text(mode.title)
                    .font(.caption)
                    .foregroundStyle(isSelected ? .primary : .secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: hovering)
        .accessibilityLabel("\(mode.title) style")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// A tiny render of the artwork, blurred behind the interface so the window takes on its colors.
/// It updates only when edits settle, so dragging never re-blurs the window.
struct AmbientBackdrop: View {
    @EnvironmentObject private var model: StudioModel
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color(nsColor: .windowBackgroundColor)
                if let image = model.ambientImage {
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFill()
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .clipped()
                        .blur(radius: 40, opaque: true)
                        .saturation(1.2)
                        .opacity(colorScheme == .dark ? 0.55 : 0.5)
                        .id(ObjectIdentifier(image))
                        .transition(.opacity)
                }
                Color(nsColor: .windowBackgroundColor)
                    .opacity(colorScheme == .dark ? 0.3 : 0.4)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

struct SliderControl: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let valueText: String

    init(title: String, value: Binding<Double>, range: ClosedRange<Double>, valueText: String) {
        self.title = title
        self._value = value
        self.range = range
        self.valueText = valueText
    }

    var body: some View {
        VStack(spacing: 5) {
            HStack {
                Text(title)
                Spacer()
                Text(valueText)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .font(.caption)
            Slider(value: $value, in: range)
                .accessibilityLabel(title)
        }
    }
}

struct HexField: View {
    let label: String
    @Binding var value: String
    @State private var draft = ""

    init(label: String, value: Binding<String>) {
        self.label = label
        self._value = value
    }

    var body: some View {
        TextField(label, text: $draft)
            .labelsHidden()
            .accessibilityLabel(label)
            .textFieldStyle(.roundedBorder)
            .font(.system(.body, design: .monospaced))
            .onAppear { draft = value }
            .onChange(of: value) { _, newValue in
                if draft != newValue { draft = newValue }
            }
            .onSubmit(commit)
    }

    private func commit() {
        if let cleaned = Hex.normalized(draft) { value = cleaned }
        draft = value
    }
}

/// A round swatch for gradient colors and suggestions. Flat color, with the same hairline and
/// shadow as the style tiles and library swatches.
struct ColorDot: View {
    let hex: String
    var size: CGFloat = 28

    var body: some View {
        Circle()
            .fill(Hex.color(hex))
            .overlay { Circle().strokeBorder(Color.primary.opacity(0.14), lineWidth: 1) }
            .frame(width: size, height: size)
            .shadow(color: .black.opacity(0.14), radius: 2, y: 1)
    }
}
