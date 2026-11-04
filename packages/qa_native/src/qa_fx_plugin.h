// The app's side of the fx plugin spec (anicel_fx_plugin.h): one plugin
// opened from a native library or a WebAssembly module, asked the same
// four questions either way.
//
// 🗣️I-132-Q5 (유저 2026-10-27): 「a + 데스크톱은 같은 규격의 네이티브(.dll ·
// .dylib)도」 — so the host has ONE frame writer and two places it writes
// to: its own memory for a native library, the module's linear memory for
// a .wasm. Everything past opening is the same code.
//
// Why the spec (anicel_fx_plugin.h) is as it is — kept here, on the app's
// side, since that header is the SDK's and speaks to plugin makers
// (fx-plugin-sdk-publish, 2026-11-04):
// 🗣️I-132-Q5: one .wasm runs on every platform and a desktop may also take
// a native build of the same source, so the spec is a C FUNCTION SPEC that a
// .dll speaks as well as a .wasm, not a WebAssembly component interface
// (I-132-Q31: the component model stays a road to add on the wasm side).
// 🗣️I-132-Q29 (유저 2026-10-29): 「a + 플러그인이 다른 레이어를 읽기」 — a
// 「layer」 parameter hands a plugin another row's picture. 「나중엔 최대한
// 극한으로 확장 … 플러그인은 확장성이 젤 중요」: a plugin says what it can
// do (`"can"`), so a later host can offer more — a GPU route, say, chosen by
// the plugin as AE's GPU effects are — and an older plugin still runs.
// ↩️No pointers in the frame: pointers would have made two layouts (4- and
// 8-byte) the host fills differently, and a plugin built for the one would
// read the other's fields wrong.
// Published, spec 1 does not break: what comes later is spec 2 and `"can"`.
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
