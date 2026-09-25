import AppKit
import SwiftUI

struct StudioCanvas: View {
    var body: some View {
        VStack(spacing: 0) {
            CanvasHeader()
                .padding(.horizontal, 28)
                .padding(.top, 4)
                .padding(.bottom, 10)
            GeometryReader { proxy in
                ArtworkView()
                    .frame(maxWidth: max(0, min(proxy.size.width - 64, 920)), maxHeight: max(0, proxy.size.height - 24))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            ColorTray()
                .padding(.top, 14)
                .padding(.bottom, 20)
                .padding(.horizontal, 24)
        }
    }
}

// MARK: - Header

private struct CanvasHeader: View {
    var body: some View {
        HStack(alignment: .center, spacing: 4) {
            GradientNameField()
                .layoutPriority(1)
            NameSuggestionButton()
            Spacer(minLength: 12)
            CanvasSizeMenu()
        }
    }
}

/// Sized to its text, so the suggestion button sits right after the name.
private struct GradientNameField: View {
    @EnvironmentObject private var model: StudioModel
    @State private var draft = ""
    @State private var editingID: UUID?
    @FocusState private var focused: Bool

    var body: some View {
        Text(draft.isEmpty ? "Name" : draft)
            .font(.title2.weight(.semibold))
            .lineLimit(1)
            .padding(.trailing, 6)
            .hidden()
            .overlay(alignment: .leading) {
                TextField("Name", text: $draft)
                    .textFieldStyle(.plain)
                    .font(.title2.weight(.semibold))
                    .focused($focused)
                    .onSubmit {
                        commit()
                        focused = false
                    }
            }
            .onChange(of: focused) { _, isFocused in
                if isFocused { editingID = model.currentGradientID } else { commit() }
            }
            .onAppear { draft = model.currentName }
            .onChange(of: model.currentName) { _, name in
                if !focused { draft = name }
            }
            .onChange(of: model.currentGradientID) { _, _ in
                if focused { commit() }
                draft = model.currentName
            }
            .onChange(of: model.renameRequest) { _, _ in
                draft = model.currentName
                focused = true
            }
            .help("Click to rename")
            .accessibilityLabel("Gradient name")
    }

    private func commit() {
        guard let id = editingID ?? model.currentGradientID else { return }
        editingID = nil
        if let gradient = model.gradients.first(where: { $0.id == id }), gradient.name != draft {
            model.renameGradient(id: id, to: draft)
        }
        draft = model.currentName
    }
}

private struct NameSuggestionButton: View {
    @EnvironmentObject private var model: StudioModel
    @State private var showsSuggestions = false

    var body: some View {
        Button {
            model.prepareNameSuggestions()
            showsSuggestions = true
        } label: {
            Image(systemName: model.canUseIntelligence ? "sparkles" : "dice")
                .font(.system(size: 14, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)
                .frame(width: 24, height: 24)
        }
        .buttonStyle(.borderless)
        .help("Suggest a name")
        .accessibilityLabel("Suggest a name")
        .popover(isPresented: $showsSuggestions, arrowEdge: .bottom) {
            NameSuggestionList(isPresented: $showsSuggestions)
                .environmentObject(model)
        }
    }
}

private struct NameSuggestionList: View {
    @EnvironmentObject private var model: StudioModel
    @Binding var isPresented: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(model.canUseIntelligence ? "Apple Intelligence Ideas" : "Name Ideas")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if model.isThinkingOfNames { ProgressView().controlSize(.small) }
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 4)

            ForEach(model.nameSuggestions, id: \.self) { name in
                SuggestionRow(name: name) {
                    model.renameCurrentGradient(name)
                    isPresented = false
                }
            }

            Divider().padding(.vertical, 4)
            HStack {
                Button("More Ideas", systemImage: "arrow.clockwise") { model.suggestNames() }
                Spacer()
                Button("Automatic") {
                    model.useAutomaticName()
                    isPresented = false
                }
                .help("Let the name follow the colors")
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
            .padding(.horizontal, 8)
        }
        .padding(10)
        .frame(width: 250)
    }
}

