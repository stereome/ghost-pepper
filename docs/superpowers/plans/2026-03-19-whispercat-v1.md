# WhisperCat V1 Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a macOS menu bar app that provides system-wide hold-Control-to-talk speech-to-text, running 100% locally via whisper.cpp.

**Architecture:** Pure Swift macOS app using SwiftUI for UI, AVAudioEngine for recording, whisper.cpp (via SPM) for transcription, and CGEvent for global hotkey monitoring and text pasting. Menu bar only, no dock icon.

**Tech Stack:** Swift, SwiftUI, AVFoundation, whisper.cpp (SPM), CGEvent/Quartz, AppKit (NSPanel, NSPasteboard)

**Spec:** `docs/superpowers/specs/2026-03-19-whispercat-design.md`

---

## File Structure

```
WhisperCat/
├── Package.swift                              # SPM manifest (whisper.cpp dependency)
├── scripts/
│   └── download-model.sh                      # Downloads ggml-small.en.bin from Hugging Face
├── WhisperCat/
│   ├── WhisperCatApp.swift                    # @main, MenuBarExtra, app orchestration
│   ├── AppState.swift                         # Observable app state (recording, transcribing, error)
│   ├── Audio/
│   │   ├── AudioRecorder.swift                # AVAudioEngine mic capture → [Float] buffer
│   │   └── SoundEffects.swift                 # NSSound playback for start/stop cues
│   ├── Transcription/
│   │   ├── WhisperTranscriber.swift           # whisper.cpp C interop wrapper
│   │   └── ModelManager.swift                 # Locates and loads model from app bundle
│   ├── Input/
│   │   ├── HotkeyMonitor.swift                # CGEvent tap for Control key
│   │   └── TextPaster.swift                   # Clipboard save/restore + Cmd+V simulation
│   ├── UI/
│   │   ├── MenuBarView.swift                  # Menu bar icon + dropdown
│   │   └── RecordingOverlay.swift             # Floating pill overlay at bottom of screen
│   └── Resources/
│       ├── start.aiff                         # Recording start sound
│       └── stop.aiff                          # Recording stop sound
├── WhisperCatTests/
│   ├── HotkeyMonitorTests.swift               # Tests for key combo filtering, timing logic
│   ├── TextPasterTests.swift                  # Tests for clipboard save/restore logic
│   ├── AudioRecorderTests.swift               # Tests for buffer management
│   └── WhisperTranscriberTests.swift          # Tests for transcription wrapper
└── Resources/
    └── models/                                # .gitignored, holds downloaded model files
        └── ggml-small.en.bin
```

---

## Task 1: Xcode Project Scaffolding

**Files:**
- Create: `WhisperCat.xcodeproj` (via Xcode CLI)
- Create: `WhisperCat/WhisperCatApp.swift`
- Create: `WhisperCat/AppState.swift`
- Create: `WhisperCat/Info.plist`
- Create: `WhisperCat/WhisperCat.entitlements`
- Create: `.gitignore`

- [ ] **Step 1: Initialize git repo and create .gitignore**

```bash
git init
```

```gitignore
# Xcode
build/
DerivedData/
*.xcuserstate
xcuserdata/

# Models (large binary files)
Resources/models/

# macOS
.DS_Store

# Swift Package Manager
.build/
.swiftpm/
```

- [ ] **Step 2: Create the Xcode project via command line**

We need a proper Xcode project (`.xcodeproj`) for this app — an SPM executable target won't give us an `.app` bundle, entitlements, Info.plist, or resource bundling.

**Create the Xcode project using Xcode:**
```bash
# Open Xcode and create: File → New → Project → macOS → App
# Settings:
#   Product Name: WhisperCat
#   Organization Identifier: com.whispercat
#   Interface: SwiftUI
#   Language: Swift
#   Uncheck "Include Tests" (we'll add a test target manually)
# Save to the project root directory
```

After creation, configure the project:
1. **Add whisper.cpp SPM dependency:** File → Add Package Dependencies → `https://github.com/ggerganov/whisper.cpp.git` (version 1.7.3+)
2. **Set deployment target:** macOS 14.0 in project settings
3. **Disable App Sandbox:** In Signing & Capabilities, remove the App Sandbox capability
4. **Add entitlements:** Add `WhisperCat.entitlements` with audio-input
5. **Set LSUIElement:** In Info.plist, set "Application is agent (UIElement)" = YES
6. **Add model to bundle:** Add a "Copy Bundle Resources" build phase that copies `Resources/models/ggml-small.en.bin` into the app bundle (file must exist first — run download script)
7. **Add test target:** File → New → Target → macOS → Unit Testing Bundle → "WhisperCatTests"

