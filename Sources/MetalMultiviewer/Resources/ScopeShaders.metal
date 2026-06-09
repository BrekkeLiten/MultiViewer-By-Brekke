#include <metal_stdlib>
using namespace metal;

constant uint kScopeColumns = 512;
constant uint kScopeLevels = 256;
constant uint kVectorscopeSize = 1024;

/// Waveform / parade IRE graticule (−20 footroom … 120 headroom); signal peaks at 100.
constant float kScopeIREMin = -20.0f;
constant float kScopeIREMax = 120.0f;
constant float kScopeIRESpan = 140.0f;
constant float kScopeSignalIREPeak = 100.0f;

struct ScopeDisplayUniforms {
  uint scopeKind; // 0 = RGB waveform, 1 = RGB parade, 2 = vectorscope
};

// MARK: - Histogram accumulation

kernel void scopeAccumulateHistogramKernel(
  texture2d<float, access::read> src [[texture(0)]],
  device atomic_uint *rgbHist [[buffer(0)]],
  device atomic_uint *vectorscopeHist [[buffer(1)]],
  uint2 gid [[thread_position_in_grid]]
) {
  const uint w = src.get_width();
  const uint h = src.get_height();
  if (gid.x >= w || gid.y >= h) return;

  float4 c = src.read(gid);
  float r = c.r;
  float g = c.g;
  float b = c.b;

  uint col = min(uint(float(gid.x) * float(kScopeColumns) / float(w)), kScopeColumns - 1);

  uint rLevel = min(uint(r * 255.0f), kScopeLevels - 1);
  uint gLevel = min(uint(g * 255.0f), kScopeLevels - 1);
  uint bLevel = min(uint(b * 255.0f), kScopeLevels - 1);

  atomic_fetch_add_explicit(rgbHist + (0u * kScopeColumns + col) * kScopeLevels + rLevel, 1u,
                          memory_order_relaxed);
  atomic_fetch_add_explicit(rgbHist + (1u * kScopeColumns + col) * kScopeLevels + gLevel, 1u,
                          memory_order_relaxed);
  atomic_fetch_add_explicit(rgbHist + (2u * kScopeColumns + col) * kScopeLevels + bLevel, 1u,
                          memory_order_relaxed);

  float cb = -0.1146f * r - 0.3854f * g + 0.5f * b;
  float cr = 0.5f * r - 0.4542f * g - 0.0458f * b;
  const float chromaScale = float(kVectorscopeSize - 1u);
  uint cbBin = min(uint(((cb) + 0.5f) * chromaScale), kVectorscopeSize - 1u);
  uint crBin = min(uint(((cr) + 0.5f) * chromaScale), kVectorscopeSize - 1u);
  atomic_fetch_add_explicit(vectorscopeHist + crBin * kVectorscopeSize + cbBin, 1u,
                          memory_order_relaxed);
}

// MARK: - Build scope textures from histograms

/// Texture row 0 = code 255 (peak white); row 255 = code 0 (black).
static uint scopeCodeLevelForTextureRow(uint row) {
  return (kScopeLevels - 1u) - row;
}

kernel void scopeBuildRGBWaveformKernel(
  texture2d<float, access::write> outTex [[texture(0)]],
  device const atomic_uint *rgbHist [[buffer(0)]],
  uint2 gid [[thread_position_in_grid]]
) {
  if (gid.x >= kScopeColumns || gid.y >= kScopeLevels) return;

  uint col = gid.x;
  uint codeLevel = scopeCodeLevelForTextureRow(gid.y);

  uint rCount = atomic_load_explicit(
    rgbHist + (0u * kScopeColumns + col) * kScopeLevels + codeLevel, memory_order_relaxed);
  uint gCount = atomic_load_explicit(
    rgbHist + (1u * kScopeColumns + col) * kScopeLevels + codeLevel, memory_order_relaxed);
  uint bCount = atomic_load_explicit(
    rgbHist + (2u * kScopeColumns + col) * kScopeLevels + codeLevel, memory_order_relaxed);

  float rInt = 1.0f - exp(-float(rCount) * 0.08f);
  float gInt = 1.0f - exp(-float(gCount) * 0.08f);
  float bInt = 1.0f - exp(-float(bCount) * 0.08f);

  outTex.write(float4(rInt, gInt, bInt, 1.0f), gid);
}

