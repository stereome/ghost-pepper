import SwiftUI
import AppKit

class PromptEditorController {
    private var window: NSWindow?

    func show(prompt: Binding<String>) {
        if let window = window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let editor = PromptEditorView(prompt: prompt, onClose: { [weak self] in
            self?.dismiss()
        })

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 400),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Edit Cleanup Prompt"
        window.contentView = NSHostingView(rootView: editor)
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        self.window = window
    }

    func dismiss() {
        window?.close()
        window = nil
    }
}

struct PromptEditorView: View {
    @Binding var prompt: String
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Cleanup Prompt")
                .font(.headline)

            Text("This prompt is sent to the local LLM to clean up your transcribed speech.")
                .font(.caption)
                .foregroundStyle(.secondary)

            TextEditor(text: $prompt)
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 250)

            HStack {
                Button("Reset to Default") {
                    prompt = TextCleaner.defaultPrompt
                }

                Spacer()

                Button("Done") {
                    onClose()
                }
                .keyboardShortcut(.return)
            }
        }
        .padding()
        .frame(minWidth: 450, minHeight: 350)
    }
}