private struct SuggestionRow: View {
    let name: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(name)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(hovering ? Color.accentColor.opacity(0.16) : Color.clear, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

private struct CanvasSizeMenu: View {
    @EnvironmentObject private var model: StudioModel
    @State private var showsCustom = false

    var body: some View {
        Menu {
            ForEach(CanvasPreset.allCases) { preset in
                Toggle(preset.title, isOn: presetBinding(preset))
            }
            Divider()
            Button("Custom Size…") { showsCustom = true }
        } label: {
            Text("\(String(model.recipe.width)) × \(String(model.recipe.height))")
                .monospacedDigit()
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .foregroundStyle(.secondary)
        .help("Canvas size")
        .popover(isPresented: $showsCustom, arrowEdge: .bottom) {
            CustomSizeForm(isPresented: $showsCustom)
                .environmentObject(model)
        }
    }

    private func presetBinding(_ preset: CanvasPreset) -> Binding<Bool> {
        Binding(
            get: { CanvasPreset.matching(width: model.recipe.width, height: model.recipe.height) == preset },
            set: { if $0 { model.setCanvasSize(width: preset.size.width, height: preset.size.height) } }
        )
    }
}

private struct CustomSizeForm: View {
    @EnvironmentObject private var model: StudioModel
    @Binding var isPresented: Bool
    @State private var width = ""
    @State private var height = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Custom Size").font(.headline)
            HStack(spacing: 8) {
                TextField("Width", text: $width).frame(width: 72)
                Text("×").foregroundStyle(.secondary)
                TextField("Height", text: $height).frame(width: 72)
                Text("px").foregroundStyle(.secondary)
            }
            .textFieldStyle(.roundedBorder)
            .monospacedDigit()
            Text("128 to 8,192 pixels per side")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Cancel") { isPresented = false }
                    .keyboardShortcut(.cancelAction)
                Button("Apply", action: apply)
                    .keyboardShortcut(.defaultAction)
                    .disabled(parsed == nil)
            }
        }
        .padding(16)
        .onAppear {
            width = String(model.recipe.width)
            height = String(model.recipe.height)
        }
    }

    private var parsed: (width: Int, height: Int)? {
        guard let w = Int(width.filter(\.isNumber)), let h = Int(height.filter(\.isNumber)),
              (128...8192).contains(w), (128...8192).contains(h), w * h <= 33_554_432 else { return nil }
        return (w, h)
    }

    private func apply() {
        guard let size = parsed else { return }
        model.setCanvasSize(width: size.width, height: size.height)
        isPresented = false
    }
}

// MARK: - Artwork

private struct ArtworkView: View {
    @EnvironmentObject private var model: StudioModel
    @State private var hovering = false
    @State private var draggingHandle = false
    @State private var snappedKeys: Set<String> = []

    private var ratio: CGFloat { CGFloat(model.recipe.width) / CGFloat(max(model.recipe.height, 1)) }
    private var showsHandles: Bool { (hovering || draggingHandle) && model.recipe.mode != .tonal }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                surface(size: geometry.size)
                if showsHandles {
                    handles(in: geometry.size)
                        .transition(.opacity)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .coordinateSpace(name: "artworkCanvas")
            .animation(.easeOut(duration: 0.15), value: showsHandles)
        }
        .aspectRatio(ratio, contentMode: .fit)
        .onHover { hovering = $0 }
        .overlay(alignment: .bottom) {
            CanvasToast().padding(14)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Gradient artwork")
    }

    private var glow: Color {
        guard let hex = model.recipe.stops.first?.hex else { return .clear }
        return Hex.color(hex)
    }