- [ ] **Step 3: Create entry point — WhisperCatApp.swift**

```swift
import SwiftUI

@main
struct WhisperCatApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(appState: appState)
        } label: {
            Image(systemName: appState.isRecording ? "waveform.circle.fill" : "waveform")
                .symbolRenderingMode(.palette)
                .foregroundStyle(appState.isRecording ? .red : .primary)
        }
    }
}
```

- [ ] **Step 4: Create AppState.swift**

```swift
import SwiftUI

enum AppStatus: String {
    case ready = "Ready"
    case recording = "Recording..."
    case transcribing = "Transcribing..."
    case error = "Error"
}

@MainActor
class AppState: ObservableObject {
    @Published var status: AppStatus = .ready
    @Published var isRecording: Bool = false
    @Published var errorMessage: String?

    var isReady: Bool {
        status == .ready
    }
}
```

- [ ] **Step 5: Create minimal MenuBarView.swift**

```swift
import SwiftUI

struct MenuBarView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(appState.status.rawValue)
                .font(.headline)

            if let error = appState.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Divider()

            Button("Quit WhisperCat") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
        .padding(8)
    }
}
```

- [ ] **Step 6: Create Info.plist with required keys**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>WhisperCat</string>
    <key>CFBundleIdentifier</key>
    <string>com.whispercat.app</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSMicrophoneUsageDescription</key>
    <string>WhisperCat needs microphone access to record your voice for transcription.</string>
</dict>
</plist>
```

`LSUIElement = true` hides the app from the Dock.

- [ ] **Step 7: Create entitlements file**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.app-sandbox</key>
    <false/>
    <key>com.apple.security.device.audio-input</key>
    <true/>
</dict>
</plist>
```

- [ ] **Step 8: Build and verify the app launches with menu bar icon**

Run: `xcodebuild build -scheme WhisperCat -configuration Debug`
Then run the app — verify a cat icon appears in the menu bar with the dropdown showing "Ready" and "Quit WhisperCat".

- [ ] **Step 9: Commit**

```bash
git add -A
git commit -m "feat: scaffold WhisperCat macOS menu bar app"
```

---

## Task 2: Model Download Script

**Files:**
- Create: `scripts/download-model.sh`

- [ ] **Step 1: Create download script**

```bash
#!/bin/bash
set -euo pipefail

MODEL_DIR="Resources/models"
MODEL_FILE="ggml-small.en.bin"
MODEL_PATH="${MODEL_DIR}/${MODEL_FILE}"
MODEL_URL="https://huggingface.co/ggerganov/whisper.cpp/resolve/main/${MODEL_FILE}"

if [ -f "${MODEL_PATH}" ]; then
    echo "Model already exists at ${MODEL_PATH}"
    exit 0
fi

mkdir -p "${MODEL_DIR}"
echo "Downloading ${MODEL_FILE} (~466 MB)..."
curl -L --progress-bar -o "${MODEL_PATH}" "${MODEL_URL}"
echo "Done. Model saved to ${MODEL_PATH}"
```

- [ ] **Step 2: Make executable and test**

Run:
```bash
chmod +x scripts/download-model.sh
./scripts/download-model.sh
```
Expected: Model downloads to `Resources/models/ggml-small.en.bin`

- [ ] **Step 3: Commit**

```bash
git add scripts/download-model.sh
git commit -m "feat: add model download script for ggml-small.en.bin"
```

---

## Task 3: whisper.cpp Integration + WhisperTranscriber

**Files:**
- Modify: `Package.swift` (add whisper.cpp dependency)
- Create: `WhisperCat/Transcription/ModelManager.swift`
- Create: `WhisperCat/Transcription/WhisperTranscriber.swift`
- Create: `WhisperCatTests/WhisperTranscriberTests.swift`

- [ ] **Step 1: Add whisper.cpp SPM dependency**

Update `Package.swift` to add the whisper.cpp dependency. The official repo at `https://github.com/ggerganov/whisper.cpp` includes SPM support:

