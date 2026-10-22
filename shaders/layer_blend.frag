#version 460 core

// 🚨★★★A LAYER'S BLEND THE GPU LACKS, ON THE PROCESSOR THAT HAS THE PIXELS
// (brush-fidelity-Q4, 유저 2026-10-17 「레이어까지 같이」).
//
// One blend, two processors. The BRUSH lays these modes on the CPU, where a
// cel's bytes are (`blendStrokeRegionPixels` in
// lib/src/services/brush_stroke_blend.dart, mirrored in C by
// `qa_stroke_blend_channel` / `qa_stroke_blend_triple`); a LAYER in one is
// composed here, over a picture of its backdrop, because a composite's
// pixels only exist on the GPU and the GPU has no blend for them. Every
// formula and the composite below are that file's, and
// `test/ui/canvas/one_blend_two_processors_test.dart` sweeps the pair.
//
// 📐WHY THE BYTES. The CPU reads straight 8-bit bytes. A sample here is a
// premultiplied byte as a float; at full alpha that IS the byte over 255, so
// each channel is brought back to its byte first and every formula taken of
// bytes: `s + d >= 255`, never `cs + cd >= 1.0`, which a float can call
// either way, and a quotient of two whole bytes — `d / s`, not
// `(d / 255) / (s / 255)` — so it is rounded once where the CPU's doubles
// carry it exact. Where that one rounding lands ON a half step, the two may
// still part by one; the sweep names those pairs rather than hiding them.
//
// ⛔NO EARLY RETURN, in main or in a helper (flutter#190809: D3D under ANGLE
// can crash on a shader that samples and returns early) — every branch is a
// select or an if that falls through to one return at the end.

#include <flutter/runtime_effect.glsl>

uniform vec2 uSize;

// The kernel's own id for the mode (`QA_STROKE_BLEND_*`, read off
// `strokeBlendModeNativeId`): one table for the three processors.
uniform float uMode;

// What lies below the row in its scope, and the row itself painted normal —
// both PREMULTIPLIED, both on the same grid as this draw.
uniform sampler2D uBackdrop;
uniform sampler2D uSource;

out vec4 fragColor;

// B(Cs, Cd) for one channel, of the source byte [s] and the backdrop byte
// [d]. ⚠️A guarded denominator is never the answer chosen: it only keeps
// the branch not taken from dividing by zero.
float channel(float mode, float s, float d) {
  float b = d / 255.0;
  if (mode == 13.0) {
    // linear burn: cs + cd - 1, floored at 0.
    b = max(s + d - 255.0, 0.0) / 255.0;
  } else if (mode == 14.0) {
    // subtract: cd - cs, floored at 0.
    b = max(d - s, 0.0) / 255.0;
  } else if (mode == 15.0) {
    // vivid light: colorBurn(2cs, cd) below the pivot, colorDodge(2cs-1, cd)
    // above — on bytes, (255 - d) / 2s and d / (510 - 2s). The pivot
    // cs <= 0.5 is s <= 127.
    float burnt = d >= 255.0
        ? 1.0
        : (s <= 0.0 ? 0.0 : 1.0 - min(1.0, (255.0 - d) / max(2.0 * s, 1.0)));
    float dodged = d <= 0.0
        ? 0.0
        : (s >= 255.0 ? 1.0 : min(1.0, d / max(510.0 - 2.0 * s, 1.0)));
    b = s <= 127.0 ? burnt : dodged;
  } else if (mode == 16.0) {
    // linear light: cd + 2cs - 1, held to 0..1.
    b = clamp(d + 2.0 * s - 255.0, 0.0, 255.0) / 255.0;
  } else if (mode == 17.0) {
    // pin light: min(cd, 2cs) below the pivot, max(cd, 2cs-1) above.
    b = s <= 127.0
        ? min(d, 2.0 * s) / 255.0
        : max(d, 2.0 * s - 255.0) / 255.0;
  } else if (mode == 18.0) {
    // hard mix: white where the two reach a whole, black where they fall
    // short — on bytes, s + d >= 255.
    b = s + d >= 255.0 ? 1.0 : 0.0;
  } else if (mode == 19.0) {
    // divide: the backdrop over the source. Nothing divided is nothing;
    // anything divided by nothing is as bright as a channel goes.
    b = d <= 0.0 ? 0.0 : (s <= 0.0 ? 1.0 : min(d / max(s, 1.0), 1.0));
  }
  return b;
}

void main() {
  vec2 uv = FlutterFragCoord().xy / uSize;
  vec4 backdrop = texture(uBackdrop, uv);
  vec4 source = texture(uSource, uv);

  float sa = floor(source.a * 255.0 + 0.5);
  float da = floor(backdrop.a * 255.0 + 0.5);
  vec3 s = floor(
    (source.a > 0.0 ? source.rgb / source.a : vec3(0.0)) * 255.0 + 0.5
  );
  vec3 d = floor(
    (backdrop.a > 0.0 ? backdrop.rgb / backdrop.a : vec3(0.0)) * 255.0 + 0.5
  );
  vec3 cs = s / 255.0;
  vec3 cd = d / 255.0;

  vec3 b;
  if (uMode == 20.0 || uMode == 21.0) {
    // darker / lighter colour: the colour whose channel total is lower /
    // higher, whole. A tie keeps what is there.
    float sourceTotal = s.r + s.g + s.b;
    float backdropTotal = d.r + d.g + d.b;
    bool takesSource = uMode == 20.0
        ? sourceTotal < backdropTotal
        : sourceTotal > backdropTotal;
    b = takesSource ? cs : cd;
  } else {
    b = vec3(
      channel(uMode, s.r, d.r),
      channel(uMode, s.g, d.g),
      channel(uMode, s.b, d.b)
    );
  }

  // The W3C composite on straight alpha, as the CPU writes it:
  //   ao = as + ad(1 - as)
  //   co = [ as(1-ad)cs + ad(1-as)cd + as·ad·B ] / ao
  float as1 = sa / 255.0;
  float ad1 = da / 255.0;
  float ao = as1 + ad1 * (1.0 - as1);
  vec3 co = (as1 * (1.0 - ad1) * cs + ad1 * (1.0 - as1) * cd
      + as1 * ad1 * b) / max(ao, 1.0e-9);

  // 📐ROUNDED HERE, NOT BY THE BACKEND: the CPU's `round(x * 255)`, handed
  // over as an exact n/255.
  vec3 blendedBytes = clamp(floor(co * 255.0 + 0.5), 0.0, 255.0);
  float alpha = clamp(floor(ao * 255.0 + 0.5), 0.0, 255.0) / 255.0;
  vec4 blended = vec4(blendedBytes / 255.0 * alpha, alpha);

  // The CPU's two verbatim copies: no row here leaves the backdrop exactly
  // as it was, and no backdrop leaves the row exactly as it is.
  fragColor = sa <= 0.0 ? backdrop : (da <= 0.0 ? source : blended);
}
