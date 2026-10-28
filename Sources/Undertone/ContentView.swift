import AppKit
import DMKit
import SwiftUI

struct ContentView: View {
    @Environment(StudioModel.self) private var model
    @Environment(\.undoManager) private var undoManager
    @Environment(\.hostingWindow) private var window
    @State private var renaming = false
    @State private var choosingCustomSize = false
    @AppStorage("showsInspector") private var showsInspector = true

    var body: some View {
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 230, ideal: 260, max: 340)
        } detail: {
            StudioCanvas()
                // The system inspector: a full-height trailing pane, toggled by View › Show Inspector
                // (⌥⌘I, in StudioCommands) and the toolbar button below.
                .inspector(isPresented: $showsInspector) {
                    InspectorView()
                        .inspectorColumnWidth(min: 280, ideal: 300, max: 360)
                }
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button { showsInspector.toggle() } label: {
                            Label(showsInspector ? "Hide Inspector" : "Show Inspector", systemImage: "sidebar.trailing")
                        }
                        .help(showsInspector ? "Hide the inspector (⌥⌘I)" : "Show the inspector (⌥⌘I)")
                    }
                }
        }
        // The window's minimum width: sidebar, room for the canvas and color tray, and the inspector
        // when it's open. StudioCanvas explains why the columns can't report this themselves.
        .frame(minWidth: showsInspector ? 1_000 : 700)
        // The backdrop fills the whole window — including behind the transparent toolbar — so the
        // content can sit in its safe area (no title-bar overlap, no dynamic insets) while the top
        // band still shows the gradient instead of an empty bar.
        .background { AmbientBackdrop() }
        // Drive the native window title (left-aligned, no toolbar-control pill). Unsaved work always
        // autosaves into its own unsaved gradient, so the subtitle marks it instead of "— Edited".
        .background(WindowChrome(title: model.currentName.isEmpty ? "Untitled" : model.currentName, subtitle: subtitle))
        .navigationSubtitle(subtitle)
        .sheet(isPresented: $renaming) {
            RenameGradientSheet().environment(model)
        }
        .onChange(of: model.renameRequest) { _, _ in renaming = true }
        .sheet(isPresented: $choosingCustomSize) {
            CustomSizeForm(isPresented: $choosingCustomSize).environment(model)
        }
        .focusedSceneValue(\.customSizeAction, CustomSizeAction { choosingCustomSize = true })
        .onAppear { model.undoManager = undoManager }
        .onChange(of: undoManager) { _, manager in model.undoManager = manager }
        .onChange(of: window, initial: true) { _, window in model.window = window }
        .alert(model.errorTitle, isPresented: errorIsPresented) {
            Button("OK", role: .cancel) { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    private var subtitle: String {
        guard model.isCurrentUnsaved else { return "" }
        return model.currentSource.map { "Unsaved · edited from \($0.name)" } ?? "Unsaved"
    }

    private var errorIsPresented: Binding<Bool> {
        Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )
    }
}

/// Sets the native window title (no toolbar-control pill on the title).
private struct WindowChrome: NSViewRepresentable {
    let title: String
    /// Not drawn here: SwiftUI resets the window title to the scene's name whenever
    /// `navigationSubtitle` changes, so a subtitle change has to reapply the title too.
    let subtitle: String

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { apply(to: view.window) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { apply(to: nsView.window) }
    }

    private func apply(to window: NSWindow?) {
        guard let window, window.title != title else { return }
        window.title = title
    }
}

/// Renames the working document, with a shuffle to pull a fresh name from the colors.
private struct RenameGradientSheet: View {
    @Environment(StudioModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var draft = ""
    /// The shuffle's last roll. Renaming to it keeps the name automatic, following the colors.
    @State private var suggestion: (name: String, seed: Int)?
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Rename Gradient").font(.title2.weight(.semibold))
            HStack(spacing: 8) {
                TextField("Name", text: $draft)
                    .textFieldStyle(.roundedBorder)
                    .focused($focused)
                    .onSubmit(commit)
                Button {
                    let rolled = model.automaticNameSuggestion()
                    suggestion = rolled
                    draft = rolled.name
                } label: {
                    Image(systemName: "die.face.5")
                }
                .help("Suggest a name from the colors")
                .accessibilityLabel("Suggest a Name")
            }
            HStack {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Rename") { commit() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 360)
        .defaultFocus($focused, true)
        .onAppear { draft = model.currentName }
    }

    private func commit() {
        if let suggestion, suggestion.name == draft { model.useAutomaticName(seed: suggestion.seed) }
        else { model.renameCurrentGradient(draft) }
        dismiss()
    }
}

struct InspectorView: View {
    @Environment(StudioModel.self) private var model
    /// Bindings into the model for the inspector's toggles and pickers.
    private var bindable: Bindable<StudioModel> { Bindable(model) }
    private static let defaults = GradientRecipe()
    private static let grainSizeFormat = SliderValueFormat(
        fractionDigits: 1, unit: .init(symbol: "×", spokenName: "times", spellings: ["×", "x"], isSpaced: false), step: 0.1
    )