    private func surface(size: CGSize) -> some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        return ZStack {
            shape.fill(Color(nsColor: .controlBackgroundColor))
            if let image = model.preview {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFill()
                    .frame(width: size.width, height: size.height)
                    .id(model.previewIdentity)
                    .transition(.opacity)
            } else {
                ProgressView().controlSize(.small)
            }
        }
        .frame(width: size.width, height: size.height)
        .clipShape(shape)
        .overlay { shape.strokeBorder(.white.opacity(0.16), lineWidth: 1) }
        .background {
            // Shadows come from a plain shape, so they don't re-render with every preview.
            shape
                .fill(glow.opacity(0.5))
                .shadow(color: glow.opacity(0.45), radius: 30, y: 16)
                .shadow(color: .black.opacity(0.18), radius: 6, y: 3)
        }
        .contentShape(shape)
        .onDrag { model.dragItemProvider() }
        .focusable()
        .focusEffectDisabled()
        .onCopyCommand { model.copyItemProvider().map { [$0] } ?? [] }
        .help("Drag into Finder, Canva or any app to export")
    }

    @ViewBuilder private func handles(in size: CGSize) -> some View {
        switch model.recipe.mode {
        case .organic:
            ForEach(Array(model.recipe.stops.enumerated()), id: \.element.id) { index, stop in
                PointHandle(color: stop.color)
                    .position(x: CGFloat(stop.x) * size.width, y: CGFloat(stop.y) * size.height)
                    .gesture(pointDrag(index: index, size: size))
                    .accessibilityLabel("Color \(index + 1) position")
            }
        case .radial:
            CenterHandle()
                .position(
                    x: CGFloat(min(max(model.recipe.centerX, -0.04), 1.04)) * size.width,
                    y: CGFloat(min(max(model.recipe.centerY, -0.04), 1.04)) * size.height
                )
                .gesture(centerDrag(size: size))
                .accessibilityLabel("Glow center")
        case .linear, .aurora:
            directionHandles(in: size)
        case .tonal:
            EmptyView()
        }
    }

    private func directionHandles(in size: CGSize) -> some View {
        let width = Double(size.width), height = Double(size.height)
        let radians = model.recipe.angleDegrees * .pi / 180
        let axisX = cos(radians), axisY = sin(radians)
        let offset = model.recipe.gradientPosition - 0.5
        let centerX = 0.5 + offset * axisX, centerY = 0.5 + offset * axisY
        let reach = 0.3
        let center = CGPoint(x: centerX * width, y: centerY * height)
        let head = CGPoint(x: (centerX + axisX * reach) * width, y: (centerY + axisY * reach) * height)
        let tail = CGPoint(x: (centerX - axisX * reach) * width, y: (centerY - axisY * reach) * height)
        let screenAngle = atan2(Double(head.y - center.y), Double(head.x - center.x))
        return ZStack {
            Path { path in
                path.move(to: tail)
                path.addLine(to: head)
            }
            .stroke(.white.opacity(0.9), style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [5, 5]))
            .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
            .allowsHitTesting(false)

            Circle()
                .fill(.white)
                .frame(width: 14, height: 14)
                .shadow(color: .black.opacity(0.35), radius: 3, y: 1)
                .frame(width: 30, height: 30)
                .contentShape(Circle())
                .position(center)
                .gesture(positionDrag(size: size))
                .accessibilityLabel("Gradient position")

            ZStack {
                Circle().fill(.white).frame(width: 24, height: 24)
                Image(systemName: "arrow.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.black.opacity(0.7))
                    .rotationEffect(.radians(screenAngle))
            }
            .shadow(color: .black.opacity(0.35), radius: 3, y: 1)
            .frame(width: 32, height: 32)
            .contentShape(Circle())
            .position(head)
            .gesture(angleDrag(size: size, centerX: centerX, centerY: centerY))
            .accessibilityLabel("Gradient angle")
        }
    }

    // MARK: Gestures

    private func canvasDrag(_ onChange: @escaping (CGPoint) -> Void) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named("artworkCanvas"))
            .onChanged { value in
                draggingHandle = true
                onChange(value.location)
            }
            .onEnded { _ in
                draggingHandle = false
                snappedKeys.removeAll()
            }
    }

    private func pointDrag(index: Int, size: CGSize) -> some Gesture {
        canvasDrag { location in
            guard model.recipe.stops.indices.contains(index), size.width > 0, size.height > 0 else { return }
            var stop = model.recipe.stops[index]
            stop.x = snap(clamp(Double(location.x / size.width), 0, 1), key: "x\(index)")
            stop.y = snap(clamp(Double(location.y / size.height), 0, 1), key: "y\(index)")
            model.recipe.stops[index] = stop
        }
    }

    private func centerDrag(size: CGSize) -> some Gesture {
        canvasDrag { location in
            guard size.width > 0, size.height > 0 else { return }
            var recipe = model.recipe
            recipe.centerX = snap(clamp(Double(location.x / size.width), -1, 2), key: "cx")
            recipe.centerY = snap(clamp(Double(location.y / size.height), -1, 2), key: "cy")
            model.recipe = recipe
        }
    }

    private func positionDrag(size: CGSize) -> some Gesture {
        canvasDrag { location in
            guard size.width > 0, size.height > 0 else { return }
            let radians = model.recipe.angleDegrees * .pi / 180
            let projected = 0.5 + (Double(location.x / size.width) - 0.5) * cos(radians) + (Double(location.y / size.height) - 0.5) * sin(radians)
            model.recipe.gradientPosition = snap(clamp(projected, 0, 1), key: "position")
        }
    }

    private func angleDrag(size: CGSize, centerX: Double, centerY: Double) -> some Gesture {
        canvasDrag { location in
            guard size.width > 0, size.height > 0 else { return }
            let dx = Double(location.x / size.width) - centerX
            let dy = Double(location.y / size.height) - centerY
            guard dx * dx + dy * dy > 0.0004 else { return }
            var degrees = atan2(dy, dx) * 180 / .pi
            if degrees < 0 { degrees += 360 }
            model.recipe.angleDegrees = snap(degrees, key: "angle", targets: [0, 45, 90, 135, 180, 225, 270, 315, 360], tolerance: 3)
        }
    }

    /// Pulls a value onto a guide and taps the trackpad once as it lands.
    private func snap(_ value: Double, key: String, targets: [Double] = [0.5], tolerance: Double = 0.015) -> Double {
        if let target = targets.first(where: { abs($0 - value) < tolerance }) {
            if !snappedKeys.contains(key) {
                snappedKeys.insert(key)
                NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
            }
            return target
        }
        snappedKeys.remove(key)
        return value
    }

    private func clamp(_ value: Double, _ lower: Double, _ upper: Double) -> Double { min(max(value, lower), upper) }
}

