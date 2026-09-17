import SwiftUI

struct ColorLibraryView: View {
    @EnvironmentObject private var model: StudioModel
    @AppStorage("selectedColorLibraryID") private var selectedLibraryIDString = ColorLibrary.coldwellBankerID.uuidString
    @State private var showsSaveColor = false
    @State private var showsCreateLibrary = false
    @State private var libraryName = ""
    @State private var colorName = ""
    @State private var colorHex = "012169"

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

            Text("Click a color to add or remove it from the gradient.")
                .font(.caption)
                .foregroundStyle(.secondary)

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
                Button("Add Color…", systemImage: "plus") { showsSaveColor = true }
                    .controlSize(.small)
                Button("Remove All", systemImage: "xmark.circle") { model.removeAllColors() }
                    .controlSize(.small)
                    .disabled(model.recipe.stops.isEmpty)
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
                    Label("Manage…", systemImage: "ellipsis.circle")
                }
                .help("Create, import, or export a color library")
            }
        }
        .onAppear(perform: repairSelection)
        .onChange(of: model.colorLibraries) { _, _ in repairSelection() }
        .sheet(isPresented: $showsSaveColor) { saveColorSheet }
        .sheet(isPresented: $showsCreateLibrary) { createLibrarySheet }
    }

    private func colorRow(_ color: LibraryColor) -> some View {
        let picked = model.containsColor(hex: color.hex)
        return Button {
            model.toggleLibraryColor(color)
        } label: {
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
                Image(systemName: picked ? "checkmark.circle.fill" : "plus.circle")
                    .foregroundStyle(picked ? Color.accentColor : .secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!picked && model.recipe.stops.count == 8)
        .accessibilityLabel("\(color.name), \(color.hex)")
        .accessibilityValue(picked ? "In gradient" : "Not in gradient")
        .help("\(picked ? "Remove" : "Add") \(color.name) \(picked ? "from" : "to") the gradient")
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
}