```swift
dependencies: [
    .package(url: "https://github.com/ggerganov/whisper.cpp.git", from: "1.7.3")
],
```

And add the dependency to the target:
```swift
.executableTarget(
    name: "WhisperCat",
    dependencies: [
        .product(name: "whisper", package: "whisper.cpp")
    ],
    path: "WhisperCat"
),
```

Note: The exact product name may differ — check whisper.cpp's Package.swift for the correct product name. It may be `"whisper-cpp"` or `"Whisper"`. Resolve with `swift package resolve` and adjust.

- [ ] **Step 2: Write failing test for ModelManager**

```swift
// WhisperCatTests/WhisperTranscriberTests.swift
import XCTest
@testable import WhisperCat

final class ModelManagerTests: XCTestCase {
    func testModelPathResolution() {
        let manager = ModelManager()
        // When no model exists at the expected path, returns nil
        let path = manager.resolveModelPath(in: "/nonexistent")
        XCTAssertNil(path)
    }

    func testModelPathFindsExistingModel() {
        let manager = ModelManager()
        // When model exists, returns the path
        let tempDir = FileManager.default.temporaryDirectory.path()
        let modelPath = tempDir + "/ggml-small.en.bin"
        FileManager.default.createFile(atPath: modelPath, contents: Data([0x00]))
        defer { try? FileManager.default.removeItem(atPath: modelPath) }

        let resolved = manager.resolveModelPath(in: tempDir)
        XCTAssertEqual(resolved, modelPath)
    }
}
```

- [ ] **Step 3: Run test to verify it fails**

Run: `swift test --filter ModelManagerTests`
Expected: FAIL — `ModelManager` not defined

- [ ] **Step 4: Implement ModelManager**

```swift
// WhisperCat/Transcription/ModelManager.swift
import Foundation

class ModelManager {
    private let modelFileName = "ggml-small.en.bin"

    /// Resolves the model file path within a given directory.
    func resolveModelPath(in directory: String? = nil) -> String? {
        let searchDir = directory ?? Bundle.main.resourcePath ?? ""
        let path = (searchDir as NSString).appendingPathComponent(modelFileName)
        return FileManager.default.fileExists(atPath: path) ? path : nil
    }

    /// Resolves model path, checking bundle first, then Resources/models/.
    func findModel() -> String? {
        if let bundled = resolveModelPath() {
            return bundled
        }
        // Fallback for development: check project Resources/models/
        let devPath = "Resources/models"
        return resolveModelPath(in: devPath)
    }
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `swift test --filter ModelManagerTests`
Expected: PASS

- [ ] **Step 6: Write failing test for WhisperTranscriber**

```swift
final class WhisperTranscriberTests: XCTestCase {
    func testTranscriberInitFailsWithoutModel() async {
        let transcriber = WhisperTranscriber()
        let loaded = transcriber.loadModel(path: "/nonexistent/model.bin")
        XCTAssertFalse(loaded)
    }

    func testTranscriberHandlesEmptyAudio() async {
        let transcriber = WhisperTranscriber()
        let result = await transcriber.transcribe(audioBuffer: [])
        XCTAssertNil(result, "Empty audio should return nil")
    }
}
```

- [ ] **Step 7: Run test to verify it fails**

Run: `swift test --filter WhisperTranscriberTests`
Expected: FAIL

- [ ] **Step 8: Implement WhisperTranscriber**

```swift
// WhisperCat/Transcription/WhisperTranscriber.swift
import Foundation
import whisper

class WhisperTranscriber {
    private var context: OpaquePointer?
    private let queue = DispatchQueue(label: "com.whispercat.transcription", qos: .userInitiated)

    func loadModel(path: String) -> Bool {
        guard FileManager.default.fileExists(atPath: path) else { return false }
        context = whisper_init_from_file(path)
        return context != nil
    }

