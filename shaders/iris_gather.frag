#version 460 core

// 🚨A CAMERA LENS BLUR'S IRIS, GATHERED OUT OF ITS ROW SUMS
// (`IrisGatherPass`): every pixel the weighted mean of the pixels about it
// whose centres the iris covers — of each row it covers, the sum between
// two of that row's sums (`row_sum.frag`), so a row costs two reads
// whatever the iris's width, and every shape is exact.
//
// The iris's rows are a table ([uTable], `IrisBlurShader`): the row
// `uReach` above the pixel first, two texels each — its outline's left and
// right column about the pixel, then its core's — in red and green, each
// a whole number over [kTableScale] past [kTableOffset].
//
// 📐THE FRINGE pushes [uFringe] of the core's light out to the edge: the
// outline's sum less that much of the core's, over [uWeight] — what every
// pixel's weights add up to.
//
// 📐THE EDGE. Past the raster there is nothing ([uRepeats] off), or —
// AE's Repeat Edge Pixels, on the paper's edge — past the paper's columns
// [uPaper].x … [uPaper].z and rows [uPaper].y … [uPaper].w lie its edge
// pixels, read from the step's input ([uInput]), and what is drawn is cut
// to it.
//
// 📐THE LIGHT ([uLights], `lens_light.glsl`): where the sums read the
// picture's light another way than as stored, so are the edge pixels read,
// and what is drawn is put back as stored.
//
// 🔬A RASTER OF ITS OWN, AT THE IDENTITY (`applyEffectSteps`), as every
// step's pass is (`directional_blur.frag`).

#include <flutter/runtime_effect.glsl>

precision highp float;

#include "lens_light.glsl"

const float kTableOffset = 8192.0;
const float kTableScale = 16384.0;

uniform vec2 uSize;

// The rows run from uReach above the pixel to uReach below it.
uniform float uReach;

// How big the table is, and how many rows a line of it holds.
uniform vec2 uTableSize;
uniform float uTableRows;

uniform float uFringe;
uniform float uWeight;
uniform float uRepeats;
uniform vec4 uPaper;
uniform float uLights;
uniform vec4 uLight;

uniform sampler2D uSums;
uniform sampler2D uInput;
uniform sampler2D uTable;

out vec4 fragColor;

vec4 sumAt(float x, float y) {
  return texture(uSums, (vec2(x, y) + 0.5) / uSize);
}

vec4 inputAt(float x, float y) {
  vec4 texel = texture(uInput, (vec2(x, y) + 0.5) / uSize);
  return uLights > 0.5 ? lit(texel, uLight) : texel;
}

// Row [row]'s outline (k 0) or core (k 1): its left and right column.
vec2 spanOf(float row, float k) {
  float line = floor(row / uTableRows);
  float column = (row - line * uTableRows) * 2.0 + k;
  vec2 kept = texture(uTable, (vec2(column, line) + 0.5) / uTableSize).rg;
  return floor(kept * kTableScale + 0.5) - kTableOffset;
}

// Row [y]'s pixels from column [a] to [b] that lie in [from] … [to], summed.
vec4 between(float a, float b, float from, float to, float y) {
  float left = max(a, from);
  float right = min(b, to);
  vec4 sum = vec4(0.0);
  if (left <= right) {
    sum = sumAt(right, y);
    if (left > 0.0) {
      sum -= sumAt(left - 1.0, y);
    }
  }
  return sum;
}

// Row [y]'s pixels from column [a] to [b] summed, as the edge has it.
vec4 spanSum(vec2 span, float y) {
  if (uRepeats < 0.5) {
    return between(span.x, span.y, 0.0, uSize.x - 1.0, y);
  }
  float before = max(0.0, min(span.y, uPaper.x - 1.0) - span.x + 1.0);
  float after = max(0.0, span.y - max(span.x, uPaper.z + 1.0) + 1.0);
  return between(span.x, span.y, uPaper.x, uPaper.z, y) +
      inputAt(uPaper.x, y) * before + inputAt(uPaper.z, y) * after;
}

void main() {
  vec2 at = floor(FlutterFragCoord().xy);
  vec4 sum = vec4(0.0);
  float rows = 2.0 * uReach + 1.0;
  // A loop needs a constant bound here: `irisRowsAtMost`.
  for (int i = 0; i < 16385; i++) {
    float row = float(i);
    // ⛔NO EARLY RETURN (`colour_key.frag`, flutter#190809): a break ends
    // the loop, the shape the probes of 10-28 ran on the Surface Pro 11's
    // ANGLE.
    if (row >= rows) {
      break;
    }
    float y = at.y + row - uReach;
    if (uRepeats > 0.5) {
      y = clamp(y, uPaper.y, uPaper.w);
    } else if (y < 0.0 || y >= uSize.y) {
      continue;
    }
    sum += spanSum(at.x + spanOf(row, 0.0), y);
    if (uFringe > 0.0) {
      sum -= spanSum(at.x + spanOf(row, 1.0), y) * uFringe;
    }
  }
  float onPaper = uRepeats < 0.5
      ? 1.0
      : step(uPaper.x, at.x) * step(at.x, uPaper.z) * step(uPaper.y, at.y) *
          step(at.y, uPaper.w);
  vec4 mean = sum / uWeight;
  fragColor = (uLights > 0.5 ? stored(mean, uLight) : mean) * onPaper;
}
