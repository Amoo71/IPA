import SwiftUI
import UIKit

/// Dispatches to the chosen animation style. Used in every island region and in
/// the in-app preview, so the preview matches exactly what the island shows.
public struct AnimationView: View {
    let anim: IslandAnim
    let levels: [Double]
    let phase: Double
    let color: Color
    var compact: Bool = true

    public init(anim: IslandAnim, levels: [Double], phase: Double, color: Color, compact: Bool = true) {
        self.anim = anim; self.levels = levels; self.phase = phase; self.color = color; self.compact = compact
    }

    public var body: some View {
        switch anim {
        case .none:
            Circle().fill(color).frame(width: 8, height: 8)
        case .equalizer:
            BarsView(levels: levels, color: color, bars: compact ? 4 : 7)
        case .wave:
            WaveView(phase: phase, amp: amp, color: color, cycles: compact ? 2 : 4)
        case .doubleWave:
            DoubleWaveView(phase: phase, amp: amp, color: color, cycles: compact ? 2 : 4)
        case .pulse:
            PulseView(level: amp, color: color)
        }
    }

    private var amp: Double {
        guard !levels.isEmpty else { return 0.5 }
        return min(1, levels.reduce(0, +) / Double(levels.count) + 0.12)
    }
}

/// Spotify-style bouncing equalizer bars.
public struct BarsView: View {
    let levels: [Double]
    let color: Color
    var bars: Int = 5

    public init(levels: [Double], color: Color, bars: Int = 5) {
        self.levels = levels; self.color = color; self.bars = bars
    }

    public var body: some View {
        GeometryReader { geo in
            let h = geo.size.height
            HStack(alignment: .center, spacing: 2) {
                ForEach(0..<bars, id: \.self) { i in
                    let l = levels.isEmpty ? 0.25 : levels[i % levels.count]
                    Capsule()
                        .fill(color)
                        .frame(height: max(3, CGFloat(l) * h))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
        .animation(.easeOut(duration: 0.12), value: levels)
    }
}

/// A single travelling sine wave.
public struct WaveView: View {
    let phase: Double
    let amp: Double
    let color: Color
    var cycles: Double = 4

    public init(phase: Double, amp: Double, color: Color, cycles: Double = 4) {
        self.phase = phase; self.amp = amp; self.color = color; self.cycles = cycles
    }

    public var body: some View {
        GeometryReader { geo in
            wavePath(in: geo.size, phase: phase, amp: amp, cycles: cycles)
                .stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .round))
        }
        .animation(.linear(duration: 0.12), value: phase)
    }
}

/// Two opposing waves — the call-style double wave.
public struct DoubleWaveView: View {
    let phase: Double
    let amp: Double
    let color: Color
    var cycles: Double = 4

    public init(phase: Double, amp: Double, color: Color, cycles: Double = 4) {
        self.phase = phase; self.amp = amp; self.color = color; self.cycles = cycles
    }

    public var body: some View {
        GeometryReader { geo in
            ZStack {
                wavePath(in: geo.size, phase: phase, amp: amp, cycles: cycles)
                    .stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                wavePath(in: geo.size, phase: phase + .pi, amp: amp, cycles: cycles)
                    .stroke(color.opacity(0.5), style: StrokeStyle(lineWidth: 2, lineCap: .round))
            }
        }
        .animation(.linear(duration: 0.12), value: phase)
    }
}

/// A pulsing dot.
public struct PulseView: View {
    let level: Double
    let color: Color

    public init(level: Double, color: Color) { self.level = level; self.color = color }

    public var body: some View {
        GeometryReader { geo in
            let d = min(geo.size.width, geo.size.height)
            ZStack {
                Circle().fill(color.opacity(0.25)).frame(width: d, height: d)
                Circle().fill(color)
                    .frame(width: d, height: d)
                    .scaleEffect(0.45 + 0.55 * CGFloat(level))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .animation(.easeOut(duration: 0.12), value: level)
    }
}

/// Shared sine path builder.
func wavePath(in size: CGSize, phase: Double, amp: Double, cycles: Double) -> Path {
    var p = Path()
    let w = size.width, h = size.height, mid = h / 2
    let steps = 40
    p.move(to: CGPoint(x: 0, y: mid))
    for s in 0...steps {
        let frac = Double(s) / Double(steps)
        let x = w * CGFloat(frac)
        let y = mid + CGFloat(sin(frac * .pi * 2 * cycles + phase)) * (mid - 1) * CGFloat(amp)
        p.addLine(to: CGPoint(x: x, y: y))
    }
    return p
}

/// Renders one image / gif frame loaded from a file path (app-group container).
public struct FrameImageView: View {
    let path: String?
    let size: CGFloat

    public init(path: String?, size: CGFloat) { self.path = path; self.size = size }

    public var body: some View {
        Group {
            if let p = path, let ui = UIImage(contentsOfFile: p) {
                Image(uiImage: ui).resizable().scaledToFill()
            } else {
                RoundedRectangle(cornerRadius: size * 0.25).fill(Color.white.opacity(0.12))
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.25))
    }
}
