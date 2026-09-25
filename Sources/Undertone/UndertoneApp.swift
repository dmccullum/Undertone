import AppKit
import SwiftUI

@MainActor final class UndertoneAppDelegate: NSObject, NSApplicationDelegate {
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
        Task { @MainActor in
            NSApplication.shared.windows.forEach { UndertoneAppDelegate.style($0) }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    private static func style(_ window: NSWindow) {
        window.styleMask.insert(.fullSizeContentView)
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.toolbarStyle = .unified
        window.backgroundColor = .windowBackgroundColor
    }
}

@main
struct UndertoneApp: App {
    @NSApplicationDelegateAdaptor(UndertoneAppDelegate.self) private var appDelegate
    @StateObject private var model = StudioModel()

    var body: some Scene {
        Window("Undertone", id: "studio") {
            ContentView()
                .environmentObject(model)
                .frame(minWidth: 980, minHeight: 660)
        }
        .defaultSize(width: 1_320, height: 860)
        .windowToolbarStyle(.unified(showsTitle: false))
        .commands {
            SidebarCommands()
            StudioCommands(model: model)
        }
    }
}

struct StudioCommands: Commands {
    @ObservedObject var model: StudioModel

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
        CommandGroup(replacing: .saveItem) {
            Button("Save") { model.saveNow(confirm: true) }
                .keyboardShortcut("s")
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
            Button("Rename…") {
                if let id = model.currentGradientID { model.beginRenaming(id: id) }
            }
            Button("Use Automatic Name") { model.useAutomaticName() }
            Divider()
            Menu("Style") {
                ForEach(Array(GradientMode.allCases.enumerated()), id: \.element) { index, mode in
                    Button(mode.title) { model.setMode(mode) }
                        .keyboardShortcut(KeyEquivalent(Character(String(index + 1))), modifiers: [.command, .option])
                }
            }
            Divider()
            Button("Delete Gradient") {
                if let id = model.currentGradientID { model.deleteGradient(id: id) }
            }
            .keyboardShortcut(.delete, modifiers: [.command])
        }
    }
}
