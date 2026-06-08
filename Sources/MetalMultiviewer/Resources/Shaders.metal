#include <metal_stdlib>
using namespace metal;

struct VertexIn {
  float2 position [[attribute(0)]];
  float2 uv [[attribute(1)]];
};

struct VertexOut {
  float4 position [[position]];
  float2 uv;
};

vertex VertexOut texturedVertex(VertexIn in [[stage_in]]) {
  VertexOut out;
  out.position = float4(in.position, 0.0, 1.0);
  out.uv = in.uv;
  return out;
}

fragment float4 texturedFragment(
  VertexOut in [[stage_in]],
  texture2d<float> tex [[texture(0)]],
  sampler samp [[sampler(0)]]
) {
  return tex.sample(samp, in.uv);
}

