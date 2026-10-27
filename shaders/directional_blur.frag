#version 460 core

// 🚨ONE PASS OF A DIRECTIONAL BLUR: the average of [uTaps] samples a step
// of [uStep] pixels apart, centred on the pixel — a box along one line.
//
// 📐PASSES MAKE THE WHOLE BOX (`directionalBlurPasses`): N taps a pass,
// each pass N times the step of the one before, land N^p taps across the
// length, each once — the box of N^p samples for p·N a pixel.
//
// 🔬A RASTER OF ITS OWN, AT THE IDENTITY (`applyEffectSteps`), never an
// `ImageFilter.shader`: on Impeller a shader filter is evaluated in device
// space, past the canvas's turn and scale, and paints no further than the
// picture it is handed (measured 10-28 — a blur 16 long over a dot spread
// it ±1 px). A step's raster is the buffer the plan already grew.

#include <flutter/runtime_effect.glsl>

uniform vec2 uSize;

// One tap's step, in this raster's pixels, along the blur's direction.
uniform vec2 uStep;

// How many taps, 1 … 32.
uniform float uTaps;

uniform sampler2D uSource;

out vec4 fragColor;

void main() {
  vec2 at = FlutterFragCoord().xy;
  float first = -(uTaps - 1.0) * 0.5;
  vec4 sum = vec4(0.0);
  // A loop needs a constant bound here; the taps past [uTaps] weigh 0.
  for (int i = 0; i < 32; i++) {
    float tap = float(i);
    float counted = step(tap + 0.5, uTaps);
    vec2 p = at + uStep * (first + tap);
    // DECAL, as the Gaussian blur's: past the picture there is nothing,
    // not its edge pixels smeared outward.
    float inside = step(0.0, p.x) * step(0.0, p.y) *
        step(p.x, uSize.x) * step(p.y, uSize.y);
    sum += texture(uSource, p / uSize) * (counted * inside);
  }
  // ⛔NO EARLY RETURN — the shape ANGLE hands Windows' D3D compiler in a
  // form it can crash on (flutter#190809; `colour_key.frag`).
  fragColor = sum / uTaps;
}
