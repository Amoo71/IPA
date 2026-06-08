import ActivityKit
import Foundation

/// Which side(s) of the Dynamic Island the content occupies.
public enum IslandSide: String, Codable, Hashable, CaseIterable {
    case left, right, both
}

/// The animation style rendered in the island.
public enum IslandAnim: String, Codable, Hashable, CaseIterable {
    case none, equalizer, wave, doubleWave, pulse

    public var label: String {
        switch self {
        case .none:       return "none"
        case .equalizer:  return "equalizer"
        case .wave:       return "wave"
        case .doubleWave: return "call wave"
        case .pulse:      return "pulse"
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
        public var leftFrame: String?    // app-group file path for left image / gif frame
        public var rightFrame: String?   // app-group file path for right image / gif frame
        public var accentHex: String

        public init(title: String = "", subtitle: String = "",
                    side: IslandSide = .both, anim: IslandAnim = .equalizer,
                    levels: [Double] = [], phase: Double = 0,
                    leftFrame: String? = nil, rightFrame: String? = nil,
                    accentHex: String = "#2FEB8C") {
            self.title = title; self.subtitle = subtitle
            self.side = side; self.anim = anim
            self.levels = levels; self.phase = phase
            self.leftFrame = leftFrame; self.rightFrame = rightFrame
            self.accentHex = accentHex
        }
    }

    public var name: String
    public init(name: String) { self.name = name }
}