private struct PointHandle: View {
    let color: Color

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 22, height: 22)
            .overlay { Circle().strokeBorder(.white, lineWidth: 2.5) }
            .shadow(color: .black.opacity(0.35), radius: 3, y: 1)
            .frame(width: 34, height: 34)
            .contentShape(Circle())
    }
}

private struct CenterHandle: View {
    var body: some View {
        ZStack {
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
        .contentShape(Circle())
    }
}

private struct CanvasToast: View {
    @EnvironmentObject private var model: StudioModel

    var body: some View {
        Group {
            if model.isRendering {
                HStack(spacing: 7) {
                    ProgressView().controlSize(.small)
                    Text("Rendering full-size image")
                }
                .toastStyle()
            } else if let toast = model.toast {
                Text(toast)
                    .toastStyle()
                    .id(toast)
            }
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .allowsHitTesting(false)
    }
}

private extension View {
    func toastStyle() -> some View {
        font(.callout.weight(.medium))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.regularMaterial, in: Capsule())
            .shadow(color: .black.opacity(0.15), radius: 8, y: 3)
    }
}

// MARK: - Color tray

private struct ColorTray: View {
    @EnvironmentObject private var model: StudioModel
    @State private var dragID: UUID?
    @State private var dragStartIndex = 0
    @State private var dragTranslation: CGSize = .zero

    /// Chip width plus spacing: how far a drag travels to move one place.
    private let slot: CGFloat = 40
    private let removeDistance: CGFloat = 56

