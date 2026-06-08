import SwiftUI
import UIKit
import ActivityKit
import AVFoundation
import Combine

/// Owns the Live Activity lifecycle and the animation loop. Because Live
/// Activities only animate via data updates, a timer pushes a fresh
/// `ContentState` several times a second (mic levels when the mic is on, a lively
/// synthetic pattern otherwise; gif frames advance each tick).
@MainActor
final class IslandController: ObservableObject {
    // Availability / status
    @Published var enabled = false
    @Published var running = false
    @Published var micActive = false
    @Published var status = "ready"

    // Configuration (bound to the UI)
    @Published var title = "Islander"
    @Published var subtitle = ""
    @Published var side: IslandSide = .both
    @Published var anim: IslandAnim = .equalizer
    @Published var accent: Color = Color(hex: "#2FEB8C") ?? .green
    @Published var leftPreview: UIImage?
    @Published var rightPreview: UIImage?

    private var activity: Activity<IslandAttributes>?
    private var leftFrames: [String] = []
    private var rightFrames: [String] = []
    private var frameIndex = 0
    private var tick = 0
    private var timer: Timer?
    private let meter = AudioMeter(bands: 7)

    init() { refresh() }

    func refresh() {
        enabled = ActivityAuthorizationInfo().areActivitiesEnabled
        // Reattach to an existing activity if the app was relaunched.
        if activity == nil, let existing = Activity<IslandAttributes>.activities.first {
            activity = existing
            running = true
        }
    }

    // MARK: lifecycle

    func start() {
        refresh()
        guard enabled else {
            status = "Live Activities are disabled in iOS Settings"
            return
        }
        guard activity == nil else { return }
        do {
            let content = ActivityContent(state: buildState(), staleDate: nil)
            activity = try Activity.request(attributes: IslandAttributes(name: title),
                                            content: content, pushType: nil)
            running = true
            status = "live"
            startLoop()
        } catch {
            status = "error: \(error.localizedDescription)"
        }
    }

    func stop() {
        timer?.invalidate(); timer = nil
        if micActive { setMic(false) }
        let final = buildState()
        let act = activity
        activity = nil
        running = false
        status = "stopped"
        Task { await act?.end(ActivityContent(state: final, staleDate: nil), dismissalPolicy: .immediate) }
    }

    private func startLoop() {
        timer?.invalidate()
        let t = Timer(timeInterval: 0.15, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.step() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func step() {
        tick += 1
        if !leftFrames.isEmpty || !rightFrames.isEmpty { frameIndex += 1 }
        let state = buildState()
        let act = activity
        Task { await act?.update(ActivityContent(state: state, staleDate: nil)) }
    }

    // MARK: content

    func buildState() -> IslandAttributes.ContentState {
        let levels = micActive ? meter.latest : synthLevels()
        let phase = Double(tick) * 0.4
        let lf = leftFrames.isEmpty ? nil : leftFrames[frameIndex % leftFrames.count]
        let rf = rightFrames.isEmpty ? nil : rightFrames[frameIndex % rightFrames.count]
        return IslandAttributes.ContentState(
            title: title, subtitle: subtitle, side: side, anim: anim,
            levels: levels, phase: phase, leftFrame: lf, rightFrame: rf,
            accentHex: accent.hexString)
    }

    /// Pushes the current config immediately (used when the user tweaks settings
    /// while a Live Activity is already running).
    func applyNow() {
        guard running else { return }
        let state = buildState()
        let act = activity
        Task { await act?.update(ActivityContent(state: state, staleDate: nil)) }
    }

    private func synthLevels() -> [Double] {
        (0..<7).map { i in
            let t = Double(tick) * 0.45
            return 0.15 + 0.85 * pow(abs(sin(t + Double(i) * 0.55)), 1.6)
        }
    }

    // MARK: media

    func setImage(_ data: Data, left: Bool) {
        let frames = MediaImporter.importFrames(data: data, slot: left ? "left" : "right")
        let preview = frames.first.flatMap { UIImage(contentsOfFile: $0) }
        if left { leftFrames = frames; leftPreview = preview }
        else { rightFrames = frames; rightPreview = preview }
        frameIndex = 0
        if frames.isEmpty { status = "couldn't import image (App Group missing?)" }
        applyNow()
    }

    func clearImage(left: Bool) {
        MediaImporter.clear(slot: left ? "left" : "right")
        if left { leftFrames = []; leftPreview = nil }
        else { rightFrames = []; rightPreview = nil }
        applyNow()
    }

    // MARK: mic

    func setMic(_ on: Bool) {
        if on {
            AVAudioSession.sharedInstance().requestRecordPermission { [weak self] granted in
                DispatchQueue.main.async {
                    guard let self else { return }
                    guard granted else { self.status = "microphone denied"; self.micActive = false; return }
                    do { try self.meter.start(); self.micActive = true }
                    catch { self.status = "mic error: \(error.localizedDescription)"; self.micActive = false }
                }
            }
        } else {
            meter.stop()
            micActive = false
        }
    }
}
