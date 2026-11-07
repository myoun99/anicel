/*
 * Shadow -- the SDK example's C build, the key the Rust example
 * (sdk/fx/example) is held to byte for byte through both hosts
 * (native/fx_plugin's tests), and what the Dart fx pin and the releases'
 * parity runs open beside the C engine. The SDK was C until 2026-11-07
 * (connection-round-checklist, user Q9: no C plugin exists to keep), and
 * this was its example; the connection round deletes it with the C host.
 *
 * SPDX-License-Identifier: MIT
 * Copyright (c) 2026 PARK GUNWOO -- the Anicel fx plugin SDK's LICENSE.
 *
 * Draws the row's picture over a shadow of itself: the picture's alpha,
 * moved by an offset and painted in a color.
 */
#include "anicel_fx_plugin.h"

static const char description[] =
    "{\"spec\":1,\"id\":\"com.example.shadow\",\"name\":\"Shadow\","
    "\"vendor\":\"Anicel SDK example\",\"version\":\"1.0.0\","
    "\"can\":[\"cpu\"],\"params\":["
    "{\"id\":\"x\",\"kind\":\"number\",\"label\":\"Offset X\","
    "\"default\":8,\"min\":-200,\"max\":200},"
    "{\"id\":\"y\",\"kind\":\"number\",\"label\":\"Offset Y\","
    "\"default\":8,\"min\":-200,\"max\":200},"
    "{\"id\":\"color\",\"kind\":\"color\",\"label\":\"Color\","
    "\"default\":[0,0,0,0.6]}]}";

/* The values, in the order of "params". */
enum { VALUE_X, VALUE_Y, VALUE_COLOR };

/* A WebAssembly module hands the host room for its frames. */
ANICEL_FX_DEFINE_ALLOC()

ANICEL_FX_EXPORT(anicel_fx_spec) uint32_t anicel_fx_spec(void) {
  return ANICEL_FX_SPEC_VERSION;
}

ANICEL_FX_EXPORT(anicel_fx_describe)
uint32_t anicel_fx_describe(char *out, uint32_t capacity) {
  uint32_t length = (uint32_t)(sizeof(description) - 1);
  for (uint32_t i = 0; i < length && i < capacity; i++) {
    out[i] = description[i];
  }
  return length;
}

/* A plugin checks first that it is handed the spec and format it knows. */
static int understands(const anicel_fx_frame *frame) {
  return frame->spec == ANICEL_FX_SPEC_VERSION &&
         frame->format == ANICEL_FX_RGBA8_PREMULTIPLIED;
}

static int32_t rounded(double value) {
  return (int32_t)(value < 0 ? value - 0.5 : value + 0.5);
}

/* The offset in output pixels: the values are canvas pixels, and a draft
 * renders at a scale below 1. */
static void offset(const anicel_fx_frame *frame, int32_t *dx, int32_t *dy) {
  const anicel_fx_value *values = anicel_fx_values(frame);
  *dx = rounded(values[VALUE_X].v[0] * frame->scale);
  *dy = rounded(values[VALUE_Y].v[0] * frame->scale);
}

/* The shadow lands as far outside the picture as it is moved. */
ANICEL_FX_EXPORT(anicel_fx_reach)
uint32_t anicel_fx_reach(const anicel_fx_frame *frame) {
  if (!understands(frame)) {
    return 0;
  }
  int32_t dx, dy;
  offset(frame, &dx, &dy);
  dx = dx < 0 ? -dx : dx;
  dy = dy < 0 ? -dy : dy;
  return (uint32_t)(dx > dy ? dx : dy);
}

static uint8_t byte_of(double unit) {
  if (unit <= 0) return 0;
  if (unit >= 1) return 255;
  return (uint8_t)(unit * 255 + 0.5);
}

/* a * b / 255, rounded -- the product of two 8-bit fractions. */
static uint32_t times(uint32_t a, uint32_t b) {
  uint32_t t = a * b + 128;
  return (t + (t >> 8)) >> 8;
}

ANICEL_FX_EXPORT(anicel_fx_render)
int32_t anicel_fx_render(anicel_fx_frame *frame) {
  if (!understands(frame)) {
    return 1;
  }
  const anicel_fx_image *in = &frame->input;
  const anicel_fx_image *out = &frame->output;
  const double *color = anicel_fx_values(frame)[VALUE_COLOR].v;
  uint32_t shadow_alpha = byte_of(color[3]);
  uint32_t shadow_red = byte_of(color[0]);
  uint32_t shadow_green = byte_of(color[1]);
  uint32_t shadow_blue = byte_of(color[2]);
  int32_t dx, dy;
  offset(frame, &dx, &dy);
  const uint8_t *from = anicel_fx_pixels(frame, in);
  uint8_t *to = anicel_fx_pixels(frame, out);
  for (int32_t y = 0; y < (int32_t)in->height; y++) {
    for (int32_t x = 0; x < (int32_t)in->width; x++) {
      const uint8_t *p = from + (size_t)y * in->stride + (size_t)x * 4;
      uint8_t *q = to + (size_t)y * out->stride + (size_t)x * 4;
      /* The shadow here is the picture's alpha where the offset came from. */
      int32_t sx = x - dx, sy = y - dy;
      uint32_t cast = 0;
      if (sx >= 0 && sy >= 0 && sx < (int32_t)in->width &&
          sy < (int32_t)in->height) {
        cast = from[(size_t)sy * in->stride + (size_t)sx * 4 + 3];
      }
      uint32_t a = times(cast, shadow_alpha);
      /* The picture over its shadow, both premultiplied. */
      uint32_t behind = 255 - p[3];
      q[0] = (uint8_t)(p[0] + times(times(shadow_red, a), behind));
      q[1] = (uint8_t)(p[1] + times(times(shadow_green, a), behind));
      q[2] = (uint8_t)(p[2] + times(times(shadow_blue, a), behind));
      q[3] = (uint8_t)(p[3] + times(a, behind));
    }
  }
  return 0;
}