    // Cards instead of a grouped Form: a Form reserves a leading label column for sliders, which
    // pushes them off to the right. Cards keep the sliders full width.
    var body: some View {
        ScrollView {
            VStack(spacing: DMLayout.inspectorSpacing) {
                InspectorCard("Canvas") {
                    CanvasSizeMenu()
                }
                InspectorCard("Style") {
                    EmptyView()
                } content: {
                    StylePicker()
                }
                InspectorCard(model.recipe.mode.title) {
                    CardResetButton("Reset \(model.recipe.mode.title) Settings") { model.resetStyle() }
                } content: {
                    styleControls
                }
                InspectorCard("Texture") {
                    CardResetButton("Reset Texture") { model.resetTexture() }
                    Toggle("Texture", isOn: bindable.recipe.textureEnabled)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.mini)
                } content: {
                    if model.recipe.textureEnabled {
                        slider("Grain", \.grain, in: 0...0.5, format: .percent)
                        slider("Grain Size", \.grainSize, in: 0.5...3, format: Self.grainSizeFormat)
                    }
                }
            }
            .padding(.horizontal, DMLayout.inspectorPadding)
            .padding(.bottom, DMLayout.inspectorPadding)
        }
    }

    /// A slider on one recipe value. Dragging edits the recipe directly; the model folds a burst of
    /// edits (700 ms) into one undo step, so the slider's commit has nothing left to do.
    private func slider(_ title: String, _ keyPath: WritableKeyPath<GradientRecipe, Double>, in range: ClosedRange<Double>,
                        format: SliderValueFormat = .percent) -> InspectorSlider {
        InspectorSlider(title, value: model.recipe[keyPath: keyPath], in: range, default: Self.defaults[keyPath: keyPath],
                        format: format, preview: { model.recipe[keyPath: keyPath] = $0 }, commit: {})
    }

    @ViewBuilder private var styleControls: some View {
        switch model.recipe.mode {
        case .organic:
            StackedControl("Flow") {
                FilledSegments("Flow", selection: bindable.recipe.organicFlow,
                               segments: OrganicFlow.allCases.map { .init(value: $0, title: $0.title) })
            }
            .help("Still melts the colors in place, Pull drags them like a brush, Wave ripples the borders, Classic is the original Organic")
            if model.recipe.organicFlow != .still {
                slider(organicStrengthTitle, \.flow, in: 0...1)
            }
            slider("Softness", \.softness, in: 0...1)
            slider("Swirl", \.swirl, in: 0...1)
            if model.recipe.organicFlow != .still || model.recipe.swirl > 0 {
                Button("Shuffle Flow", systemImage: "shuffle") { model.shuffleMesh() }
                    .help("New directions for the flow and swirl, without moving your colors")
            }
        case .mesh:
            StackedControl("Grid") {
                FilledSegments("Grid", selection: Binding(get: { model.meshSize }, set: { model.setMeshSize($0) }),
                               segments: MeshGrid.sizes.map { .init(value: $0, title: "\($0) × \($0)") })
            }
            slider("Softness", \.softness, in: 0...1)
            HStack(spacing: 8) {
                Button { model.straightenMesh() } label: {
                    Text("Straighten").frame(maxWidth: .infinity)
                }
                .help("Put every point back on an even grid, keeping its color")
                Button { model.shuffleMeshColors() } label: {
                    Text("Shuffle Colors").frame(maxWidth: .infinity)
                }
                .help("Deal your colors across the points in a new arrangement")
                .disabled(Set(model.meshVertices.map(\.hex)).count < 2)
            }
            Text(meshCaption)
                .font(.caption)
                .foregroundStyle(.secondary)
        case .linear:
            AnglePresetGrid(current: model.linearAngle) { model.setLinearAngle($0) }
            StackedControl("Blend") {
                FilledSegments("Blend", selection: bindable.recipe.smoothBlend,
                               segments: [.init(value: false, title: "Crisp"), .init(value: true, title: "Smooth")])
            }
            if !model.recipe.smoothBlend {
                slider("Ease", \.easing, in: 0...1)
            }
        case .tonal:
            slider("Flow", \.flow, in: 0...1)
            slider("Softness", \.softness, in: 0...1)
            slider("Variation", \.colorArc, in: 0...1)
            slider("Swirl", \.swirl, in: 0...1)
            Button("Shuffle Texture", systemImage: "shuffle") { model.shuffleMesh() }
                .help("Vary the tonal shapes without changing the base color")
        case .radial:
            slider("Center X", \.centerX, in: -1...2)
            slider("Center Y", \.centerY, in: -1...2)
            slider("Spread", \.fadeWidth, in: 0.15...1.5)
            slider("Ease", \.easing, in: 0...1)
        case .aurora:
            AnglePresetGrid(current: model.recipe.angleDegrees) { model.recipe.angleDegrees = $0 }
            slider("Angle", \.angleDegrees, in: 0...360, format: SliderValueFormat(unit: .degrees))
            slider("Position", \.gradientPosition, in: 0...1)
            slider("Flow", \.flow, in: 0...1)
            slider("Fade Width", \.fadeWidth, in: 0.15...5)
            slider("Ease", \.easing, in: 0...1)
            slider("Color Arc", \.colorArc, in: 0...1)
        }
    }

