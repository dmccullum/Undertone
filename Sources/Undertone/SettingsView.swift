import SwiftUI

/// Undertone › Settings (⌘,): defaults for Export Image.
struct SettingsView: View {
    @AppStorage(ExportFormat.preference) private var exportFormat: ExportFormat = .png
    @AppStorage(ExportFormat.jpegQualityPreference) private var jpegQuality = ExportFormat.defaultJPEGQuality

    var body: some View {
        Form {
            Section {
                Picker("Export Format", selection: $exportFormat) {
                    ForEach(ExportFormat.allCases) { Text($0.title).tag($0) }
                }
                LabeledContent("JPEG Quality") {
                    HStack {
                        Slider(value: $jpegQuality, in: 0.5...1, step: 0.01)
                            .labelsHidden()
                            .accessibilityLabel("JPEG Quality")
                        Text("\(Int((jpegQuality * 100).rounded()))%")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 40, alignment: .trailing)
                    }
                }
            } footer: {
                Text("Export Image (⌘E) opens with this format selected; its save panel can switch to the other.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 500)
        .fixedSize(horizontal: false, vertical: true)
    }
}
