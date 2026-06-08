import SwiftUI
import UIKit
import ActivityKit
import AVFoundation
import Combine

/// Smoothness ↔ battery trade-off: lower frame rate = less work = less drain.
enum Smoothness: String, CaseIterable, Identifiable {
    case battery, balanced, smooth
    var id: String { rawValue }
    var label: String { rawValue }
    /// Update interval; the actual animation speed is time-based so a lower rate
    /// just looks choppier, it doesn't slow down.
    var interval: TimeInterval {
        switch self { case .battery: return 0.30; case .balanced: return 0.18; case .smooth: return 0.11 }
    }
}

/// Owns the Live Activity lifecycle + the animation loop.
///
/// Battery strategy:
/// - The update loop runs **only while the app is in the foreground**. On
///   background we stop pushing and stop the mic; the island keeps showing the
///   last frame for free.
/// - **Static** content (no animation, single image, no mic) pushes once and
///   then runs no loop at all.
/// - Frame rate adapts to a battery/balanced/smooth setting and is forced to the
///   lowest rate in Low Power Mode.
/// - Identical frames are not re-sent (skip-if-unchanged).
/// - The countdown uses the system's native `Text(timerInterval:)`, which ticks
///   with zero app updates.
@MainActor
final class IslandController: ObservableObject {
    // Availability / status
    @Published var enabled = false
    @Published var running = false
    @Published var micActive = false
    @Published var lowPower = false
    @Published var status = "ready"

    // Configuration (bound to the UI)
    @Published var title = "Islander"        { didSet { changed() } }
    @Published var subtitle = ""             { didSet { changed() } }
    @Published var side: IslandSide = .both  { didSet { changed() } }
    @Published var anim: IslandAnim = .equalizer { didSet { changed() } }
    @Published var accent = Color(hex: "#2FEB8C") ?? .green { didSet { changed() } }
    @Published var leftText = ""             { didSet { changed() } }
    @Published var rightText = ""            { didSet { changed() } }
    @Published var speed: Double = 1.0       { didSet { changed() } }
    @Published var sensitivity: Double = 9   { didSet { meter.gain = sensitivity; save() } }
    @Published var smoothness: Smoothness = .balanced { didSet { retimeLoop(); save() } }
    @Published var countdownOn = false       { didSet { updateTimer() } }
    @Published var countdownMinutes: Double = 5

    // Picker thumbnails (decoded directly from the picked data — always shows,
    // even if the App Group container isn't available).
    @Published var leftPreview: UIImage?
    @Published var rightPreview: UIImage?
    @Published var appGroupOK = true

    private var leftFrames: [String] = []
    private var rightFrames: [String] = []
    private var timerEndDate: Date?

    private var activity: Activity<IslandAttributes>?
    private var lastPushed: IslandAttributes.ContentState?
    private var timer: Timer?
    private var appActive = true
    private let meter = AudioMeter(bands: 7)

