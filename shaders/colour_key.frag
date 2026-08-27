#version 460 core

// 🚨★★★THE COLOUR KEY, ON THE PROCESSOR THAT HAS THE PIXELS.
//
// One effect, two implementations, and they must agree bit for bit: the
// BUTTON edits cel bytes on the CPU (`CelColorKey` in
// lib/src/services/cel_source_effect_pass.dart) and the FX keys a composited
// image here, where the pixels only exist on the GPU. Every line below
// mirrors a line there — see `matches`, `erases` and `alphaFor`.
//
// 📐WHY THE 255 SCALE AND THE HALF STEP. The CPU compares 8-bit integers
// with `<=`. Comparing normalised floats against `tolerance / 255` puts the
// threshold exactly ON a representable value, where a float that is one ulp
// heavy answers the other way. Scaling to 0…255 and testing against
// `tolerance + 0.5` puts it at the FARTHEST point from any 8-bit value, so
// no precision a backend could plausibly use can flip it. That is a design
// that cannot go wrong rather than one that happens not to.

#include <flutter/runtime_effect.glsl>

uniform vec2 uSize;

// The source, straight from the composite. ⚠️PREMULTIPLIED — the CPU side
// reads straight cel bytes, so this has to undo the multiply before it can
// ask the same question about the same numbers.
uniform sampler2D uSource;

// The key colour in 0…255, matching the CPU's ints exactly.
uniform vec3 uKey255;

// The largest per-channel gap that still counts as the key, 0…255.
// ⛔CHEBYSHEV, NOT EUCLIDEAN — the same metric `CelColorKey.matches` uses,
// and the one a tolerance slider is read as everywhere else.
uniform float uTolerance255;

// 0…1. A colour key has no value that is an identity, so this is what makes
// a freshly added effect do nothing.
uniform float uAmount;

// 1 for KEEP COLOR, 0 for DELETE COLOR — the same comparison, opposite
// answer (`CelColorKey.keepsMatches`).
uniform float uKeepsMatches;

out vec4 fragColor;

void main() {
  vec4 src = texture(uSource, FlutterFragCoord().xy / uSize);
  if (src.a <= 0.0) {
    // The CPU returns the alpha untouched at zero rather than dividing by
    // it. Same answer, and no division by zero here either.
    fragColor = vec4(0.0);
    return;
  }
  vec3 straight = src.rgb / src.a;
  vec3 gap = abs(straight * 255.0 - uKey255);
  float widest = max(max(gap.r, gap.g), gap.b);
  // `<= tolerance` on integers, asked where no float can be ambiguous.
  float matches = step(widest, uTolerance255 + 0.5);
  // `matches != keepsMatches`, in the arithmetic available here.
  float erases = abs(matches - uKeepsMatches);

  // 📐THE MIX, ROUNDED HERE RATHER THAN BY THE BACKEND.
  //
  // Handing a normalised float to an 8-bit target leaves the rounding to
  // whoever is writing the pixel, and the CPU side has to be able to predict
  // it. So the alpha is quantised on purpose: recover the source's own byte,
  // do the multiply the CPU does, round the way the CPU rounds, and hand
  // back an exact n/255.
  //
  // ⛔ONE PASS. The Amount mix is folded into the alpha rather than drawn as
  // a second layer over the first, because a two-pass mix accumulates alpha.
  // RGB is never touched: an RGB comparison still picks exactly the same
  // pixels after this has run, which is what lets the destructive verb's
  // undo replay positionally.
  float sourceByte = floor(src.a * 255.0 + 0.5);
  float kept = 1.0 - uAmount * erases;
  float keptByte = floor(sourceByte * kept + 0.5);
  float alpha = keptByte / 255.0;
  fragColor = vec4(straight * alpha, alpha);
}
