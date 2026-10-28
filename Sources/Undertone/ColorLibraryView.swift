import AppKit
import SwiftUI

enum SidebarTab: String {
    case gradients, colors
}

struct SidebarView: View {
    @Environment(StudioModel.self) private var model
    @AppStorage("sidebarTab") private var tab: SidebarTab = .gradients
    /// Held here rather than in the Colors tab so the menu bar can open one from either tab.
    @State private var colorSheet: ColorSheet?

    var body: some View {
        Group {
            switch tab {
            case .gradients: GradientLibraryView()
            case .colors: ColorLibraryView(showSheet: { colorSheet = $0 })
            }
        }
        .sheet(item: $colorSheet) { sheet in
            sheetContent(sheet)
                .environment(model)
        }
        .focusedSceneValue(\.colorSheetAction, ColorSheetAction { sheet in
            tab = .colors
            colorSheet = sheet
        })
        .safeAreaBar(edge: .top, spacing: 0) {
            LibraryTabPicker(tab: $tab)
                .padding(.horizontal, 12)
                .padding(.top, 6)
                .padding(.bottom, 8)
                .frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder private func sheetContent(_ sheet: ColorSheet) -> some View {
        switch sheet {
        case .addColor(let libraryID):
            ColorEditorSheet(title: "Add a Color", confirmTitle: "Add Color", name: "", hex: model.recipe.stops.first?.hex ?? "012169") { name, hex in
                model.saveColor(name: name, hex: hex, libraryID: libraryID) != nil
            }
        case .editColor(let libraryID, let color):
            ColorEditorSheet(title: "Edit Color", confirmTitle: "Save", name: color.name, hex: color.hex) { name, hex in
                model.updateLibraryColor(color.id, in: libraryID, name: name, hex: hex)
            }
        case .newCollection:
            NameSheet(title: "New Collection", message: "A collection holds named colors: a brand library or a small palette.", confirmTitle: "Create", name: "") { name in
                model.createColorLibrary(name: name) != nil
            }
        case .renameCollection(let library):
            NameSheet(title: "Rename Collection", message: nil, confirmTitle: "Rename", name: library.name) { name in
                model.renameColorLibrary(id: library.id, to: name)
            }
        }
    }
}

/// Opens a Colors sheet (New Collection…, Add Color…) from the menu bar, switching the sidebar to Colors.
struct ColorSheetAction {
    let open: (ColorSheet) -> Void
    func callAsFunction(_ sheet: ColorSheet) { open(sheet) }
}

extension FocusedValues {
    @Entry var colorSheetAction: ColorSheetAction?
}

/// The sidebar's Gradients and Colors tabs: the system's tab-style picker on macOS 27 and later,
/// a segmented one on macOS 26.
private struct LibraryTabPicker: View {
    @Binding var tab: SidebarTab

    var body: some View {
        let picker = Picker("Library", selection: $tab) {
            Text("Gradients").tag(SidebarTab.gradients)
            Text("Colors").tag(SidebarTab.colors)
        }
        .labelsHidden()
        .frame(maxWidth: .infinity)
        if #available(macOS 27.0, *) {
            picker.pickerStyle(.tabs)
        } else {
            picker.pickerStyle(.segmented)
        }
    }
}

// MARK: - Gradients

struct GradientLibraryView: View {
    @Environment(StudioModel.self) private var model
    @State private var renaming: SavedGradient?

    private var selection: Binding<UUID?> {
        Binding(get: { model.currentGradientID }, set: { model.selectGradient(id: $0) })
    }

    var body: some View {
        ScrollViewReader { proxy in
            List(selection: selection) {
                let unsaved = model.gradients.filter(\.isUnsaved)
                if !unsaved.isEmpty {
                    Section("Unsaved") { rows(unsaved) }
                }
                Section("Saved") {
                    rows(model.gradients.filter { !$0.isUnsaved })
                        .onMove { model.moveSavedGradients(fromOffsets: $0, toOffset: $1) }
                }
            }
            .listStyle(.sidebar)
            // New, Duplicate and edits insert at the top of their section; scroll there so the new
            // row isn't tucked under the tab picker.
            .onChange(of: model.currentGradientID) { _, id in
                guard let id, let gradient = model.currentGradient,
                      model.gradients.first(where: { $0.isUnsaved == gradient.isUnsaved })?.id == id else { return }
                withAnimation { proxy.scrollTo(id, anchor: .top) }
            }
        }
        .onDeleteCommand {
            if let id = model.currentGradientID { model.deleteGradient(id: id) }
        }
        .safeAreaBar(edge: .bottom, spacing: 0) {
            HStack(spacing: 12) {
                Button("New", systemImage: "plus") { model.newGradient() }
                    .help("Start a new gradient (⌘N)")
                Spacer()
                Button("Duplicate", systemImage: "plus.square.on.square") {
                    if let id = model.currentGradientID { model.duplicateGradient(id: id) }
                }
                .help("Duplicate the current gradient (⌘D)")
            }
            .buttonStyle(.borderless)
            .padding(10)
        }
        .sheet(item: $renaming) { gradient in
            NameSheet(title: "Rename Gradient", message: nil, confirmTitle: "Rename", name: gradient.name) { name in
                model.renameGradient(id: gradient.id, to: name)
                return true
            }
        }
    }

