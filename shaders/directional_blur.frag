#version 460 core

// 🚨ONE PASS OF A BLUR ALONG A WAY: the average of [uTaps] samples along
// the way through the pixel, centred on it — a box along one line, one
// circle or one ray (`LineBoxPass`). Each tap steps by the same map: a
// shift of [uStep] pixels (a directional blur), and a turn and a scale
// about [uCenter] (a radial blur's spin and zoom) — the map [uEach], which
// the tap before the first has already taken [uFirst] of.
//
// 📐PASSES MAKE THE WHOLE BOX (`lineBoxPlan`): N taps a pass, each pass N
// times the step of the one before, land N^p taps across the way, each
// once — the box of N^p samples for p·N a pixel.
//
// 🔬IN A STEP'S RASTER, AT THE IDENTITY (`applyEffectSteps`), never an
// `ImageFilter.shader` in the frame: on Impeller a shader filter is
// evaluated in device space, past the canvas's turn and scale, and paints
// no further than the picture it is handed (measured 10-28 — a blur 16
// long over a dot spread it ±1 px). A step's raster is the buffer the plan
// already grew — and there, on Impeller, the passes ARE shader filters, the
// layers of one picture (`_passesInOnePicture`, 10-29: a raster a pass cost
// ~22ms each on the Surface).
//
// ⛔[uSize] FIRST AMONG THE FLOATS AND [uSource] FIRST AMONG THE SAMPLERS:
// as a filter the ENGINE binds the layer to the first sampler and its size
// to the first vec2.

#include <flutter/runtime_effect.glsl>

uniform vec2 uSize;

// One tap's shift, in this raster's pixels, along the blur's direction.
uniform vec2 uStep;

// How many taps, 1 … 32.
uniform float uTaps;

// What the turn and the scale are about, in this raster's pixels.
uniform vec2 uCenter;

// The turn and scale of the first tap, and of one tap to the next, as the
// columns of a 2×2 map — the identity on a line.
uniform vec4 uFirst;
uniform vec4 uEach;

uniform sampler2D uSource;

out vec4 fragColor;

void main() {
  vec2 at = FlutterFragCoord().xy;
  vec2 away = at - uCenter;
  float first = -(uTaps - 1.0) * 0.5;
  // The map's columns, written out: a matrix type is one more thing each
  // backend's compiler is handed.
  vec2 across = uFirst.xy;
  vec2 down = uFirst.zw;
  vec4 sum = vec4(0.0);
  // A loop needs a constant bound here; the taps past [uTaps] weigh 0.
  for (int i = 0; i < 32; i++) {
    float tap = float(i);
    float counted = step(tap + 0.5, uTaps);
    vec2 p = uCenter + across * away.x + down * away.y +
        uStep * (first + tap);
    // DECAL, as the Gaussian blur's: past the picture there is nothing,
    // not its edge pixels smeared outward.
    float inside = step(0.0, p.x) * step(0.0, p.y) *
        step(p.x, uSize.x) * step(p.y, uSize.y);
    sum += texture(uSource, p / uSize) * (counted * inside);
    across = uEach.xy * across.x + uEach.zw * across.y;
    down = uEach.xy * down.x + uEach.zw * down.y;
  }
  // ⛔NO EARLY RETURN — the shape ANGLE hands Windows' D3D compiler in a
  // form it can crash on (flutter#190809; `colour_key.frag`).
  fragColor = sum / uTaps;
}