kernel void scopeBuildRGBParadeKernel(
  texture2d<float, access::write> outTex [[texture(0)]],
  device const atomic_uint *rgbHist [[buffer(0)]],
  uint2 gid [[thread_position_in_grid]]
) {
  const uint totalWidth = kScopeColumns * 3u;
  if (gid.x >= totalWidth || gid.y >= kScopeLevels) return;

  uint channel = gid.x / kScopeColumns;
  uint col = gid.x % kScopeColumns;
  uint codeLevel = scopeCodeLevelForTextureRow(gid.y);
  uint idx = (channel * kScopeColumns + col) * kScopeLevels + codeLevel;
  uint count = atomic_load_explicit(rgbHist + idx, memory_order_relaxed);
  float intensity = 1.0f - exp(-float(count) * 0.08f);

  float3 color = float3(0.0f);
  if (channel == 0u) color = float3(intensity, 0.0f, 0.0f);
  else if (channel == 1u) color = float3(0.0f, intensity, 0.0f);
  else color = float3(0.0f, 0.0f, intensity);

  outTex.write(float4(color, 1.0f), gid);
}

static float3 vectorscopeHueFromAngle(float angle) {
  float h = fract(angle / (2.0f * M_PI_F) + 1.0f);
  float r = abs(h * 6.0f - 3.0f) - 1.0f;
  float g = 2.0f - abs(h * 6.0f - 2.0f);
  float b = 2.0f - abs(h * 6.0f - 4.0f);
  return saturate(float3(r, g, b));
}

static float3 vectorscopeRingColor(float angle) {
  float h = fract(angle / (2.0f * M_PI_F) + 0.666667f);
  float r = abs(h * 6.0f - 3.0f) - 1.0f;
  float g = 2.0f - abs(h * 6.0f - 2.0f);
  float b = 2.0f - abs(h * 6.0f - 4.0f);
  float3 rgb = saturate(float3(r, g, b));
  float peak = max(rgb.r, max(rgb.g, rgb.b));
  return peak > 0.001f ? rgb / peak : rgb;
}

static float vectorscopeLocalDensity(
  device const atomic_uint *hist,
  int2 center
) {
  float accum = 0.0f;
  float weight = 0.0f;
  for (int y = -1; y <= 1; ++y) {
    for (int x = -1; x <= 1; ++x) {
      int sx = clamp(center.x + x, 0, int(kVectorscopeSize) - 1);
      int sy = clamp(center.y + y, 0, int(kVectorscopeSize) - 1);
      float w = (x == 0 && y == 0) ? 1.0f : 0.32f;
      uint count = atomic_load_explicit(
        hist + uint(sy) * kVectorscopeSize + uint(sx), memory_order_relaxed);
      accum += float(count) * w;
      weight += w;
    }
  }
  return accum / max(weight, 0.0001f);
}

kernel void scopeBuildVectorscopeKernel(
  texture2d<float, access::write> outTex [[texture(0)]],
  device const atomic_uint *vectorscopeHist [[buffer(0)]],
  uint2 gid [[thread_position_in_grid]]
) {
  if (gid.x >= kVectorscopeSize || gid.y >= kVectorscopeSize) return;

  float density = vectorscopeLocalDensity(vectorscopeHist, int2(int(gid.x), int(gid.y)));
  float intensity = density > 0.0f ? (1.0f - exp(-density * 0.11f)) : 0.0f;
  outTex.write(float4(intensity, intensity, intensity, 1.0f), gid);
}

// MARK: - Scope display

struct ScopeVertexIn {
  float2 position [[attribute(0)]];
  float2 uv [[attribute(1)]];
};

struct ScopeVertexOut {
  float4 position [[position]];
  float2 uv;
};

vertex ScopeVertexOut scopeDisplayVertex(ScopeVertexIn in [[stage_in]]) {
  ScopeVertexOut out;
  out.position = float4(in.position, 0.0, 1.0);
  out.uv = in.uv;
  return out;
}

static float scopeDisplayYForIRE(float ire) {
  return (kScopeIREMax - ire) / kScopeIRESpan;
}

static float scopeIREAtDisplayY(float uvY) {
  return mix(kScopeIREMax, kScopeIREMin, uvY);
}

