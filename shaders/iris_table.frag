#version 460 core

// 🚨A CAMERA LENS BLUR'S IRIS, ROW BY ROW (`IrisGatherPass`): for each of
// its levels and each row about a pixel, the columns whose pixel centres
// the iris covers — the table `iris_gather.frag` reads its rows' sums by.
//
// A level is the iris at one radius: one alone without a blur map, else
// one for each of a map's 256 values. Each takes [uLinesALevel] lines of
// [uRowsALine] rows from [uReachMost] above the pixel down, two texels a
// row — the outline's span, then the core's — each its left and right
// column in red and green, and the level's reach in blue. A row past it
// is empty, its left past its right.
//
// 📐THE IRIS (ours, 🗣️I-132-Q4 b: 「식은 지금대로」 — Adobe's help names
// the properties and gives no shapes): a regular polygon of its sides
// whose corners lie its radius out, an edge lying flat along its bottom —
// a triangle points up, a square stands square. Its roundness rounds it
// toward the circle of that radius: the polygon drawn `1 - roundness` as
// big, and every point within `roundness · radius` of it. Its aspect
// squeezes it up and down (above 1) or across (below), so it fits the
// circle still, and its rotation turns it clockwise.
//
// 🔬EXACT, NOT TRACED (🗣️I-132-Q15 a: 「모든 모양을 정확히」): the rounded
// polygon is the polygon, the strip outward of each edge and the disc
// about each corner, and a row through it is the span of the rows through
// those — each worked out where it crosses the row. A centre within
// [kOnTheEdge] of the edge is in it: the rounding puts it a hair either
// way. ↩️Laid on the CPU until 10-28, a table drawn rect by rect: 256
// levels of a blur map at a radius of 500 took it 191–293ms a frame on
// the Surface Pro 11.
//
// 📐THE CORE is the iris drawn [kCoreScale] as big — the inside a
// diffraction fringe pushes the light out of, to the edge. Ours, as the
// fringe's form is (🗣️I-132-Q4 b): no help page says how wide AE's ring
// is.

#include <flutter/runtime_effect.glsl>

precision highp float;

const float kPi = 3.14159265358979;
const float kCoreScale = 0.8;
const float kOnTheEdge = 1e-3;
const float kFar = 1e30;

// The table's size.
uniform vec2 uSize;

uniform float uRowsALine;
uniform float uLinesALevel;
uniform float uReachMost;

// The iris's radius in raster pixels, and its levels: 1, or 256 read off a
// map — each the radius times how far its value (or its inverse, where the
// map is inverted) lies from the focal distance, over 255.
uniform float uRadius;
uniform float uLevels;
uniform float uFocal;
uniform float uInverts;

// Its sides, roundness (0…1), aspect and rotation (radians, clockwise).
uniform vec4 uIris;

out vec4 fragColor;

// [span] of t, where `at + t · along` keeps `normal · p <= most` too.
vec2 within(vec2 span, vec2 at, vec2 along, vec2 normal, float most) {
  float room = most - dot(normal, at);
  float rate = dot(normal, along);
  vec2 kept = span;
  if (abs(rate) < 1e-6) {
    // Along the edge: on it, as the edge's centres are.
    if (room < -kOnTheEdge) {
      kept = vec2(kFar, -kFar);
    }
  } else if (rate > 0.0) {
    kept.y = min(kept.y, room / rate);
  } else {
    kept.x = max(kept.x, room / rate);
  }
  return kept;
}

// The span of t where `at + t · along` lies within [radius] of [centre].
vec2 withinDisc(vec2 at, vec2 along, vec2 centre, float radius) {
  vec2 away = at - centre;
  float a = dot(along, along);
  float b = dot(along, away);
  float reach = b * b - a * (dot(away, away) - radius * radius);
  vec2 span = vec2(kFar, -kFar);
  if (reach >= 0.0) {
    float root = sqrt(reach);
    span = vec2((-b - root) / a, (-b + root) / a);
  }
  return span;
}

vec2 joined(vec2 whole, vec2 span) {
  return span.x <= span.y
      ? vec2(min(whole.x, span.x), max(whole.y, span.y))
      : whole;
}

// The columns whose centres row [dy] of the iris [radius] out covers.
vec2 spanOf(float dy, float radius) {
  float sides = uIris.x;
  float roundness = uIris.y;
  float corner = (1.0 - roundness) * radius;
  float halfTurn = kPi / sides;
  float apothem = corner * cos(halfTurn);
  float side = corner * sin(halfTurn);
  float rounding = roundness * radius;
  float across = min(uIris.z, 1.0);
  float upDown = min(1.0 / uIris.z, 1.0);
  float c = cos(uIris.w);
  float s = sin(uIris.w);
  // The row's line, in the iris's own unturned, unsqueezed space.
  vec2 at = vec2(s * dy / across, c * dy / upDown);
  vec2 along = vec2(c / across, -s / upDown);
  vec2 whole = vec2(kFar, -kFar);
  vec2 polygon = vec2(-kFar, kFar);
  // A loop needs a constant bound here: a decagon's ten sides.
  for (int k = 0; k < 10; k++) {
    if (float(k) >= sides) {
      break;
    }
    float turn = kPi / 2.0 + 2.0 * halfTurn * float(k);
    vec2 normal = vec2(cos(turn), sin(turn));
    polygon = within(polygon, at, along, normal, apothem);
    if (rounding > 0.0) {
      vec2 tangent = vec2(-normal.y, normal.x);
      vec2 strip = vec2(-kFar, kFar);
      strip = within(strip, at, along, normal, apothem + rounding);
      strip = within(strip, at, along, -normal, -apothem);
      strip = within(strip, at, along, tangent, side);
      strip = within(strip, at, along, -tangent, side);
      whole = joined(whole, strip);
      float cornerTurn = kPi / 2.0 + halfTurn * (2.0 * float(k) + 1.0);
      vec2 cornerAt = corner * vec2(cos(cornerTurn), sin(cornerTurn));
      whole = joined(whole, withinDisc(at, along, cornerAt, rounding));
    }
  }
  if (apothem > 0.0) {
    whole = joined(whole, polygon);
  }
  vec2 columns = vec2(1.0, 0.0);
  if (whole.x <= whole.y) {
    columns = vec2(ceil(whole.x - kOnTheEdge), floor(whole.y + kOnTheEdge));
  }
  return columns;
}

void main() {
  vec2 at = floor(FlutterFragCoord().xy);
  float level = floor(at.y / uLinesALevel);
  float row = (at.y - level * uLinesALevel) * uRowsALine + floor(at.x / 2.0);
  bool core = at.x - floor(at.x / 2.0) * 2.0 > 0.5;
  float value = uInverts > 0.5 ? 255.0 - level : level;
  float radius = uLevels > 1.5
      ? uRadius * abs(value - uFocal) / 255.0
      : uRadius;
  float reach = floor(radius);
  float dy = row - uReachMost;
  vec2 span = vec2(1.0, 0.0);
  if (abs(dy) <= reach) {
    span = spanOf(dy, core ? radius * kCoreScale : radius);
  }
  fragColor = vec4(span, reach, 1.0);
}