    private var organicStrengthTitle: String {
        switch model.recipe.organicFlow {
        case .pull: "Pull"
        case .wave: "Wave Height"
        case .still, .classic: "Flow"
        }
    }

    private var meshCaption: String {
        "Click a point on the canvas or in the tray, then click colors in your collections to paint it; it moves to the next point. Double-click a point for more colors. Drag points to bend the grid."
    }
}

/// Live previews of the current colors in every style.
struct StylePicker: View {
    @Environment(StudioModel.self) private var model
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
    @Environment(\.colorSchemeContrast) private var contrast
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
                // Hover strengthens the outline instead of growing the tile.
                .overlay {
                    shape.strokeBorder(isSelected ? Color.accentColor : Color.primary.opacity(hovering ? contrast.hairline(0.35) : contrast.hairline(0.1)), lineWidth: isSelected ? 2.5 : (hovering ? 1.5 : 1))
                }
                .shadow(color: .black.opacity(0.08), radius: 2, y: 2)
                Text(mode.title)
                    .font(.caption)
                    .foregroundStyle(isSelected ? .primary : .secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
        .accessibilityLabel("\(mode.title) style")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// The window takes on the artwork's colors by blurring the live preview behind the interface.
/// It reads the same preview image the canvas shows, so it tracks edits in realtime with no extra
/// render and no update jump.
struct AmbientBackdrop: View {
    @Environment(StudioModel.self) private var model
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color(nsColor: .windowBackgroundColor)
                // Reduce Transparency: a plain window background, without the artwork showing through.
                if let image = model.preview, !reduceTransparency {
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.low)
                        .scaledToFill()
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .clipped()
                        .blur(radius: 60, opaque: true)
                        .saturation(1.2)
                        .opacity(colorScheme == .dark ? 0.55 : 0.5)
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

/// Quick 45° angle presets for Linear and Aurora.
struct AnglePresetGrid: View {
    @Environment(\.colorSchemeContrast) private var contrast
    let current: Double
    let onSelect: (Double) -> Void
    private let angles: [Double] = [0, 45, 90, 135, 180, 225, 270, 315]
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 4)

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Angle")
                .font(.caption)
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(angles, id: \.self) { angle in
                    let selected = isSelected(angle)
                    Button { onSelect(angle) } label: {
                        // 0° points right; rotating clockwise by the angle matches the on-canvas
                        // direction (screen y runs downward).
                        Image(systemName: "arrow.right")
                            .font(.system(size: 12, weight: .semibold))
                            .rotationEffect(.degrees(angle))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 7)
                            .background(selected ? Color.accentColor : Color.primary.opacity(contrast.hairline(0.06)), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                            .foregroundStyle(selected ? Color.onAccent : Color.primary)
                            .overlay { RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(Color.primary.opacity(selected ? 0 : contrast.hairline(0.1)), lineWidth: 1) }
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(Int(angle)) degrees")
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
        }
    }

    private func isSelected(_ angle: Double) -> Bool {
        let diff = abs(current - angle).truncatingRemainder(dividingBy: 360)
        return min(diff, 360 - diff) < 1.5
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
    @Environment(\.colorSchemeContrast) private var contrast
    let hex: String
    var size: CGFloat = 28

    var body: some View {
        Circle()
            .fill(Hex.color(hex))
            .overlay { Circle().strokeBorder(Color.primary.opacity(contrast.hairline(0.14)), lineWidth: 1) }
            .frame(width: size, height: size)
            .shadow(color: .black.opacity(0.14), radius: 2, y: 1)
    }
}

extension ColorSchemeContrast {
    /// A hairline, card tint or outline opacity: tripled (up to 0.45) with Increase Contrast.
    func hairline(_ standard: Double) -> Double {
        self == .increased ? min(0.45, standard * 3) : standard
    }
}

extension Color {
    /// Glyphs drawn on an accent fill: white, or black when the accent is light enough (yellow) that
    /// white would wash out.
    static var onAccent: Color {
        guard let accent = NSColor.controlAccentColor.usingColorSpace(.sRGB) else { return .white }
        func linear(_ channel: CGFloat) -> CGFloat {
            channel <= 0.04045 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
        }
        let luminance = 0.2126 * linear(accent.redComponent) + 0.7152 * linear(accent.greenComponent) + 0.0722 * linear(accent.blueComponent)
        return luminance > 0.5 ? .black : .white
    }
}
