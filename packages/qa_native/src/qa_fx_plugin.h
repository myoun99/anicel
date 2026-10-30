// The app's side of the fx plugin spec (anicel_fx_plugin.h): one plugin
// opened from a native library or a WebAssembly module, asked the same
// four questions either way.
//
// 🗣️I-132-Q5 (유저 2026-10-27): 「a + 데스크톱은 같은 규격의 네이티브(.dll ·
// .dylib)도」 — so the host has ONE frame writer and two places it writes
// to: its own memory for a native library, the module's linear memory for
// a .wasm. Everything past opening is the same code.
//
// ⚠️A plugin is asked by one thread at a time; two plugins may be asked at
// once.
#ifndef QA_FX_PLUGIN_H
#define QA_FX_PLUGIN_H

#include <stdint.h>

// A picture the app hands a plugin or takes back: premultiplied RGBA8,
// rows top to bottom, `stride` bytes apart. `left` · `top` place its first
// pixel on the canvas (anicel_fx_image).
typedef struct qa_fx_picture {
  const uint8_t *pixels;
  int32_t width;
  int32_t height;
  int32_t stride;
  int32_t left;
  int32_t top;
} qa_fx_picture;

// One render: the row's picture (the reach included), where the result
// goes (the input's size, `output_stride` bytes a row), the values in the
// description's order — four doubles each (anicel_fx_value) — and the
// pictures of the rows its layer parameters name.
typedef struct qa_fx_render_job {
  qa_fx_picture input;
  uint8_t *output;
  int32_t output_stride;
  int32_t value_count;
  const double *values;
  const qa_fx_picture *layers;
  int32_t layer_count;
  int32_t frame_index;
  double time;
  double frame_rate;
  double scale;
} qa_fx_render_job;

// What a render or a question answers besides a length.
#define QA_FX_OK 0
#define QA_FX_BAD_JOB -1      // a size or a pointer the job cannot have
#define QA_FX_FAILED -2       // the plugin answered non-zero
#define QA_FX_TRAPPED -3      // a .wasm trapped, or a call into it failed
#define QA_FX_NO_ROOM -4      // no memory for the frame

#endif  // QA_FX_PLUGIN_H
