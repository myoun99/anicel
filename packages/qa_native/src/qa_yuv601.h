// The app's colour law for movies: BT.601, studio range, 4:2:0 — how a
// picture becomes YCbCr when this app writes a movie, and how YCbCr becomes
// a picture where this app converts one back itself. BOTH DIRECTIONS HERE,
// so the matrix one side writes is the matrix the other side reads.
//
// 🚨★★★**THE WRITERS CONVERT, NOT THE OS.** Apple's writer handed its
// encoder BGRA and let VideoToolbox turn it into YCbCr, and what came back
// through the Apple reader had lost red in exact proportion to it — 0.9136
// of itself each way round, which is BT.709 in and BT.601 out. Measured on
// the Apple runner: red 110 written came back 101, and a piece cut from a
// take came back 168 where the take showed 185 and 200 was written
// (2026-09-25, board `trimmed-piece-apple-parity`). Naming BT.601 in the
// writer's colour properties moved none of those numbers, so the matrix is
// not the writer's to choose that way — it is chosen by handing the encoder
// YCbCr made HERE. The Android writer always converted by hand; this is now
// that conversion, for both. (Media Foundation's writer and reader agree
// with each other within 3, and keep their own.)
//
// Header-only and `static inline`: Android's C writer and reader and Apple's
// Objective-C writer each call it from their own translation unit, and one
// of its own would buy a link dependency and nothing else.

#ifndef QA_YUV601_H
#define QA_YUV601_H

#include <stdint.h>

/// [width]×[height] of 4:2:0 BT.601 studio range from straight RGBA whose
/// first [src_width]×[src_height] are the picture and the rest is PADDING,
/// painted white (an encoder takes even sizes; the picture may be odd).
///
/// The planes are written where the caller says, because every buffer this
/// fills lays them out its own way: [y_plane] rows are [y_stride] bytes
/// apart, and the chroma sample for 2×2 pixels lands at
/// `cb_plane[row * chroma_stride + column * chroma_step]` and the same
/// place in [cr_plane] — `chroma_step` 2 with `cr_plane = cb_plane + 1` for
/// interleaved NV12, 1 with two separate planes for I420.
///
/// ⚠️Each 2×2 block takes its chroma from its top-left pixel rather than an
/// average: it is what the Android writer always did, and a flat picture —
/// what every test of this reads — is the same either way.
static inline void qa_yuv601_from_rgba(const uint8_t* rgba,
                                       int32_t src_width,
                                       int32_t src_height,
                                       int32_t width,
                                       int32_t height,
                                       uint8_t* y_plane,
                                       int32_t y_stride,
                                       uint8_t* cb_plane,
                                       uint8_t* cr_plane,
                                       int32_t chroma_stride,
                                       int32_t chroma_step) {
  for (int32_t y = 0; y < height; y += 1) {
    for (int32_t x = 0; x < width; x += 1) {
      int32_t r = 255;
      int32_t g = 255;
      int32_t b = 255;
      if (x < src_width && y < src_height) {
        const uint8_t* pixel =
            rgba + ((int64_t)y * (int64_t)src_width + (int64_t)x) * 4;
        r = pixel[0];
        g = pixel[1];
        b = pixel[2];
      }
      y_plane[(int64_t)y * y_stride + x] =
          (uint8_t)(((66 * r + 129 * g + 25 * b + 128) >> 8) + 16);
      if ((x & 1) == 0 && (y & 1) == 0) {
        const int64_t at =
            (int64_t)(y / 2) * chroma_stride + (int64_t)(x / 2) * chroma_step;
        cb_plane[at] =
            (uint8_t)(((-38 * r - 74 * g + 112 * b + 128) >> 8) + 128);
        cr_plane[at] =
            (uint8_t)(((112 * r - 94 * g - 18 * b + 128) >> 8) + 128);
      }
    }
  }
}

/// YUV420 → RGBA, BT.601 studio range — the inverse of
/// [qa_yuv601_from_rgba].
///
/// [stride] is BYTES PER LUMA ROW and [slice] the rows between the Y plane
/// and the chroma that follows it. Both are ≥ the picture, and assuming
/// either equals it is the classic way to get a green-striped frame on one
/// vendor's hardware and a correct one on another's. [semi_planar] picks
/// NV12 (interleaved chroma) over planar I420.
///
/// 🚨★★★**IT LIVES IN THE LAW BECAUSE IT IS ARITHMETIC, AND BECAUSE IT WAS
/// NEVER RUN.** This was inside the `__ANDROID__` backend, where it
/// compiles on every PR and executes on no machine anybody has — the card
/// `android-decoder-branch-never-runs` is about exactly that gap. Nothing
/// in it touches a platform: it reads bytes and writes bytes, so it can be
/// proven on the bench (`qa_video_decode_law_test.c`), round trip included.
///
/// ⛔The picture size comes in as ARGUMENTS. It used to read the decoder's
/// global document, which is what tied a pure calculation to a backend
/// having opened something.
static inline void qa_yuv420_to_rgba(const uint8_t* data,
                                     int32_t width,
                                     int32_t height,
                                     int32_t stride,
                                     int32_t slice,
                                     int semi_planar,
                                     uint8_t* rgba) {
  const uint8_t* y_plane = data;
  const uint8_t* u_plane = data + (int64_t)stride * slice;
  const uint8_t* v_plane =
      semi_planar ? u_plane + 1
                  : u_plane + ((int64_t)stride / 2) * (slice / 2);
  const int32_t chroma_stride = semi_planar ? stride : stride / 2;
  const int32_t chroma_step = semi_planar ? 2 : 1;

  for (int32_t y = 0; y < height; y += 1) {
    const uint8_t* y_row = y_plane + (int64_t)y * stride;
    const int32_t cy = y / 2;
    for (int32_t x = 0; x < width; x += 1) {
      const int32_t cx = x / 2;
      const int32_t luma = (int32_t)y_row[x] - 16;
      const int32_t cb =
          (int32_t)u_plane[(int64_t)cy * chroma_stride + cx * chroma_step] -
          128;
      const int32_t cr =
          (int32_t)v_plane[(int64_t)cy * chroma_stride + cx * chroma_step] -
          128;
      int32_t r = (298 * luma + 409 * cr + 128) >> 8;
      int32_t g = (298 * luma - 100 * cb - 208 * cr + 128) >> 8;
      int32_t b = (298 * luma + 516 * cb + 128) >> 8;
      r = r < 0 ? 0 : (r > 255 ? 255 : r);
      g = g < 0 ? 0 : (g > 255 ? 255 : g);
      b = b < 0 ? 0 : (b > 255 ? 255 : b);
      uint8_t* out = rgba + ((int64_t)y * width + x) * 4;
      out[0] = (uint8_t)r;
      out[1] = (uint8_t)g;
      out[2] = (uint8_t)b;
      out[3] = 255;
    }
  }
}

#endif  // QA_YUV601_H
