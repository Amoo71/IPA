import AVFoundation

/// Captures the microphone and produces `bands` amplitude values (0…1) by taking
/// the RMS of contiguous slices of each audio buffer. Not a true FFT spectrum,
/// but it reacts to live sound and drives the equalizer/wave convincingly.
final class AudioMeter {
    let bands: Int
    private(set) var latest: [Double]
    private(set) var running = false

    private let engine = AVAudioEngine()
    private var smoothed: [Double]

    init(bands: Int = 7) {
        self.bands = bands
        latest = Array(repeating: 0, count: bands)
        smoothed = Array(repeating: 0, count: bands)
    }

    func start() throws {
        guard !running else { return }
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .measurement,
                                options: [.mixWithOthers, .defaultToSpeaker, .allowBluetooth])
        try session.setActive(true)
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.process(buffer)
        }
        engine.prepare()
        try engine.start()
        running = true
    }

    func stop() {
        guard running else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        running = false
        latest = Array(repeating: 0, count: bands)
        smoothed = latest
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func process(_ buffer: AVAudioPCMBuffer) {
        guard let channel = buffer.floatChannelData?[0] else { return }
        let n = Int(buffer.frameLength)
        guard n > 0 else { return }
        let per = max(1, n / bands)
        var out = [Double](repeating: 0, count: bands)
        for b in 0..<bands {
            let start = b * per
            let end = min(n, start + per)
            guard end > start else { continue }
            var sum: Float = 0
            for i in start..<end { let v = channel[i]; sum += v * v }
            let rms = sqrt(sum / Float(end - start))
            // Boost + clamp; quiet rooms still show a little life.
            let level = min(1.0, Double(rms) * 9.0)
            // Exponential smoothing so bars fall back gently.
            smoothed[b] = max(level, smoothed[b] * 0.6)
            out[b] = smoothed[b]
        }
        latest = out
    }
}
