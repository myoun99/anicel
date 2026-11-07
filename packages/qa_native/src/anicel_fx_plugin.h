/*
 * Anicel fx plugin specification, version 1 -- the C host's copy.
 *
 * SPDX-License-Identifier: MIT
 * Copyright (c) 2026 PARK GUNWOO -- the Anicel fx plugin SDK's LICENSE.
 *
 * The spec is the Rust crate sdk/fx/anicel-fx since 2026-11-07
 * (connection-round-checklist, user Q9: no C plugin exists to keep): what a
 * plugin exports, its description, the file and the versions are said
 * there. This header is what the C host (qa_fx_plugin.c), its test and the
 * C builds of the sample and the SDK example read the same frame by -- held
 * to the crate byte for byte through native/fx_plugin's tests, where the C
 * host opens the plugins the crate builds -- and the connection round
 * deletes it with them.
 *
 * ONE LAYOUT ON EVERY TARGET. Nothing the host hands a plugin is a pointer:
 * every place is a byte DISTANCE from the frame's own address, so the
 * structs below are the same bytes in a 32-bit WebAssembly module and in a
 * 64-bit native library.
 */
#ifndef ANICEL_FX_PLUGIN_H
#define ANICEL_FX_PLUGIN_H

#include <stddef.h>
#include <stdint.h>

#define ANICEL_FX_SPEC_VERSION 1u

/* Premultiplied 8-bit RGBA, rows top to bottom -- the only format of
 * spec 1. A new format comes with a new number here and the plugin's
 * "can" naming it; a plugin that names none of them is handed this one. */
#define ANICEL_FX_RGBA8_PREMULTIPLIED 1u

/* One picture: its first pixel lies `pixels` bytes past the frame. Its
 * columns start at canvas x `left` and its rows at canvas y `top`, in the
 * output's pixels -- the reach included, so `left` is negative where the
 * input reaches past the paper. */
typedef struct anicel_fx_image {
  uint32_t pixels;
  uint32_t width;
  uint32_t height;
  uint32_t stride; /* bytes from one row to the next */
  int32_t left;
  int32_t top;
} anicel_fx_image;

/* One parameter's value at this frame. number, angle (degrees),
 * checkbox (0 or 1) and menu (the choice's place) use v[0]; point is v[0],
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
  double scale;      /* output pixels per canvas pixel -- below 1 in a draft */
  int32_t frame_index;
  uint32_t reserved; /* 0 -- room for spec 2 without moving a field */
} anicel_fx_frame;

/* A size of -1 fails the build where the layout moved. Not `_Static_assert`:
 * that is C11, and a plugin may be built as C99 -- the app's host is. */
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
 *   ANICEL_FX_EXPORT(anicel_fx_render) int32_t anicel_fx_render(...) { ... }
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
 * once in one source of the plugin. Built with a C library (WASI SDK) it is
 * malloc; built without one (clang --target=wasm32 alone) it grows the
 * module's memory by what is asked -- the host asks only for the room it
 * writes a frame into, and keeps it. Native builds define nothing. */
#if defined(__wasm__) && defined(__wasi__)
#include <stdlib.h>
#define ANICEL_FX_DEFINE_ALLOC()                                   \
  ANICEL_FX_EXPORT(anicel_fx_alloc) void *anicel_fx_alloc(uint32_t size) { \
    return malloc(size);                                           \
  }
#elif defined(__wasm__)
#define ANICEL_FX_DEFINE_ALLOC()                                   \
  ANICEL_FX_EXPORT(anicel_fx_alloc) void *anicel_fx_alloc(uint32_t size) { \
    size_t pages = ((size_t)size + 65535u) / 65536u;               \
    size_t at = __builtin_wasm_memory_grow(0, pages);              \
    return at == (size_t)-1 ? NULL : (void *)(at * 65536u);        \
  }
#else
#define ANICEL_FX_DEFINE_ALLOC()
#endif

#endif /* ANICEL_FX_PLUGIN_H */