    func transcribe(audioBuffer: [Float]) async -> String? {
        guard !audioBuffer.isEmpty else { return nil }

        return await withCheckedContinuation { continuation in
            queue.async { [weak self] in
                guard let ctx = self?.context else {
                    continuation.resume(returning: nil)
                    return
                }
                var params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY)
                params.print_progress = false
                params.print_timestamps = false
                params.print_realtime = false
                params.print_special = false
                // Use a static string pointer — whisper only needs it valid during the call
                let langPtr = ("en" as NSString).utf8String
                params.language = langPtr
                params.n_threads = Int32(max(1, ProcessInfo.processInfo.activeProcessorCount - 2))

                let result = audioBuffer.withUnsafeBufferPointer { bufferPtr in
                    whisper_full(ctx, params, bufferPtr.baseAddress, Int32(audioBuffer.count))
                }

                guard result == 0 else {
                    continuation.resume(returning: nil)
                    return
                }

                let nSegments = whisper_full_n_segments(ctx)
                var text = ""
                for i in 0..<nSegments {
                    if let segmentText = whisper_full_get_segment_text(ctx, i) {
                        text += String(cString: segmentText)
                    }
                }

                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                continuation.resume(returning: trimmed.isEmpty ? nil : trimmed)
            }
        }
    }

    deinit {
        if let ctx = context {
            whisper_free(ctx)
        }
    }
}
```

- [ ] **Step 9: Run tests to verify they pass**

Run: `swift test --filter WhisperTranscriberTests`
Expected: PASS

- [ ] **Step 10: Commit**

```bash
git add -A
git commit -m "feat: add whisper.cpp integration with ModelManager and WhisperTranscriber"
```

---

## Task 4: AudioRecorder

**Files:**
- Create: `WhisperCat/Audio/AudioRecorder.swift`
- Create: `WhisperCatTests/AudioRecorderTests.swift`

- [ ] **Step 1: Write failing test for buffer management**

```swift
// WhisperCatTests/AudioRecorderTests.swift
import XCTest
@testable import WhisperCat

final class AudioRecorderTests: XCTestCase {
    func testBufferStartsEmpty() {
        let recorder = AudioRecorder()
        XCTAssertTrue(recorder.audioBuffer.isEmpty)
    }

    func testBufferClearsOnStartRecording() {
        let recorder = AudioRecorder()
        // Simulate some leftover data
        recorder.audioBuffer = [1.0, 2.0, 3.0]
        recorder.resetBuffer()
        XCTAssertTrue(recorder.audioBuffer.isEmpty)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter AudioRecorderTests`
Expected: FAIL

- [ ] **Step 3: Implement AudioRecorder**

```swift
// WhisperCat/Audio/AudioRecorder.swift
import AVFoundation

class AudioRecorder {
    private let audioEngine = AVAudioEngine()
    private let targetSampleRate: Double = 16000.0
    private(set) var audioBuffer: [Float] = []
    private var isCurrentlyRecording = false

    func resetBuffer() {
        audioBuffer = []
    }

    func startRecording() throws {
        resetBuffer()

        let inputNode = audioEngine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        // Install tap to capture audio
        let formatConverter = AVAudioConverter(
            from: inputFormat,
            to: AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: targetSampleRate, channels: 1, interleaved: false)!
        )!

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] buffer, _ in
            guard let self = self else { return }

            let outputFrameCapacity = AVAudioFrameCount(
                Double(buffer.frameLength) * self.targetSampleRate / inputFormat.sampleRate
            )
            guard let convertedBuffer = AVAudioPCMBuffer(
                pcmFormat: formatConverter.outputFormat,
                frameCapacity: outputFrameCapacity
            ) else { return }

            var error: NSError?
            var inputConsumed = false
            formatConverter.convert(to: convertedBuffer, error: &error) { _, outStatus in
                if inputConsumed {
                    outStatus.pointee = .noDataNow
                    return nil
                }
                inputConsumed = true
                outStatus.pointee = .haveData
                return buffer
            }

            if let channelData = convertedBuffer.floatChannelData?[0] {
                let frames = Int(convertedBuffer.frameLength)
                let newSamples = Array(UnsafeBufferPointer(start: channelData, count: frames))
                DispatchQueue.main.async {
                    self.audioBuffer.append(contentsOf: newSamples)
                }
            }
        }

