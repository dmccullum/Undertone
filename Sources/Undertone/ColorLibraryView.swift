import AppKit
import SwiftUI

enum SidebarTab: String {
    case gradients, colors
}

struct SidebarView: View {
    @AppStorage("sidebarTab") private var tab: SidebarTab = .gradients

    var body: some View {
        VStack(spacing: 0) {
            Picker("Library", selection: $tab) {
                Text("Gradients").tag(SidebarTab.gradients)
                Text("Colors").tag(SidebarTab.colors)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 12)
            .padding(.top, 4)
            .padding(.bottom, 8)

            switch tab {
            case .gradients: GradientLibraryView()
            case .colors: ColorLibraryView()
            }
        }
    }
}

// MARK: - Gradients

struct GradientLibraryView: View {
    @EnvironmentObject private var model: StudioModel

    private var selection: Binding<UUID?> {
        Binding(get: { model.currentGradientID }, set: { model.selectGradient(id: $0) })
    }

    var body: some View {
        List(selection: selection) {
            ForEach(model.gradients) { gradient in
                GradientRow(gradient: gradient, thumbnail: model.thumbnail(for: gradient))
                    .tag(gradient.id)
                    .contextMenu { menu(for: gradient) }
            }
        }
        .listStyle(.sidebar)
        .onDeleteCommand {
            if let id = model.currentGradientID { model.deleteGradient(id: id) }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            HStack {
                Button("New Gradient", systemImage: "plus") { model.newGradient() }
                    .buttonStyle(.borderless)
                    .help("New gradient from the current colors (⌘N)")
                Spacer()
            }
            .padding(10)
            .background(.bar)
        }
    }

    @ViewBuilder private func menu(for gradient: SavedGradient) -> some View {
        Button("Rename…") { model.beginRenaming(id: gradient.id) }
        Button("Duplicate") { model.duplicateGradient(id: gradient.id) }
        Button("Replace with Current Gradient") { model.replaceGradient(id: gradient.id) }
            .disabled(gradient.id == model.currentGradientID)
        Divider()
        Button("Export Recipe…") {
            model.selectGradient(id: gradient.id)
            model.exportRecipe()
        }
        Divider()
        Button("Delete", role: .destructive) { model.deleteGradient(id: gradient.id) }
    }
}

private struct GradientRow: View {
    let gradient: SavedGradient
    let thumbnail: NSImage?

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
                Text("\(gradient.recipe.mode.title) · \(String(gradient.recipe.width)) × \(String(gradient.recipe.height))")
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

/// The sheets the Colors tab can show.
private enum ColorSheet: Identifiable {
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
    @EnvironmentObject private var model: StudioModel
    @AppStorage("collapsedCollections") private var collapsedStorage = ""
    @State private var sheet: ColorSheet?
    @State private var deleting: ColorLibrary?

    private var collapsed: Set<String> {
        Set(collapsedStorage.split(separator: ",").map(String.init))
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(model.colorLibraries) { library in
                        CollectionSection(
                            library: library,
                            isExpanded: expansion(for: library),
                            showSheet: { sheet = $0 },
                            requestDelete: { deleting = $0 }
                        )
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
            }

            HStack {
                Menu {
                    Button("New Collection…", systemImage: "folder.badge.plus") { sheet = .newCollection }
                    Button("New Collection from Gradient Colors", systemImage: "square.stack") {
                        model.createColorLibraryFromCurrentColors()
                    }
                    .disabled(model.recipe.stops.isEmpty)
                    Divider()
                    Button("Import Collection…", systemImage: "square.and.arrow.down") {
                        _ = model.importColorLibraryFromPanel()
                    }
                } label: {
                    Label("New Collection", systemImage: "plus")
                } primaryAction: {
                    sheet = .newCollection
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("New collection. Hold for more options.")
                Spacer()
            }
            .padding(10)
            .background(.bar)
        }
        .sheet(item: $sheet) { sheet in
            sheetContent(sheet)
                .environmentObject(model)
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

/// One collapsible collection: a header row, then swatches shaped like the style tiles.
private struct CollectionSection: View {
    @EnvironmentObject private var model: StudioModel
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
                    ForEach(library.colors) { color in
                        swatch(color)
                    }
                    if !library.isBuiltIn {
                        AddSwatchTile { showSheet(.addColor(libraryID: library.id)) }
                    }
                }
                .padding(.bottom, 8)
                .transition(.opacity)
            }
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
                    if library.isBuiltIn {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                            .help("Built-in collections can't be changed")
                    }
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

            Menu {
                if !library.isBuiltIn {
                    Button("Add Color…", systemImage: "plus") { showSheet(.addColor(libraryID: library.id)) }
                    Button("Rename…", systemImage: "pencil") { showSheet(.renameCollection(library)) }
                }
                Button("Export…", systemImage: "square.and.arrow.up") { model.exportColorLibrary(id: library.id) }
                if !library.isBuiltIn {
                    Divider()
                    Button("Delete…", systemImage: "trash", role: .destructive) { requestDelete(library) }
                }
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

    private func swatch(_ color: LibraryColor) -> some View {
        let count = model.count(of: color.hex)
        let canAdd = model.recipe.mode == .tonal || model.recipe.stops.count < StudioModel.maximumStops
        return SwatchTile(color: color, count: count, isEnabled: canAdd) {
            model.addLibraryColor(color)
        }
        .contextMenu {
            Button("Add to Gradient") { model.addLibraryColor(color) }
                .disabled(!canAdd)
            Button("Copy Hex") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString("#" + color.hex, forType: .string)
            }
            Divider()
            Button("Edit…") { showSheet(.editColor(libraryID: library.id, color: color)) }
                .disabled(library.isBuiltIn)
            Button("Rename…") { showSheet(.editColor(libraryID: library.id, color: color)) }
                .disabled(library.isBuiltIn)
            Button("Delete", role: .destructive) { model.deleteLibraryColor(color.id, from: library.id) }
                .disabled(library.isBuiltIn)
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
                    .overlay(alignment: .topTrailing) {
                        if count > 0 {
                            Text(count > 1 ? "\(count)" : "✓")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(minWidth: 16, minHeight: 16)
                                .background(Color.accentColor, in: Circle())
                                .offset(x: 4, y: -4)
                                .transition(.scale.combined(with: .opacity))
                        }
                    }
                    .shadow(color: .black.opacity(hovering ? 0.22 : 0.08), radius: hovering ? 6 : 2, y: 2)
                    .scaleEffect(hovering && isEnabled ? 1.04 : 1)
                Text(color.name)
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
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: hovering)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: count)
        .help("Add \(color.name) · #\(color.hex)")
        .accessibilityLabel("\(color.name), \(color.hex)")
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
                    .overlay {
                        Image(systemName: "plus")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    .scaleEffect(hovering ? 1.04 : 1)
                Text("Add")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: hovering)
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

    init(title: String, confirmTitle: String, name: String, hex: String, save: @escaping (String, String) -> Bool) {
        self.title = title
        self.confirmTitle = confirmTitle
        self._name = State(initialValue: name.isEmpty ? (Hex.normalized(hex).map(ColorNamer.name) ?? "") : name)
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
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || Hex.normalized(hex) == nil)
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
