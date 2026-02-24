// -----------------------------------------------------------------------------
// This file is part of VirtualC64
//
// Copyright (C) Dirk W. Hoffmann. www.dirkwhoffmann.de
// This FILE is dual-licensed. You are free to choose between:
//
//     - The GNU General Public License v3 (or any later version)
//     - The Mozilla Public License v2
//
// SPDX-License-Identifier: GPL-3.0-or-later OR MPL-2.0
// -----------------------------------------------------------------------------

#include <metal_stdlib>
using namespace metal;

struct VertexOut {
    float4 position [[position]];
    float2 texCoord;
};

vertex VertexOut iosVertexShader(uint vertexID [[vertex_id]],
                                 constant float4 *vertices [[buffer(0)]]) {
    // Each vertex is packed as (x, y, u, v) in a float4
    float4 v = vertices[vertexID];

    VertexOut out;
    out.position = float4(v.x, v.y, 0.0, 1.0);
    out.texCoord = float2(v.z, v.w);
    return out;
}

fragment float4 iosFragmentShader(VertexOut in [[stage_in]],
                                   texture2d<float> tex [[texture(0)]],
                                   sampler smp [[sampler(0)]]) {
    return tex.sample(smp, in.texCoord);
}
