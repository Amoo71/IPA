import ActivityKit
import WidgetKit
import SwiftUI
import UIKit

/// The Live Activity: lock-screen banner + the full Dynamic Island presentation
/// (compact leading/trailing = left/right, minimal, expanded). All content comes
/// from `context.state`, which the app updates to animate. A countdown, when set,
/// is rendered with the system's native ticking text (no app updates needed).
struct IslandLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: IslandAttributes.self) { context in
            LockScreenView(state: context.state)
                .padding(14)
                .activityBackgroundTint(Color.black.opacity(0.55))
                .activitySystemActionForegroundColor(Color(hex: context.state.accentHex) ?? .green)
        } dynamicIsland: { context in
            let s = context.state
            let accent = Color(hex: s.accentHex) ?? .green
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    SlotView(state: s, leading: true, imageSize: 48, compact: false)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if let end = s.timerEnd {
                        CountdownText(end: end, color: accent, size: 22)
                    } else {
                        SlotView(state: s, leading: false, imageSize: 48, compact: false)
                    }
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(spacing: 1) {
                        if !s.title.isEmpty {
                            Text(s.title).font(.headline).foregroundColor(.white).lineLimit(1)
                        }
                        if !s.subtitle.isEmpty {
                            Text(s.subtitle).font(.caption2).foregroundColor(.white.opacity(0.7)).lineLimit(1)
                        }
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    if s.timerEnd == nil {
                        AnimationView(anim: s.anim, levels: s.levels, phase: s.phase, color: accent, compact: false)
                            .frame(height: 30).padding(.horizontal, 6)
                    }
                }
            } compactLeading: {
                SlotView(state: s, leading: true, imageSize: 24, compact: true)
            } compactTrailing: {
                if let end = s.timerEnd {
                    CountdownText(end: end, color: accent, size: 14).frame(width: 44)
                } else {
                    SlotView(state: s, leading: false, imageSize: 24, compact: true)
                }
            } minimal: {
                if let end = s.timerEnd {
                    CountdownText(end: end, color: accent, size: 12).frame(width: 34)
                } else {
                    MinimalSlot(state: s)
                }
            }
            .keylineTint(accent)
        }
    }
}

private struct MinimalSlot: View {
    let state: IslandAttributes.ContentState
    var body: some View {
        let accent = Color(hex: state.accentHex) ?? .green
        if let d = state.leftImage ?? state.rightImage, let ui = UIImage(data: d) {
            FrameImageView(image: ui, size: 20)
        } else if !state.leftText.isEmpty || !state.rightText.isEmpty {
            Text(state.leftText.isEmpty ? state.rightText : state.leftText)
                .font(.system(size: 13, weight: .bold)).foregroundColor(accent).lineLimit(1)
        } else {
            AnimationView(anim: state.anim, levels: state.levels, phase: state.phase,
                          color: accent, compact: true)
                .frame(width: 24, height: 18)
        }
    }
}

private struct LockScreenView: View {
    let state: IslandAttributes.ContentState
    var body: some View {
        let accent = Color(hex: state.accentHex) ?? .green
        HStack(spacing: 12) {
            SlotView(state: state, leading: true, imageSize: 46, compact: false)
            VStack(alignment: .leading, spacing: 4) {
                if !state.title.isEmpty {
                    Text(state.title).font(.headline).foregroundColor(.white).lineLimit(1)
                }
                if !state.subtitle.isEmpty {
                    Text(state.subtitle).font(.caption).foregroundColor(.white.opacity(0.7)).lineLimit(1)
                }
                if let end = state.timerEnd {
                    CountdownText(end: end, color: accent, size: 18)
                } else {
                    AnimationView(anim: state.anim, levels: state.levels, phase: state.phase,
                                  color: accent, compact: false)
                        .frame(height: 26)
                }
            }
            Spacer(minLength: 4)
            SlotView(state: state, leading: false, imageSize: 46, compact: false)
        }
    }
}
