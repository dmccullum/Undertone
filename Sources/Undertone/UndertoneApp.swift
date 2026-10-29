import AppKit
import DMKit
import SwiftUI
import UndertoneKit

final class UndertoneAppDelegate: NSObject, NSApplicationDelegate {
    private var observer: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        observer = NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: nil,
            queue: .main
        ) { notification in
            guard let window = notification.object as? NSWindow else { return }
            MainActor.assumeIsolated { UndertoneAppDelegate.style(window) }
        }
        Task {
            NSApplication.shared.windows.forEach { UndertoneAppDelegate.style($0) }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    /// Styles the studio window only. Panels, alerts, the color panel and About keep their own chrome.
    /// SwiftUI names the scene's window after its id ("studio", or "studio-AppWindow-1").
    private static func style(_ window: NSWindow) {
        guard window.identifier?.rawValue.hasPrefix("studio") == true else { return }
        window.styleMask.insert(.fullSizeContentView)
        window.titleVisibility = .visible
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.toolbarStyle = .unified
        window.backgroundColor = .windowBackgroundColor
    }
}

/// Carries settings over from Undertone's old bundle identifier, once.
nonisolated enum BundleIDMigration {
    static let oldBundleID = "studio.undertone.mac"
    static let newBundleID = "com.danielmccullum.Undertone"
    static let marker = "migratedFromBundleID"

    /// The app's own keys from a preferences domain, without the ones AppKit and the system write
    /// (window frames, panel state, NS*, Apple*, com.apple.*).
    static func appKeys(_ domain: [String: Any]) -> [String: Any] {
        domain.filter { key, _ in !["NS", "Apple", "com.apple."].contains { key.hasPrefix($0) } }
    }

    /// Copies the old domain's keys into `defaults` when it holds none of the app's keys yet, then
    /// writes the marker so this runs once. Returns whether it copied anything.
    @discardableResult static func migrate(from oldDomain: [String: Any]?, into defaults: UserDefaults, currentDomain: [String: Any]) -> Bool {
        guard currentDomain[marker] == nil else { return false }
        defer { defaults.set(oldBundleID, forKey: marker) }
        guard appKeys(currentDomain).isEmpty, let oldDomain else { return false }
        let keys = appKeys(oldDomain)
        for (key, value) in keys { defaults.set(value, forKey: key) }
        return !keys.isEmpty
    }

    /// Runs before anything reads settings. Only the packaged app (with the new identifier) migrates;
    /// `swift run` and tests have no bundle identifier and keep their own domain.
    static func run() {
        guard Bundle.main.bundleIdentifier == newBundleID else { return }
        let defaults = UserDefaults.standard
        migrate(
            from: defaults.persistentDomain(forName: oldBundleID),
            into: defaults,
            currentDomain: defaults.persistentDomain(forName: newBundleID) ?? [:]
        )
    }
}

@main
struct UndertoneApp: App {
    @NSApplicationDelegateAdaptor(UndertoneAppDelegate.self) private var appDelegate
    @State private var model: StudioModel
    /// The About window's live gradient, shared by its backdrop and its palette signature.
    @State private var aboutGradient = AboutGradient()

    init() {
        // Before the model and @AppStorage read the open gradient, canvas size and sidebar state.
        BundleIDMigration.run()
        _model = State(initialValue: StudioModel())
    }

    var body: some Scene {
        Window("Undertone", id: "studio") {
            ContentView()
                .environment(model)
                .providesHostingWindow()
                // ContentView sets the minimum width, which depends on whether the inspector is open.
                .frame(minHeight: 660)
        }
        .defaultSize(width: 1_320, height: 860)
        .windowToolbarStyle(.unified)
        .keyboardShortcut("0", modifiers: .command)
        .commands {
            // AboutScene doesn't add App › About; it comes from here, opening the About window.
            AboutCommands()
            FamilyHelpCommands(
                help: URL(string: "https://github.com/dmccullum/Undertone/blob/main/docs/USAGE.md")!,
                keyboardShortcuts: .url(URL(string: "https://github.com/dmccullum/Undertone#keyboard-shortcuts")!),
                reportIssue: URL(string: "https://github.com/dmccullum/Undertone/issues/new")
            )
            UndoCommands()
            SidebarCommands()
            StudioCommands(model: model)
        }
        Settings {
            SettingsView()
        }
        AboutScene(
            links: AboutLinks(sourceCode: URL(string: "https://github.com/dmccullum/Undertone")),
            backdrop: AnyView(AboutGradientBackdrop(gradient: aboutGradient))
        ) {
            PaletteSignature(gradient: aboutGradient)
        }
    }
}



/// Opens the Custom Size sheet from Gradient › Canvas Size.
struct CustomSizeAction {
    let open: () -> Void
    func callAsFunction() { open() }
}

extension FocusedValues {
    @Entry var customSizeAction: CustomSizeAction?
}

