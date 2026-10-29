import AppKit
import DMKit
import SwiftUI

struct StudioCanvas: View {
    @Environment(StudioModel.self) private var model

    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { proxy in
                ArtworkView()
                    .frame(maxWidth: max(0, min(proxy.size.width - 64, 920)), maxHeight: max(0, proxy.size.height - 24))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(.top, 10)
            ColorTray()
                .padding(.top, 14)
                .padding(.bottom, 20)
                .padding(.horizontal, 24)
        }
        // The canvas column runs under the floating sidebar, and the split view counts
        // the sidebar twice when it adds up the window's minimum width: once for the sidebar column
        // and again inside this column's minimum. Any minimum here (the color tray's width) then
        // lands on top of that, so the canvas reports none and ContentView sets the window's minimum.
        .frame(minWidth: 0, maxWidth: .infinity)
        // The title is the native window title, with "Unsaved" as its subtitle for unsaved work; the
        // toolbar just carries the actions on the trailing side.
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { model.randomize() } label: { Label("Randomize", systemImage: "shuffle") }
                    .help("Randomize the layout (⌘R)")
            }
            ToolbarSpacer(.fixed, placement: .primaryAction)
            ToolbarItemGroup(placement: .primaryAction) {
                Button { model.copyImage() } label: { Label("Copy Image", systemImage: "doc.on.doc") }
                    .help("Copy the full-size image (⇧⌘C)")
                    .disabled(model.isRendering)
                Button { model.exportImage() } label: { Label("Export Image", systemImage: "square.and.arrow.up") }
                    .help("Export a PNG or JPEG (⌘E)")
                    .disabled(model.isRendering)
            }
        }
    }
}

struct CanvasSizeMenu: View {
    @Environment(StudioModel.self) private var model
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
                .environment(model)
        }
    }

    private func presetBinding(_ preset: CanvasPreset) -> Binding<Bool> {
        Binding(
            get: { CanvasPreset.matching(width: model.recipe.width, height: model.recipe.height) == preset },
            set: { if $0 { model.setCanvasSize(width: preset.size.width, height: preset.size.height) } }
        )
    }
}

/// Width and height fields for a canvas size that isn't a preset. Shown from the inspector's size
/// menu and from Gradient › Canvas Size › Custom Size….
struct CustomSizeForm: View {
    @Environment(StudioModel.self) private var model
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
    @Environment(StudioModel.self) private var model
    @State private var hovering = false
    @State private var draggingHandle = false
    @State private var snappedKeys: Set<String> = []
    /// The mesh point whose color popover is open; its handles stay visible meanwhile.
    @State private var editingVertex: Int?
    @State private var vertexDragOrigin: CGPoint?
    @State private var lastPointClick: (index: Int, time: Date)?

    private var ratio: CGFloat { CGFloat(model.recipe.width) / CGFloat(max(model.recipe.height, 1)) }
    private var modeHasHandles: Bool {
        switch model.recipe.mode {
        case .organic, .mesh, .radial, .linear, .aurora: true
        case .tonal: false
        }
    }
    private var showsHandles: Bool { (hovering || draggingHandle || model.pointsRevealed || editingVertex != nil) && modeHasHandles }

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
        .statusCapsule(Bindable(model).status)
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
            if let metal = RenderEngine.metal {
                MetalCanvas(recipe: model.recipe, renderer: metal)
                    .frame(width: size.width, height: size.height)
            } else if let image = model.preview {
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
            // Drag out and ⌘C; the handles sit above this, so they still get their own clicks.
            CanvasDragSource(model: model)
                .frame(width: size.width, height: size.height)
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
        .help("Drag into Finder, Canva or any app to export")
    }

