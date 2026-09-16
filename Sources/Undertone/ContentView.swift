import AppKit
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: StudioModel
    @State private var showsHandles = false
    @State private var paletteName = ""

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 240, ideal: 270, max: 340)
        } content: {
            workspace
                .navigationSplitViewColumnWidth(min: 500, ideal: 720)
        } detail: {
            inspector
                .navigationSplitViewColumnWidth(min: 270, ideal: 305, max: 360)
        }
        .navigationSplitViewStyle(.balanced)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button("Randomize", systemImage: "shuffle") {
                    model.randomize()
                }
                .keyboardShortcut("r", modifiers: [.command])
                .accessibilityHint("Generate a new color composition")

                Button("Copy Image", systemImage: "doc.on.doc") {
                    model.copyImage()
                }
                .keyboardShortcut("c", modifiers: [.command, .shift])
                .disabled(model.preview == nil || model.isRendering)

                Button("Save Image…", systemImage: "square.and.arrow.down") {
                    model.exportImage()
                }
                .keyboardShortcut("e", modifiers: [.command, .shift])
                .disabled(model.preview == nil || model.isRendering)
            }
        }
        .onChange(of: model.recipe) { _, _ in
            model.refreshPreview()
        }
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

    private var sidebar: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 5) {
                    Text("UNDERTONE")
                        .font(.caption.weight(.semibold))
                        .tracking(1.6)
                        .foregroundStyle(.secondary)
                    Text("Color studies")
                        .font(.title3.weight(.semibold))
                    Text("Quiet gradients for the work in progress.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 5)
            }

            Section("Color libraries") {
                ColorLibraryView()
            }

            Section("Gradient presets") {
                if model.palettes.isEmpty {
                    Text("Save a color set to find it here.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(model.palettes) { palette in
                        Button {
                            model.applyPalette(palette)
                        } label: {
                            HStack(spacing: 9) {
                                PaletteDots(colors: palette.colors, dotSize: 15)
                                Text(palette.name)
                                    .lineLimit(1)
                                Spacer()
                            }
                        }
                        .accessibilityLabel("Apply \(palette.name) palette")
                    }
                }
                Divider()
                HStack(spacing: 6) {
                    TextField("Save current gradient", text: $paletteName)
                        .onSubmit(savePalette)
                    Button("Save Gradient", systemImage: "plus") {
                        savePalette()
                    }
                    .labelStyle(.iconOnly)
                    .disabled(paletteName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .listStyle(.sidebar)
    }

    private var workspace: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Untitled study")
                        .font(.title2.weight(.semibold))
                    Text("\(model.recipe.width) × \(model.recipe.height) px")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if model.recipe.mode == .organic {
                    Toggle("Edit points", isOn: $showsHandles)
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .accessibilityHint("Show and move color points on the artwork")
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 22)
            .padding(.bottom, 14)

            GeometryReader { proxy in
                VStack(spacing: 16) {
                    artwork
                        .frame(maxWidth: min(proxy.size.width - 48, 880), maxHeight: proxy.size.height - 32)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                    Spacer(minLength: 16)
                }
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var artwork: some View {
        GeometryReader { geometry in
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))

                if let image = model.preview {
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFill()
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .clipped()
                } else {
                    ProgressView("Rendering study…")
                        .controlSize(.small)
                }

                if showsHandles && model.recipe.mode == .organic {
                    ForEach(Array(model.recipe.stops.enumerated()), id: \.element.id) { index, stop in
                        pointHandle(stop: stop, index: index, in: geometry.size)
                    }
                }

                if model.isRendering {
                    VStack {
                        Spacer()
                        HStack(spacing: 7) {
                            ProgressView().controlSize(.small)
                            Text("Rendering full-resolution image")
                        }
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(.regularMaterial, in: Capsule())
                        .padding(14)
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .coordinateSpace(name: "artworkCanvas")
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(.black.opacity(0.10), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.12), radius: 18, y: 7)
        }
        .aspectRatio(CGFloat(model.recipe.width) / CGFloat(max(model.recipe.height, 1)), contentMode: .fit)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Gradient artwork preview")
    }

    private var inspector: some View {
        Form {
            Section("Colors") {
                if model.recipe.mode == .magicSingle {
                    if let stop = model.recipe.stops.first {
                        colorRow(index: 0, stop: stop, canRemove: false)
                    }
                    Text("Pick any library swatch to use it as the base. Undertone creates the tonal variations.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(Array(model.recipe.stops.enumerated()), id: \.element.id) { index, stop in
                        colorRow(index: index, stop: stop)
                    }
                    Button("Add Color", systemImage: "plus") {
                        model.addColor(hex: "D7D3C7")
                    }
                    .controlSize(.small)
                }
            }

            Section("Color suggestions") {
                HStack(spacing: 7) {
                    ForEach(Array(model.suggestedColors().enumerated()), id: \.offset) { _, hex in
                        Button {
                            if model.recipe.mode == .magicSingle { model.setBaseColor(hex: hex) }
                            else { model.addColor(hex: hex) }
                        } label: {
                            Circle()
                                .fill(Color(nsColor: ColorStop(hex: hex, x: 0, y: 0).nsColor))
                                .frame(width: 20, height: 20)
                                .overlay(Circle().stroke(.primary.opacity(0.15), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Add suggested color \(hex)")
                    }
                }
            }

            Section("Gradient") {
                Picker("Type", selection: modeBinding) {
                    ForEach(GradientMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.menu)
                gradientControls
            }

            Section("Texture") {
                SliderControl(title: "Grain", value: doubleBinding(\.grain), range: 0...0.5, valueText: percent(model.recipe.grain))
                SliderControl(title: "Grain size", value: doubleBinding(\.grainSize), range: 0.5...3, valueText: String(format: "%.1f×", model.recipe.grainSize))
            }

            Section("Canvas") {
                Picker("Preset", selection: dimensionPreset) {
                    Text("4K · 3840 × 2160").tag("3840x2160")
                    Text("Instagram Portrait · 2160 × 2880").tag("2160x2880")
                    Text("Desktop · 2560 × 1440").tag("2560x1440")
                    Text("Square · 2048 × 2048").tag("2048x2048")
                    Text("Portrait · 1440 × 2560").tag("1440x2560")
                    Text("Custom").tag("custom")
                }
                .pickerStyle(.menu)

                HStack(spacing: 8) {
                    DimensionField(title: "Width", value: intBinding(\.width), peer: intBinding(\.height))
                    Text("×").foregroundStyle(.secondary)
                    DimensionField(title: "Height", value: intBinding(\.height), peer: intBinding(\.width))
                }
            }

            if !model.status.isEmpty {
                Section {
                    Text(model.status)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder private var gradientControls: some View {
        switch model.recipe.mode {
        case .organic:
            SliderControl(title: "Flow", value: doubleBinding(\.flow), range: 0...1, valueText: percent(model.recipe.flow))
            SliderControl(title: "Softness", value: doubleBinding(\.softness), range: 0...1, valueText: percent(model.recipe.softness))
        case .linear:
            linearGeometryControls
            SliderControl(title: "Ease", value: doubleBinding(\.easing), range: 0...1, valueText: percent(model.recipe.easing))
        case .magicLinear:
            linearGeometryControls
            SliderControl(title: "Ease", value: doubleBinding(\.easing), range: 0...1, valueText: percent(model.recipe.easing))
            SliderControl(title: "Color arc", value: doubleBinding(\.colorArc), range: 0...1, valueText: percent(model.recipe.colorArc))
            Text("Color arc bends each transition through a nearby contrasting tone in perceptual color space.")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .magicSingle:
            SliderControl(title: "Flow", value: doubleBinding(\.flow), range: 0...1, valueText: percent(model.recipe.flow))
            SliderControl(title: "Softness", value: doubleBinding(\.softness), range: 0...1, valueText: percent(model.recipe.softness))
            SliderControl(title: "Variation", value: doubleBinding(\.colorArc), range: 0...1, valueText: percent(model.recipe.colorArc))
        case .radial:
            SliderControl(title: "Center X", value: doubleBinding(\.centerX), range: 0...1, valueText: percent(model.recipe.centerX))
            SliderControl(title: "Center Y", value: doubleBinding(\.centerY), range: 0...1, valueText: percent(model.recipe.centerY))
            SliderControl(title: "Spread", value: doubleBinding(\.fadeWidth), range: 0.15...1.5, valueText: percent(model.recipe.fadeWidth))
            SliderControl(title: "Ease", value: doubleBinding(\.easing), range: 0...1, valueText: percent(model.recipe.easing))
        case .aurora:
            SliderControl(title: "Angle", value: doubleBinding(\.angleDegrees), range: 0...360, valueText: "\(Int(model.recipe.angleDegrees.rounded()))°")
            SliderControl(title: "Position", value: doubleBinding(\.gradientPosition), range: 0...1, valueText: percent(model.recipe.gradientPosition))
            SliderControl(title: "Flow", value: doubleBinding(\.flow), range: 0...1, valueText: percent(model.recipe.flow))
            SliderControl(title: "Fade width", value: doubleBinding(\.fadeWidth), range: 0.15...1.5, valueText: percent(model.recipe.fadeWidth))
            SliderControl(title: "Ease", value: doubleBinding(\.easing), range: 0...1, valueText: percent(model.recipe.easing))
            SliderControl(title: "Color arc", value: doubleBinding(\.colorArc), range: 0...1, valueText: percent(model.recipe.colorArc))
        }
    }

    @ViewBuilder private var linearGeometryControls: some View {
        SliderControl(title: "Angle", value: doubleBinding(\.angleDegrees), range: 0...360, valueText: "\(Int(model.recipe.angleDegrees.rounded()))°")
        SliderControl(title: "Position", value: doubleBinding(\.gradientPosition), range: 0...1, valueText: percent(model.recipe.gradientPosition))
        SliderControl(title: "Fade width", value: doubleBinding(\.fadeWidth), range: 0.15...1.5, valueText: percent(model.recipe.fadeWidth))
    }

    private func colorRow(index: Int, stop: ColorStop, canRemove: Bool = true) -> some View {
        HStack(spacing: 12) {
            ColorPicker("Color \(index + 1)", selection: colorBinding(index: index), supportsOpacity: false)
                .labelsHidden()
                .fixedSize()
                .accessibilityLabel("Choose color \(index + 1)")
            HexField(label: "Hex color \(index + 1)", value: hexBinding(index: index))
            if canRemove {
                Button("Remove color \(index + 1)", systemImage: "minus.circle") {
                    model.removeColor(id: stop.id)
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .disabled(model.recipe.stops.count <= 2)
            }
        }
    }

    private func pointHandle(stop: ColorStop, index: Int, in size: CGSize) -> some View {
        Circle()
            .fill(stop.color)
            .frame(width: 20, height: 20)
            .overlay(Circle().stroke(.white, lineWidth: 2))
            .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
            .position(x: CGFloat(stop.x) * size.width, y: CGFloat(stop.y) * size.height)
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .named("artworkCanvas"))
                    .onChanged { value in
                        guard model.recipe.stops.indices.contains(index), size.width > 0, size.height > 0 else { return }
                        model.recipe.stops[index].x = min(max(Double(value.location.x / size.width), 0), 1)
                        model.recipe.stops[index].y = min(max(Double(value.location.y / size.height), 0), 1)
                    }
            )
            .accessibilityLabel("Move color \(index + 1)")
            .accessibilityHint("Drag to change the color point position")
    }

    private var dimensionPreset: Binding<String> {
        Binding(
            get: {
                switch (model.recipe.width, model.recipe.height) {
                case (3840, 2160): "3840x2160"
                case (2160, 2880): "2160x2880"
                case (2560, 1440): "2560x1440"
                case (2048, 2048): "2048x2048"
                case (1440, 2560): "1440x2560"
                default: "custom"
                }
            },
            set: { preset in
                switch preset {
                case "3840x2160": model.recipe.width = 3840; model.recipe.height = 2160
                case "2160x2880": model.recipe.width = 2160; model.recipe.height = 2880
                case "2560x1440": model.recipe.width = 2560; model.recipe.height = 1440
                case "2048x2048": model.recipe.width = 2048; model.recipe.height = 2048
                case "1440x2560": model.recipe.width = 1440; model.recipe.height = 2560
                default: break
                }
            }
        )
    }

    private var modeBinding: Binding<GradientMode> {
        Binding(get: { model.recipe.mode }, set: { model.recipe.mode = $0 })
    }

    private func doubleBinding(_ keyPath: WritableKeyPath<GradientRecipe, Double>) -> Binding<Double> {
        Binding(get: { model.recipe[keyPath: keyPath] }, set: { model.recipe[keyPath: keyPath] = $0 })
    }

    private func intBinding(_ keyPath: WritableKeyPath<GradientRecipe, Int>) -> Binding<Int> {
        Binding(get: { model.recipe[keyPath: keyPath] }, set: { model.recipe[keyPath: keyPath] = $0 })
    }

    private func hexBinding(index: Int) -> Binding<String> {
        Binding(
            get: { model.recipe.stops.indices.contains(index) ? model.recipe.stops[index].hex : "" },
            set: { input in
                let cleaned = normalizedHex(input)
                guard model.recipe.stops.indices.contains(index), cleaned.count == 6,
                      UInt32(cleaned, radix: 16) != nil else { return }
                model.recipe.stops[index].hex = cleaned
            }
        )
    }

    private func colorBinding(index: Int) -> Binding<Color> {
        Binding(
            get: { model.recipe.stops.indices.contains(index) ? model.recipe.stops[index].color : .clear },
            set: { color in
                guard model.recipe.stops.indices.contains(index) else { return }
                model.recipe.stops[index].hex = hex(for: color)
            }
        )
    }

    private func savePalette() {
        let name = paletteName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        model.savePalette(name: name)
        paletteName = ""
    }

    private func normalizedHex(_ string: String) -> String {
        string.uppercased().trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "#", with: "")
    }

    private func hex(for color: Color) -> String {
        let nsColor = NSColor(color).usingColorSpace(.sRGB) ?? .black
        return String(format: "%02X%02X%02X", Int(nsColor.redComponent * 255), Int(nsColor.greenComponent * 255), Int(nsColor.blueComponent * 255))
    }

    private func percent(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
    }
}

private struct SliderControl: View {
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

private struct DimensionField: View {
    let title: String
    @Binding var value: Int
    @Binding var peer: Int
    @State private var draft = ""

    init(title: String, value: Binding<Int>, peer: Binding<Int>) {
        self.title = title
        self._value = value
        self._peer = peer
    }

    var body: some View {
        TextField(title, text: $draft)
            .textFieldStyle(.roundedBorder)
            .multilineTextAlignment(.center)
            .font(.system(.caption, design: .monospaced))
            .accessibilityLabel(title + " pixels")
            .onAppear { draft = String(value) }
            .onChange(of: value) { _, newValue in
                if draft != String(newValue) { draft = String(newValue) }
            }
            .onSubmit(commit)
    }

    private func commit() {
        let digits = draft.filter(\.isNumber)
        if let candidate = Int(digits), (128...8192).contains(candidate),
           candidate * peer <= 33_554_432 {
            value = candidate
        }
        draft = String(value)
    }
}

private struct HexField: View {
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
            .textCase(.uppercase)
            .onAppear { draft = value }
            .onChange(of: value) { _, newValue in
                if draft != newValue { draft = newValue }
            }
            .onSubmit(commit)
    }

    private func commit() {
        let cleaned = draft.uppercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "#", with: "")
        if cleaned.count == 6, UInt32(cleaned, radix: 16) != nil {
            value = cleaned
        }
        draft = value
    }
}

private struct PaletteDots: View {
    let colors: [String]
    let dotSize: CGFloat

    var body: some View {
        HStack(spacing: -4) {
            ForEach(Array(colors.prefix(5).enumerated()), id: \.offset) { _, hex in
                Circle()
                    .fill(Color(nsColor: ColorStop(hex: hex, x: 0, y: 0).nsColor))
                    .frame(width: dotSize, height: dotSize)
                    .overlay(Circle().stroke(.windowBackground, lineWidth: 1.5))
            }
        }
        .frame(width: max(0, dotSize * 3.5), alignment: .leading)
        .accessibilityHidden(true)
    }
}
