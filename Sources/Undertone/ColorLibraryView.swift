import AppKit
import SwiftUI

struct ColorLibraryView: View {
    @EnvironmentObject private var model: StudioModel
    @AppStorage("selectedColorLibraryID") private var selectedLibraryIDString = ColorLibrary.coldwellBankerID.uuidString
    @State private var showsSaveColor = false
    @State private var showsCreateLibrary = false
    @State private var libraryName = ""
    @State private var colorName = ""
    @State private var colorHex = "012169"
    @State private var libraryPendingRemoval: ColorLibrary?
    @State private var colorPendingRemoval: LibraryColor?
    @State private var colorRemovalLibraryID: UUID?

    private var selectedLibraryID: UUID {
        UUID(uuidString: selectedLibraryIDString) ?? ColorLibrary.coldwellBankerID
    }
    private var selectedLibrary: ColorLibrary {
        model.colorLibraries.first { $0.id == selectedLibraryID } ?? model.colorLibraries[0]
    }
    private var selection: Binding<UUID> {
        Binding(get: { selectedLibrary.id }, set: { selectedLibraryIDString = $0.uuidString })
    }
    private var validColor: Bool {
        !colorName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        cleanHex.range(of: "^[0-9A-F]{6}$", options: .regularExpression) != nil
    }
    private var cleanHex: String {
        colorHex.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "#", with: "").uppercased()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("Library", selection: selection) {
                ForEach(model.colorLibraries) { library in
                    Text(library.name).tag(library.id)
                }
            }
            .labelsHidden()
            .contextMenu {
                if !selectedLibrary.isBuiltIn {
                    Button("Remove Palette", systemImage: "trash", role: .destructive) {
                        libraryPendingRemoval = selectedLibrary
                    }
                }
            }

            if selectedLibrary.colors.isEmpty {
                ContentUnavailableView(
                    "No Colors Yet",
                    systemImage: "paintpalette",
                    description: Text("Add a named color to this library.")
                )
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            } else {
                VStack(spacing: 3) {
                    ForEach(selectedLibrary.colors) { color in
                        colorRow(color)
                    }
                }
            }

