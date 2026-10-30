import AVFoundation
import Foundation
import Speech

/// On-device speech-to-text (Apple Speech framework). Audio never leaves the phone;
/// only the resulting text goes to the parser, after the user stops recording.
///
/// Deliberately not main-actor isolated: AVAudioEngine calls the tap block on its own
/// audio thread, and Swift 6 traps if a main-actor closure runs there.
final class SpeechTranscriber: @unchecked Sendable {
    enum TranscriberError: LocalizedError {
        case notAuthorized, unavailable
        var errorDescription: String? {
            switch self {
            case .notAuthorized: "Allow microphone and speech recognition in Settings to describe pain by voice."
            case .unavailable: "On-device speech recognition isn't available for your language on this device."
            }
        }
    }

    private let lock = NSLock()
    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    /// Asks for microphone and speech permission (once).
    static func requestPermission() async -> Bool {
        let speech = await withCheckedContinuation { (c: CheckedContinuation<Bool, Never>) in
            SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0 == .authorized) }
        }
        guard speech else { return false }
        return await AVAudioApplication.requestRecordPermission()
    }

    /// Starts recording. `onText` receives the running transcript (on the main actor).
    func start(onText: @escaping @MainActor @Sendable (String) -> Void) throws {
        guard let recognizer = SFSpeechRecognizer(), recognizer.isAvailable, recognizer.supportsOnDeviceRecognition else {
            throw TranscriberError.unavailable
        }
        stop()

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: .duckOthers)
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = true
        request.addsPunctuation = true

        let input = engine.inputNode
        input.installTap(onBus: 0, bufferSize: 1024, format: input.outputFormat(forBus: 0)) { buffer, _ in
            request.append(buffer)
        }
        engine.prepare()
        try engine.start()

        let task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            if let text = result?.bestTranscription.formattedString {
                Task { @MainActor in onText(text) }
            }
            if error != nil || result?.isFinal == true { self?.stop() }
        }
        lock.withLock {
            self.request = request
            self.task = task
        }
    }

    func stop() {
        let (request, task) = lock.withLock { () -> (SFSpeechAudioBufferRecognitionRequest?, SFSpeechRecognitionTask?) in
            defer { self.request = nil; self.task = nil }
            return (self.request, self.task)
        }
        if engine.isRunning {
            engine.stop()
            engine.inputNode.removeTap(onBus: 0)
        }
        request?.endAudio()
        task?.finish()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
