#version 460 core

// 🚨A CAMERA LENS BLUR'S IRIS, GATHERED OUT OF ITS ROW SUMS
// (`IrisGatherPass`): every pixel the mean of the pixels about it whose
// centres the iris covers — of each row it covers, the sum between two of
// that row's sums (`row_sum.frag`), so a row costs two reads whatever the
// iris's width, and every shape is exact.
//
// The iris's rows are a table ([uTable], `iris_table.frag`): its levels,
// each [uLinesALevel] lines of [uRowsALine] rows from [uReachMost] above
// the pixel down, two texels a row — its outline's left and right column
// about the pixel, then its core's — and from line [uHeads] on its levels'
// heads, a texel each: the level's reach, and the centres its outline and
// its core cover, what the pixels' weights add up to. A pixel reads one
// level: the first, or — where a blur map is read ([uMapped]) — the one
// its map's value names, through [uChannel].
//
// 📐THE FRINGE pushes [uFringe] of the core's light out to the edge: the
// outline's sum less that much of the core's, over what the pixels' weights
// add up to — where the edge holds a pixel the core does not, or there is
// nowhere to push it to. An iris that covers no centre at all, a blur
// map's in focus, is the pixel itself.
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

uniform vec2 uSize;

// The rows of every level run from uReachMost above the pixel down.
uniform float uReachMost;

// How big the table is, and how it is laid.
uniform vec2 uTableSize;
uniform float uRowsALine;
uniform float uLinesALevel;

uniform float uFringe;
uniform float uRepeats;
uniform vec4 uPaper;
uniform float uLights;
uniform vec4 uLight;

// Whether a blur map names each pixel's level, and what of its pixel it
// reads: luma, or one channel.
uniform float uMapped;
uniform vec4 uChannel;

// The table's first line of heads.
uniform float uHeads;

uniform sampler2D uSums;
uniform sampler2D uInput;
uniform sampler2D uTable;
uniform sampler2D uMap;

out vec4 fragColor;

vec4 sumAt(float x, float y) {
  return texture(uSums, (vec2(x, y) + 0.5) / uSize);
}

vec4 inputAt(float x, float y) {
  vec4 texel = texture(uInput, (vec2(x, y) + 0.5) / uSize);
  return uLights > 0.5 ? lit(texel, uLight) : texel;
}

// Level [level]'s row [row] from the top: its outline's (k 0) or core's
// (k 1) left and right column.
vec2 rowOf(float level, float row, float k) {
  float line = floor(row / uRowsALine);
  float column = (row - line * uRowsALine) * 2.0 + k;
  vec2 texel = vec2(column, level * uLinesALevel + line) + 0.5;
  return texture(uTable, texel / uTableSize).rg;
}

// Level [level]'s head: its reach, and the centres its outline and its
// core cover.
vec3 headOf(float level) {
  float line = floor(level / uTableSize.x);
  vec2 texel = vec2(level - line * uTableSize.x, uHeads + line) + 0.5;
  return texture(uTable, texel / uTableSize).rgb;
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
  float level = 0.0;
  if (uMapped > 0.5) {
    vec4 map = texture(uMap, (at + 0.5) / uSize);
    level = clamp(floor(dot(map, uChannel) * 255.0 + 0.5), 0.0, 255.0);
  }
  vec3 head = headOf(level);
  float reach = head.x;
  float outlineWeight = head.y;
  float coreWeight = uFringe > 0.0 ? head.z : 0.0;
  vec4 outline = vec4(0.0);
  vec4 core = vec4(0.0);
  // A loop needs a constant bound here: `irisRowsAtMost`.
  for (int i = 0; i < 16385; i++) {
    float dy = float(i) - reach;
    // ⛔NO EARLY RETURN (`colour_key.frag`, flutter#190809): a break ends
    // the loop, the shape the probes of 10-28 ran on the Surface Pro 11's
    // ANGLE.
    if (dy > reach) {
      break;
    }
    // A row off the raster sums nothing, and its table is not read.
    float y = at.y + dy;
    if (uRepeats > 0.5) {
      y = clamp(y, uPaper.y, uPaper.w);
    } else if (y < 0.0 || y >= uSize.y) {
      continue;
    }
    float row = dy + uReachMost;
    outline += spanSum(at.x + rowOf(level, row, 0.0), y);
    if (uFringe > 0.0) {
      core += spanSum(at.x + rowOf(level, row, 1.0), y);
    }
  }
  float pushed = outlineWeight > coreWeight ? uFringe : 0.0;
  float weight = outlineWeight - coreWeight * pushed;
  vec4 mean = weight > 0.0
      ? (outline - core * pushed) / weight
      : inputAt(at.x, at.y);
  float onPaper = uRepeats < 0.5
      ? 1.0
      : step(uPaper.x, at.x) * step(at.x, uPaper.z) * step(uPaper.y, at.y) *
          step(at.y, uPaper.w);
  fragColor = (uLights > 0.5 ? stored(mean, uLight) : mean) * onPaper;
}