    @ViewBuilder private func handles(in size: CGSize) -> some View {
        switch model.recipe.mode {
        case .mesh:
            meshHandles(in: size)
        case .organic:
            ForEach(Array(model.recipe.stops.enumerated()), id: \.element.id) { index, stop in
                PointHandle(color: stop.color, emphasized: stop.id == model.highlightedStopID)
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
        case .linear:
            linearHandles(in: size)
        case .aurora:
            directionHandles(in: size)
        case .tonal:
            EmptyView()
        }
    }

    /// The mesh grid, drawn along the same curves the renderer bends, with a handle on every point.
    private func meshHandles(in size: CGSize) -> some View {
        let vertices = model.meshVertices
        let gridSize = model.meshSize
        return ZStack {
            Path { path in
                let steps = 40
                for line in 0..<gridSize {
                    let fixed = Double(line) / Double(gridSize - 1)
                    for across in [true, false] {
                        for step in 0...steps {
                            let t = Double(step) / Double(steps)
                            let point = MeshGrid.point(on: vertices, size: gridSize, u: across ? t : fixed, v: across ? fixed : t)
                            let location = CGPoint(x: point.x * size.width, y: point.y * size.height)
                            if step == 0 { path.move(to: location) } else { path.addLine(to: location) }
                        }
                    }
                }
            }
            .stroke(.white.opacity(0.55), lineWidth: 1)
            .shadow(color: .black.opacity(0.3), radius: 1.5, y: 0.5)
            .allowsHitTesting(false)

            ForEach(vertices.indices, id: \.self) { index in
                let hex = vertices[index].hex
                PointHandle(
                    color: hex.isEmpty ? .clear : Hex.color(hex),
                    emphasized: model.highlightedMeshPoint == index,
                    selected: model.selectedMeshPoint == index
                )
                // The popover hangs off the handle itself (so it's attached before positioning), on
                // whichever side of the point has room.
                .popover(isPresented: Binding(get: { editingVertex == index }, set: { if !$0 { editingVertex = nil } }),
                         arrowEdge: MeshPointEditor.edge(x: vertices[index].x, y: vertices[index].y)) {
                    MeshPointEditor(index: index)
                        .environment(model)
                }
                .position(x: CGFloat(vertices[index].x) * size.width, y: CGFloat(vertices[index].y) * size.height)
                .gesture(vertexDrag(index: index, size: size))
                .accessibilityLabel("Mesh point \(index + 1)")
                .accessibilityAddTraits(model.selectedMeshPoint == index ? .isSelected : [])
                .accessibilityAction { model.selectMeshPoint(index) }
                .accessibilityAction(named: "Edit Color") { editingVertex = index }
            }
        }
    }

    /// Drags a mesh point from where it sits (so a click doesn't nudge it). A click selects the point
    /// for painting; a double-click opens its colors.
    private func vertexDrag(index: Int, size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named("artworkCanvas"))
            .onChanged { value in
                guard size.width > 0, size.height > 0 else { return }
                if vertexDragOrigin == nil {
                    guard hypot(value.translation.width, value.translation.height) > 3, model.meshVertices.indices.contains(index) else { return }
                    let vertex = model.meshVertices[index]
                    vertexDragOrigin = CGPoint(x: vertex.x, y: vertex.y)
                    draggingHandle = true
                }
                guard let origin = vertexDragOrigin else { return }
                let x = snap(Double(origin.x) + Double(value.translation.width / size.width), key: "mx\(index)")
                let y = snap(Double(origin.y) + Double(value.translation.height / size.height), key: "my\(index)")
                model.moveMeshVertex(index, x: x, y: y)
            }
            .onEnded { _ in
                if vertexDragOrigin == nil {
                    let now = Date()
                    if let last = lastPointClick, last.index == index, now.timeIntervalSince(last.time) < NSEvent.doubleClickInterval {
                        editingVertex = index
                        lastPointClick = nil
                    } else {
                        model.selectMeshPoint(index)
                        lastPointClick = (index, now)
                    }
                }
                vertexDragOrigin = nil
                draggingHandle = false
                snappedKeys.removeAll()
            }
    }