    private func rows(_ gradients: [SavedGradient]) -> some DynamicViewContent {
        ForEach(gradients) { gradient in
            GradientRow(gradient: gradient, thumbnail: model.thumbnail(for: gradient), sourceName: sourceName(of: gradient))
                .tag(gradient.id)
                .contextMenu { menu(for: gradient) }
        }
    }

    private func sourceName(of gradient: SavedGradient) -> String? {
        guard let sourceID = gradient.sourceID else { return nil }
        return model.gradients.first { $0.id == sourceID && !$0.isUnsaved }?.name
    }

    @ViewBuilder private func menu(for gradient: SavedGradient) -> some View {
        if gradient.isUnsaved {
            let source = sourceName(of: gradient)
            // Same titles as File › Save Gradient / Save as New Gradient.
            Button(source == nil ? "Save Gradient" : "Save as New Gradient") {
                model.selectGradient(id: gradient.id)
                model.saveAsNewGradient()
            }
            if let source {
                Button("Update “\(source)”") {
                    model.selectGradient(id: gradient.id)
                    model.updateSavedGradient()
                }
                Button("Revert to Saved") {
                    model.selectGradient(id: gradient.id)
                    model.revertToSaved()
                }
            }
            Divider()
        }
        Button("Rename…") { renaming = gradient }
        Button("Duplicate") { model.duplicateGradient(id: gradient.id) }
        Divider()
        Button("Export Recipe…") { model.exportRecipe(id: gradient.id) }
        Divider()
        Button(gradient.isUnsaved ? "Discard" : "Delete", role: .destructive) { model.deleteGradient(id: gradient.id) }
    }
}

private struct GradientRow: View {
    let gradient: SavedGradient
    let thumbnail: NSImage?
    /// For an unsaved gradient, the saved gradient it was edited from.
    let sourceName: String?

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 9, style: .continuous)
        HStack(spacing: 10) {
            ZStack {
                shape.fill(.quaternary)
                if let thumbnail {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .scaledToFill()
                }
            }
            .frame(width: 44, height: 44)
            .clipShape(shape)
            .overlay { shape.strokeBorder(Color.primary.opacity(0.1), lineWidth: 1) }
            .shadow(color: .black.opacity(0.08), radius: 2, y: 1)

            VStack(alignment: .leading, spacing: 2) {
                Text(gradient.name)
                    .lineLimit(1)
                Text(sourceName.map { "Edited from \($0)" } ?? "\(gradient.recipe.mode.title) · \(String(gradient.recipe.width)) × \(String(gradient.recipe.height))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Colors

/// Applies swatch drags between and within collections (macOS 27 and later).
private struct SwatchReordering: ViewModifier {
    let model: StudioModel

    func body(content: Content) -> some View {
        if #available(macOS 27.0, *) {
            content.reorderContainer(for: LibraryColor.self, in: UUID.self) { difference in
                let before: UUID? = switch difference.destination.position {
                case .before(let id): id
                case .end: nil
                }
                model.moveLibraryColors(difference.sources, to: difference.destination.collectionID, before: before)
            }
        } else {
            content
        }
    }
}

/// The sheets the Colors tab can show.
enum ColorSheet: Identifiable {
    case addColor(libraryID: UUID)
    case editColor(libraryID: UUID, color: LibraryColor)
    case newCollection
    case renameCollection(ColorLibrary)

    var id: String {
        switch self {
        case .addColor(let libraryID): "add-\(libraryID)"
        case .editColor(_, let color): "edit-\(color.id)"
        case .newCollection: "new-collection"
        case .renameCollection(let library): "rename-\(library.id)"
        }
    }
}

struct ColorLibraryView: View {
    @Environment(StudioModel.self) private var model
    @AppStorage("collapsedCollections") private var collapsedStorage = ""
    let showSheet: (ColorSheet) -> Void
    @State private var deleting: ColorLibrary?

    private var collapsed: Set<String> {
        Set(collapsedStorage.split(separator: ",").map(String.init))
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 4) {
                ForEach(model.colorLibraries) { library in
                    CollectionSection(
                        library: library,
                        isExpanded: expansion(for: library),
                        showSheet: showSheet,
                        requestDelete: { deleting = $0 }
                    )
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
            .modifier(SwatchReordering(model: model))
        }
        .safeAreaBar(edge: .bottom, spacing: 0) {
            HStack {
                Menu {
                    Button("New Collection…") { showSheet(.newCollection) }
                    Button("New Collection from Gradient Colors") {
                        model.createColorLibraryFromCurrentColors()
                    }
                    .disabled(model.recipe.stops.isEmpty)
                    Divider()
                    Button("Import Collection…") {
                        model.importColorLibraryFromPanel()
                    }
                } label: {
                    Label("New Collection", systemImage: "plus")
                } primaryAction: {
                    showSheet(.newCollection)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("New collection. Hold for more options.")
                Spacer()
            }
            .padding(10)
        }
        .confirmationDialog(
            "Delete \(deleting?.name ?? "collection")?",
            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })
        ) {
            Button("Delete Collection", role: .destructive) {
                if let library = deleting { model.deleteColorLibrary(id: library.id) }
                deleting = nil
            }
        } message: {
            Text("Gradients that use these colors keep them.")
        }
    }

    private func expansion(for library: ColorLibrary) -> Binding<Bool> {
        let key = library.id.uuidString
        return Binding(
            get: { !collapsed.contains(key) },
            set: { expanded in
                var keys = collapsed
                if expanded { keys.remove(key) } else { keys.insert(key) }
                collapsedStorage = keys.sorted().joined(separator: ",")
            }
        )
    }
}

/// One collapsible collection: a header row, then swatches shaped like the style tiles.
private struct CollectionSection: View {
    @Environment(StudioModel.self) private var model
    let library: ColorLibrary
    @Binding var isExpanded: Bool
    let showSheet: (ColorSheet) -> Void
    let requestDelete: (ColorLibrary) -> Void

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 3)

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            if isExpanded {
                LazyVGrid(columns: columns, spacing: 10) {
                    swatches
                    AddSwatchTile { showSheet(.addColor(libraryID: library.id)) }
                }
                .padding(.bottom, 8)
                .transition(.opacity)
            }
        }
    }

    /// On macOS 27 and later, swatches drag to reorder, within the collection or into another one;
    /// ColorLibraryView applies the moves.
    @ViewBuilder private var swatches: some View {
        if #available(macOS 27.0, *) {
            ForEach(library.colors) { swatch($0) }
                .reorderable(collectionID: library.id)
        } else {
            ForEach(library.colors) { swatch($0) }
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Button {
                withAnimation(.snappy(duration: 0.25)) { isExpanded.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .frame(width: 12)
                    Text(library.name)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    if !isExpanded {
                        HStack(spacing: -3) {
                            ForEach(library.colors.prefix(6)) { color in
                                ColorDot(hex: color.hex, size: 12)
                            }
                        }
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .contextMenu { collectionMenu }

            Menu {
                collectionMenu
            } label: {
                Image(systemName: "ellipsis")
                    .foregroundStyle(.secondary)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .accessibilityLabel("\(library.name) actions")
        }
        .padding(.vertical, 6)
    }

    /// The header's ⋯ menu, repeated as its right-click menu.
    @ViewBuilder private var collectionMenu: some View {
        Button("Add Color…") { showSheet(.addColor(libraryID: library.id)) }
        Button("Rename…") { showSheet(.renameCollection(library)) }
        Button("Export…") { model.exportColorLibrary(id: library.id) }
        Divider()
        Button("Delete…", role: .destructive) { requestDelete(library) }
    }

    private func swatch(_ color: LibraryColor) -> some View {
        let count = model.count(of: color.hex)
        let canAdd = model.canUseLibraryColor
        return SwatchTile(color: color, count: count, isEnabled: canAdd) {
            model.addLibraryColor(color)
        }
        .contextMenu {
            Button(model.recipe.mode == .mesh ? "Paint Selected Point" : "Add to Gradient") { model.addLibraryColor(color) }
                .disabled(!canAdd)
            Divider()
            Button("Edit…") { showSheet(.editColor(libraryID: library.id, color: color)) }
            Button("Copy Hex") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString("#" + color.hex, forType: .string)
            }
            Divider()
            Button("Delete", role: .destructive) { model.deleteLibraryColor(color.id, from: library.id) }
        }
    }
}

/// A library swatch with the same shape, hairline and hover as the style tiles.
/// Every click adds the color again; the badge counts how many times it's in the gradient.
private struct SwatchTile: View {
    let color: LibraryColor
    let count: Int
    let isEnabled: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 9, style: .continuous)
        Button(action: action) {
            VStack(spacing: 5) {
                shape
                    .fill(Hex.color(color.hex))
                    .frame(height: 44)
                    .overlay { shape.strokeBorder(Color.primary.opacity(count > 0 ? 0 : 0.1), lineWidth: 1) }
                    .overlay {
                        if count > 0 {
                            shape.strokeBorder(Color.accentColor, lineWidth: 2.5)
                        }
                    }
                    .overlay {
                        // Hover outlines the swatch instead of growing it.
                        if hovering && isEnabled && count == 0 {
                            shape.strokeBorder(Color.primary.opacity(0.35), lineWidth: 1.5)
                        }
                    }
                    .overlay(alignment: .topTrailing) {
                        if count > 0 {
                            Group {
                                if count > 1 { Text("\(count)") } else { Image(systemName: "checkmark") }
                            }
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(minWidth: 16, minHeight: 16)
                            .background(Color.accentColor, in: Circle())
                            .offset(x: 4, y: -4)
                            .transition(.scale.combined(with: .opacity))
                        }
                    }
                    .shadow(color: .black.opacity(0.08), radius: 2, y: 2)
                Text(color.displayName)
                    .font(.caption)
                    .lineLimit(1)
                    .foregroundStyle(count > 0 ? .primary : .secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.5)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
        .animation(.snappy, value: count)
        .help("Add \(color.displayName) · #\(color.hex)")
        .accessibilityLabel("\(color.displayName), \(color.hex)")
        .accessibilityValue(count == 0 ? "Not in gradient" : "In gradient \(count) times")
        .accessibilityHint("Adds this color to the gradient")
    }
}

private struct AddSwatchTile: View {
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 9, style: .continuous)
        Button(action: action) {
            VStack(spacing: 5) {
                shape
                    .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                    .foregroundStyle(.secondary)
                    .frame(height: 44)
                    .foregroundStyle(hovering ? .primary : .secondary)
                    .overlay {
                        Image(systemName: "plus")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(hovering ? .primary : .secondary)
                    }
                Text("Add")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
        .help("Add a color to this collection")
        .accessibilityLabel("Add a color")
    }
}

// MARK: - Sheets

private struct ColorEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    let confirmTitle: String
    @State var name: String
    @State var hex: String
    let save: (String, String) -> Bool
    @FocusState private var focused: Bool

    init(title: String, confirmTitle: String, name: String, hex: String, save: @escaping (String, String) -> Bool) {
        self.title = title
        self.confirmTitle = confirmTitle
        // Name is optional — leave it blank by default; the hex stands in where a name is needed.
        self._name = State(initialValue: name)
        self._hex = State(initialValue: hex)
        self.save = save
    }

    private var colorBinding: Binding<Color> {
        Binding(get: { Hex.color(Hex.normalized(hex) ?? "808080") }, set: { hex = Hex.string(from: $0) })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title).font(.title2.weight(.semibold))
            HStack(spacing: 14) {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Hex.color(Hex.normalized(hex) ?? "808080"))
                    .overlay { RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Color.primary.opacity(0.1), lineWidth: 1) }
                    .frame(width: 56, height: 56)
                Form {
                    TextField("Name", text: $name)
                        .focused($focused)
                        .onAppear { DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { focused = true } }
                    HStack {
                        TextField("Hex", text: $hex)
                        ColorPicker("Color", selection: colorBinding, supportsOpacity: false)
                            .labelsHidden()
                    }
                }
            }
            HStack {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button(confirmTitle) {
                    if save(name, hex) { dismiss() }
                }
                .disabled(Hex.normalized(hex) == nil)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 400)
    }
}

private struct NameSheet: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    let message: String?
    let confirmTitle: String
    @State var name: String
    let save: (String) -> Bool
    @FocusState private var focused: Bool

    init(title: String, message: String?, confirmTitle: String, name: String, save: @escaping (String) -> Bool) {
        self.title = title
        self.message = message
        self.confirmTitle = confirmTitle
        self._name = State(initialValue: name)
        self.save = save
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title).font(.title2.weight(.semibold))
            if let message {
                Text(message).foregroundStyle(.secondary)
            }
            TextField("Name", text: $name)
                .focused($focused)
                .onAppear { DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { focused = true } }
            HStack {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button(confirmTitle) {
                    if save(name) { dismiss() }
                }
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 400)
    }
}