static float3 graticuleLine(float2 uv, float ireLevel, float halfWidth, float3 color) {
  const float y = scopeDisplayYForIRE(ireLevel);
  if (abs(uv.y - y) < halfWidth) return color;
  return float3(0.0f);
}

static float3 waveformGraticule(float2 uv) {
  const float kIRELevels[8] = {-20, 0, 20, 40, 60, 80, 100, 120};
  const float3 majorColor = float3(0.42f, 0.28f, 0.14f);
  const float3 minorColor = float3(0.22f, 0.15f, 0.09f);

  float3 grid = float3(0.0);
  for (int i = 0; i < 8; ++i) {
    const float ire = kIRELevels[i];
    const bool isMajor = (ire <= 0.0f || ire >= kScopeSignalIREPeak);
    const float3 color = isMajor ? majorColor : minorColor;
    const float halfWidth = isMajor ? 0.0045f : 0.0035f;
    grid = max(grid, graticuleLine(uv, ire, halfWidth, color));
  }
  return grid;
}

static float4 sampleScopeTrace(float2 uv, texture2d<float> scopeTex, sampler samp) {
  const float ire = scopeIREAtDisplayY(uv.y);
  if (ire < 0.0f || ire > kScopeSignalIREPeak) return float4(0.0f);
  // Map display IRE (0…100) to histogram code row (255 at texture top).
  const float signal = ire / kScopeSignalIREPeak;
  const float texV = 1.0f - signal;
  return scopeTex.sample(samp, float2(uv.x, texV));
}

static float2 scopeDisplayUV(float2 uv) {
  return float2(uv.x, 1.0f - uv.y);
}

/// 1.0 = full chroma field; values >1 magnify the center (Resolve-style gain).
constant float kVectorscopeZoom = 1.0f;
/// Inscribed chroma plot (100% saturation); inset so the hue ring fits in the square.
constant float kVectorscopeDataEdge = 0.86f;
/// Hue ring just outside peak saturation, still inside the square clip.
constant float kVectorscopeHueRingRadius = 0.955f;

static float vectorscopeDataDist(float screenDist) {
  return screenDist / (kVectorscopeDataEdge * kVectorscopeZoom);
}

static float2 vectorscopeDataUV(float2 screenUV) {
  float2 vuv = scopeDisplayUV(screenUV);
  float2 screenC = vuv - 0.5f;
  return 0.5f + screenC / (kVectorscopeDataEdge * kVectorscopeZoom);
}

constant float kVectorscopeTargetAngles[6] = {
  2.35619f, 3.14159f, 3.92699f, 5.49779f, 0.0f, 0.785398f
};

static float vectorscopeTraceIntensity(float2 dataUV, texture2d<float> scopeTex, sampler samp) {
  float2 uv = saturate(dataUV);
  const float2 texel = float2(1.0f / float(scopeTex.get_width()),
                              1.0f / float(scopeTex.get_height()));
  float sharp = scopeTex.sample(samp, uv).r;
  float soft = 0.0f;
  float weight = 0.0f;
  for (int y = -1; y <= 1; ++y) {
    for (int x = -1; x <= 1; ++x) {
      float w = exp(-float(x * x + y * y) * 0.65f);
      float2 off = float2(float(x), float(y)) * texel * 0.9f;
      soft += scopeTex.sample(samp, uv + off).r * w;
      weight += w;
    }
  }
  float blended = mix(sharp, soft / max(weight, 0.0001f), 0.4f);
  return saturate(blended * 1.06f);
}