    private var visibleStops: [ColorStop] {
        model.recipe.mode == .tonal ? Array(model.recipe.stops.prefix(1)) : model.recipe.stops
    }

    var body: some View {
        HStack(spacing: 10) {
            if model.recipe.stops.isEmpty {
                Text(model.recipe.mode == .tonal ? "Pick a base color" : "Add colors from your collections")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 6)
            }
            ForEach(visibleStops) { stop in
                let isDragging = dragID == stop.id
                StopChip(stop: stop, isLifted: isDragging, isRemoving: isDragging && abs(dragTranslation.height) > removeDistance)
                    .offset(isDragging ? dragOffset(for: stop) : .zero)
                    .zIndex(isDragging ? 1 : 0)
                    .transaction { transaction in
                        // The lifted chip tracks the pointer exactly; only its neighbors animate.
                        if isDragging { transaction.animation = nil }
                    }
                    .gesture(reorderGesture(for: stop))
                    .transition(.scale.combined(with: .opacity))
            }
            if model.canAddStop {
                AddStopButton()
            }
            if !model.recipe.stops.isEmpty {
                Divider().frame(height: 22)
                Button {
                    model.removeAllColors()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help("Remove all colors")
                .accessibilityLabel("Remove all colors")
            }
        }
        .coordinateSpace(name: "tray")
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: Capsule())
        .overlay { Capsule().strokeBorder(Color.primary.opacity(0.1), lineWidth: 1) }
        .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
        .animation(.spring(response: 0.3, dampingFraction: 0.78), value: model.recipe.stops.map(\.id))
    }

    private func dragOffset(for stop: ColorStop) -> CGSize {
        guard let index = model.recipe.stops.firstIndex(where: { $0.id == stop.id }) else { return .zero }
        return CGSize(width: dragTranslation.width - CGFloat(index - dragStartIndex) * slot, height: dragTranslation.height)
    }

    /// Dock-style dragging: the chip follows the pointer, neighbors slide aside as it passes,
    /// and pulling it well above or below the tray removes it.
    private func reorderGesture(for stop: ColorStop) -> some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .named("tray"))
            .onChanged { value in
                if dragID != stop.id {
                    dragID = stop.id
                    dragStartIndex = model.recipe.stops.firstIndex { $0.id == stop.id } ?? 0
                }
                dragTranslation = value.translation
                guard model.recipe.mode != .tonal, !model.recipe.stops.isEmpty else { return }
                let steps = Int((value.translation.width / slot).rounded())
                let target = min(max(dragStartIndex + steps, 0), model.recipe.stops.count - 1)
                if let current = model.recipe.stops.firstIndex(where: { $0.id == stop.id }), current != target {
                    model.moveColor(id: stop.id, toIndex: target)
                }
            }
            .onEnded { value in
                let remove = abs(value.translation.height) > removeDistance
                withAnimation(.spring(response: 0.32, dampingFraction: 0.75)) {
                    dragID = nil
                    dragTranslation = .zero
                    if remove { model.removeColor(id: stop.id) }
                }
            }
    }
}

private struct StopChip: View {
    @EnvironmentObject private var model: StudioModel
    let stop: ColorStop
    let isLifted: Bool
    let isRemoving: Bool
    @State private var editing = false
    @State private var hovering = false

    private var name: String { model.libraryName(for: stop.hex) ?? ColorNamer.name(stop.hex) }

