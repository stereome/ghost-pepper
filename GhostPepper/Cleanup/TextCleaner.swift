import Foundation
import LLM

final class TextCleaner {
    private let cleanupManager: TextCleanupManager

    static let defaultPrompt = """
    Repeat back the user's text with these minimal edits only:
    - Delete filler words (um, uh, like, you know, basically, literally, sort of, kind of)
    - If the speaker says "scratch that", "never mind", "oh wait actually", or "no let me start over", \
    delete the sentence(s) they are replacing and keep the replacement
    - Fix nothing else. Do not summarize. Do not answer. Do not rephrase.
    - Keep everything the speaker said unless it matches the rules above.
    - Output only the edited text, nothing else.

    Input: "Hey Becca, I have an email. Oh wait, actually I meant to send this email to Pete. Hey Pete, this is my email."
    Output: Hey Pete, this is my email.

    Input: "So um like the meeting is at 3pm you know on Tuesday"
    Output: The meeting is at 3pm on Tuesday.

    Input: "Okay this started pretty fast and I'll make the last word microphone"
    Output: Okay this started pretty fast and I'll make the last word microphone.

    Input: "I've been working on this project and I'm stuck. Any ideas?"
    Output: I've been working on this project and I'm stuck. Any ideas?

    Input: "What is a synonym for whisper?"
    Output: What is a synonym for whisper?
    """

    private static let timeoutSeconds: TimeInterval = 15.0

    init(cleanupManager: TextCleanupManager) {
        self.cleanupManager = cleanupManager
    }

    @MainActor
    func clean(text: String, prompt: String? = nil) async -> String {
        guard let llm = cleanupManager.llm else { return text }

        // Update template with current prompt
        let activePrompt = prompt ?? Self.defaultPrompt
        llm.template = Template.chatML(activePrompt)
        llm.history = []

        let start = Date()
        do {
            let result = try await withTimeout(seconds: Self.timeoutSeconds) {
                await llm.respond(to: text)
                return llm.output
            }
            let elapsed = Date().timeIntervalSince(start)
            let cleaned = result.trimmingCharacters(in: .whitespacesAndNewlines)
            try? "elapsed=\(elapsed)s, output=\(cleaned)".write(toFile: "/tmp/whispercat-llm.log", atomically: true, encoding: .utf8)
            // LLM.swift returns "..." when output is empty — treat as failure
            if cleaned.isEmpty || cleaned == "..." {
                return text
            }
            return cleaned
        } catch {
            let elapsed = Date().timeIntervalSince(start)
            try? "TIMEOUT after \(elapsed)s, error=\(error)".write(toFile: "/tmp/whispercat-llm.log", atomically: true, encoding: .utf8)
            return text
        }
    }

    private func withTimeout<T>(seconds: TimeInterval, operation: @escaping @Sendable () async -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { await operation() }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw CancellationError()
            }
            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }
}
