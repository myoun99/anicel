// The fx plugin the host's test opens as a native library — and the C its
// WebAssembly twin in qa_fx_plugin_test.c is written from, line for line.
//
// It inverts where its Amount is at least 50 and its Map's alpha (read at
// the same canvas place, nothing outside the map) is over 127; with no Map
// it inverts everywhere Amount allows. Amount below 0 answers a failure.
// Its reach is Amount / 10 plus the frame's index, so a reach that comes
// back right has read the values and the frame both.
//
// Built twice more for what the host must refuse: QA_FX_SAMPLE_SPEC names
// another spec version, QA_FX_SAMPLE_NO_RENDER keeps its render unexported.
#include <stdint.h>
#include <string.h>

#include "anicel_fx_plugin.h"

#ifndef QA_FX_SAMPLE_SPEC
#define QA_FX_SAMPLE_SPEC ANICEL_FX_SPEC_VERSION
#endif
#if defined(QA_FX_SAMPLE_NO_RENDER)
#define QA_FX_SAMPLE_RENDER_EXPORT static
#else
#define QA_FX_SAMPLE_RENDER_EXPORT ANICEL_FX_EXPORT(anicel_fx_render)
#endif

static const char description[] =
    "{\"spec\":1,\"id\":\"app.anicel.test.invert\",\"name\":\"Invert\","
    "\"vendor\":\"Anicel test\",\"version\":\"1.0.0\",\"can\":[\"cpu\"],"
    "\"params\":[{\"id\":\"amount\",\"kind\":\"number\",\"label\":\"Amount\","
    "\"default\":100,\"min\":0,\"max\":100},"
    "{\"id\":\"map\",\"kind\":\"layer\",\"label\":\"Map\"}]}";

ANICEL_FX_EXPORT(anicel_fx_spec) uint32_t anicel_fx_spec(void) {
  return QA_FX_SAMPLE_SPEC;
}

ANICEL_FX_EXPORT(anicel_fx_describe)
uint32_t anicel_fx_describe(char *out, uint32_t capacity) {
  uint32_t length = (uint32_t)(sizeof(description) - 1);
  memcpy(out, description, length < capacity ? length : capacity);
  return length;
}

ANICEL_FX_EXPORT(anicel_fx_reach)
uint32_t anicel_fx_reach(const anicel_fx_frame *frame) {
  const anicel_fx_value *values = anicel_fx_values(frame);
  return (uint32_t)(values[0].v[0] / 10.0) + (uint32_t)frame->frame_index;
}

static int map_allows(const anicel_fx_frame *frame, const anicel_fx_image *map,
                      int32_t x, int32_t y) {
  if (map == NULL) {
    return 1;
  }
  int32_t mx = x - map->left;
  int32_t my = y - map->top;
  if (mx < 0 || my < 0 || mx >= (int32_t)map->width ||
      my >= (int32_t)map->height) {
    return 0;
  }
  const uint8_t *pixel = anicel_fx_pixels(frame, map) +
                         (size_t)my * map->stride + (size_t)mx * 4u;
  return pixel[3] > 127;
}

QA_FX_SAMPLE_RENDER_EXPORT
int32_t anicel_fx_render(anicel_fx_frame *frame) {
  const anicel_fx_value *values = anicel_fx_values(frame);
  double amount = values[0].v[0];
  if (amount < 0) {
    return 1;
  }
  int32_t map_at = (int32_t)values[1].v[0];
  const anicel_fx_image *map =
      map_at >= 0 && (uint32_t)map_at < frame->layer_count
          ? &anicel_fx_layers(frame)[map_at]
          : NULL;
  const anicel_fx_image *in = &frame->input;
  const anicel_fx_image *out = &frame->output;
  for (uint32_t y = 0; y < in->height; y++) {
    const uint8_t *from = anicel_fx_pixels(frame, in) + (size_t)y * in->stride;
    uint8_t *to = anicel_fx_pixels(frame, out) + (size_t)y * out->stride;
    for (uint32_t x = 0; x < in->width; x++) {
      const uint8_t *p = from + (size_t)x * 4u;
      uint8_t *q = to + (size_t)x * 4u;
      int inverts = amount >= 50 &&
                    map_allows(frame, map, in->left + (int32_t)x,
                               in->top + (int32_t)y);
      for (int c = 0; c < 3; c++) {
        q[c] = inverts ? (uint8_t)(p[3] - p[c]) : p[c];
      }
      q[3] = p[3];
    }
  }
  return 0;
}