    var body: some View {
        ColorDot(hex: stop.hex, size: 30)
            .shadow(color: .black.opacity(isLifted ? 0.3 : 0), radius: 8, y: 5)
            .scaleEffect(isRemoving ? 0.8 : (isLifted ? 1.18 : (hovering ? 1.08 : 1)))
            .opacity(isRemoving ? 0.4 : 1)
            .overlay(alignment: .top) {
                if isRemoving {
                    Text("Remove")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.regularMaterial, in: Capsule())
                        .fixedSize()
                        .offset(y: -24)
                }
            }
            .animation(.spring(response: 0.25, dampingFraction: 0.65), value: hovering)
            .animation(.spring(response: 0.25, dampingFraction: 0.65), value: isLifted)
            .animation(.easeOut(duration: 0.15), value: isRemoving)
            .contentShape(Circle())
            .onHover { hovering = $0 }
            .onTapGesture { editing = true }
            .popover(isPresented: $editing, arrowEdge: .top) {
                StopEditor(stopID: stop.id, dismiss: { editing = false })
                    .environmentObject(model)
            }
            .contextMenu {
                Button("Duplicate") { model.duplicateColor(id: stop.id) }
                    .disabled(!model.canAddStop || model.recipe.mode == .tonal)
                Button("Copy Hex") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString("#" + stop.hex, forType: .string)
                }
                Divider()
                Button("Remove", role: .destructive) { model.removeColor(id: stop.id) }
            }
            .help("\(name) · #\(stop.hex). Click to edit, drag to reorder, drag away to remove.")
            .accessibilityElement()
            .accessibilityLabel("\(name), \(stop.hex)")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { editing = true }
    }
}

private struct StopEditor: View {
    @EnvironmentObject private var model: StudioModel
    let stopID: UUID
    let dismiss: () -> Void

    private var stop: ColorStop? { model.recipe.stops.first { $0.id == stopID } }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let stop {
                HStack(spacing: 10) {
                    ColorPicker("Color", selection: colorBinding, supportsOpacity: false)
                        .labelsHidden()
                    HexField(label: "Hex color", value: hexBinding)
                        .frame(width: 96)
                }
                Text(model.libraryName(for: stop.hex) ?? ColorNamer.name(stop.hex))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack {
                    Button("Duplicate", systemImage: "plus.square.on.square") { model.duplicateColor(id: stopID) }
                        .disabled(!model.canAddStop || model.recipe.mode == .tonal)
                    Spacer()
                    Button("Remove", systemImage: "minus.circle", role: .destructive) {
                        // Close the popover before its anchor disappears.
                        dismiss()
                        let target = self.model
                        let id = stopID
                        Task { @MainActor in
                            try? await Task.sleep(nanoseconds: 200_000_000)
                            target.removeColor(id: id)
                        }
                    }
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
            }
        }
        .padding(14)
        .frame(width: 230)
    }

    private var colorBinding: Binding<Color> {
        Binding(
            get: { Hex.color(stop?.hex ?? "000000") },
            set: { model.setColor(hex: Hex.string(from: $0), for: stopID) }
        )
    }

    private var hexBinding: Binding<String> {
        Binding(
            get: { stop?.hex ?? "" },
            set: { model.setColor(hex: $0, for: stopID) }
        )
    }
}

private struct AddStopButton: View {
    @EnvironmentObject private var model: StudioModel
    @State private var showsPicker = false
    @State private var custom = Color(red: 0.84, green: 0.83, blue: 0.78)

    var body: some View {
        Button {
            showsPicker = true
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 12, weight: .bold))
                .frame(width: 30, height: 30)
                .overlay {
                    Circle().strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
                }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .help("Add a color")
        .accessibilityLabel("Add a color")
        .popover(isPresented: $showsPicker, arrowEdge: .top) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Related Tones")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                HStack(spacing: 10) {
                    ForEach(Array(model.suggestedColors().enumerated()), id: \.offset) { _, hex in
                        Button {
                            model.addColor(hex: hex)
                            showsPicker = model.canAddStop
                        } label: {
                            ColorDot(hex: hex, size: 26)
                        }
                        .buttonStyle(.plain)
                        .help("#\(hex)")
                        .accessibilityLabel("Add \(ColorNamer.name(hex))")
                    }
                }
                Divider()
                HStack {
                    ColorPicker("Custom", selection: $custom, supportsOpacity: false)
                    Spacer()
                    Button("Add") {
                        model.addColor(hex: Hex.string(from: custom))
                        showsPicker = false
                    }
                }
            }
            .padding(14)
            .frame(width: 240)
        }
    }
}
