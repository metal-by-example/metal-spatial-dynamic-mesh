#include <metal_stdlib>
using namespace metal;

#include "ShaderTypes.h"

float wave_height(constant WaveDescriptor &wave, float x, float z) {
    float r = sqrt(x * x + z * z);
    float y = wave.amplitude * cos(-r * 2.0f * M_PI_F * wave.waveDensity + wave.time);
    return y;
}

[[kernel]]
void update_grid_indices(device uint *indices [[buffer(0)]],
                         constant WaveDescriptor &wave [[buffer(1)]],
                         uint2 gridCoords [[thread_position_in_grid]])
{
    if ((gridCoords[0] >= wave.segmentCount) || (gridCoords[1] >= wave.segmentCount)) {
        return; // Avoid writing out of bounds
    }

    uint widthSegments = wave.segmentCount;
    uint widthVertexCount = widthSegments + 1;
    uint baseIndex = (gridCoords.y * widthSegments + gridCoords.x) * 6;
    uint baseVertex = gridCoords.y * widthVertexCount + gridCoords.x;
    // Each grid segment is composed of two triangles wound in counter-clockwise order.
    indices[baseIndex + 0] = baseVertex;
    indices[baseIndex + 1] = baseVertex + widthVertexCount;
    indices[baseIndex + 2] = baseVertex + 1;
    indices[baseIndex + 3] = baseVertex + 1;
    indices[baseIndex + 4] = baseVertex + widthVertexCount;
    indices[baseIndex + 5] = baseVertex + widthVertexCount + 1;
}

[[kernel]]
void update_wave_vertex(device MeshVertex *vertices [[buffer(0)]],
                        constant WaveDescriptor &wave [[buffer(1)]],
                        uint2 gridCoords [[thread_position_in_grid]])
{
    if ((gridCoords[0] > wave.segmentCount) || (gridCoords[1] > wave.segmentCount)) {
        return; // Avoid writing out of bounds
    }

    // The entire mesh is defined to span from -0.5 to 0.5 along the XZ plane in model space.
    const float width = 1.0f;
    const float depth = 1.0f;

    // Although we only pass in a single segment count value, for the sake of clarity, here
    // we define separate variables for the number of width and depth segments.
    const float widthSegments = wave.segmentCount;
    const float depthSegments = wave.segmentCount;

    // As a final bit of prelude, we define the model-space width and depth of each segment
    const float segmentWidth = width / widthSegments;
    const float segmentDepth = depth / depthSegments;

    // Here we convert from the 2D index of the vertex we're handling to the 1D vertex index
    // in the array of mesh vertices.
    const uint widthVertexCount = widthSegments + 1;
    const uint vertexIndex = gridCoords[1] * widthVertexCount + gridCoords[0];

    // This is the vertex we're responsible for updating
    device MeshVertex &vert = vertices[vertexIndex];

    // The position of the vertex is determined by interpolating
    // in grid space then sampling the wave height.
    const float x = gridCoords[0] * segmentWidth - (width * 0.5f);
    const float z = gridCoords[1] * segmentDepth - (depth * 0.5f);
    const float y = wave_height(wave, x, z);

    // To find the surface normal we take additional samples at
    // differential offsets in the X and Z directions.
    const float eps = 0.01f;
    const float dydx = wave_height(wave, x + eps, z) - wave_height(wave, x - eps, z);
    const float dydz = wave_height(wave, x, z + eps) - wave_height(wave, x, z - eps);
    const float dydy = eps * 2;
    const float3 N = normalize(float3(dydx, dydy, dydz));

    // To find the uv coordinates of the vertex we do a straight
    // linear interpolation in grid space, flipping the vertical
    // axis to agree with Metal texture space.
    const float u = gridCoords[0] / widthSegments;
    const float v = 1.0f - (gridCoords[1] / depthSegments);

    // Finally we update our output vertex attributes.
    vert.position = float3(x, y, z);
    vert.normal = N;
    vert.uv = float2(u, v);
}