    /// Two draggable endpoints tinted with the first and last colors, joined by the gradient line.
    private func linearHandles(in size: CGSize) -> some View {
        let start = CGPoint(x: clamp(model.recipe.startX, 0, 1) * size.width, y: clamp(model.recipe.startY, 0, 1) * size.height)
        let end = CGPoint(x: clamp(model.recipe.endX, 0, 1) * size.width, y: clamp(model.recipe.endY, 0, 1) * size.height)
        return ZStack {
            Path { path in
                path.move(to: start)
                path.addLine(to: end)
            }
            .stroke(.white.opacity(0.9), style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [5, 5]))
            .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
            .allowsHitTesting(false)

            PointHandle(color: model.recipe.stops.first?.color ?? .white)
                .position(start)
                .gesture(endpointDrag(size: size, isStart: true))
                .accessibilityLabel("Gradient start")
            PointHandle(color: model.recipe.stops.last?.color ?? .white)
                .position(end)
                .gesture(endpointDrag(size: size, isStart: false))
                .accessibilityLabel("Gradient end")
        }
    }

    private func endpointDrag(size: CGSize, isStart: Bool) -> some Gesture {
        canvasDrag { location in
            guard size.width > 0, size.height > 0 else { return }
            // Keep endpoints on the canvas so the handles never hide behind the UI.
            let x = snap(clamp(Double(location.x / size.width), 0, 1), key: isStart ? "sx" : "ex", targets: [0, 0.5, 1], tolerance: 0.02)
            let y = snap(clamp(Double(location.y / size.height), 0, 1), key: isStart ? "sy" : "ey", targets: [0, 0.5, 1], tolerance: 0.02)
            if isStart {
                model.recipe.startX = x
                model.recipe.startY = y
            } else {
                model.recipe.endX = x
                model.recipe.endY = y
            }
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
    var emphasized = false
    /// Mesh: the point library clicks paint, ringed in the accent color.
    var selected = false

    var body: some View {
        Circle()
            .fill(color)
            .overlay {
                if selected {
                    Circle().strokeBorder(Color.accentColor, lineWidth: 3).frame(width: 34, height: 34)
                }
            }
            .frame(width: emphasized ? 26 : 22, height: emphasized ? 26 : 22)
            .overlay { Circle().strokeBorder(.white, lineWidth: emphasized ? 3.5 : 2.5) }
            // A steady outer ring marks the hovered point — no motion.
            .overlay {
                if emphasized {
                    Circle().strokeBorder(.white.opacity(0.7), lineWidth: 2).frame(width: 40, height: 40)
                }
            }
            .shadow(color: .black.opacity(emphasized ? 0.45 : 0.35), radius: emphasized ? 5 : 3, y: 1)
            .frame(width: 40, height: 40)
            .contentShape(Circle())
    }
}

/// A mesh point's color: any color already in the mesh or the gradient, or a custom one.
struct MeshPointEditor: View {
    @Environment(StudioModel.self) private var model
    let index: Int

    /// Which side of a point its popover opens on, so it stays clear of the canvas edges.
    static func edge(x: Double, y: Double) -> Edge {
        if y < 0.3 { return .bottom }
        if y > 0.7 { return .top }
        return x < 0.5 ? .trailing : .leading
    }

    private var hex: String { model.meshColor(at: index) }

    /// Colors on the grid, then the gradient's own, without repeats.
    private var choices: [String] {
        var seen: Set<String> = []
        return (model.meshVertices.map(\.hex) + model.recipe.stops.map(\.hex)).filter { !$0.isEmpty && seen.insert($0.uppercased()).inserted }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                ColorPicker("Color", selection: Binding(
                    get: { Hex.color(hex.isEmpty ? "808080" : hex) },
                    set: { model.setMeshColor(Hex.string(from: $0), at: index) }
                ), supportsOpacity: false)
                .labelsHidden()
                HexField(label: "Hex color", value: Binding(get: { hex }, set: { model.setMeshColor($0, at: index) }))
                    .frame(width: 96)
            }
            if !hex.isEmpty {
                Text(model.libraryName(for: hex) ?? ColorNamer.name(hex))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if !choices.isEmpty {
                Divider()
                Text("In This Gradient")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(28), spacing: 6), count: 6), alignment: .leading, spacing: 6) {
                    ForEach(choices, id: \.self) { choice in
                        Button { model.setMeshColor(choice, at: index) } label: {
                            ColorDot(hex: choice, size: 22)
                                .overlay {
                                    if choice.caseInsensitiveCompare(hex) == .orderedSame {
                                        Circle().strokeBorder(Color.accentColor, lineWidth: 2.5).frame(width: 28, height: 28)
                                    }
                                }
                                .frame(width: 28, height: 28)
                        }
                        .buttonStyle(.plain)
                        .help(model.libraryName(for: choice) ?? ColorNamer.name(choice))
                        .accessibilityLabel(model.libraryName(for: choice) ?? ColorNamer.name(choice))
                    }
                }
            }
            Text("Tip: select a point, then click colors in your collections to paint it.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(width: 236)
        .onAppear { model.selectMeshPoint(index) }
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

// MARK: - Color tray

private struct ColorTray: View {
    @Environment(StudioModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
        if model.recipe.mode == .mesh {
            MeshTray()
                .onHover { model.setTrayHovering($0) }
        } else {
            chips
        }
    }

    /// DMKit's FloatingBar: glass with no stroke or shadow, an opaque capsule under Reduce
    /// Transparency. Its 10-point spacing is part of `slot`.
    private var chips: some View {
        FloatingBar(spacing: 10) {
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
                    .transition(DMMotion.transition(.scale.combined(with: .opacity), reduceMotion: reduceMotion))
            }
            // At eight colors the button stays, disabled, and its help says why. Tonal takes one
            // base color, so its button simply leaves once that's set.
            if model.canAddStop || model.recipe.mode != .tonal {
                AddStopButton()
                    .disabled(!model.canAddStop)
            }
            if !model.recipe.stops.isEmpty {
                Divider().frame(height: 22)
                Button("Remove All Colors", systemImage: "xmark") { model.removeAllColors() }
                    .buttonStyle(.floatingBar)
                    .foregroundStyle(.secondary)
                    .help("Remove All Colors")
            }
        }
        .coordinateSpace(name: "tray")
        // Neighbors slide aside as a chip passes; under Reduce Motion, a short ease with no overshoot.
        .dmAnimation(.spring, value: model.recipe.stops.map(\.id))
        // Hovering anywhere over the tray reveals all the canvas points.
        .onHover { model.setTrayHovering($0) }
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
                withDMAnimation(.spring) {
                    dragID = nil
                    dragTranslation = .zero
                    if remove { model.removeColor(id: stop.id) }
                }
            }
    }
}

