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

// MARK: - Picture monitoring overlays

struct PictureMonitoringUniforms {
  uint flags; // bit 0 = peaking, 1 = false color, 2 = zebra
  float peakingThreshold;
  float zebraLevel;
  float2 texelSize;
  float4 peakingColor; // rgb in xyz
};

constant uint kMonitoringPeaking = 1u;
constant uint kMonitoringFalseColor = 2u;
constant uint kMonitoringZebra = 4u;

inline float luma709(float3 rgb) {
  return 0.2126f * rgb.r + 0.7152f * rgb.g + 0.0722f * rgb.b;
}

inline float3 falseColorFromLuma(float y) {
  // Broadcast-style ramp: blue shadows → cyan → green → yellow → red clip.
  if (y < 0.10f) {
    return float3(0.0f, 0.0f, mix(0.35f, 1.0f, y / 0.10f));
  }
  if (y < 0.30f) {
    float t = (y - 0.10f) / 0.20f;
    return float3(0.0f, mix(0.0f, 1.0f, t), 1.0f);
  }
  if (y < 0.55f) {
    float t = (y - 0.30f) / 0.25f;
    return float3(0.0f, 1.0f, mix(1.0f, 0.0f, t));
  }
  if (y < 0.80f) {
    float t = (y - 0.55f) / 0.25f;
    return float3(mix(0.0f, 1.0f, t), 1.0f, 0.0f);
  }
  if (y < 0.95f) {
    float t = (y - 0.80f) / 0.15f;
    return float3(1.0f, mix(1.0f, 0.0f, t), 0.0f);
  }
  return float3(1.0f, 0.0f, 0.0f);
}

inline float3 applyFocusPeaking(
  float3 base,
  float2 uv,
  texture2d<float> tex,
  sampler samp,
  float2 texelSize,
  float threshold,
  float4 peakColor
) {
  float3 c = tex.sample(samp, uv).rgb;
  float yC = luma709(c);

  float yL = luma709(tex.sample(samp, uv + float2(-texelSize.x, 0.0f)).rgb);
  float yR = luma709(tex.sample(samp, uv + float2(texelSize.x, 0.0f)).rgb);
  float yU = luma709(tex.sample(samp, uv + float2(0.0f, -texelSize.y)).rgb);
  float yD = luma709(tex.sample(samp, uv + float2(0.0f, texelSize.y)).rgb);
  float yUL = luma709(tex.sample(samp, uv + float2(-texelSize.x, -texelSize.y)).rgb);
  float yUR = luma709(tex.sample(samp, uv + float2(texelSize.x, -texelSize.y)).rgb);
  float yDL = luma709(tex.sample(samp, uv + float2(-texelSize.x, texelSize.y)).rgb);
  float yDR = luma709(tex.sample(samp, uv + float2(texelSize.x, texelSize.y)).rgb);

  float blur = (yL + yR + yU + yD + yUL + yUR + yDL + yDR) / 8.0f;
  float edge = abs(yC - blur);
  float highlight = smoothstep(threshold * 0.5f, threshold, edge);
  return mix(base, peakColor.xyz, highlight * 0.8f);
}

inline float3 applyZebra(float3 base, float2 uv, float y, float zebraLevel) {
  if (y < zebraLevel) {
    return base;
  }
  const float frequency = 48.0f;
  float stripe = fract((uv.x + uv.y) * frequency);
  float3 stripeColor = stripe < 0.5f ? float3(1.0f) : float3(0.0f);
  return mix(base, stripeColor, 0.5f);
}

fragment float4 monitoredFragment(
  VertexOut in [[stage_in]],
  texture2d<float> tex [[texture(0)]],
  sampler samp [[sampler(0)]],
  constant PictureMonitoringUniforms &u [[buffer(0)]]
) {
  float4 sample = tex.sample(samp, in.uv);
  if (u.flags == 0u) {
    return sample;
  }

  float3 color = sample.rgb;
  float y = luma709(color);

  if ((u.flags & kMonitoringFalseColor) != 0u) {
    color = falseColorFromLuma(y);
    y = luma709(color);
  }

  if ((u.flags & kMonitoringPeaking) != 0u) {
    color = applyFocusPeaking(
      color,
      in.uv,
      tex,
      samp,
      u.texelSize,
      u.peakingThreshold,
      u.peakingColor
    );
  }

  if ((u.flags & kMonitoringZebra) != 0u) {
    color = applyZebra(color, in.uv, y, u.zebraLevel);
  }

  return float4(color, sample.a);
}
