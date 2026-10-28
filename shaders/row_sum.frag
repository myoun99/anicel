#version 460 core

// 🚨ONE PASS OF A ROW SUM: every texel the sum of [uTaps] texels [uStride]
// apart along its row — itself, then the ones to its left, none past the
// raster's left edge (`RowSumPass`). Strides 1, taps, taps², … make each
// texel the sum of its row up to it (`rowSumPasses`) — what a camera lens
// blur's iris reads each of its rows out of in two reads
// (`iris_gather.frag`).
//
// 🚨LAID IN FLOATS (`rgbaFloat32`, drawn in `BlendMode.src`): a sum runs
// past 1, and a byte would clamp it. What is summed is premultiplied, as a
// raster is, so a mean of it is the blur of what it shows. ⚠️HIGHP, for
// the same reason: a sum across a raster thousands of pixels wide must
// keep the last pixel's eighth bit.
//
// 🔬A RASTER OF ITS OWN, AT THE IDENTITY (`applyEffectSteps`), as every
// step's pass is (`directional_blur.frag`).

#include <flutter/runtime_effect.glsl>

precision highp float;

uniform vec2 uSize;

// How far apart, in this raster's pixels, two taps lie.
uniform float uStride;

// How many taps, 1 … 64.
uniform float uTaps;

uniform sampler2D uSource;

out vec4 fragColor;

void main() {
  vec2 at = floor(FlutterFragCoord().xy);
  vec4 sum = vec4(0.0);
  // A loop needs a constant bound here: `rowSumTapsAPass`.
  for (int i = 0; i < 64; i++) {
    float x = at.x - float(i) * uStride;
    // ⛔NO EARLY RETURN (`colour_key.frag`, flutter#190809): a break ends
    // the loop, the shape the probes of 10-28 ran on the Surface Pro 11's
    // ANGLE.
    if (float(i) >= uTaps || x < 0.0) {
      break;
    }
    sum += texture(uSource, (vec2(x, at.y) + 0.5) / uSize);
  }
  fragColor = sum;
}
