import AppKit
import SwiftUI

final class UndertoneAppDelegate: NSObject, NSApplicationDelegate {
    weak var model: StudioModel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            NSApplication.shared.windows.forEach(configure)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        model?.flushLastRecipe()
    }

    private func configure(_ window: NSWindow) {
        // Restrict window resizing without imposing a minimum on the split
        // view's intermediate layout proposals during sidebar animation.
        window.contentMinSize = NSSize(width: 1_050, height: 700)
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.backgroundColor = .windowBackgroundColor
    }
}

@main
struct UndertoneApp: App {
    @NSApplicationDelegateAdaptor(UndertoneAppDelegate.self) private var appDelegate
    @StateObject private var model = StudioModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
                .onAppear { appDelegate.model = model }
        }
        .defaultSize(width: 1_280, height: 820)
        .windowToolbarStyle(.unified(showsTitle: true))
        .commands {
            AboutCommands()

            CommandMenu("Recipe") {
                Button("Open Recipe…") {
                    model.openRecipe()
                }
                .keyboardShortcut("o", modifiers: [.command])

                Button("Save Recipe…") {
                    model.saveRecipe()
                }
                .keyboardShortcut("s", modifiers: [.command])
            }
        }

        Window("About Undertone", id: "about") {
            AboutView()
        }
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)
    }
}
