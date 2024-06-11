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

#if os(iOS)
struct ARViewContainer : UIViewRepresentable {
    typealias UIViewType = ARView

    @State var content: SceneContent

    func makeUIView(context: Context) -> ARView {
        return ARView(frame: .zero,
                      cameraMode: .nonAR,
                      automaticallyConfigureSession: true)
    }

    func updateUIView(_ uiView: ARView, context: Context) {
        content.modelEntity.transform.scale = SIMD3<Float>(repeating: 2.0)

        let anchorEntity = AnchorEntity(world: SIMD3<Float>(0, 0, -0.5))
        anchorEntity.transform.rotation = simd_quatf(angle: .pi / 4, axis: SIMD3<Float>(1, 0, 0))
        anchorEntity.addChild(content.modelEntity)
        uiView.scene.addAnchor(anchorEntity)
    }
}
#elseif os(macOS)
struct ARViewContainer : NSViewRepresentable {
    typealias NSViewType = ARView

    @State var content: SceneContent

    func makeNSView(context: Context) -> ARView {
        return ARView(frame: .zero)
    }

    func updateNSView(_ nsView: ARView, context: Context) {
        content.modelEntity.transform.scale = SIMD3<Float>(repeating: 2.0)

        let anchorEntity = AnchorEntity(world: SIMD3<Float>(0, 0, -0.5))
        anchorEntity.transform.rotation = simd_quatf(angle: .pi / 4, axis: SIMD3<Float>(1, 0, 0))
        anchorEntity.addChild(content.modelEntity)
        nsView.scene.addAnchor(anchorEntity)
    }
}
#endif

let animationFrameDuration: TimeInterval = 1.0 / 60.0

struct ContentView: View {
    @State private var sceneContent = SceneContent(context: MetalContext.shared)
    @State private var frameDuration: TimeInterval = 0.0
    @State private var lastUpdateTime = CACurrentMediaTime()

    private let timer = Timer.publish(every: animationFrameDuration, on: .main, in: .common).autoconnect()

    var body: some View {
        #if os(visionOS)
        RealityView { content in
            content.add(sceneContent.modelEntity)
        } update: { content in
            sceneContent.wave.update(frameDuration)
        }
        .onReceive(timer) { input in
            let currentTime = CACurrentMediaTime()
            frameDuration = currentTime - lastUpdateTime
            lastUpdateTime = currentTime
        }
        .ignoresSafeArea()
        #else
        ARViewContainer(content: sceneContent)
        .onReceive(timer) { input in
            let currentTime = CACurrentMediaTime()
            frameDuration = currentTime - lastUpdateTime
            lastUpdateTime = currentTime
            sceneContent.wave.update(frameDuration)
        }
        .ignoresSafeArea()
        #endif
    }
}

#Preview {
    ContentView()
}
