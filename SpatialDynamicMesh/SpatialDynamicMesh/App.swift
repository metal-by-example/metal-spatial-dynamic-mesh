import SwiftUI

@main
struct SpatialDynamicMeshApp: App {
    
    var body: some Scene {
        WindowGroup() {
            ContentView()
        }
        #if os(visionOS)
        .windowStyle(.volumetric)
        .defaultSize(width: 1.0, height: 0.2, depth: 1.0, in: .meters)
        #endif
    }
}
