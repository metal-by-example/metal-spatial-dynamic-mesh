#pragma once

#include <simd/simd.h>

#ifndef __METAL__
typedef struct { float x; float y; float z; } packed_float3;
#endif

struct MeshVertex {
    packed_float3 position;
    packed_float3 normal;
    simd_packed_float2 uv;
};

struct WaveDescriptor {
    unsigned int segmentCount;
    float time;
    float waveDensity;
    float amplitude;
};
