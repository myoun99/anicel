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

// The RUN's input — what the picture was before the keys standing together
// with this one; uSource itself for the run's first key. A restore gives
// back to its alphas, and its colours are the ones every key of the run
// asks about and leaves: no key touches a colour, so they are the run's.
uniform sampler2D uOriginal;

// The key colour in 0…255, matching the CPU's ints exactly.
uniform vec3 uKey255;

// The largest per-channel gap that still counts as the key, 0…255.
// ⛔CHEBYSHEV, NOT EUCLIDEAN — the same metric `CelColorKey.matches` uses,
// and the one a tolerance slider is read as everywhere else.
uniform float uTolerance255;

// 0…1. A colour key has no value that is an identity, so this is what makes
// a freshly added effect do nothing.
uniform float uAmount;

// 1 for Keep Colors, 0 for Key Colors (`CelKeyOperation`): a restore gives
// back what the run erased of what the colour names, an erase takes it.
uniform float uRestores;

out vec4 fragColor;

void main() {
  vec2 uv = FlutterFragCoord().xy / uSize;
  vec4 src = texture(uSource, uv);
  vec4 original = texture(uOriginal, uv);
  // The CPU returns the alpha untouched at zero rather than dividing by it,
  // and so does this: a transparent pixel divides nothing, and its byte of
  // 0 runs through the arithmetic below to an alpha of 0 — the vec4(0.0)
  // the CPU hands back, bit for bit.
  //
  // ⛔NO EARLY RETURN. A fragment shader that samples a texture and returns
  // early is the shape ANGLE hands Windows' D3D shader compiler in a form it
  // can crash on (flutter#190809, closed 2026-09-29 with a compiler warning
  // for exactly that pair rather than a fix). This one used to leave here.
  vec3 straight =
      original.a > 0.0 ? original.rgb / original.a : vec3(0.0);
  vec3 gap = abs(straight * 255.0 - uKey255);
  float widest = max(max(gap.r, gap.g), gap.b);
  // `<= tolerance` on integers, asked where no float can be ambiguous.
  float matches = step(widest, uTolerance255 + 0.5);

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
  //
  // A restore is the same arithmetic over what is MISSING:
  // `original - erased(original - alpha)` (`CelColorKey.alphaFor`). Both
  // answers are whole bytes, so choosing between them by a 0 or a 1 is
  // exact.
  float sourceByte = floor(src.a * 255.0 + 0.5);
  float originalByte = floor(original.a * 255.0 + 0.5);
  float kept = 1.0 - uAmount;
  float erasedByte = floor(sourceByte * kept + 0.5);
  float restoredByte =
      originalByte - floor((originalByte - sourceByte) * kept + 0.5);
  float keyedByte = mix(erasedByte, restoredByte, uRestores);
  float alpha = mix(sourceByte, keyedByte, matches) / 255.0;
  fragColor = vec4(straight * alpha, alpha);
}