struct StudioCommands: Commands {
    let model: StudioModel
    /// The same setting ContentView's inspector reads, so the menu item and toolbar button agree.
    @AppStorage("showsInspector") private var showsInspector = true
    @FocusedValue(\.colorSheetAction) private var colorSheetAction
    @FocusedValue(\.customSizeAction) private var customSizeAction

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Gradient") { model.newGradient() }
                .keyboardShortcut("n")
            Button("Duplicate Gradient") { model.duplicateCurrentGradient() }
                .keyboardShortcut("d")
            Divider()
            Button("Import Recipe…") { model.importRecipe() }
                .keyboardShortcut("o")
        }
        // After, not replacing: the system's save group holds File › Close (⌘W).
        CommandGroup(after: .saveItem) {
            Button(model.currentSource == nil ? "Save Gradient" : "Save as New Gradient") { model.saveAsNewGradient() }
                .keyboardShortcut("s")
                .disabled(!model.isCurrentUnsaved)
            Button(model.currentSource.map { "Update “\($0.name)”" } ?? "Update Saved Gradient") { model.updateSavedGradient() }
                .keyboardShortcut("s", modifiers: [.command, .option])
                .disabled(model.currentSource == nil)
            Button("Revert to Saved") { model.revertToSaved() }
                .disabled(model.currentSource == nil)
            Divider()
            Button("Export Image…") { model.exportImage() }
                .keyboardShortcut("e")
                .disabled(model.isRendering)
            Button("Copy Image") { model.copyImage() }
                .keyboardShortcut("c", modifiers: [.command, .shift])
                .disabled(model.isRendering)
            Button("Export Recipe…") { model.exportRecipe() }
                .keyboardShortcut("e", modifiers: [.command, .option])
        }
        // Replaces the system inspector command so the shortcut is ⌥⌘I, the family's inspector key.
        CommandGroup(after: .sidebar) {
            Button(showsInspector ? "Hide Inspector" : "Show Inspector") { showsInspector.toggle() }
                .keyboardShortcut("i", modifiers: [.command, .option])
        }
        CommandMenu("Gradient") {
            Button("Randomize") { model.randomize() }
                .keyboardShortcut("r")
            Button("Rename…") { model.beginRenaming() }
            Button("Use Automatic Name") { model.useAutomaticName() }
                .disabled(model.currentGradient?.hasCustomName != true)
            Divider()
            Menu("Style") {
                ForEach(Array(GradientMode.allCases.enumerated()), id: \.element) { index, mode in
                    // Toggles, so the current style shows a checkmark.
                    Toggle(mode.title, isOn: Binding(get: { model.recipe.mode == mode }, set: { if $0 { model.setMode(mode) } }))
                        .keyboardShortcut(KeyEquivalent(Character(String(index + 1))), modifiers: [.command, .option])
                }
            }
            Menu("Canvas Size") {
                ForEach(CanvasPreset.allCases) { preset in
                    Toggle(preset.title, isOn: Binding(
                        get: { CanvasPreset.matching(width: model.recipe.width, height: model.recipe.height) == preset },
                        set: { if $0 { model.setCanvasSize(width: preset.size.width, height: preset.size.height) } }
                    ))
                }
                Divider()
                Button("Custom Size…") { customSizeAction?() }
                    .disabled(customSizeAction == nil)
            }
            Toggle("Texture", isOn: Binding(get: { model.recipe.textureEnabled }, set: { model.recipe.textureEnabled = $0 }))
            Divider()
            Button(model.recipe.mode == .tonal ? "Shuffle Texture" : "Shuffle Flow") { model.shuffleMesh() }
                .disabled(model.recipe.mode != .organic && model.recipe.mode != .tonal)
            Button("Reset Style") { model.resetStyle() }
            Button("Reset Texture") { model.resetTexture() }
            Divider()
            Button("Remove All Colors") { model.removeAllColors() }
                .disabled(model.recipe.stops.isEmpty)
        }
        CommandMenu("Colors") {
            Button("New Collection…") { colorSheetAction?(.newCollection) }
                .disabled(colorSheetAction == nil)
            Button("New Collection from Gradient Colors") { model.createColorLibraryFromCurrentColors() }
                .disabled(model.recipe.stops.isEmpty)
            Button("Import Collection…") { model.importColorLibraryFromPanel() }
            Divider()
            // Collections have no selection, so these name their target in a submenu.
            Menu("Add Color") {
                ForEach(model.colorLibraries) { library in
                    Button("\(library.name)…") { colorSheetAction?(.addColor(libraryID: library.id)) }
                }
            }
            .disabled(colorSheetAction == nil || model.colorLibraries.isEmpty)
            Menu("Export Collection") {
                ForEach(model.colorLibraries) { library in
                    Button("\(library.name)…") { model.exportColorLibrary(id: library.id) }
                }
            }
            .disabled(model.colorLibraries.isEmpty)
        }
    }
}