/// Mesh's tray: a small grid that mirrors the canvas points one to one. Click a cell to select that
/// point (library clicks paint it), double-click for its colors; hovering lights the point up.
private struct MeshTray: View {
    @Environment(StudioModel.self) private var model
    @State private var editing: Int?
    @State private var lastClick: (index: Int, time: Date)?

    var body: some View {
        let size = model.meshSize
        let cell: CGFloat = size == 3 ? 22 : 17
        // A rounded, vertical FloatingBar: the grid is several rows tall, which a capsule's ends
        // would cut into. Its one row holds the grid and the caption.
        FloatingBar(shape: RoundedRectangle(cornerRadius: DMRadius.large, style: .continuous), axis: .vertical,
                    padding: EdgeInsets(top: 10, leading: 14, bottom: 10, trailing: 14)) {
            HStack(spacing: 12) {
                Grid(horizontalSpacing: 5, verticalSpacing: 5) {
                    ForEach(0..<size, id: \.self) { row in
                        GridRow {
                            ForEach(0..<size, id: \.self) { column in
                                cellView(row * size + column, diameter: cell)
                            }
                        }
                    }
                }
                Text(model.meshColor(at: model.selectedMeshPoint).isEmpty
                     ? "Pick a point,\nthen a color"
                     : "Point \(model.selectedMeshPoint + 1) of \(size * size)\nClick colors to paint")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize()
            }
        }
    }

    private func cellView(_ index: Int, diameter: CGFloat) -> some View {
        let hex = model.meshColor(at: index)
        let selected = model.selectedMeshPoint == index
        return Circle()
            .fill(hex.isEmpty ? Color.clear : Hex.color(hex))
            .overlay { Circle().strokeBorder(Color.primary.opacity(hex.isEmpty ? 0.35 : 0.14), style: StrokeStyle(lineWidth: 1, dash: hex.isEmpty ? [2, 2] : [])) }
            .frame(width: diameter, height: diameter)
            .padding(3)
            .overlay { if selected { Circle().strokeBorder(Color.accentColor, lineWidth: 2) } }
            .contentShape(Circle())
            .onHover { hovering in
                if hovering { model.highlightedMeshPoint = index } else if model.highlightedMeshPoint == index { model.highlightedMeshPoint = nil }
            }
            .onTapGesture {
                let now = Date()
                if let last = lastClick, last.index == index, now.timeIntervalSince(last.time) < NSEvent.doubleClickInterval {
                    editing = index
                    lastClick = nil
                } else {
                    model.selectMeshPoint(index)
                    lastClick = (index, now)
                }
            }
            .popover(isPresented: Binding(get: { editing == index }, set: { if !$0 { editing = nil } }), arrowEdge: .top) {
                MeshPointEditor(index: index).environment(model)
            }
            .help(hex.isEmpty ? "Point \(index + 1): unpainted" : "Point \(index + 1): \(model.libraryName(for: hex) ?? ColorNamer.name(hex)). Double-click to edit.")
            .accessibilityElement()
            .accessibilityLabel("Point \(index + 1), \(hex.isEmpty ? "unpainted" : hex)")
            .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
            .accessibilityAction { model.selectMeshPoint(index) }
            .accessibilityAction(named: "Edit Color") { editing = index }
    }
}

