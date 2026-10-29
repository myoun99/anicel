/*
 * Anicel fx plugin specification, version 1 — the one header a plugin is
 * built against, as a native library (.dll · .dylib · .so) and as a
 * WebAssembly module (.wasm) from the SAME source.
 *
 * 🗣️I-132-Q5 (유저 2026-10-27): 「a + 데스크톱은 같은 규격의 네이티브(.dll ·
 * .dylib)도」 — one .wasm runs on every platform, and a desktop may also take
 * a native build of the same source. So this is a C FUNCTION SPEC that a
 * .dll can speak as well as a .wasm, not a WebAssembly component interface
 * (I-132-Q31: the component model stays a road to add on the wasm side).
 * 🗣️I-132-Q29 (유저 2026-10-29): 「a + 플러그인이 다른 레이어를 읽기」 — a
 * plugin declares its parameters, takes the row's picture (wider by the reach
 * it declares) and gives back a picture; a 「layer」 parameter hands it
 * another row's picture too. 「나중엔 최대한 극한으로 확장 … 플러그인은
 * 확장성이 젤 중요」: a plugin says what it can do in its description
 * (`"can"`), so a later host can offer more — a GPU route, say, chosen by
 * the plugin as AE's GPU effects are — and an older plugin still runs.
 *
 * ★ONE LAYOUT ON EVERY TARGET. Nothing the host hands a plugin is a pointer:
 * every place is a byte DISTANCE from the frame's own address, so the
 * structs below are the same bytes in a 32-bit WebAssembly module and in a
 * 64-bit native library, and the host writes them once. ↩️Pointers in the
 * structs would have made two layouts (4- and 8-byte pointers) the host
 * fills differently — a plugin built for the one would read the other's
 * fields wrong. The ANICEL_FX_ASSERT lines below hold the layout to the
 * numbers on every compiler a plugin is built with.
 *
 * WHAT A PLUGIN EXPORTS (the names are the spec):
 *
 *   uint32_t anicel_fx_spec(void);
 *       The spec version it was built against: ANICEL_FX_SPEC_VERSION.
 *
 *   uint32_t anicel_fx_describe(char *out, uint32_t capacity);
 *       Writes its description — UTF-8 JSON, below — into out and returns
 *       its length in bytes. A length past capacity asks to be called again
 *       with that much room; nothing past capacity is written.
 *
 *   uint32_t anicel_fx_reach(const anicel_fx_frame *frame);
 *       How many pixels past each edge of its input the effect reads and
 *       draws, for the values in frame (its images are empty here). The
 *       host hands the next render an input that much wider each way.
 *
 *   int32_t anicel_fx_render(anicel_fx_frame *frame);
 *       Writes every pixel of frame->output from frame->input, its values
 *       and its layers. 0 is done; anything else is a failure, and the host
 *       draws the row as if the effect were off.
 *
 *   A WebAssembly module also exports its linear memory as "memory" and
 *       void *anicel_fx_alloc(uint32_t size);
 *   which the host calls for the room it writes a frame into
 *   (ANICEL_FX_DEFINE_ALLOC below is one). A native library does not: the
 *   host's own memory is the frame's.
 *
 * THE DESCRIPTION:
 *
 *   {"spec":1, "id":"com.example.invert", "name":"Invert",
 *    "vendor":"Example", "version":"1.0.0", "can":["cpu"],
 *    "params":[
 *      {"id":"amount", "kind":"number", "label":"Amount",
 *       "default":100, "min":0, "max":100},
 *      {"id":"map", "kind":"layer", "label":"Map"}]}
 *
 *   "kind" is one of number · angle · color · point · checkbox · menu ·
 *   layer — the kinds the app's own effects have, keyed, graphed and linked
 *   the same way. What each says beside its id and label:
 *     number, angle  "default", "min", "max" (an angle in degrees)
 *     color          "default":[r, g, b, a], each from 0 to 1
 *     checkbox       "default": true or false
 *     menu           "choices":[{"id":…,"label":…}, …], "default": its place
 *     point, layer   nothing (a point starts at the paper's middle, a layer
 *                    names no row until one is picked)
 *   An id is letters, digits and `_ . -`. A description that leaves out
 *   what its kind says, or says it past its range, is no plugin: the app
 *   makes nothing up for it. A key the spec does not name is passed over,
 *   so a later spec's hints do not stop an older host. A parameter's
 *   place in "params" is its place in frame->values.
 */
#ifndef ANICEL_FX_PLUGIN_H
#define ANICEL_FX_PLUGIN_H

#include <stddef.h>
#include <stdint.h>

#define ANICEL_FX_SPEC_VERSION 1u

/* Premultiplied 8-bit RGBA, rows top to bottom — the only format of
 * spec 1. ⚠️A new format comes with a new number here and the plugin's
 * "can" naming it; a plugin that names none of them is handed this one. */
