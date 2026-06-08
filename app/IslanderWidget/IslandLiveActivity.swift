import ActivityKit
import WidgetKit
import SwiftUI

/// The Live Activity. Provides the lock-screen banner and the full Dynamic
/// Island presentation (compact leading/trailing = left/right, minimal, and the
/// expanded layout). All content comes from `context.state`, which the app
/// updates several times a second to animate.
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
                    ExpandedSide(state: s, leading: true)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    ExpandedSide(state: s, leading: false)
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
                    AnimationView(anim: s.anim, levels: s.levels, phase: s.phase, color: accent, compact: false)
                        .frame(height: 30)
                        .padding(.horizontal, 6)
                }
            } compactLeading: {
                CompactSlot(state: s, leading: true)
            } compactTrailing: {
                CompactSlot(state: s, leading: false)
            } minimal: {
                MinimalSlot(state: s)
            }
            .keylineTint(accent)
        }
    }
}

// MARK: - Regions

private struct CompactSlot: View {
    let state: IslandAttributes.ContentState
    let leading: Bool

    var body: some View {
        let accent = Color(hex: state.accentHex) ?? .green
        let active = leading ? (state.side == .left || state.side == .both)
                             : (state.side == .right || state.side == .both)
        let frame = leading ? state.leftFrame : state.rightFrame
        Group {
            if !active {
                EmptyView()
            } else if let f = frame {
                FrameImageView(path: f, size: 24)
            } else {
                AnimationView(anim: state.anim, levels: state.levels, phase: state.phase,
                              color: accent, compact: true)
                    .frame(width: 36, height: 22)
            }
        }
    }
}

private struct MinimalSlot: View {
    let state: IslandAttributes.ContentState

    var body: some View {
        let accent = Color(hex: state.accentHex) ?? .green
        if let f = state.leftFrame ?? state.rightFrame {
            FrameImageView(path: f, size: 20)
        } else {
            AnimationView(anim: state.anim, levels: state.levels, phase: state.phase,
                          color: accent, compact: true)
                .frame(width: 24, height: 18)
        }
    }
}

private struct ExpandedSide: View {
    let state: IslandAttributes.ContentState
    let leading: Bool

    var body: some View {
        let accent = Color(hex: state.accentHex) ?? .green
        let active = leading ? (state.side == .left || state.side == .both)
                             : (state.side == .right || state.side == .both)
        let frame = leading ? state.leftFrame : state.rightFrame
        Group {
            if !active {
                EmptyView()
            } else if let f = frame {
                FrameImageView(path: f, size: 48)
            } else {
                AnimationView(anim: state.anim, levels: state.levels, phase: state.phase,
                              color: accent, compact: false)
                    .frame(width: 60, height: 42)
            }
        }
    }
}

private struct LockScreenView: View {
    let state: IslandAttributes.ContentState

    var body: some View {
        let accent = Color(hex: state.accentHex) ?? .green
        HStack(spacing: 12) {
            if let f = state.leftFrame { FrameImageView(path: f, size: 46) }
            VStack(alignment: .leading, spacing: 4) {
                if !state.title.isEmpty {
                    Text(state.title).font(.headline).foregroundColor(.white).lineLimit(1)
                }
                if !state.subtitle.isEmpty {
                    Text(state.subtitle).font(.caption).foregroundColor(.white.opacity(0.7)).lineLimit(1)
                }
                AnimationView(anim: state.anim, levels: state.levels, phase: state.phase,
                              color: accent, compact: false)
                    .frame(height: 26)
            }
            Spacer(minLength: 4)
            if let f = state.rightFrame { FrameImageView(path: f, size: 46) }
        }
    }
}