private struct StopChip: View {
    @Environment(StudioModel.self) private var model
    let stop: ColorStop
    let isLifted: Bool
    let isRemoving: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast
    @State private var editing = false
    @State private var hovering = false

    private var name: String { model.libraryName(for: stop.hex) ?? ColorNamer.name(stop.hex) }

    var body: some View {
        ColorDot(hex: stop.hex, size: 30)
            // Hover rings the chip; only a drag lifts (scales) it.
            .overlay {
                Circle().strokeBorder(Color.primary.opacity(hovering && !isLifted ? (contrast == .increased ? 0.8 : 0.45) : 0), lineWidth: 2)
            }
            .shadow(color: .black.opacity(isLifted ? 0.3 : 0), radius: 8, y: 5)
            // Reduce Motion: the lifted chip keeps its size and shows lift and removal by shadow and fade.
            .scaleEffect(reduceMotion ? 1 : (isRemoving ? 0.8 : (isLifted ? 1.18 : 1)))
            .opacity(isRemoving ? 0.4 : 1)
            .overlay(alignment: .top) {
                if isRemoving {
                    // A flat label: the tray it rises from is already glass.
                    Text("Remove")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color(nsColor: .controlBackgroundColor), in: Capsule())
                        .fixedSize()
                        .offset(y: -24)
                }
            }
            .animation(.easeOut(duration: 0.12), value: hovering)
            .animation(reduceMotion ? .easeOut(duration: 0.12) : .snappy(duration: 0.25), value: isLifted)
            .animation(.easeOut(duration: 0.15), value: isRemoving)
            .contentShape(Circle())
            .onHover { isHovering in
                hovering = isHovering
                // Highlight this point on the canvas while hovering its chip.
                if isHovering { model.highlightedStopID = stop.id }
                else if model.highlightedStopID == stop.id { model.highlightedStopID = nil }
            }
            .onTapGesture { editing = true }
            .popover(isPresented: $editing, arrowEdge: .top) {
                StopEditor(stopID: stop.id, dismiss: { editing = false })
                    .environment(model)
            }
            .contextMenu {
                Button("Edit Color…") { editing = true }
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
    @Environment(StudioModel.self) private var model
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
                if model.usesPointStrength {
                    Divider()
                    VStack(spacing: 5) {
                        HStack(spacing: 6) {
                            Text("Strength")
                            if stop.weight != 1 {
                                Button { model.setWeight(1, for: stopID) } label: {
                                    Image(systemName: "arrow.counterclockwise")
                                        .font(.system(size: 9, weight: .semibold))
                                }
                                .buttonStyle(.borderless)
                                .foregroundStyle(.secondary)
                                .help("Reset to 100%")
                                .accessibilityLabel("Reset strength to 100%")
                            }
                            Spacer()
                            Text("\(Int((stop.weight * 100).rounded()))%")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        .font(.caption)
                        Slider(value: weightBinding, in: 0.1...3)
                    }
                }
                HStack {
                    Button("Duplicate", systemImage: "plus.square.on.square") { model.duplicateColor(id: stopID) }
                        .disabled(!model.canAddStop || model.recipe.mode == .tonal)
                    Spacer()
                    Button("Remove", systemImage: "minus.circle", role: .destructive) {
                        // Close the popover before its anchor disappears.
                        dismiss()
                        let target = self.model
                        let id = stopID
                        Task {
                            try? await Task.sleep(for: .milliseconds(200))
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

    private var weightBinding: Binding<Double> {
        Binding(
            get: { stop?.weight ?? 1 },
            set: { model.setWeight($0, for: stopID) }
        )
    }
}

private struct AddStopButton: View {
    @Environment(StudioModel.self) private var model
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
        .help(model.canAddStop ? "Add a color" : StudioModel.colorLimitMessage)
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