    init() {
        load()
        meter.gain = sensitivity
        refresh()
        lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        NotificationCenter.default.addObserver(forName: .NSProcessInfoPowerStateDidChange,
                                               object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.powerChanged() }
        }
    }

    private func powerChanged() {
        lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        retimeLoop()
    }

    func refresh() {
        enabled = ActivityAuthorizationInfo().areActivitiesEnabled
        if activity == nil, let existing = Activity<IslandAttributes>.activities.first {
            activity = existing
            running = true
        }
    }

    // MARK: foreground / background — the key battery lever

    func setActive(_ active: Bool) {
        appActive = active
        guard running else { return }
        if active {
            syncMic()
            retimeLoop()
            applyNow()
        } else {
            stopLoop()
            meter.stop()          // never record in the background
        }
    }

    // MARK: lifecycle

    func start() {
        refresh()
        guard enabled else { status = "Live Activities are disabled in iOS Settings"; return }
        guard activity == nil else { return }
        updateTimer()
        let state = buildState()
        do {
            activity = try Activity.request(attributes: IslandAttributes(name: title),
                                            content: ActivityContent(state: state, staleDate: nil),
                                            pushType: nil)
            lastPushed = state
            running = true
            status = "live"
            syncMic()
            retimeLoop()
        } catch {
            status = "error: \(error.localizedDescription)"
        }
    }

    func stop() {
        stopLoop()
        meter.stop(); micActive = false
        let final = buildState()
        let act = activity
        activity = nil
        lastPushed = nil
        running = false
        status = "stopped"
        Task { await act?.end(ActivityContent(state: final, staleDate: nil), dismissalPolicy: .immediate) }
    }

    // MARK: animation loop (foreground only, adaptive, skip-if-unchanged)

    /// True only when a moving animation is actually visible somewhere — if both
    /// active sides show an image/text, the equalizer is hidden, so we don't burn
    /// battery updating it.
    private var animationVisible: Bool {
        guard anim != .none else { return false }
        let leftShows = (side == .left || side == .both) && leftFrames.isEmpty && leftText.isEmpty
        let rightShows = (side == .right || side == .both) && rightFrames.isEmpty && rightText.isEmpty
        return leftShows || rightShows
    }

    private var hasMovingFrames: Bool { leftFrames.count > 1 || rightFrames.count > 1 }

    private var isAnimated: Bool { animationVisible || hasMovingFrames }

    private var effectiveInterval: TimeInterval {
        lowPower ? Smoothness.battery.interval : smoothness.interval
    }

    private func retimeLoop() {
        guard running, appActive, isAnimated else { stopLoop(); return }
        stopLoop()
        let t = Timer(timeInterval: effectiveInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.step() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func stopLoop() { timer?.invalidate(); timer = nil }

    private func step() {
        let state = buildState()
        guard state != lastPushed else { return }   // don't re-send identical frames
        lastPushed = state
        let act = activity
        Task { await act?.update(ActivityContent(state: state, staleDate: nil)) }
    }

    /// Pushes once if the content changed; also (re)starts/stops the loop to match
    /// whether the current content is animated. Used when settings change.
    func applyNow() {
        guard running else { return }
        syncMic()
        retimeLoop()
        let state = buildState()
        guard state != lastPushed else { return }
        lastPushed = state
        let act = activity
        Task { await act?.update(ActivityContent(state: state, staleDate: nil)) }
    }

    private func changed() { save(); applyNow() }

    // MARK: content

    func buildState() -> IslandAttributes.ContentState {
        let now = Date().timeIntervalSinceReferenceDate
        let levels: [Double]
        if anim == .none && leftFrames.count <= 1 && rightFrames.count <= 1 {
            levels = []
        } else if meter.running {
            levels = meter.latest
        } else {
            levels = synth(now)
        }
        return IslandAttributes.ContentState(
            title: title, subtitle: subtitle, side: side, anim: anim,
            levels: levels, phase: now * 2.0 * speed,
            leftFrame: frame(leftFrames, now), rightFrame: frame(rightFrames, now),
            leftText: leftText, rightText: rightText,
            accentHex: accent.hexString, timerEnd: timerEndDate)
    }

    private func frame(_ frames: [String], _ now: Double) -> String? {
        guard !frames.isEmpty else { return nil }
        if frames.count == 1 { return frames[0] }
        let idx = Int(now * 12 * speed) % frames.count
        return frames[idx]
    }

    private func synth(_ now: Double) -> [Double] {
        (0..<7).map { i in 0.15 + 0.85 * pow(abs(sin(now * 1.8 * speed + Double(i) * 0.55)), 1.6) }
    }

    // MARK: countdown

    private func updateTimer() {
        timerEndDate = countdownOn ? Date().addingTimeInterval(countdownMinutes * 60) : nil
        applyNow()
    }

    // MARK: media

    func setMedia(_ data: Data, left: Bool) {
        status = "importing…"
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let result = MediaImporter.importMedia(data: data, slot: left ? "left" : "right")
            DispatchQueue.main.async {
                if left { self.leftFrames = result.paths; self.leftPreview = result.thumbnail }
                else { self.rightFrames = result.paths; self.rightPreview = result.thumbnail }
                self.appGroupOK = result.appGroupOK
                self.status = result.paths.isEmpty ? "couldn't read that file"
                    : (result.appGroupOK ? "live" : "imported — enable App Group in KSign so the island can read it")
                self.applyNow()
            }
        }
    }

    func clearMedia(left: Bool) {
        MediaImporter.clear(slot: left ? "left" : "right")
        if left { leftFrames = []; leftPreview = nil } else { rightFrames = []; rightPreview = nil }
        applyNow()
    }

    // MARK: mic

    func setMic(_ on: Bool) {
        micActive = on
        if on {
            AVAudioSession.sharedInstance().requestRecordPermission { [weak self] granted in
                DispatchQueue.main.async {
                    guard let self else { return }
                    if !granted { self.status = "microphone denied"; self.micActive = false }
                    self.syncMic(); self.retimeLoop()
                }
            }
        } else {
            syncMic(); retimeLoop()
        }
    }

    /// Engine runs only when the user wants it, we're foregrounded + live, and an
    /// animation is actually on screen to react.
    private func syncMic() {
        let shouldRun = micActive && appActive && running && animationVisible
        if shouldRun && !meter.running {
            do { try meter.start() } catch { status = "mic error: \(error.localizedDescription)"; micActive = false }
        } else if !shouldRun && meter.running {
            meter.stop()
        }
    }

    // MARK: persistence

    private struct Saved: Codable {
        var title: String; var subtitle: String; var side: IslandSide; var anim: IslandAnim
        var accentHex: String; var leftText: String; var rightText: String
        var speed: Double; var sensitivity: Double; var smoothness: String
    }

    private func save() {
        let s = Saved(title: title, subtitle: subtitle, side: side, anim: anim,
                      accentHex: accent.hexString, leftText: leftText, rightText: rightText,
                      speed: speed, sensitivity: sensitivity, smoothness: smoothness.rawValue)
        if let data = try? JSONEncoder().encode(s) {
            UserDefaults.standard.set(data, forKey: "islander.config.v1")
        }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: "islander.config.v1"),
              let s = try? JSONDecoder().decode(Saved.self, from: data) else { return }
        title = s.title; subtitle = s.subtitle; side = s.side; anim = s.anim
        accent = Color(hex: s.accentHex) ?? accent
        leftText = s.leftText; rightText = s.rightText
        speed = s.speed; sensitivity = s.sensitivity
        smoothness = Smoothness(rawValue: s.smoothness) ?? .balanced
    }

    /// Apply a one-tap preset.
    func applyPreset(_ p: Preset) {
        anim = p.anim; side = p.side
        if let hex = p.accentHex, let c = Color(hex: hex) { accent = c }
        leftText = p.leftText; rightText = p.rightText
        title = p.title; subtitle = p.subtitle
        applyNow()
    }
}

/// A one-tap configuration.
struct Preset: Identifiable {
    let id = UUID()
    var name: String
    var anim: IslandAnim
    var side: IslandSide
    var accentHex: String?
    var title = ""
    var subtitle = ""
    var leftText = ""
    var rightText = ""

    static let all: [Preset] = [
        Preset(name: "Now Playing", anim: .equalizer, side: .both, accentHex: "#2FEB8C",
               title: "Now Playing", leftText: "🎵"),
        Preset(name: "On Call", anim: .doubleWave, side: .both, accentHex: "#34C759",
               title: "On Call", leftText: "📞"),
        Preset(name: "Recording", anim: .pulse, side: .left, accentHex: "#FF3B30",
               title: "REC", leftText: "●"),
        Preset(name: "Loading", anim: .dots, side: .both, accentHex: "#0A84FF", title: "Working…"),
        Preset(name: "Heartbeat", anim: .heart, side: .both, accentHex: "#FF2D55", leftText: "❤️"),
        Preset(name: "Loading ring", anim: .ring, side: .right, accentHex: "#FFD60A", title: "Syncing"),
    ]
}
