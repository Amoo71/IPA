import SwiftUI

@main
struct IslanderApp: App {
    @StateObject private var island = IslandController()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(island)
                .preferredColorScheme(.dark)
                .onAppear { island.refresh() }
        }
        // Pausing updates in the background is the single biggest battery saver:
        // the island keeps showing the last frame for free.
        .onChange(of: scenePhase) { phase in
            island.setActive(phase == .active)
        }
    }
}
