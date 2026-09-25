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
            .padding(.top, 6)
            .padding(.bottom, 10)

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
                    .contextMenu {
                        Button("Duplicate") {
                            model.selectGradient(id: gradient.id)
                            model.duplicateCurrentGradient()
                        }
                        Button("Export Recipe…") {
                            model.selectGradient(id: gradient.id)
                            model.exportRecipe()
                        }
                        Divider()
                        Button("Delete", role: .destructive) { model.deleteGradient(id: gradient.id) }
                    }
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
}

private struct GradientRow: View {
    let gradient: SavedGradient
    let thumbnail: NSImage?

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
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
            .overlay { shape.strokeBorder(.primary.opacity(0.1), lineWidth: 1) }
            .shadow(color: .black.opacity(0.12), radius: 2, y: 1)

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

struct ColorLibraryView: View {
    @EnvironmentObject private var model: StudioModel
    @AppStorage("selectedColorLibraryID") private var selectedLibraryIDString = ColorLibrary.coldwellBankerID.uuidString
    @State private var showsSaveColor = false
    @State private var showsCreateLibrary = false
    @State private var confirmsDelete = false
    @State private var libraryName = ""
    @State private var colorName = ""
    @State private var colorHex = "012169"

    private let columns = [GridItem(.adaptive(minimum: 64, maximum: 96), spacing: 10)]

    private var selectedLibraryID: UUID {
        UUID(uuidString: selectedLibraryIDString) ?? ColorLibrary.coldwellBankerID
    }
    private var selectedLibrary: ColorLibrary {
        model.colorLibraries.first { $0.id == selectedLibraryID } ?? model.colorLibraries[0]
    }
    private var selection: Binding<UUID> {
        Binding(get: { selectedLibrary.id }, set: { selectedLibraryIDString = $0.uuidString })
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Picker("Collection", selection: selection) {
                    ForEach(model.colorLibraries) { library in
                        Text(library.name).tag(library.id)
                    }
                }
                .labelsHidden()
                manageMenu
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 6)

            ScrollView {
                if selectedLibrary.colors.isEmpty {
                    ContentUnavailableView(
                        "No Colors Yet",
                        systemImage: "paintpalette",
                        description: Text("Add a color, or save the colors in your gradient as a collection.")
                    )
                    .padding(.top, 24)
                } else {
                    LazyVGrid(columns: columns, spacing: 14) {
                        ForEach(selectedLibrary.colors) { color in
                            swatch(color)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                }
            }

            HStack {
                Button("Add Color…", systemImage: "plus") {
                    colorHex = model.recipe.stops.first?.hex ?? "012169"
                    showsSaveColor = true
                }
                .buttonStyle(.borderless)
                Spacer()
            }
            .padding(10)
            .background(.bar)
        }
        .onAppear(perform: repairSelection)
        .onChange(of: model.colorLibraries) { _, _ in repairSelection() }
        .sheet(isPresented: $showsSaveColor) { saveColorSheet }
        .sheet(isPresented: $showsCreateLibrary) { createLibrarySheet }
        .confirmationDialog("Delete \(selectedLibrary.name)?", isPresented: $confirmsDelete) {
            Button("Delete Collection", role: .destructive) { model.deleteColorLibrary(id: selectedLibrary.id) }
        } message: {
            Text("Gradients that use these colors keep them.")
        }
    }

    private func swatch(_ color: LibraryColor) -> some View {
        let picked = model.containsColor(hex: color.hex)
        let enabled = picked || model.recipe.mode == .tonal || model.recipe.stops.count < StudioModel.maximumStops
        return SwatchChip(color: color, isPicked: picked, isEnabled: enabled) {
            model.toggleLibraryColor(color)
        }
        .contextMenu {
            Button("Copy Hex") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString("#" + color.hex, forType: .string)
            }
            if !selectedLibrary.isBuiltIn {
                Divider()
                Button("Remove from \(selectedLibrary.name)", role: .destructive) {
                    model.deleteLibraryColor(color.id, from: selectedLibrary.id)
                }
            }
        }
    }