static float3 vectorscopeGraticuleAt(float2 screenUV) {
  float2 vuv = scopeDisplayUV(screenUV);
  float2 screenC = vuv - 0.5f;
  float screenDist = length(screenC) * 2.0f;
  float angle = atan2(screenC.y, screenC.x);
  float dataDist = vectorscopeDataDist(screenDist);

  const float3 ringColor = float3(0.155f);
  const float3 axisColor = float3(0.115f);
  const float3 boxLine = float3(0.21f);
  const float3 boxFill = float3(0.055f);

  float3 grid = float3(0.0f);
  float hueRingHalf = max(fwidth(screenDist) * 2.4f, 0.0035f);
  if (screenDist > kVectorscopeHueRingRadius + hueRingHalf * 3.0f) return grid;

  if (screenDist <= kVectorscopeDataEdge + 0.01f) {
    for (int i = 1; i <= 8; ++i) {
      float ring = float(i) / 8.0f;
      if (abs(dataDist - ring) < 0.006f) grid = max(grid, ringColor);
    }

    for (int i = 0; i < 6; ++i) {
      float axis = kVectorscopeTargetAngles[i];
      if (abs(sin(angle - axis)) * screenDist < 0.022f && dataDist < 0.9f) {
        grid = max(grid, axisColor);
      }
    }

    if (abs(screenC.x) < 0.008f && dataDist < 0.92f) grid = max(grid, axisColor);
    if (abs(screenC.y) < 0.008f && dataDist < 0.92f) grid = max(grid, axisColor);
  }

  if (abs(screenDist - kVectorscopeDataEdge) < 0.005f) {
    grid = max(grid, float3(0.28f));
  }

  if (abs(screenDist - kVectorscopeHueRingRadius) < hueRingHalf) {
    grid = vectorscopeRingColor(angle);
  }

  const float targetRadius = 0.375f;
  const float boxHalf = 0.017f;
  float2 dataC = screenC / (kVectorscopeDataEdge * kVectorscopeZoom);
  for (int i = 0; i < 6; ++i) {
    float2 tick = float2(cos(kVectorscopeTargetAngles[i]), sin(kVectorscopeTargetAngles[i])) * targetRadius;
    float2 p = dataC - tick;
    float edge = max(abs(p.x), abs(p.y));
    if (edge < boxHalf - 0.003f) grid = max(grid, boxFill);
    if (edge > boxHalf - 0.0022f && edge < boxHalf + 0.0006f) grid = max(grid, boxLine);
  }

  return grid;
}

static float4 sampleVectorscopeTrace(float2 screenUV, texture2d<float> scopeTex, sampler samp) {
  float2 vuv = scopeDisplayUV(screenUV);
  float screenDist = length(vuv - 0.5f) * 2.0f;
  if (screenDist > kVectorscopeDataEdge - 0.004f) return float4(0.0f);

  float2 dataUV = vectorscopeDataUV(screenUV);
  float2 c = dataUV - 0.5f;
  if (length(c) > 0.52f) return float4(0.0f);
  float intensity = vectorscopeTraceIntensity(dataUV, scopeTex, samp);
  return float4(intensity, intensity, intensity, 1.0f);
}

static float3 paradeColumnDividers(float2 uv) {
  const float3 divider = float3(0.22f, 0.15f, 0.09f);
  float3 out = float3(0.0);
  if (abs(uv.x - 1.0f / 3.0f) < 0.0018f || abs(uv.x - 2.0f / 3.0f) < 0.0018f) out = divider;
  return out;
}

fragment float4 scopeDisplayFragment(
  ScopeVertexOut in [[stage_in]],
  texture2d<float> scopeTex [[texture(0)]],
  sampler samp [[sampler(0)]],
  constant ScopeDisplayUniforms &u [[buffer(0)]]
) {
  float2 uv = in.uv;
  float3 phosphor = float3(0.0);

  if (u.scopeKind == 0u) {
    float4 sample = sampleScopeTrace(uv, scopeTex, samp);
    phosphor = max(phosphor, sample.rgb);
    phosphor = max(phosphor, waveformGraticule(uv));
  } else if (u.scopeKind == 1u) {
    phosphor = max(phosphor, paradeColumnDividers(uv));
    float4 sample = sampleScopeTrace(uv, scopeTex, samp);
    phosphor = max(phosphor, sample.rgb);
    phosphor = max(phosphor, waveformGraticule(uv));
  } else {
    float2 vuv = scopeDisplayUV(uv);
    float dist = length(vuv - 0.5f) * 2.0f;
    float hueRingHalf = max(fwidth(dist) * 2.4f, 0.0035f);
    if (dist <= kVectorscopeHueRingRadius + hueRingHalf * 3.0f) {
      phosphor = max(phosphor, vectorscopeGraticuleAt(uv));
    }
    if (dist <= kVectorscopeDataEdge) {
      float4 sample = sampleVectorscopeTrace(uv, scopeTex, samp);
      phosphor = max(phosphor, sample.rgb);
    }
  }

  return float4(phosphor, 1.0);
}
