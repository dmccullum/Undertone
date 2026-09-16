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
            window.titlebarAppearsTransparent = true
            window.titlebarSeparatorStyle = .none
            window.toolbarStyle = .unified
            window.backgroundColor = .windowBackgroundColor
        }
        DispatchQueue.main.async {
            NSApplication.shared.windows.forEach {
                $0.titlebarAppearsTransparent = true
                $0.titlebarSeparatorStyle = .none
                $0.toolbarStyle = .unified
                $0.backgroundColor = .windowBackgroundColor
            }
        }
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
                .frame(minWidth: 1_050, minHeight: 700)
        }
        .defaultSize(width: 1_280, height: 820)
        .windowToolbarStyle(.unified(showsTitle: true))
        .commands {
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
    }
}
