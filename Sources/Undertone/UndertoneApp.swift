import AppKit
import SwiftUI

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

@main
struct UndertoneApp: App {
    @NSApplicationDelegateAdaptor(UndertoneAppDelegate.self) private var appDelegate
    @State private var model = StudioModel()

    var body: some Scene {
        Window("Undertone", id: "studio") {
            ContentView()
                .environment(model)
                // ContentView sets the minimum width, which depends on whether the inspector is open.
                .frame(minHeight: 660)
        }
        .defaultSize(width: 1_320, height: 860)
        .windowToolbarStyle(.unified)
        .keyboardShortcut("0", modifiers: .command)
        .commands {
            AboutCommands()
            HelpCommands()
            SidebarCommands()
            InspectorCommands()
            StudioCommands(model: model)
        }
        Settings {
            SettingsView()
        }
    }
}

private struct AboutCommands: Commands {
    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("About Undertone") {
                NSApp.activate()
                AboutWindowController.shared.show()
            }
        }
    }
}

private struct HelpCommands: Commands {
    private static let usageURL = URL(string: "https://github.com/dmccullum/Undertone/blob/main/docs/USAGE.md")!

    var body: some Commands {
        CommandGroup(replacing: .help) {
            Button("Undertone Help") { NSWorkspace.shared.open(Self.usageURL) }
                .keyboardShortcut("?", modifiers: .command)
        }
    }
}

struct StudioCommands: Commands {
    let model: StudioModel

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
        }
    }
}
