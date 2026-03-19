import Foundation
import LLM

final class TextCleaner {
    private let cleanupManager: TextCleanupManager

    static let defaultPrompt = """
    You clean up speech transcriptions. Rules: \
    1. Remove ALL filler words (um, uh, like, you know, so, basically, literally, right, okay). \
    2. When the speaker corrects themselves or changes their mind (e.g. "oh wait", "actually", "no let me say", "I mean", "sorry"), \
    DISCARD everything before the correction and keep ONLY what they said after correcting themselves. \
    3. Remove false starts and abandoned sentences. \
    4. Do not add, rephrase, or change any words the speaker intended to say. \
    5. If the text is already clean, return it unchanged. \
    Output ONLY the cleaned text. No explanations, no quotes.
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
            return cleaned.isEmpty ? text : cleaned
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
