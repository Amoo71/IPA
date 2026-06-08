import SwiftUI

@main
struct IslanderApp: App {
    @StateObject private var island = IslandController()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(island)
                .preferredColorScheme(.dark)
                .onAppear { island.refresh() }
        }
    }
}
