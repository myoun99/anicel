#version 460 core

// 🚨★★★A LAYER'S ADVANCED BLEND, ON THE PROCESSOR THAT HAS THE PIXELS
// (brush-fidelity-Q4, 유저 2026-10-17 「레이어까지 같이」).
//
// One blend, two processors. The BRUSH lays these modes on the CPU, where a
// cel's bytes are (`blendStrokeRegionPixels` in
// lib/src/services/brush_stroke_blend.dart, mirrored in C by
// `qa_stroke_blend_channel` / `qa_stroke_blend_triple`); a LAYER in one is
// composed here, over a picture of its backdrop, because a composite's
// pixels only exist on the GPU. Every formula and the composite below are
// that file's, and `test/ui/canvas/one_blend_two_processors_test.dart`
// sweeps the pair.
//
// 🗣️EVERY ADVANCED BLEND, the GPU's own fifteen too (a-blurred-folder-cut-
// by-the-view-moves-on-vulkan Q3 · Q4, 유저 2026-10-16 · 10-22: 「제일
// 미래지향적인 근본적인 해결」, 「골은 b(레이어 합성 전체를 한 패스 셰이더로)」).
// ↩️Multiply, screen, overlay … went to the engine's blend, and every
// defect it had came with them, each answered by a detour of its own: past
// the drawn rect (F-243), doubled under a saveLayer (F-172), leaking out of
// a patch (F-287), a diagonal on Android Vulkan (flutter#179547), 1/255
// rounding on Windows GLES. Here a mode is one formula on every device —
// the brush's.
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

// Where [uSource] lies on this draw, in the draw's own 0..1: its corner and
// its span. The whole draw — (0, 0, 1, 1) — for a source rastered on the
// draw's grid; a part of it for a row's own image handed over as it is,
// texel for texel on that grid, which shows nothing past its edge.
uniform vec4 uSourceRect;

// What lies below the row in its scope, and the row itself painted normal —
// both PREMULTIPLIED, the backdrop on the same grid as this draw.
uniform sampler2D uBackdrop;
uniform sampler2D uSource;

out vec4 fragColor;

// Hard light of the source byte [s] over the backdrop byte [d]: multiply(2cs,
// cd) below the pivot, screen(2cs - 1, cd) above it — on bytes, with
// x = 2s - 255, (255(x + d) - x·d) / 65025.
float hardLight(float s, float d) {
  float x = 2.0 * s - 255.0;
  return s <= 127.0
      ? 2.0 * s * d / 65025.0
      : (255.0 * (x + d) - x * d) / 65025.0;
}

// W3C's Lum, ClipColor, SetLum, Sat and SetSat, the way the CPU writes them
// (`_ChannelMix` in brush_stroke_blend.dart): SetSat as Skia's, every
// channel (c - min)·s / (max - min), ties included.
float lum(vec3 c) {
  return 0.3 * c.r + 0.59 * c.g + 0.11 * c.b;
}

vec3 clipColour(vec3 c) {
  float l = lum(c);
  float low = min(min(c.r, c.g), c.b);
  float high = max(max(c.r, c.g), c.b);
  // ⚠️The two `!= 0` guards are the CPU's: a grey whose luminosity landed
  // a rounding under 0 (or over 1) would otherwise divide 0 by 0.
  vec3 out1 = (low < 0.0 && l - low != 0.0)
      ? l + (c - l) * l / (l - low)
      : c;
  return (high > 1.0 && high - l != 0.0)
      ? l + (out1 - l) * (1.0 - l) / (high - l)
      : out1;
}

vec3 setLum(vec3 c, float l) {
  return clipColour(c + (l - lum(c)));
}

float sat(vec3 c) {
  return max(max(c.r, c.g), c.b) - min(min(c.r, c.g), c.b);
}

vec3 setSat(vec3 c, float s) {
  float low = min(min(c.r, c.g), c.b);
  float range = max(max(c.r, c.g), c.b) - low;
  return range > 0.0 ? (c - low) * s / range : vec3(0.0);
}