        audioEngine.prepare()
        try audioEngine.start()
        isCurrentlyRecording = true
    }

    func stopRecording() -> [Float] {
        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.stop()
        isCurrentlyRecording = false
        // Drain any pending main queue blocks to capture trailing audio samples
        // This ensures all async buffer appends have completed before we return
        DispatchQueue.main.sync {} // no-op sync to flush pending async blocks
        return audioBuffer
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter AudioRecorderTests`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat: add AudioRecorder with AVAudioEngine mic capture"
```

---

## Task 5: HotkeyMonitor

**Files:**
- Create: `WhisperCat/Input/HotkeyMonitor.swift`
- Create: `WhisperCatTests/HotkeyMonitorTests.swift`

- [ ] **Step 1: Write failing test for key filtering logic**

```swift
// WhisperCatTests/HotkeyMonitorTests.swift
import XCTest
@testable import WhisperCat

final class HotkeyMonitorTests: XCTestCase {
    func testControlOnlyDetection() {
        // Control flag alone = true
        let controlOnly: CGEventFlags = .maskControl
        XCTAssertTrue(HotkeyMonitor.isControlOnly(flags: controlOnly))
    }

    func testControlWithOtherModifierRejected() {
        // Control + Command = not control-only
        let controlCmd: CGEventFlags = [.maskControl, .maskCommand]
        XCTAssertFalse(HotkeyMonitor.isControlOnly(flags: controlCmd))
    }

    func testNoControlRejected() {
        let noFlags: CGEventFlags = []
        XCTAssertFalse(HotkeyMonitor.isControlOnly(flags: noFlags))
    }

    func testMinimumHoldDuration() {
        let monitor = HotkeyMonitor()
        // Press for less than 0.3 seconds should be ignored
        let shortDuration: TimeInterval = 0.2
        XCTAssertFalse(monitor.isHoldLongEnough(duration: shortDuration))

        // Press for 0.3+ seconds should trigger
        let longDuration: TimeInterval = 0.4
        XCTAssertTrue(monitor.isHoldLongEnough(duration: longDuration))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter HotkeyMonitorTests`
Expected: FAIL

- [ ] **Step 3: Implement HotkeyMonitor**

```swift
// WhisperCat/Input/HotkeyMonitor.swift
import Cocoa
import CoreGraphics

class HotkeyMonitor {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var controlPressTime: Date?
    private var otherKeyPressed = false
    private var holdTimer: DispatchWorkItem?

    var onRecordingStart: (() -> Void)?
    var onRecordingStop: (() -> Void)?

    private static let minimumHoldDuration: TimeInterval = 0.3
    private static let modifierMask: CGEventFlags = [.maskControl, .maskAlternate, .maskCommand, .maskShift]

    static func isControlOnly(flags: CGEventFlags) -> Bool {
        let active = flags.intersection(modifierMask)
        return active == .maskControl
    }

    func isHoldLongEnough(duration: TimeInterval) -> Bool {
        return duration >= Self.minimumHoldDuration
    }

    func start() -> Bool {
        let eventMask: CGEventMask = (1 << CGEventType.flagsChanged.rawValue)
            | (1 << CGEventType.keyDown.rawValue)

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: { _, type, event, refcon -> Unmanaged<CGEvent>? in
                guard let refcon = refcon else { return Unmanaged.passRetained(event) }
                let monitor = Unmanaged<HotkeyMonitor>.fromOpaque(refcon).takeUnretainedValue()
                return monitor.handleEvent(type: type, event: event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            return false
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    private func handleEvent(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .keyDown {
            // Another key was pressed while Control is held — this is a combo (Ctrl+C etc.)
            // Cancel the hold timer so recording never starts
            if controlPressTime != nil {
                otherKeyPressed = true
                holdTimer?.cancel()
                holdTimer = nil
            }
            return Unmanaged.passRetained(event)
        }

        guard type == .flagsChanged else {
            return Unmanaged.passRetained(event)
        }

        let flags = event.flags

        if Self.isControlOnly(flags: flags) && controlPressTime == nil {
            // Control pressed — start a 0.3s timer before activating recording
            // This prevents overlay/sound flash on short taps and Ctrl+key combos
            controlPressTime = Date()
            otherKeyPressed = false

            let timer = DispatchWorkItem { [weak self] in
                guard let self = self, self.controlPressTime != nil, !self.otherKeyPressed else { return }
                self.onRecordingStart?()
            }
            holdTimer = timer
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.minimumHoldDuration, execute: timer)

        } else if !flags.contains(.maskControl) && controlPressTime != nil {
            // Control released
            let wasRecording = holdTimer == nil || holdTimer?.isCancelled == true
            holdTimer?.cancel()
            holdTimer = nil
            controlPressTime = nil

            // Only fire stop if recording actually started (timer had fired) and no combo keys
            if !otherKeyPressed && wasRecording {
                onRecordingStop?()
            }
            otherKeyPressed = false
        }

        return Unmanaged.passRetained(event)
    }

    func stop() {
        holdTimer?.cancel()
        holdTimer = nil
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
    }
}
```

Note: The `start()` method returns `false` if Accessibility permission is not granted — the CGEvent tap will fail to create.

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter HotkeyMonitorTests`
Expected: PASS (the pure logic tests pass; the CGEvent tap itself requires Accessibility permission and is tested manually)

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat: add HotkeyMonitor with CGEvent tap for Control key"
```

---

## Task 6: TextPaster

**Files:**
- Create: `WhisperCat/Input/TextPaster.swift`
- Create: `WhisperCatTests/TextPasterTests.swift`

- [ ] **Step 1: Write failing test for clipboard save/restore**

```swift
// WhisperCatTests/TextPasterTests.swift
import XCTest
@testable import WhisperCat

final class TextPasterTests: XCTestCase {
    func testSaveAndRestoreClipboard() {
        let paster = TextPaster()

        // Set known clipboard content
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString("original content", forType: .string)

        // Save clipboard state
        let saved = paster.saveClipboard()
        XCTAssertNotNil(saved)

        // Overwrite clipboard
        pasteboard.clearContents()
        pasteboard.setString("new content", forType: .string)

        // Restore
        paster.restoreClipboard(saved!)

        // Verify original content is back
        XCTAssertEqual(pasteboard.string(forType: .string), "original content")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter TextPasterTests`
Expected: FAIL

- [ ] **Step 3: Implement TextPaster**

```swift
// WhisperCat/Input/TextPaster.swift
import Cocoa

struct ClipboardState {
    let items: [NSPasteboardItem]
    let types: [[NSPasteboard.PasteboardType]]
    let data: [[(NSPasteboard.PasteboardType, Data)]]
}

class TextPaster {
    private static let delayBeforePaste: TimeInterval = 0.05
    private static let delayBeforeRestore: TimeInterval = 0.1

    func saveClipboard() -> ClipboardState? {
        let pasteboard = NSPasteboard.general
        guard let items = pasteboard.pasteboardItems, !items.isEmpty else { return nil }

        var allData: [[(NSPasteboard.PasteboardType, Data)]] = []
        var allTypes: [[NSPasteboard.PasteboardType]] = []

        for item in items {
            let types = item.types
            var itemData: [(NSPasteboard.PasteboardType, Data)] = []
            for type in types {
                if let data = item.data(forType: type) {
                    itemData.append((type, data))
                }
            }
            allTypes.append(types)
            allData.append(itemData)
        }

        return ClipboardState(items: items, types: allTypes, data: allData)
    }

    func restoreClipboard(_ state: ClipboardState) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        // Collect all items first, then write once — writeObjects replaces, not appends
        var newItems: [NSPasteboardItem] = []
        for itemData in state.data {
            let newItem = NSPasteboardItem()
            for (type, data) in itemData {
                newItem.setData(data, forType: type)
            }
            newItems.append(newItem)
        }
        pasteboard.writeObjects(newItems)
    }

    func paste(text: String) {
        // Save current clipboard
        let savedState = saveClipboard()

        // Write text to clipboard
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        // Simulate Cmd+V after short delay
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.delayBeforePaste) {
            self.simulateCmdV()

            // Restore clipboard after paste completes
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.delayBeforeRestore) {
                if let saved = savedState {
                    self.restoreClipboard(saved)
                }
            }
        }
    }

    private func simulateCmdV() {
        let source = CGEventSource(stateID: .hidSystemState)

        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true) // 0x09 = 'v'
        keyDown?.flags = .maskCommand
        keyDown?.post(tap: .cghidEventTap)

        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)
        keyUp?.flags = .maskCommand
        keyUp?.post(tap: .cghidEventTap)
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter TextPasterTests`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat: add TextPaster with clipboard save/restore and Cmd+V simulation"
```

---

## Task 7: SoundEffects

**Files:**
- Create: `WhisperCat/Audio/SoundEffects.swift`
- Create: `WhisperCat/Resources/start.aiff` (system sound)
- Create: `WhisperCat/Resources/stop.aiff` (system sound)

- [ ] **Step 1: Implement SoundEffects using system sounds**

For v1, use macOS built-in system sounds rather than bundling custom .aiff files. This avoids needing audio assets.

```swift
// WhisperCat/Audio/SoundEffects.swift
import AppKit

class SoundEffects {
    private let startSound: NSSound?
    private let stopSound: NSSound?

    init() {
        // Use system sounds — Tink for start, Pop for stop
        startSound = NSSound(named: "Tink")
        stopSound = NSSound(named: "Pop")
    }

    func playStart() {
        startSound?.stop()
        startSound?.play()
    }

    func playStop() {
        stopSound?.stop()
        stopSound?.play()
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add -A
git commit -m "feat: add SoundEffects using macOS system sounds"
```

---

## Task 8: RecordingOverlay

**Files:**
- Create: `WhisperCat/UI/RecordingOverlay.swift`

- [ ] **Step 1: Implement floating overlay**

```swift
// WhisperCat/UI/RecordingOverlay.swift
import SwiftUI
import AppKit

class RecordingOverlayController {
    private var panel: NSPanel?

    func show() {
        guard panel == nil else { return }

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 180, height: 44),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .floating
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let hostingView = NSHostingView(rootView: RecordingPillView())
        panel.contentView = hostingView

        // Position at bottom center of main screen
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let x = screenFrame.midX - 90
            let y = screenFrame.minY + 40
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }

        panel.orderFrontRegardless()
        self.panel = panel
    }

    func dismiss() {
        panel?.orderOut(nil)
        panel = nil
    }
}

struct RecordingPillView: View {
    @State private var isPulsing = false

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(.red)
                .frame(width: 10, height: 10)
                .opacity(isPulsing ? 0.4 : 1.0)
                .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true), value: isPulsing)

            Text("Recording...")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            Capsule()
                .fill(.black.opacity(0.85))
        )
        .onAppear { isPulsing = true }
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add -A
git commit -m "feat: add floating recording overlay pill"
```

---

## Task 9: Permission Handling

**Files:**
- Create: `WhisperCat/PermissionChecker.swift`

- [ ] **Step 1: Implement permission checks**

```swift
// WhisperCat/PermissionChecker.swift
import Cocoa
import AVFoundation