            HStack(spacing: 8) {
                Button("Add color", systemImage: "plus") { showsSaveColor = true }
                    .labelStyle(.iconOnly)
                    .controlSize(.small)
                    .help("Add a color to this library")
                Spacer()
                Menu {
                    Button("New Library…", systemImage: "folder.badge.plus") {
                        showsCreateLibrary = true
                    }
                    Button("Import Library…", systemImage: "square.and.arrow.down") {
                        if let id = model.importColorLibraryFromPanel() {
                            selectedLibraryIDString = id.uuidString
                        }
                    }
                    Divider()
                    Button("Export \(selectedLibrary.name)…", systemImage: "square.and.arrow.up") {
                        model.exportColorLibrary(id: selectedLibrary.id)
                    }
                } label: {
                    Label("Manage libraries", systemImage: "ellipsis.circle")
                }
                .labelStyle(.iconOnly)
                .controlSize(.small)
                .help("Create, import, or export a color library")
            }
        }
        .onAppear(perform: repairSelection)
        .onChange(of: model.colorLibraries) { _, _ in repairSelection() }
        .sheet(isPresented: $showsSaveColor) { saveColorSheet }
        .sheet(isPresented: $showsCreateLibrary) { createLibrarySheet }
        .confirmationDialog(
            libraryPendingRemoval.map { "Remove \"\($0.name)\"?" } ?? "Remove palette?",
            isPresented: libraryRemovalIsPresented,
            titleVisibility: .visible
        ) {
            Button("Remove Palette", role: .destructive) {
                if let library = libraryPendingRemoval {
                    model.removeColorLibrary(id: library.id)
                }
                libraryPendingRemoval = nil
            }
            Button("Cancel", role: .cancel) { libraryPendingRemoval = nil }
        } message: {
            Text("This palette and its saved colors will be permanently removed.")
        }
        .alert(
            colorPendingRemoval.map { "Remove \"\($0.name)\"?" } ?? "Remove palette color?",
            isPresented: colorRemovalIsPresented
        ) {
            Button("Remove Color", role: .destructive) {
                if let color = colorPendingRemoval, let libraryID = colorRemovalLibraryID {
                    model.removeLibraryColor(id: color.id, from: libraryID)
                }
                colorPendingRemoval = nil
                colorRemovalLibraryID = nil
            }
            Button("Cancel", role: .cancel) {
                colorPendingRemoval = nil
                colorRemovalLibraryID = nil
            }
        } message: {
            Text("This color will be permanently removed from the palette.")
        }
    }

    private func colorRow(_ color: LibraryColor) -> some View {
        HStack(spacing: 9) {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(nsColor: ColorStop(hex: color.hex, x: 0, y: 0).nsColor))
                .frame(width: 34, height: 24)
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.primary.opacity(0.18)))
            VStack(alignment: .leading, spacing: 1) {
                Text(color.name).font(.caption).lineLimit(1)
                Text("#" + color.hex)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            Image(systemName: "plus.circle")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 3)
        .contentShape(Rectangle())
        .accessibilityLabel("\(color.name), \(color.hex)")
        .accessibilityHint("Add this color to the gradient")
        .accessibilityAddTraits(.isButton)
        .help("Add \(color.name) to the gradient")
        .overlay {
            PaletteItemInteractionOverlay(
                primaryAction: { model.addLibraryColor(color) },
                removalAction: {
                colorPendingRemoval = color
                colorRemovalLibraryID = selectedLibrary.id
                }
            )
        }
    }

    private var saveColorSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Add a Color").font(.title2.weight(.semibold))
            Text(selectedLibrary.isBuiltIn
                 ? "Built-in libraries stay unchanged. This color will be saved in My Colors."
                 : "Save this swatch in \(selectedLibrary.name).")
                .foregroundStyle(.secondary)
            Form {
                TextField("Name", text: $colorName)
                TextField("Hex", text: $colorHex)
            }
            HStack {
                Button("Cancel") { showsSaveColor = false }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Add Color") {
                    if let id = model.saveColor(name: colorName, hex: cleanHex, libraryID: selectedLibrary.id) {
                        selectedLibraryIDString = id.uuidString
                        colorName = ""
                        showsSaveColor = false
                    }
                }
                .disabled(!validColor)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 390)
    }

    private var createLibrarySheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("New Color Library").font(.title2.weight(.semibold))
            Text("Create a reusable collection of named colors.")
                .foregroundStyle(.secondary)
            TextField("Library name", text: $libraryName)
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
        .frame(width: 390)
    }

    private func repairSelection() {
        if !model.colorLibraries.contains(where: { $0.id == selectedLibraryID }) {
            selectedLibraryIDString = model.colorLibraries[0].id.uuidString
        }
    }

    private var libraryRemovalIsPresented: Binding<Bool> {
        Binding(
            get: { libraryPendingRemoval != nil },
            set: { if !$0 { libraryPendingRemoval = nil } }
        )
    }

    private var colorRemovalIsPresented: Binding<Bool> {
        Binding(
            get: { colorPendingRemoval != nil },
            set: {
                if !$0 {
                    colorPendingRemoval = nil
                    colorRemovalLibraryID = nil
                }
            }
        )
    }
}

private struct PaletteItemInteractionOverlay: NSViewRepresentable {
    let primaryAction: () -> Void
    let removalAction: () -> Void

    func makeNSView(context: Context) -> PaletteItemInteractionView {
        let view = PaletteItemInteractionView()
        view.primaryAction = primaryAction
        view.removalAction = removalAction
        return view
    }

    func updateNSView(_ view: PaletteItemInteractionView, context: Context) {
        view.primaryAction = primaryAction
        view.removalAction = removalAction
    }
}

private final class PaletteItemInteractionView: NSView {
    var primaryAction: (() -> Void)?
    var removalAction: (() -> Void)?

    override func mouseDown(with event: NSEvent) {
        primaryAction?()
    }

    override func rightMouseDown(with event: NSEvent) {
        let menu = NSMenu()
        let item = NSMenuItem(title: "Remove from Palette", action: #selector(removeItem), keyEquivalent: "")
        item.target = self
        item.image = NSImage(systemSymbolName: "trash", accessibilityDescription: nil)
        menu.addItem(item)
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    @objc private func removeItem() {
        removalAction?()
    }
}
