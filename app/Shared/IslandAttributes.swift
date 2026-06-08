import ActivityKit
import Foundation

/// Which side(s) of the Dynamic Island the content occupies.
public enum IslandSide: String, Codable, Hashable, CaseIterable {
    case left, right, both
}

/// The animation style rendered in the island.
public enum IslandAnim: String, Codable, Hashable, CaseIterable {
    case none, equalizer, wave, doubleWave, pulse, ring, dots, heart

    public var label: String {
        switch self {
        case .none:       return "none"
        case .equalizer:  return "equalizer"
        case .wave:       return "wave"
        case .doubleWave: return "call wave"
        case .pulse:      return "pulse"
        case .ring:       return "ring"
        case .dots:       return "dots"
        case .heart:      return "heart"
        }
    }

    public var icon: String {
        switch self {
        case .none:       return "circle"
        case .equalizer:  return "waveform"
        case .wave:       return "wave.3.right"
        case .doubleWave: return "phone.fill"
        case .pulse:      return "dot.radiowaves.left.and.right"
        case .ring:       return "circle.dashed"
        case .dots:       return "ellipsis"
        case .heart:      return "heart.fill"
        }
    }
}

/// Live Activity attributes shared between the app (which drives updates) and the
/// widget extension (which renders the Dynamic Island). The `ContentState` is the
/// part that changes on every update — that's how we animate, since Live
/// Activities only move via data updates (self-running animations are ignored by
/// the system).
public struct IslandAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        public var title: String
        public var subtitle: String
        public var side: IslandSide
        public var anim: IslandAnim
        public var levels: [Double]      // 0…1 bar / amplitude samples (mic or synthetic)
        public var phase: Double         // advancing phase for wave animations
        public var leftImage: Data?      // small JPEG embedded directly (no App Group needed)
        public var rightImage: Data?     // small JPEG embedded directly
        public var leftText: String      // text / emoji shown on the left (optional)
        public var rightText: String     // text / emoji shown on the right (optional)
        public var accentHex: String
        public var timerEnd: Date?       // when set, the island shows a native live countdown

        public init(title: String = "", subtitle: String = "",
                    side: IslandSide = .both, anim: IslandAnim = .equalizer,
                    levels: [Double] = [], phase: Double = 0,
                    leftImage: Data? = nil, rightImage: Data? = nil,
                    leftText: String = "", rightText: String = "",
                    accentHex: String = "#2FEB8C", timerEnd: Date? = nil) {
            self.title = title; self.subtitle = subtitle
            self.side = side; self.anim = anim
            self.levels = levels; self.phase = phase
            self.leftImage = leftImage; self.rightImage = rightImage
            self.leftText = leftText; self.rightText = rightText
            self.accentHex = accentHex; self.timerEnd = timerEnd
        }
    }

    public var name: String
    public init(name: String) { self.name = name }
}
