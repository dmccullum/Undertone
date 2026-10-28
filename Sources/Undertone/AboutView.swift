import AppKit
import SwiftUI

final class AboutWindowController: NSWindowController {
    static let shared = AboutWindowController()
    /// Lets the app delegate's window styling skip this panel, which draws its own backdrop.
    static let windowIdentifier = NSUserInterfaceItemIdentifier("about")

    private init() {
        let hostingController = NSHostingController(rootView: AboutView())
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: NSSize(width: 420, height: 350)),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.identifier = Self.windowIdentifier
        panel.contentViewController = hostingController
        panel.title = "About Undertone"
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.isReleasedWhenClosed = false
        panel.isRestorable = false
        panel.isExcludedFromWindowsMenu = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        super.init(window: panel)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show() {
        guard let window else { return }
        if !window.isVisible {
            window.center()
        }
        showWindow(nil)
        window.makeKeyAndOrderFront(nil)
    }
}

/// The default recipe's colors, lifted a little so they read on dark glass.
private enum AboutPalette {
    static let peach = Color(red: 0.95, green: 0.67, blue: 0.57)
    static let violet = Color(red: 0.58, green: 0.45, blue: 0.80)
    static let gold = Color(red: 0.95, green: 0.80, blue: 0.57)
    static let slate = Color(red: 0.45, green: 0.58, blue: 0.76)
}

struct AboutView: View {
    private var versionLine: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "Version \(version) (\(build))"
    }

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()

            LinearGradient(
                colors: [
                    AboutPalette.peach.opacity(0.16),
                    Color.clear,
                    AboutPalette.slate.opacity(0.10)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            Circle()
                .fill(AboutPalette.violet.opacity(0.16))
                .frame(width: 190, height: 190)
                .blur(radius: 52)
                .offset(x: 155, y: -125)

            Circle()
                .fill(AboutPalette.gold.opacity(0.10))
                .frame(width: 170, height: 170)
                .blur(radius: 52)
                .offset(x: -150, y: 135)

            VStack(spacing: 0) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 86, height: 86)
                    .shadow(color: .black.opacity(0.28), radius: 18, y: 8)
                    .padding(.bottom, 13)
                    .accessibilityHidden(true)

                Text("Undertone")
                    .font(.system(size: 28, weight: .semibold, design: .rounded))

                Text("Soft color, finished with fine grain.")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.top, 8)

                StudioSignature()
                    .padding(.top, 23)

                Text(versionLine)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary.opacity(0.72))
                    .padding(.top, 22)

                Text("Made with love by Daniel McCullum")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.tertiary)
                    .padding(.top, 3)
            }
            .padding(.top, 18)
        }
        .frame(width: 420, height: 350)
        .background(.regularMaterial, ignoresSafeAreaEdges: .all)
    }
}

private struct StudioSignature: View {
    private let stages: [(symbol: String, tint: Color)] = [
        ("swatchpalette", AboutPalette.peach),
        ("scribble.variable", AboutPalette.violet),
        ("aqi.medium", AboutPalette.gold),
        ("photo", AboutPalette.slate)
    ]

    var body: some View {
        HStack(spacing: 10) {
            ForEach(Array(stages.enumerated()), id: \.offset) { index, stage in
                Image(systemName: stage.symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(stage.tint)
                    .frame(width: 24, height: 24)

                if index < stages.count - 1 {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(.quaternary)
                }
            }
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 8)
        .background(.thinMaterial, in: Capsule())
        .overlay {
            Capsule()
                .strokeBorder(.white.opacity(0.09), lineWidth: 0.5)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Pick colors, shape the flow, add grain, and export an image")
    }
}
