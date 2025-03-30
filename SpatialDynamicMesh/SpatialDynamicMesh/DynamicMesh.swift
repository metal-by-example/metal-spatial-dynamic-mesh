import Metal
import RealityKit

@MainActor
class AnimatedWaveMesh {
    let maxSegmentCount = 128
    let context: MetalContext
    let lowLevelMesh: LowLevelMesh

    var waveDensity: Float = 3.0
    var amplitude: Float = 0.1
    var speed: Float = 1.0

    var segmentCount = 64 {
        didSet {
            needsTopologyUpdate = true
        }
    }

    private var needsTopologyUpdate = true

    private var time: TimeInterval = 0.0

    init(context: MetalContext) throws {
        self.context = context

        // Get the memory layout of our vertex type so we can use it below
        let vertex = MemoryLayout<MeshVertex>.self

        // Create an attribute array whose elements match the order, format, and offsets of our vertex type
        let attributes: [LowLevelMesh.Attribute] = [
            .init(semantic: .position, format: .float3, offset: vertex.offset(of: \.position)!),
            .init(semantic: .normal, format: .float3, offset: vertex.offset(of: \.normal)!),
            .init(semantic: .uv0, format: .float2, offset: vertex.offset(of: \.uv)!)
        ]

        // Create a layout describing a vertex buffer that holds packed instances of our vertex
        let layouts: [LowLevelMesh.Layout] = [
            .init(bufferIndex: 0, bufferOffset: 0, bufferStride: vertex.stride)
        ]

        let vertexCapacity = (maxSegmentCount + 1) * (maxSegmentCount + 1)
        let indexCapacity = maxSegmentCount * maxSegmentCount * 6

        // Create a mesh descriptor that describes a mesh comprised of vertices as laid out above
        let meshDescriptor = LowLevelMesh.Descriptor(vertexCapacity: vertexCapacity,
                                                     vertexAttributes: attributes,
                                                     vertexLayouts: layouts,
                                                     indexCapacity: indexCapacity,
                                                     indexType: MTLIndexType.uint32)

        self.lowLevelMesh = try LowLevelMesh(descriptor: meshDescriptor)

        update(0.0)
    }

    func update(_ timestep: TimeInterval) {
        self.time += timestep

        guard let updateCommandBuffer = context.commandQueue.makeCommandBuffer() else { return }

        let activeSegmentCount = max(0, min(segmentCount, maxSegmentCount))
        let indexCount = activeSegmentCount * activeSegmentCount * 6

        var waveDescriptor = WaveDescriptor(segmentCount: UInt32(activeSegmentCount),
                                            time: Float(time) * speed,
                                            waveDensity: waveDensity,
                                            amplitude: amplitude)

        let threadgroupSize = MTLSize(width: 8, height: 8, depth: 1)
        let requiresUniformDispatch = !context.device.supportsFamily(.apple4)

        if let commandEncoder = updateCommandBuffer.makeComputeCommandEncoder() {
            commandEncoder.setBytes(&waveDescriptor, length: MemoryLayout.size(ofValue: waveDescriptor), index: 1)

            let vertexBuffer = lowLevelMesh.replace(bufferIndex: 0, using: updateCommandBuffer)
            commandEncoder.setComputePipelineState(context.computePipelines[PipelineIndex.waveVertexUpdate.rawValue])
            commandEncoder.setBuffer(vertexBuffer, offset: 0, index: 0)
            let vertexThreads = MTLSize(width: activeSegmentCount + 1, height: activeSegmentCount + 1, depth: 1)
            if requiresUniformDispatch {
                let vertexThreadgroups = MTLSize(width: (vertexThreads.width + threadgroupSize.width - 1) / threadgroupSize.width,
                                                 height: (vertexThreads.height + threadgroupSize.height - 1) / threadgroupSize.height,
                                                 depth: 1)
                commandEncoder.dispatchThreadgroups(vertexThreadgroups, threadsPerThreadgroup: threadgroupSize)
            } else {
                commandEncoder.dispatchThreads(vertexThreads, threadsPerThreadgroup: threadgroupSize)
            }

            if needsTopologyUpdate {
                let indexBuffer = lowLevelMesh.replaceIndices(using: updateCommandBuffer)
                commandEncoder.setComputePipelineState(context.computePipelines[PipelineIndex.gridIndexUpdate.rawValue])
                commandEncoder.setBuffer(indexBuffer, offset: 0, index: 0)
                let indexThreads = MTLSize(width: activeSegmentCount, height: activeSegmentCount, depth: 1)
                if requiresUniformDispatch {
                    let indexThreadgroups = MTLSize(width: (indexThreads.width + threadgroupSize.width - 1) / threadgroupSize.width,
                                                    height: (indexThreads.height + threadgroupSize.height - 1) / threadgroupSize.height,
                                                    depth: 1)
                    commandEncoder.dispatchThreadgroups(indexThreadgroups, threadsPerThreadgroup: threadgroupSize)
                } else {
                    commandEncoder.dispatchThreads(indexThreads, threadsPerThreadgroup: threadgroupSize)
                }

                let bounds = BoundingBox(min: SIMD3<Float>(-0.5, -1.0, -0.5), 
                                         max: SIMD3<Float>(0.5, 1.0, 0.5))
                lowLevelMesh.parts.replaceAll([
                    LowLevelMesh.Part(indexOffset: 0,
                                      indexCount: indexCount,
                                      topology: .triangle,
                                      materialIndex: 0,
                                      bounds: bounds)
                ])

                needsTopologyUpdate = false
            }

            commandEncoder.endEncoding()
        }

        updateCommandBuffer.commit()
    }
}
