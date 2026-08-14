import S950Library
import SwiftUI

struct FindDiagnosticLogView: View {
    @ObservedObject var model: Find950Model

    var body: some View {
        FindDiagnosticLogContents(
            diagnostics: model.diagnostics,
            onCopy: model.copyDiagnosticLog,
            onSave: model.saveDiagnosticLog,
            onReveal: model.revealDiagnosticLog,
            onClear: model.clearDiagnosticLog,
            onClose: { model.isLogVisible = false }
        )
    }
}

private struct FindDiagnosticLogContents: View {
    @ObservedObject var diagnostics: DiagnosticLogStore
    let onCopy: () -> Void
    let onSave: () -> Void
    let onReveal: () -> Void
    let onClear: () -> Void
    let onClose: () -> Void

    @State private var confirmClear = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label("Diagnostic Activity Log", systemImage: "waveform.path.ecg")
                    .font(SuiteFont.medium(10))
                Text("ROLLING · \(diagnostics.text.utf8.count.formatted()) BYTES")
                    .font(SuiteFont.regular(9))
                    .foregroundStyle(Color.suiteUnit)
                Spacer()
                Button("Copy", action: onCopy)
                    .buttonStyle(.borderless)
                    .help("Copy the visible diagnostic timeline")
                Button("Save…", action: onSave)
                    .buttonStyle(.borderless)
                    .help("Save a readable copy for a bug report")
                Button("Reveal", action: onReveal)
                    .buttonStyle(.borderless)
                    .help("Reveal the live rolling log in Finder")
                Button("Clear") { confirmClear = true }
                    .buttonStyle(.borderless)
                    .help("Clear earlier diagnostic entries")
                Button(action: onClose) {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.borderless)
                .help("Hide diagnostic log")
            }
            .padding(.horizontal, 12)
            .frame(height: 32)
            Divider()
            if let warning = diagnostics.storageWarning {
                Label(
                    "The activity is visible here, but the rolling file could not be updated: \(warning)",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(SuiteFont.regular(9))
                .foregroundStyle(Color.suiteAmber)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                Divider()
            }
            ScrollViewReader { proxy in
                ScrollView {
                    Text(
                        diagnostics.text.isEmpty
                            ? "Activity, library scans, dialogue state, exports, handoffs, audition and errors will appear here."
                            : diagnostics.text
                    )
                    .font(SuiteFont.regular(10))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(10)
                    Color.clear.frame(height: 1).id("find-diagnostic-log-end")
                }
                .onAppear { proxy.scrollTo("find-diagnostic-log-end", anchor: .bottom) }
                .onChange(of: diagnostics.text) { _, _ in
                    proxy.scrollTo("find-diagnostic-log-end", anchor: .bottom)
                }
            }
            .background(Color.suiteBackground)
        }
        .alert("Clear the diagnostic log?", isPresented: $confirmClear) {
            Button("Cancel", role: .cancel) {}
            Button("Clear Log", role: .destructive, action: onClear)
        } message: {
            Text("Earlier entries will be removed. FIND950 will immediately continue recording new activity.")
        }
    }
}