class PermissionChecker {
    enum Permission {
        case accessibility
        case microphone
    }

    static func checkAccessibility() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): false] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    static func promptAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    static func checkMicrophone() async -> Bool {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        switch status {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .audio)
        default:
            return false
        }
    }

    static func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    static func openMicrophoneSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
            NSWorkspace.shared.open(url)
        }
    }
}
```

- [ ] **Step 2: Update MenuBarView to show permission status**

Update `WhisperCat/UI/MenuBarView.swift`:

```swift
import SwiftUI

struct MenuBarView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(appState.status.rawValue)
                .font(.headline)

            if let error = appState.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)

                if error.contains("Accessibility") {
                    Button("Open Accessibility Settings") {
                        PermissionChecker.openAccessibilitySettings()
                    }
                }
                if error.contains("Microphone") {
                    Button("Open Microphone Settings") {
                        PermissionChecker.openMicrophoneSettings()
                    }
                }
            }

            Divider()

            Button("Quit WhisperCat") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
        .padding(8)
    }
}
```

- [ ] **Step 3: Commit**

```bash
git add -A
git commit -m "feat: add permission checking and settings navigation"
```

---

## Task 10: Wire Everything Together — App Orchestration

**Files:**
- Modify: `WhisperCat/WhisperCatApp.swift`
- Modify: `WhisperCat/AppState.swift`

This is the integration task that connects all components.

- [ ] **Step 1: Expand AppState to hold all component references**

```swift
// WhisperCat/AppState.swift
import SwiftUI