// B(Cs, Cd) for one channel, of the source byte [s] and the backdrop byte
// [d]. ⚠️A guarded denominator is never the answer chosen: it only keeps
// the branch not taken from dividing by zero.
float channel(float mode, float s, float d) {
  float b = d / 255.0;
  // 📐A product of two channels is a whole number over 65025 (= 255²): the
  // numerator is carried exact and divided once.
  if (mode == 2.0) {
    // darken
    b = min(s, d) / 255.0;
  }
  if (mode == 3.0) {
    // multiply: cs·cd.
    b = s * d / 65025.0;
  }
  if (mode == 4.0) {
    // color burn: 1 - (1 - cd) / cs — on bytes, (255 - d) / s.
    b = d >= 255.0
        ? 1.0
        : (s <= 0.0 ? 0.0 : 1.0 - min(1.0, (255.0 - d) / max(s, 1.0)));
  }
  if (mode == 5.0) {
    // lighten
    b = max(s, d) / 255.0;
  }
  if (mode == 6.0) {
    // screen: cs + cd - cs·cd.
    b = (255.0 * (s + d) - s * d) / 65025.0;
  }
  if (mode == 7.0) {
    // color dodge: cd / (1 - cs) — on bytes, d / (255 - s).
    b = d <= 0.0
        ? 0.0
        : (s >= 255.0 ? 1.0 : min(1.0, d / max(255.0 - s, 1.0)));
  }
  if (mode == 8.0) {
    // overlay: hard light with the two the other way round.
    b = hardLight(d, s);
  }
  if (mode == 9.0) {
    // soft light, W3C's: below the pivot cd - (1 - 2cs)·cd·(1 - cd), above
    // it cd + (2cs - 1)·(D(cd) - cd). cs <= 0.5 is s <= 127, cd <= 0.25 is
    // d <= 63.
    float cs = s / 255.0;
    float cd = d / 255.0;
    float lifted = d <= 63.0 ? ((16.0 * cd - 12.0) * cd + 4.0) * cd : sqrt(cd);
    b = s <= 127.0
        ? cd - (1.0 - 2.0 * cs) * cd * (1.0 - cd)
        : cd + (2.0 * cs - 1.0) * (lifted - cd);
  }
  if (mode == 10.0) {
    // hard light
    b = hardLight(s, d);
  }
  if (mode == 11.0) {
    // difference
    b = abs(s - d) / 255.0;
  }
  if (mode == 12.0) {
    // exclusion: cs + cd - 2·cs·cd.
    b = (255.0 * (s + d) - 2.0 * s * d) / 65025.0;
  }
  if (mode == 13.0) {
    // linear burn: cs + cd - 1, floored at 0.
    b = max(s + d - 255.0, 0.0) / 255.0;
  }
  if (mode == 14.0) {
    // subtract: cd - cs, floored at 0.
    b = max(d - s, 0.0) / 255.0;
  }
  if (mode == 15.0) {
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
  }
  if (mode == 16.0) {
    // linear light: cd + 2cs - 1, held to 0..1.
    b = clamp(d + 2.0 * s - 255.0, 0.0, 255.0) / 255.0;
  }
  if (mode == 17.0) {
    // pin light: min(cd, 2cs) below the pivot, max(cd, 2cs-1) above.
    b = s <= 127.0
        ? min(d, 2.0 * s) / 255.0
        : max(d, 2.0 * s - 255.0) / 255.0;
  }
  if (mode == 18.0) {
    // hard mix: white where the two reach a whole, black where they fall
    // short — on bytes, s + d >= 255.
    b = s + d >= 255.0 ? 1.0 : 0.0;
  }
  if (mode == 19.0) {
    // divide: the backdrop over the source. Nothing divided is nothing;
    // anything divided by nothing is as bright as a channel goes.
    b = d <= 0.0 ? 0.0 : (s <= 0.0 ? 1.0 : min(d / max(s, 1.0), 1.0));
  }
  return b;
}

void main() {
  vec2 uv = FlutterFragCoord().xy / uSize;
  vec4 backdrop = texture(uBackdrop, uv);
  vec2 sourceUv = (uv - uSourceRect.xy) / uSourceRect.zw;
  bool onSource = all(greaterThanEqual(sourceUv, vec2(0.0))) &&
      all(lessThan(sourceUv, vec2(1.0)));
  vec4 source = onSource ? texture(uSource, sourceUv) : vec4(0.0);

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

  // ⚠️ONE `if` PER MODE, NONE NESTED IN ANOTHER'S `else` — here and in
  // [channel]. An else-if chain of this length compiles to SkSL nested past
  // its parser's depth ("exceeded max parse depth"), and the asset then
  // carries no stage for the backends that read SkSL. Exactly one mode
  // matches, so the separate ifs answer what the chain did.
  vec3 b = vec3(
    channel(uMode, s.r, d.r),
    channel(uMode, s.g, d.g),
    channel(uMode, s.b, d.b)
  );
  if (uMode == 20.0 || uMode == 21.0) {
    // darker / lighter colour: the colour whose channel total is lower /
    // higher, whole. A tie keeps what is there.
    float sourceTotal = s.r + s.g + s.b;
    float backdropTotal = d.r + d.g + d.b;
    bool takesSource = uMode == 20.0
        ? sourceTotal < backdropTotal
        : sourceTotal > backdropTotal;
    b = takesSource ? cs : cd;
  }
  if (uMode == 22.0) {
    // hue: the source's hue at the backdrop's saturation and luminosity.
    b = setLum(setSat(cs, sat(cd)), lum(cd));
  }
  if (uMode == 23.0) {
    // saturation: the backdrop with the source's saturation.
    b = setLum(setSat(cd, sat(cs)), lum(cd));
  }
  if (uMode == 24.0) {
    // colour: the source's hue and saturation at the backdrop's luminosity.
    b = setLum(cs, lum(cd));
  }
  if (uMode == 25.0) {
    // luminosity: the backdrop at the source's luminosity.
    b = setLum(cd, lum(cs));
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
