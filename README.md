# Dynamic RealityKit Meshes with LowLevelMesh

This sample is a demonstration of how to use the [`LowLevelMesh`](https://developer.apple.com/documentation/realitykit/lowlevelmesh) class in RealityKit, introduced in visionOS 2 , iOS 18, and macOS 15 Sequoia. **Requires Xcode 16.0 Beta 1 or newer.**

![A screenshot of the sample app running on the visionOS Simulator](screenshots/01.png)

The core idea behind this API is that sometimes you'd like to update the contents of a `MeshResource` without having to recreate it from scratch or pack your data into the prescribed [`MeshBuffers`](https://developer.apple.com/documentation/realitykit/meshbuffers) format. To that end, a `LowLevelMesh` is an alternative to `MeshDescriptor` that allows you to specify your own vertex buffer layout and regenerate mesh contents either on the CPU or on the GPU with a Metal compute shader.

## Attributes and Layouts

A `LowLevelMesh` is constructed from a descriptor, which holds attributes and layouts. Attributes and layouts work together to tell RealityKit where to find all of the data for a given vertex. Attributes and layouts are an abstraction that give you a lot of flexibility over how vertex data is laid out in vertex buffers.

An _attribute_ is a property of a vertex: position, normal, texture coordinate, etc. All of the data for a single attribute for a given mesh resides in one vertex buffer. Since vertex data might be interleaved in a vertex buffer, each attribute has an _offset_ which tells RealityKit where the data starts relative to the beginning of the buffer. Additionally, each attribute has a _format_ that indicates the type and size of the data. For example, vertex positions are commonly stored as `float3`, and a vertex color might be packed into a `uchar4Normalized`.

For each vertex buffer, the low-level mesh descriptor contains a _layout_ which mostly exists to indicate the _stride_ or distance between the start of data for one vertex and the start of the next. Although it is possible to completely deinterleave vertex data, using one vertex buffer per attribute, it is common to interleave vertex data into as small a number of buffers as possible (one or maybe two).

## Attributes and Layouts in Practice

To construct a `LowLevelMesh.Descriptor`, we first need to design our vertex layout. In this sample, I use a fully interleaved layout, with one buffer holding all attributes. Again, this isn't necessary, and one of the major selling points of the API is that you can use a completely arbitrary data layout.

Suppose I have a vertex structure that looks like this in MSL:

```metal
struct MeshVertex {
    packed_float3 position;
    packed_float3 normal;
    packed_float2 texCoords;
};
```

From the use of packed types, we know that the position is at offset 0, the normal is at offset 12, the texture coordinates are at offset 24, and the whole vertex has a size and stride of 32 bytes. This type is difficult to write as a Swift struct, since we don't have control over layout and padding, but that doesn't stop us from working with such vertices, especially if we only manipulate the data from a compute shader.

Here's how to construct the attributes and layouts needed to represent this vertex structure in RealityKit:

```swift
let attributes: [LowLevelMesh.Attribute] = [
    .init(semantic: .position, format: .float3, offset: 0),
    .init(semantic: .normal, format: .float3, offset: 12),
    .init(semantic: .uv0, format: .float2, offset: 24)
]

let layouts: [LowLevelMesh.Layout] = [
    .init(bufferIndex: 0, bufferOffset: 0, bufferStride: 32)
]
```

(Note that each `LowLevelMesh.Attribute` has a default layout index of 0, corresponding to the first vertex buffer. You can change this if using more than one buffer/layout.)

(You might object that this is brittle and will break if anything about our vertex struct changes. You'd be right. See the code for an example of how to make this slightly more robust by using Swift's `MemoryLayout` type.)

## Creating a `LowLevelMesh`

One of the most important things to note about this API is that RealityKit manages the actual Metal buffers that store vertex and index data; you don't create these buffers yourself. This is so that RealityKit can perform internal synchronization and efficiently reuse resources over time. 

Since a `LowLevelMesh` can be updated at run-time without being recreated, we need to pick capacities for its vertex and index buffers. If you know that your vertex and index counts will never change, you can just use these as your vertex and index capacities. Otherwise, you need to establish an upper bound representing the maximum amount of data you expect the mesh to need during its whole lifetime.

This sample builds an animated grid mesh whose resolution can be controlled at runtime. So, we select an upper bound of how finely subdivided the grid can be and calculate our vertex and index capacities based on our knowledge of the mesh topology we'll create:

```swift
let vertexCapacity = (maxSegmentCount + 1) * (maxSegmentCount + 1)
let indexCapacity = maxSegmentCount * maxSegmentCount * 6
```

Putting all of this together, we can now construct a `LowLevelMesh` object:

```swift
let meshDescriptor = LowLevelMesh.Descriptor(vertexCapacity: vertexCapacity,
                                             vertexAttributes: attributes,
                                             vertexLayouts: layouts,
                                             indexCapacity: indexCapacity,
                                             indexType: .uint32)
lowLevelMesh = try LowLevelMesh(descriptor: meshDescriptor)
```

## Populating Mesh Data and Parts

At this point, our mesh contains no data and no geometry. To actually draw anything with RealityKit, we need to populate our vertex buffers and tell our mesh how to group their contents into mesh parts.

The core API for populating a low-level mesh's vertex buffers is the `replace(bufferIndex: Int, using: MTLCommandBuffer)` method. For each vertex buffer you want to fill with data, you call this method, which returns an `MTLBuffer`. You can then dispatch a compute function to populate the buffer. You have complete control over the work you do to achieve this; the only requisite is that you tell RealityKit which command buffer holds the commands that perform the update. RealityKit can then wait on its completion before using the contents of the buffer to render. This prevents race conditions and allows you to seamlessly update mesh data even while a previous version of the mesh's contents are being rendered.

Similarly, you use the `replaceIndices(using: MTLCommandBuffer)` method to update mesh indices.

When first populating a mesh, and whenever you change the number of indices thereafter, you must recreate the _parts_ of the mesh. You can think of a part as a sub-mesh: it has a range of indices and can be assigned a unique material. You are also responsible for calculating the model-space bounding box of the part, so RealityKit can perform frustum culling.

In the sample, our grid mesh only has one part, and we use a fixed bounding volume that always contains it. Depending on your use case, you might need to do more work.

Since we want to completely replace the pre-existing mesh part(s), we use the `replaceAll` method, calling it with a single-element array containing our one part. You're welcome to divide your mesh into as many parts as are necessary to achieve your desired effect.

```swift
let bounds = BoundingBox(min: SIMD3<Float>(-0.5, -1.0, -0.5), 
                         max: SIMD3<Float>(0.5, 1.0, 0.5))
lowLevelMesh.parts.replaceAll([
    LowLevelMesh.Part(indexOffset: 0,
    indexCount: indexCount,
    topology: .triangle,
    materialIndex: 0,
    bounds: bounds)
])
```

Here's a sketch of how you might dispatch the compute work to perform a mesh update:

```swift
let commandBuffer = commandQueue.makeCommandBuffer()!
let threadgroupSize = MTLSize(...)

let commandEncoder = commandBuffer.makeComputeCommandEncoder()!
let vertexBuffer = lowLevelMesh.replace(bufferIndex: 0, using: commandBuffer)
commandEncoder.setBuffer(vertexBuffer, offset: 0, index: 0)
// ... set compute pipeline and other necessary state ...
commandEncoder.dispatchThreadgroups(..., threadsPerThreadgroup: threadgroupSize)

let indexBuffer = lowLevelMesh.replaceIndices(using: updateCommandBuffer)
commandEncoder.setBuffer(indexBuffer, offset: 0, index: 0)
// ... set compute pipeline and other necessary state ...
commandEncoder.dispatchThreads(..., threadsPerThreadgroup: threadgroupSize)
commandEncoder.endEncoding()

commandBuffer.commit()
```

Since this is an introduction to the `LowLevelMesh` API and not a Metal tutorial, I refer you to the source code for the details of how the vertex and index buffers are populated on the GPU using compute shaders.

## Displaying a Low-Level Mesh

The final step of getting a mesh on screen with RealityKit is using it to generate a `MeshResource` and attaching it to a `ModelEntity`. This is our opportunity to determine which `Material` should be used to shade each mesh part.

```swift
let meshResource = try MeshResource(from: lowLevelMesh)

var material = PhysicallyBasedMaterial()
// ... set material properties ...

let modelEntity = ModelEntity()
modelEntity.model = ModelComponent(mesh: meshResource, materials: [material])
```

We can then situate the model entity in the world using the ordinary APIs.

A mesh resource created from a low-level mesh retains it, so that the mesh resource is aware of when its buffers and parts are updated. This allows RealityKit to seamlessly display the mesh whenever it changes (whether by being updated on the CPU or the GPU).

The sample updates the animated mesh at a cadence of 60 FPS, but you may find that for your use cases, you want to update less frequently, or only in response to user input. 

For a more thorough example of how to use this API, consult Apple's sample code project, [_Creating a spatial drawing app with RealityKit_](https://developer.apple.com/documentation/RealityKit/creating-a-spatial-drawing-app-with-realitykit).