enum AppStatus: String {
    case ready = "Ready"
    case recording = "Recording..."
    case transcribing = "Transcribing..."
    case error = "Error"
}

@MainActor
class AppState: ObservableObject {
    @Published var status: AppStatus = .ready
    @Published var isRecording: Bool = false
    @Published var errorMessage: String?

    let audioRecorder = AudioRecorder()
    let transcriber = WhisperTranscriber()
    let textPaster = TextPaster()
    let soundEffects = SoundEffects()
    let hotkeyMonitor = HotkeyMonitor()
    let overlay = RecordingOverlayController()
    let modelManager = ModelManager()

    var isReady: Bool {
        status == .ready
    }

    func initialize() async {
        // Check permissions
        let hasMic = await PermissionChecker.checkMicrophone()
        if !hasMic {
            errorMessage = "Microphone access required"
            status = .error
            return
        }

        if !PermissionChecker.checkAccessibility() {
            PermissionChecker.promptAccessibility()
            errorMessage = "Accessibility access required — grant permission and relaunch"
            status = .error
            return
        }

        // Load model
        guard let modelPath = modelManager.findModel() else {
            errorMessage = "Model not found. Run scripts/download-model.sh first."
            status = .error
            return
        }

        guard transcriber.loadModel(path: modelPath) else {
            errorMessage = "Failed to load whisper model"
            status = .error
            return
        }

        // Set up hotkey callbacks
        hotkeyMonitor.onRecordingStart = { [weak self] in
            Task { @MainActor in
                self?.startRecording()
            }
        }
        hotkeyMonitor.onRecordingStop = { [weak self] in
            Task { @MainActor in
                await self?.stopRecordingAndTranscribe()
            }
        }

        guard hotkeyMonitor.start() else {
            errorMessage = "Failed to start hotkey monitor — check Accessibility permission"
            status = .error
            return
        }

        status = .ready
        errorMessage = nil
    }

