import AppKit
import SwiftUI

struct AboutView: View {
    var body: some View {
        ZStack {
            aboutBackground

            VStack(spacing: 0) {
                Image(nsImage: NSApplication.shared.applicationIconImage)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 124, height: 124)
                    .shadow(color: .black.opacity(0.34), radius: 22, y: 10)
                    .accessibilityHidden(true)

                Text("Undertone")
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.95))
                    .padding(.top, 22)

                Text("Expressive gradients, made on your Mac.")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.56))
                    .padding(.top, 10)

                featureFlow
                    .padding(.top, 32)

                Spacer()

                Text(versionDescription)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.42))

                Text("Made with love by Daniel McCullum")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.32))
                    .padding(.top, 7)
            }
            .multilineTextAlignment(.center)
            .padding(.top, 70)
            .padding(.bottom, 38)
        }
        .frame(width: 560, height: 510)
        .preferredColorScheme(.dark)
    }

    private var aboutBackground: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.12, green: 0.15, blue: 0.23),
                    Color(red: 0.13, green: 0.13, blue: 0.20),
                    Color(red: 0.10, green: 0.18, blue: 0.21)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RadialGradient(
                colors: [Color.indigo.opacity(0.18), .clear],
                center: .topLeading,
                startRadius: 10,
                endRadius: 420
            )

            RadialGradient(
                colors: [Color.cyan.opacity(0.10), .clear],
                center: .bottomTrailing,
                startRadius: 20,
                endRadius: 360
            )
        }
        .ignoresSafeArea()
    }

    private var featureFlow: some View {
        HStack(spacing: 17) {
            flowIcon("paintpalette.fill", color: .blue)
            chevron
            flowIcon("circle.hexagongrid.fill", color: .cyan)
            chevron
            flowIcon("sparkles", color: .purple)
            chevron
            flowIcon("photo.fill", color: .mint)
            chevron
            flowIcon("square.and.arrow.up", color: .cyan)
        }
        .padding(.horizontal, 25)
        .frame(height: 54)
        .background(.black.opacity(0.09), in: Capsule())
        .overlay {
            Capsule()
                .stroke(.white.opacity(0.09), lineWidth: 1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Choose colors, compose a gradient, add texture, preview, and export")
    }

    private func flowIcon(_ name: String, color: Color) -> some View {
        Image(systemName: name)
            .font(.system(size: 20, weight: .medium))
            .foregroundStyle(color)
            .frame(width: 24)
    }

    private var chevron: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(.white.opacity(0.16))
    }

    private var versionDescription: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String
        let build = info?["CFBundleVersion"] as? String

        switch (version, build) {
        case let (.some(version), .some(build)):
            return "Version \(version) (\(build))"
        case let (.some(version), .none):
            return "Version \(version)"
        default:
            return "Development Build"
        }
    }
}

struct AboutCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("About Undertone") {
                openWindow(id: "about")
            }
        }
    }
}
