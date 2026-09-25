import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject private var model: StudioModel
    @State private var showsHandles = false
    @State private var paletteName = ""
    @State private var showsSaveGradientPreset = false
    @State private var gradientPresetPendingRemoval: BrandPalette?
    @State private var draggedColorID: UUID?

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 220, ideal: 250, max: 320)
        } content: {
            workspace
                .navigationSplitViewColumnWidth(min: 430, ideal: 630)
        } detail: {
            inspector
                .navigationSplitViewColumnWidth(290)
        }
        .navigationSplitViewStyle(.balanced)
        .background(FocusClearingMonitor())
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
        .labelStyle(.iconOnly)
        .onChange(of: model.recipe) { _, _ in
            model.refreshPreview()
        }
        .onChange(of: model.recipe.mode) { _, _ in
            withAnimation(.smooth(duration: 0.18)) {
                showsHandles = false
            }
        }
        .onExitCommand {
            withAnimation(.smooth(duration: 0.18)) {
                showsHandles = false
            }
        }
        .alert("Couldn’t complete that action", isPresented: errorIsPresented) {
            Button("OK", role: .cancel) { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "Unknown error")
        }
        .sheet(isPresented: $showsSaveGradientPreset) {
            saveGradientPresetSheet
        }
        .confirmationDialog(
            gradientPresetPendingRemoval.map { "Remove \"\($0.name)\"?" } ?? "Remove gradient preset?",
            isPresented: gradientPresetRemovalIsPresented,
            titleVisibility: .visible
        ) {
            Button("Remove Gradient Preset", role: .destructive) {
                if let preset = gradientPresetPendingRemoval {
                    model.removeGradientPreset(id: preset.id)
                }
                gradientPresetPendingRemoval = nil
            }
            Button("Cancel", role: .cancel) { gradientPresetPendingRemoval = nil }
        } message: {
            Text("This can’t be undone.")
        }
    }

    private var errorIsPresented: Binding<Bool> {
        Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )
    }

    private var gradientPresetRemovalIsPresented: Binding<Bool> {
        Binding(
            get: { gradientPresetPendingRemoval != nil },
            set: { if !$0 { gradientPresetPendingRemoval = nil } }
        )
    }

    private var sidebar: some View {
        List {
            Section {
                Text("Color library")
                    .font(.title3.weight(.semibold))
                .padding(.vertical, 5)
            }

            Section("Palettes") {
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
                        .accessibilityLabel("Apply \(palette.name) gradient preset")
                        .contextMenu {
                            Button("Remove Gradient Preset", systemImage: "trash", role: .destructive) {
                                gradientPresetPendingRemoval = palette
                            }
                        }
                    }
                }
                Divider()
                HStack(spacing: 8) {
                    Button("Add gradient preset", systemImage: "plus") {
                        paletteName = ""
                        showsSaveGradientPreset = true
                    }
                    .labelStyle(.iconOnly)
                    .controlSize(.small)
                    .help("Save the current gradient as a preset")
                    Spacer()
                    Menu {
                        Button("Import Gradient Presets…", systemImage: "square.and.arrow.down") {
                            model.importGradientPresetsFromPanel()
                        }
                        Button("Export Gradient Presets…", systemImage: "square.and.arrow.up") {
                            model.exportGradientPresets()
                        }
                        .disabled(model.palettes.isEmpty)
                    } label: {
                        Label("Manage gradient presets", systemImage: "ellipsis.circle")
                    }
                    .labelStyle(.iconOnly)
                    .controlSize(.small)
                    .help("Import or export gradient presets")
                }
            }
        }
        .listStyle(.sidebar)
    }

    private var workspace: some View {
        GeometryReader { proxy in
            VStack(spacing: 16) {
                artwork
                    .frame(maxWidth: min(proxy.size.width - 48, 880), maxHeight: proxy.size.height - 32)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                Spacer(minLength: 16)
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
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(.black.opacity(0.10), lineWidth: 1)
                    if showsHandles && model.recipe.mode == .radial {
                        radialCenterHandle(in: geometry.size)
                    }
                    if showsHandles && (model.recipe.mode == .linear || model.recipe.mode == .softLinear || model.recipe.mode == .magicLinear) {
                        linearDirectionHandles(in: geometry.size)
                    }
                    if showsHandles && supportsCanvasHandles {
                        VStack {
                            canvasEditingStatusPill
                                .padding(.top, 14)
                            Spacer()
                        }
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
            }
            .shadow(color: .black.opacity(0.12), radius: 18, y: 7)
        }
        .aspectRatio(CGFloat(model.recipe.width) / CGFloat(max(model.recipe.height, 1)), contentMode: .fit)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Gradient artwork preview")
    }

    private var inspector: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                inspectorCard(title: "Canvas") {
                    Picker("Preset", selection: dimensionPreset) {
                        Text("4K").tag("3840x2160")
                        Text("Instagram").tag("2160x2880")
                        Text("Desktop").tag("2560x1440")
                        Text("Square").tag("2048x2048")
                        Text("Portrait").tag("1440x2560")
                        Text("Custom").tag("custom")
                    }
                    .pickerStyle(.menu)

                    HStack(spacing: 8) {
                        DimensionField(title: "Width", value: intBinding(\.width), peer: intBinding(\.height))
                        Text("×").foregroundStyle(.secondary)
                        DimensionField(title: "Height", value: intBinding(\.height), peer: intBinding(\.width))
                    }
                }

                inspectorCard(title: "Colors", reset: model.removeAllColors) {
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
                            .onDrop(of: [.text], delegate: ColorStopDropDelegate(targetID: stop.id, draggedID: $draggedColorID, model: model))
                        if index < model.recipe.stops.count - 1 {
                            Divider()
                        }
                    }
                    Button("Add color", systemImage: "plus") {
                        model.addColor(hex: "D7D3C7")
                    }
                    .labelStyle(.iconOnly)
                    .controlSize(.small)
                    .help("Add a color")
                }
                }

                inspectorCard(title: "Color suggestions") {
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

                inspectorCard(
                    title: "Gradient",
                    reset: model.resetGradientSettings
                ) {
                    Picker("Type", selection: modeBinding) {
                        ForEach(GradientMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.menu)
                    gradientControls
                    if supportsCanvasHandles {
                        canvasEditingControl
                    }
                }

                inspectorCard(
                    title: "Texture",
                    enabled: boolBinding(\.isTextureEnabled),
                    reset: model.resetTextureSettings
                ) {
                    SliderControl(title: "Grain", value: doubleBinding(\.grain), range: 0...0.5, valueText: percent(model.recipe.grain))
                    SliderControl(title: "Grain size", value: doubleBinding(\.grainSize), range: 0.5...3, valueText: String(format: "%.1f×", model.recipe.grainSize))
                }

            }
            .padding(16)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    @ViewBuilder private var gradientControls: some View {
        switch model.recipe.mode {
        case .organic:
            SliderControl(title: "Flow", value: doubleBinding(\.flow), range: 0...1, valueText: percent(model.recipe.flow))
            SliderControl(title: "Softness", value: doubleBinding(\.softness), range: 0...1, valueText: percent(model.recipe.softness))
        case .linear:
            linearGeometryControls
            SliderControl(title: "Ease", value: doubleBinding(\.easing), range: 0...1, valueText: percent(model.recipe.easing))
        case .softLinear:
            linearGeometryControls
            SliderControl(title: "Softness", value: doubleBinding(\.softness), range: 0...1, valueText: percent(model.recipe.softness))
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
            SeedControl(seed: seedBinding) {
                model.recipe.seed = UInt64.random(in: 1...UInt64.max)
            }
        case .radial:
            SliderControl(title: "Center X", value: doubleBinding(\.centerX), range: -1...2, valueText: percent(model.recipe.centerX))
            SliderControl(title: "Center Y", value: doubleBinding(\.centerY), range: -1...2, valueText: percent(model.recipe.centerY))
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
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4), spacing: 6) {
            ForEach([0.0, 45, 90, 135, 180, 225, 270, 315], id: \.self) { angle in
                LinearAnglePresetButton(
                    angle: angle,
                    isSelected: angularDistance(model.recipe.angleDegrees, angle) < 0.5
                ) {
                    model.setLinearPreset(angle: angle)
                }
            }
        }
        SliderControl(title: "Fade width", value: doubleBinding(\.fadeWidth), range: 0.15...1.5, valueText: percent(model.recipe.fadeWidth))
    }

    private func colorRow(index: Int, stop: ColorStop, canRemove: Bool = true) -> some View {
        HStack(spacing: 9) {
            if canRemove {
                Image(systemName: "line.3.horizontal")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .frame(width: 24, height: 30)
                    .contentShape(Rectangle())
                    .onDrag {
                        draggedColorID = stop.id
                        return NSItemProvider(object: stop.id.uuidString as NSString)
                    } preview: {
                        Color.clear
                            .frame(width: 1, height: 1)
                    }
                    .help("Drag to reorder")
            }
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
                .help("Remove color")
            }
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .contextMenu {
            if canRemove {
                Button("Duplicate Color", systemImage: "plus.square.on.square") { model.duplicateColor(id: stop.id) }
                    .disabled(model.recipe.stops.count >= 8)
                Divider()
                Button("Remove Color", systemImage: "trash", role: .destructive) { model.removeColor(id: stop.id) }
            }
        }
        .help(canRemove ? "Drag to reorder. Right-click for duplicate or remove." : "Base color")
    }

    private func linearDirectionHandles(in size: CGSize) -> some View {
        ZStack {
            Path { path in
                path.move(to: CGPoint(x: model.recipe.linearStartX * Double(size.width), y: model.recipe.linearStartY * Double(size.height)))
                path.addLine(to: CGPoint(x: model.recipe.linearEndX * Double(size.width), y: model.recipe.linearEndY * Double(size.height)))
            }
            .stroke(.white.opacity(0.9), style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
            linearHandle(isStart: true, in: size)
            linearHandle(isStart: false, in: size)
        }
    }

    private func linearHandle(isStart: Bool, in size: CGSize) -> some View {
        let x = isStart ? model.recipe.linearStartX : model.recipe.linearEndX
        let y = isStart ? model.recipe.linearStartY : model.recipe.linearEndY
        return Circle()
            .fill(isStart ? Color.black.opacity(0.75) : Color.white)
            .frame(width: 22, height: 22)
            .overlay(Circle().stroke(isStart ? .white : .black.opacity(0.65), lineWidth: 2))
            .shadow(color: .black.opacity(0.35), radius: 3, y: 1)
            .position(x: CGFloat(x) * size.width, y: CGFloat(y) * size.height)
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .named("artworkCanvas"))
                    .onChanged { value in
                        guard size.width > 0, size.height > 0 else { return }
                        let newX = min(max(Double(value.location.x / size.width), 0), 1)
                        let newY = min(max(Double(value.location.y / size.height), 0), 1)
                        if isStart { model.recipe.linearStartX = newX; model.recipe.linearStartY = newY }
                        else { model.recipe.linearEndX = newX; model.recipe.linearEndY = newY }
                        let dx = model.recipe.linearEndX - model.recipe.linearStartX
                        let dy = model.recipe.linearEndY - model.recipe.linearStartY
                        model.recipe.angleDegrees = (atan2(dy, dx) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
                    }
            )
            .accessibilityLabel(isStart ? "Linear gradient start point" : "Linear gradient end point")
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

    private func radialCenterHandle(in size: CGSize) -> some View {
        let displayX = min(max(model.recipe.centerX, -0.06), 1.06)
        let displayY = min(max(model.recipe.centerY, -0.06), 1.06)
        return ZStack {
            Circle()
                .fill(.black.opacity(0.18))
                .frame(width: 30, height: 30)
            Circle()
                .stroke(.white, lineWidth: 2)
                .frame(width: 20, height: 20)
            Path { path in
                path.move(to: CGPoint(x: 4, y: 15)); path.addLine(to: CGPoint(x: 26, y: 15))
                path.move(to: CGPoint(x: 15, y: 4)); path.addLine(to: CGPoint(x: 15, y: 26))
            }
            .stroke(.white, lineWidth: 1.5)
            .frame(width: 30, height: 30)
        }
        .shadow(color: .black.opacity(0.35), radius: 3, y: 1)
        .position(x: CGFloat(displayX) * size.width, y: CGFloat(displayY) * size.height)
        .gesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .named("artworkCanvas"))
                .onChanged { value in
                    guard size.width > 0, size.height > 0 else { return }
                    model.recipe.centerX = min(max(Double(value.location.x / size.width), -1), 2)
                    model.recipe.centerY = min(max(Double(value.location.y / size.height), -1), 2)
                }
        )
        .accessibilityLabel("Move radial glow center")
        .accessibilityHint("Drag on or beyond the artwork edge, or use Center X and Center Y controls for farther off-canvas placement")
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
        Binding(
            get: { model.recipe.mode },
            set: { newMode in
                let previousMode = model.recipe.mode
                model.recipe.mode = newMode
                if newMode == .aurora, previousMode != .aurora {
                    model.recipe.colorArc = 0
                }
            }
        )
    }

    private var seedBinding: Binding<UInt64> {
        Binding(get: { model.recipe.seed }, set: { model.recipe.seed = $0 })
    }

    private var handleToggleTitle: String {
        switch model.recipe.mode {
        case .organic: "Edit points"
        case .radial: "Edit center"
        case .linear, .softLinear, .magicLinear: "Edit direction"
        default: "Edit"
        }
    }

    private var supportsCanvasHandles: Bool {
        switch model.recipe.mode {
        case .organic, .radial, .linear, .softLinear, .magicLinear: true
        case .magicSingle, .aurora: false
        }
    }

    private var canvasEditingControl: some View {
        Button {
            withAnimation(.smooth(duration: 0.2)) {
                showsHandles.toggle()
            }
        } label: {
            HStack(spacing: 7) {
                Image(systemName: showsHandles ? "checkmark.circle.fill" : "viewfinder")
                Text(handleToggleTitle)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .tint(showsHandles ? .accentColor : nil)
        .help(showsHandles ? "Finish editing on the artwork" : handleToggleHint)
        .accessibilityLabel(showsHandles ? "Finish \(handleToggleTitle.lowercased())" : handleToggleTitle)
    }

    private var canvasEditingStatusPill: some View {
        HStack(spacing: 9) {
            Image(systemName: editingStatusIcon)
                .foregroundStyle(Color.accentColor)
            Text(editingStatusTitle)
                .fontWeight(.medium)
            Divider()
                .frame(height: 14)
            Text(editingStatusDetail)
                .monospacedDigit()
                .foregroundStyle(.secondary)
            Button("Done") {
                withAnimation(.smooth(duration: 0.18)) {
                    showsHandles = false
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .keyboardShortcut(.return, modifiers: [])
        }
        .font(.caption)
        .padding(.leading, 12)
        .padding(.trailing, 7)
        .padding(.vertical, 7)
        .background(.regularMaterial, in: Capsule())
        .overlay {
            Capsule()
                .strokeBorder(.white.opacity(0.11), lineWidth: 0.5)
        }
        .shadow(color: .black.opacity(0.2), radius: 8, y: 3)
        .accessibilityElement(children: .contain)
    }

    private var editingStatusIcon: String {
        switch model.recipe.mode {
        case .organic: "point.3.connected.trianglepath.dotted"
        case .radial: "scope"
        case .linear, .softLinear, .magicLinear: "arrow.left.and.right"
        default: "viewfinder"
        }
    }

    private var editingStatusTitle: String {
        switch model.recipe.mode {
        case .organic: "Adjust Gradient Points"
        case .radial: "Adjust Gradient Center"
        case .linear, .softLinear, .magicLinear: "Adjust Gradient Direction"
        default: "Adjust Gradient"
        }
    }

    private var editingStatusDetail: String {
        switch model.recipe.mode {
        case .organic:
            "\(model.recipe.stops.count) points"
        case .radial:
            "X \(percent(model.recipe.centerX))  Y \(percent(model.recipe.centerY))"
        case .linear, .softLinear, .magicLinear:
            "\(Int(model.recipe.angleDegrees.rounded()))°"
        default:
            ""
        }
    }

    private var handleToggleHint: String {
        switch model.recipe.mode {
        case .organic: "Show and move color points on the artwork"
        case .radial: "Show and move the radial glow center"
        case .linear, .softLinear, .magicLinear: "Show and move the linear gradient start and end points"
        default: "Show editing controls on the artwork"
        }
    }

    private func inspectorCard<Content: View>(
        title: String,
        enabled: Binding<Bool>? = nil,
        reset: (() -> Void)? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 9) {
                Text(title)
                    .font(.headline)
                Spacer()
                if let reset {
                    Button("Reset \(title)", systemImage: "arrow.counterclockwise", action: reset)
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                        .help("Reset \(title.lowercased()) settings")
                }
                if let enabled {
                    Toggle("Enable \(title)", isOn: enabled)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                }
            }

            if enabled?.wrappedValue ?? true {
                VStack(alignment: .leading, spacing: 10) {
                    content()
                }
                .padding(.top, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(13)
        .background(.quaternary.opacity(0.34), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .animation(.smooth(duration: 0.24), value: enabled?.wrappedValue ?? true)
    }

    private func doubleBinding(_ keyPath: WritableKeyPath<GradientRecipe, Double>) -> Binding<Double> {
        Binding(get: { model.recipe[keyPath: keyPath] }, set: { model.recipe[keyPath: keyPath] = $0 })
    }

    private func boolBinding(_ keyPath: WritableKeyPath<GradientRecipe, Bool>) -> Binding<Bool> {
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

    private var saveGradientPresetSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("New Gradient Preset")
                .font(.title2.weight(.semibold))
            Text("Save the current gradient colors as a reusable preset.")
                .foregroundStyle(.secondary)
            TextField("Preset name", text: $paletteName)
                .onSubmit(savePalette)
            HStack {
                Button("Cancel") {
                    paletteName = ""
                    showsSaveGradientPreset = false
                }
                .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Save") { savePalette() }
                    .disabled(paletteName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 390)
    }

    private func savePalette() {
        let name = paletteName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        model.savePalette(name: name)
        paletteName = ""
        showsSaveGradientPreset = false
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

    private func angularDistance(_ first: Double, _ second: Double) -> Double {
        let difference = abs(first.truncatingRemainder(dividingBy: 360) - second.truncatingRemainder(dividingBy: 360))
        return min(difference, 360 - difference)
    }
}

private struct LinearAnglePresetButton: View {
    let angle: Double
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "arrow.right")
                .font(.system(size: 13, weight: .semibold))
                .rotationEffect(.degrees(angle))
                .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                .frame(maxWidth: .infinity, minHeight: 27)
                .background(
                    isSelected ? Color.accentColor.opacity(0.14) : Color.primary.opacity(0.055),
                    in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(isSelected ? Color.accentColor.opacity(0.75) : Color.primary.opacity(0.08))
                }
        }
        .buttonStyle(.plain)
        .help("Set gradient direction to \(Int(angle))°")
        .accessibilityLabel("\(Int(angle)) degree gradient")
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

private struct SeedControl: View {
    @Binding var seed: UInt64
    let randomize: () -> Void

    var body: some View {
        HStack {
            Text("Pattern seed")
            Spacer()
            TextField("Pattern seed", value: $seed, format: .number)
                .labelsHidden()
                .multilineTextAlignment(.trailing)
                .font(.system(.caption, design: .monospaced))
                .frame(width: 96)
            Button("New seed", systemImage: "dice") { randomize() }
                .labelStyle(.iconOnly)
                .help("Generate a new underlying pattern")
        }
        .font(.caption)
    }
}

private struct ColorStopDropDelegate: DropDelegate {
    let targetID: UUID
    @Binding var draggedID: UUID?
    let model: StudioModel

    func dropEntered(info: DropInfo) {
        guard let draggedID, draggedID != targetID,
              let source = model.recipe.stops.firstIndex(where: { $0.id == draggedID }),
              let target = model.recipe.stops.firstIndex(where: { $0.id == targetID }) else { return }
        withAnimation(.snappy) {
            model.moveColor(from: source, to: target)
        }
    }

    func performDrop(info: DropInfo) -> Bool {
        draggedID = nil
        return true
    }

    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }
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

private struct FocusClearingMonitor: NSViewRepresentable {
    func makeNSView(context: Context) -> FocusClearingMonitorView {
        FocusClearingMonitorView()
    }

    func updateNSView(_ nsView: FocusClearingMonitorView, context: Context) {}
}

private final class FocusClearingMonitorView: NSView {
    private var eventMonitor: Any?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            removeMonitor()
        } else if eventMonitor == nil {
            eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
                guard let self, let window = self.window, event.window === window,
                      let contentView = window.contentView else { return event }
                let point = contentView.convert(event.locationInWindow, from: nil)
                if !self.isTextInput(contentView.hitTest(point)) {
                    window.makeFirstResponder(nil)
                }
                return event
            }
        }
    }

    deinit { removeMonitor() }

    private func isTextInput(_ hitView: NSView?) -> Bool {
        var candidate = hitView
        while let view = candidate {
            if view is NSTextField || view is NSTextView { return true }
            candidate = view.superview
        }
        return false
    }

    private func removeMonitor() {
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
            self.eventMonitor = nil
        }
    }
}