    private var manageMenu: some View {
        Menu {
            Button("New Collection…", systemImage: "folder.badge.plus") { showsCreateLibrary = true }
            Button("New Collection from Gradient Colors", systemImage: "square.stack") {
                if let id = model.createColorLibraryFromCurrentColors() { selectedLibraryIDString = id.uuidString }
            }
            .disabled(model.recipe.stops.isEmpty)
            Button("Import Collection…", systemImage: "square.and.arrow.down") {
                if let id = model.importColorLibraryFromPanel() { selectedLibraryIDString = id.uuidString }
            }
            Divider()
            Button("Export \(selectedLibrary.name)…", systemImage: "square.and.arrow.up") {
                model.exportColorLibrary(id: selectedLibrary.id)
            }
            if !selectedLibrary.isBuiltIn {
                Button("Delete \(selectedLibrary.name)…", systemImage: "trash", role: .destructive) {
                    confirmsDelete = true
                }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Create, import or export collections")
        .accessibilityLabel("Collection actions")
    }

    private var saveColorSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Add a Color").font(.title2.weight(.semibold))
            Text(selectedLibrary.isBuiltIn
                 ? "Built-in collections stay unchanged. This color will be saved in My Colors."
                 : "Save this swatch in \(selectedLibrary.name).")
                .foregroundStyle(.secondary)
            HStack(spacing: 12) {
                GlossyDot(hex: Hex.normalized(colorHex) ?? "808080", size: 40)
                Form {
                    TextField("Name", text: $colorName)
                    TextField("Hex", text: $colorHex)
                }
            }
            HStack {
                Button("Cancel") { showsSaveColor = false }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Add Color") {
                    if let id = model.saveColor(name: colorName, hex: colorHex, libraryID: selectedLibrary.id) {
                        selectedLibraryIDString = id.uuidString
                        colorName = ""
                        showsSaveColor = false
                    }
                }
                .disabled(colorName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || Hex.normalized(colorHex) == nil)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 400)
        .onAppear {
            if colorName.isEmpty, let hex = Hex.normalized(colorHex) { colorName = ColorNamer.name(hex) }
        }
    }

    private var createLibrarySheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("New Collection").font(.title2.weight(.semibold))
            Text("A collection holds named colors: a brand library or a small palette.")
                .foregroundStyle(.secondary)
            TextField("Collection name", text: $libraryName)
            HStack {
                Button("Cancel") { showsCreateLibrary = false }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Create") {
                    if let id = model.createColorLibrary(name: libraryName) {
                        selectedLibraryIDString = id.uuidString
                        libraryName = ""
                        showsCreateLibrary = false
                    }
                }
                .disabled(libraryName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 400)
    }

    private func repairSelection() {
        if !model.colorLibraries.contains(where: { $0.id == selectedLibraryID }) {
            selectedLibraryIDString = model.colorLibraries[0].id.uuidString
        }
    }
}

/// A glossy library swatch. A picked swatch gets a ring in its own color and a checkmark.
private struct SwatchChip: View {
    let color: LibraryColor
    let isPicked: Bool
    let isEnabled: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        let fill = Hex.color(color.hex)
        let luminance = Hex.luminance(color.hex)
        let shape = RoundedRectangle(cornerRadius: 13, style: .continuous)
        Button(action: action) {
            VStack(spacing: 6) {
                ZStack {
                    shape.fill(fill)
                    shape
                        .fill(LinearGradient(colors: [.white.opacity(0.42), .white.opacity(0)], startPoint: .top, endPoint: .center))
                        .padding(3)
                    shape.strokeBorder(.primary.opacity(0.12), lineWidth: 1)
                    if isPicked {
                        Image(systemName: "checkmark")
                            .font(.system(size: 15, weight: .heavy))
                            .foregroundStyle(luminance > 0.6 ? Color.black.opacity(0.7) : Color.white)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .frame(height: 50)
                .padding(3)
                .overlay {
                    if isPicked {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(luminance > 0.85 ? Color.accentColor : fill, lineWidth: 2.5)
                    }
                }
                .shadow(color: fill.opacity(hovering ? 0.55 : 0.28), radius: hovering ? 9 : 4, y: hovering ? 5 : 2)
                .scaleEffect(hovering && isEnabled ? 1.06 : 1)

                Text(color.name)
                    .font(.caption2)
                    .lineLimit(1)
                    .foregroundStyle(isPicked ? .primary : .secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.45)
        .onHover { hovering = $0 }
        .animation(.spring(response: 0.28, dampingFraction: 0.6), value: hovering)
        .animation(.spring(response: 0.32, dampingFraction: 0.55), value: isPicked)
        .help("\(isPicked ? "Remove" : "Add") \(color.name) · #\(color.hex)")
        .accessibilityLabel("\(color.name), \(color.hex)")
        .accessibilityValue(isPicked ? "In gradient" : "Not in gradient")
    }
}
