import SwiftUI
import RealityKit

class SceneContent {
    let context: MetalContext
    let modelEntity = ModelEntity()
    let wave: AnimatedWaveMesh

    init(context: MetalContext) {
        self.context = context
        do {
            wave = try AnimatedWaveMesh(context: context)
            wave.segmentCount = 96
            wave.amplitude = 0.02
            wave.waveDensity = 5.0
            wave.speed = 1.0

            let meshResource = try MeshResource(from: wave.lowLevelMesh)

            var material = PhysicallyBasedMaterial()
            material.baseColor.tint = .white
            material.roughness.scale = 0.0
            material.metallic.scale = 1.0
            material.faceCulling = .none

            modelEntity.model = ModelComponent(mesh: meshResource, materials: [material])
        } catch {
            fatalError("Failed to intialize scene content")
        }
    }

    func update(timestep: TimeInterval) {
        wave.update(timestep)
    }
}

let animationFrameDuration: TimeInterval = 1.0 / 60.0

struct ContentView: View {
    @State private var sceneContent = SceneContent(context: MetalContext.shared)
    @State private var frameDuration: TimeInterval = 0.0
    @State private var lastUpdateTime = CACurrentMediaTime()

    private let timer = Timer.publish(every: animationFrameDuration, on: .main, in: .common).autoconnect()

    var body: some View {
        RealityView { content in
            #if os(visionOS)
            content.add(sceneContent.modelEntity)
            #else
            sceneContent.modelEntity.transform.scale = SIMD3<Float>(repeating: 2.0)
            let anchorEntity = AnchorEntity(world: SIMD3<Float>(0, 0, -0.5))
            anchorEntity.transform.rotation = simd_quatf(angle: .pi / 4, axis: SIMD3<Float>(1, 0, 0))
            anchorEntity.addChild(sceneContent.modelEntity)
            content.add(anchorEntity)
            #endif
        } update: { content in
            sceneContent.wave.update(frameDuration)
        }
        .onReceive(timer) { input in
            let currentTime = CACurrentMediaTime()
            frameDuration = currentTime - lastUpdateTime
            lastUpdateTime = currentTime
        }
        .ignoresSafeArea()
    }
}

#Preview {
    ContentView()
}
