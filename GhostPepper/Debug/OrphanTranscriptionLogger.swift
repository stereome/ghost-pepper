import Foundation

/// Logs transcriptions that couldn't be pasted because no text field was focused.
/// Saves to ~/Library/Application Support/GhostPepper/orphan-transcriptions.log
final class OrphanTranscriptionLogger {
    static let shared = OrphanTranscriptionLogger()

    private let fileURL: URL
    private let formatter: ISO8601DateFormatter

    init(fileURL: URL? = nil) {
        self.formatter = ISO8601DateFormatter()
        self.fileURL = fileURL ?? Self.defaultFileURL
    }

    func log(text: String) {
        let timestamp = formatter.string(from: Date())
        let entry = "[\(timestamp)] \(text)\n"

        let directory = fileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        if FileManager.default.fileExists(atPath: fileURL.path) {
            if let handle = try? FileHandle(forWritingTo: fileURL) {
                handle.seekToEndOfFile()
                handle.write(entry.data(using: .utf8)!)
                handle.closeFile()
            }
        } else {
            try? entry.data(using: .utf8)?.write(to: fileURL, options: .atomic)
        }
    }

    private static var defaultFileURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport
            .appendingPathComponent("GhostPepper", isDirectory: true)
            .appendingPathComponent("orphan-transcriptions.log")
    }
}
