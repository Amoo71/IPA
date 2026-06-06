import Foundation
import AVFoundation
import Combine

/// Records a voice note to a temporary .m4a file. Tap to start, tap to stop;
/// the recorded file is then sent as an audio message.
final class VoiceRecorder: NSObject, ObservableObject {
    @Published var isRecording = false
    @Published var elapsed: TimeInterval = 0

    private var recorder: AVAudioRecorder?
    private var timer: Timer?
    private(set) var fileURL: URL?

    /// Requests mic permission (if needed) and starts recording. `onDenied` is
    /// called on the main thread when permission is refused.
    func start(onDenied: @escaping () -> Void) {
        AVAudioSession.sharedInstance().requestRecordPermission { granted in
            DispatchQueue.main.async {
                guard granted else { onDenied(); return }
                self.begin()
            }
        }
    }

    private func begin() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playAndRecord, mode: .default)
        try? session.setActive(true)

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".m4a")
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
        ]
        recorder = try? AVAudioRecorder(url: url, settings: settings)
        guard recorder != nil else { return }
        fileURL = url
        recorder?.record()
        isRecording = true
        elapsed = 0
        timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            self?.elapsed = self?.recorder?.currentTime ?? 0
        }
    }

    /// Stops and returns the recorded file (or nil if it was too short / failed).
    func stop() -> URL? {
        timer?.invalidate(); timer = nil
        recorder?.stop()
        isRecording = false
        try? AVAudioSession.sharedInstance().setActive(false)
        let url = fileURL
        recorder = nil
        if elapsed < 0.4 { cancel(); return nil }
        return url
    }

    func cancel() {
        timer?.invalidate(); timer = nil
        recorder?.stop()
        recorder = nil
        isRecording = false
        if let u = fileURL { try? FileManager.default.removeItem(at: u) }
        fileURL = nil
    }

    var label: String {
        let s = Int(elapsed)
        return String(format: "%01d:%02d", s / 60, s % 60)
    }
}