    private func startRecording() {
        guard status == .ready else { return }

        do {
            try audioRecorder.startRecording()
            soundEffects.playStart()
            overlay.show()
            isRecording = true
            status = .recording
        } catch {
            errorMessage = "Failed to start recording: \(error.localizedDescription)"
            status = .error
        }
    }

    private func stopRecordingAndTranscribe() async {
        guard status == .recording else { return }

        let buffer = audioRecorder.stopRecording()
        soundEffects.playStop()
        overlay.dismiss()
        isRecording = false
        status = .transcribing

        if let text = await transcriber.transcribe(audioBuffer: buffer) {
            textPaster.paste(text: text)
        }

        status = .ready
    }
}
```

- [ ] **Step 2: Update WhisperCatApp.swift entry point**

```swift
// WhisperCat/WhisperCatApp.swift
import SwiftUI

@main
struct WhisperCatApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(appState: appState)
        } label: {
            Image(systemName: appState.isRecording ? "waveform.circle.fill" : "waveform")
                .symbolRenderingMode(.palette)
                .foregroundStyle(appState.isRecording ? .red : .primary)
        }
        .onChange(of: appState.status) { _, _ in }
        .task {
            await appState.initialize()
        }
    }
}
```

- [ ] **Step 3: Build the complete app**

Run: `xcodebuild build -scheme WhisperCat -configuration Debug`
Expected: Build succeeds with no errors

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "feat: wire all components together in app orchestration"
```

---

## Task 11: Manual Integration Test

This task verifies the complete end-to-end flow on the real system.

- [ ] **Step 1: Ensure model is downloaded**

Run: `./scripts/download-model.sh`

- [ ] **Step 2: Build and run the app**

Run: `xcodebuild build -scheme WhisperCat -configuration Debug && open DerivedData/Build/Products/Debug/WhisperCat.app`

- [ ] **Step 3: Verify checklist**

1. Cat icon appears in menu bar
2. Click icon — dropdown shows "Ready"
3. Grant Accessibility permission when prompted
4. Grant Microphone permission when prompted
5. Hold Control for 1+ seconds while speaking — overlay pill appears, start sound plays
6. Release Control — stop sound plays, overlay dismisses, icon returns to idle
7. Text appears in the focused text field (open TextEdit or Notes to test)
8. Original clipboard contents are preserved after paste

- [ ] **Step 4: Commit any fixes from testing**

```bash
git add -A
git commit -m "fix: integration test adjustments"
```

---

## Summary

| Task | Component | Dependencies |
|------|-----------|-------------|
| 1 | Project scaffolding | None |
| 2 | Model download script | None |
| 3 | whisper.cpp + Transcriber | Task 1 |
| 4 | AudioRecorder | Task 1 |
| 5 | HotkeyMonitor | Task 1 |
| 6 | TextPaster | Task 1 |
| 7 | SoundEffects | Task 1 |
| 8 | RecordingOverlay | Task 1 |
| 9 | Permission handling | Task 1 |
| 10 | App orchestration | Tasks 3-9 |
| 11 | Integration test | Task 10 |

Tasks 2-9 can be parallelized (all depend only on Task 1). Task 10 depends on all of them. Task 11 depends on Task 10.