#define ANICEL_FX_RGBA8_PREMULTIPLIED 1u

/* One picture: its first pixel lies `pixels` bytes past the frame. Its
 * columns start at canvas x `left` and its rows at canvas y `top`, in the
 * output's pixels — the reach included, so `left` is negative where the
 * input reaches past the paper. */
typedef struct anicel_fx_image {
  uint32_t pixels;
  uint32_t width;
  uint32_t height;
  uint32_t stride; /* bytes from one row to the next */
  int32_t left;
  int32_t top;
} anicel_fx_image;

/* One parameter's value at this frame. number · angle (degrees) ·
 * checkbox (0 or 1) · menu (the choice's place) use v[0]; point is v[0],
 * v[1] in canvas pixels; color is r, g, b, a from 0 to 1; layer is the
 * place of its picture in frame->layers, or -1 where it names no row. */
typedef struct anicel_fx_value {
  double v[4];
} anicel_fx_value;

typedef struct anicel_fx_frame {
  uint32_t spec;   /* the host's spec version */
  uint32_t format; /* ANICEL_FX_RGBA8_PREMULTIPLIED */
  anicel_fx_image input;
  anicel_fx_image output; /* the input's size and place */
  uint32_t value_count;
  uint32_t values; /* bytes past the frame to anicel_fx_value[value_count] */
  uint32_t layer_count;
  uint32_t layers; /* bytes past the frame to anicel_fx_image[layer_count] */
  double time;       /* seconds from the cut's first frame */
  double frame_rate; /* frames per second */
  double scale;      /* output pixels per canvas pixel — below 1 in a draft */
  int32_t frame_index;
  uint32_t reserved; /* 0 — room for spec 2 without moving a field */
} anicel_fx_frame;

/* A size of -1 fails the build where the layout moved. ⛔Not
 * `_Static_assert`: that is C11, and the host is built as C99. */
#define ANICEL_FX_ASSERT(name, holds) typedef char anicel_fx_##name[(holds) ? 1 : -1]
ANICEL_FX_ASSERT(image_is_24, sizeof(anicel_fx_image) == 24);
ANICEL_FX_ASSERT(value_is_32, sizeof(anicel_fx_value) == 32);
ANICEL_FX_ASSERT(input_at_8, offsetof(anicel_fx_frame, input) == 8);
ANICEL_FX_ASSERT(output_at_32, offsetof(anicel_fx_frame, output) == 32);
ANICEL_FX_ASSERT(values_at_56, offsetof(anicel_fx_frame, value_count) == 56);
ANICEL_FX_ASSERT(layers_at_64, offsetof(anicel_fx_frame, layer_count) == 64);
ANICEL_FX_ASSERT(time_at_72, offsetof(anicel_fx_frame, time) == 72);
ANICEL_FX_ASSERT(index_at_96, offsetof(anicel_fx_frame, frame_index) == 96);
ANICEL_FX_ASSERT(frame_is_104, sizeof(anicel_fx_frame) == 104);
#undef ANICEL_FX_ASSERT

/* What a plugin reads and writes through. */
static inline uint8_t *anicel_fx_pixels(const anicel_fx_frame *frame,
                                        const anicel_fx_image *image) {
  return (uint8_t *)frame + image->pixels;
}

static inline const anicel_fx_value *anicel_fx_values(
    const anicel_fx_frame *frame) {
  return (const anicel_fx_value *)((const uint8_t *)frame + frame->values);
}

static inline const anicel_fx_image *anicel_fx_layers(
    const anicel_fx_frame *frame) {
  return (const anicel_fx_image *)((const uint8_t *)frame + frame->layers);
}

/* Put before each exported function, with its name:
 *   ANICEL_FX_EXPORT(anicel_fx_render) int32_t anicel_fx_render(…) { … }
 * A WebAssembly module exports a function by name only where the name is
 * said (`export_name`), so the name is part of the macro. */
#if defined(_WIN32)
#define ANICEL_FX_EXPORT(name) __declspec(dllexport)
#elif defined(__wasm__)
#define ANICEL_FX_EXPORT(name) __attribute__((export_name(#name)))
#else
#define ANICEL_FX_EXPORT(name) __attribute__((visibility("default")))
#endif

/* The allocator a WebAssembly module exports: `ANICEL_FX_DEFINE_ALLOC()`
 * once in one source of the plugin. Native builds define nothing. */
#if defined(__wasm__)
#include <stdlib.h>
#define ANICEL_FX_DEFINE_ALLOC()                                   \
  ANICEL_FX_EXPORT(anicel_fx_alloc) void *anicel_fx_alloc(uint32_t size) { \
    return malloc(size);                                           \
  }
#else
#define ANICEL_FX_DEFINE_ALLOC()
#endif

#endif /* ANICEL_FX_PLUGIN_H */
