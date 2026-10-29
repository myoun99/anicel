// The fx plugin host (qa_fx_plugin.c), held to ONE SPEC: the same plugin
// opened as a native library (qa_fx_plugin_sample.c) and as WebAssembly
// (the twin below, written from that C line for line) answers every
// question the same way — and the same as the answer this test computes
// itself, so two twins that agree on a wrong answer still fail.
//
// What it covers: the description through each one's memory, the reach
// (values and the frame's index both read), a render with a map layer
// placed elsewhere on the canvas, without one, below the plugin's
// threshold, a plugin's failure, a module's trap (and a render after it),
// strides on both sides with the output's padding untouched, the modules
// and libraries the host must refuse (another spec version, no render, no
// plugin at all), a module started before it is asked (`_initialize`), and
// WASI linked with no folder behind it.
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "qa_fx_plugin.h"

#if QA_FX_WASM
#include <wasm.h>
#include <wasmtime.h>
#endif

void *qa_fx_plugin_open_native(const char *path, char *error,
                               int32_t error_capacity);
void *qa_fx_plugin_open_wasm(const uint8_t *bytes, int64_t length,
                             char *error, int32_t error_capacity);
int32_t qa_fx_plugin_describe(void *plugin, char *out, int32_t capacity);
int32_t qa_fx_plugin_reach(void *plugin, const double *values,
                           int32_t value_count, int32_t frame_index,
                           double time, double frame_rate, double scale);
int32_t qa_fx_plugin_render(void *plugin, const qa_fx_render_job *job);
void qa_fx_plugin_close(void *plugin);

static int failures = 0;

#define CHECK(holds, ...)                                  \
  do {                                                     \
    if (!(holds)) {                                        \
      failures++;                                          \
      printf("FAIL %s:%d: ", __FILE__, __LINE__);          \
      printf(__VA_ARGS__);                                 \
      printf("\n");                                        \
    }                                                      \
  } while (0)

// The input: 6×4, rows 32 bytes apart (8 past the pixels), its first pixel
// at canvas (−1, −1). Premultiplied: no colour above its alpha.
enum { IN_W = 6, IN_H = 4, IN_STRIDE = IN_W * 4 + 8 };
enum { OUT_STRIDE = IN_W * 4 + 12 };
// The map: 3×3 at canvas (1, 0), alpha a checkerboard.
enum { MAP_W = 3, MAP_H = 3, MAP_STRIDE = MAP_W * 4 + 4 };
static const int32_t IN_LEFT = -1, IN_TOP = -1, MAP_LEFT = 1, MAP_TOP = 0;

static uint8_t input[IN_H * IN_STRIDE];
static uint8_t map[MAP_H * MAP_STRIDE];

static void make_pictures(void) {
  memset(input, 0xAB, sizeof(input));
  for (int y = 0; y < IN_H; y++) {
    for (int x = 0; x < IN_W; x++) {
      uint8_t *p = input + y * IN_STRIDE + x * 4;
      p[3] = (uint8_t)(150 + x * 15 + y * 5);
      p[0] = (uint8_t)(x * 20);
      p[1] = (uint8_t)(y * 30);
      p[2] = (uint8_t)(10 + x + y);
    }
  }
  memset(map, 0xCD, sizeof(map));
  for (int y = 0; y < MAP_H; y++) {
    for (int x = 0; x < MAP_W; x++) {
      uint8_t *p = map + y * MAP_STRIDE + x * 4;
      p[0] = p[1] = p[2] = 0;
      p[3] = (uint8_t)(((x + y) % 2 == 0) ? 255 : 0);
    }
  }
}

// What the sample's render gives, worked out here on its own.
static void expected(double amount, int with_map, uint8_t *out) {
  memset(out, 0xEE, (size_t)IN_H * OUT_STRIDE);
  for (int y = 0; y < IN_H; y++) {
    for (int x = 0; x < IN_W; x++) {
      const uint8_t *p = input + y * IN_STRIDE + x * 4;
      uint8_t *q = out + y * OUT_STRIDE + x * 4;
      int inverts = amount >= 50;
      if (inverts && with_map) {
        int mx = IN_LEFT + x - MAP_LEFT, my = IN_TOP + y - MAP_TOP;
        inverts = mx >= 0 && my >= 0 && mx < MAP_W && my < MAP_H &&
                  map[my * MAP_STRIDE + mx * 4 + 3] > 127;
      }
      for (int c = 0; c < 3; c++) {
        q[c] = inverts ? (uint8_t)(p[3] - p[c]) : p[c];
      }
      q[3] = p[3];
    }
  }
}

static int32_t render(void *plugin, double amount, int with_map,
                      int32_t frame_index, uint8_t *out) {
  memset(out, 0xEE, (size_t)IN_H * OUT_STRIDE);
  double values[8] = {amount, 0, 0, 0, with_map ? 0 : -1, 0, 0, 0};
  qa_fx_picture layer = {map, MAP_W, MAP_H, MAP_STRIDE, MAP_LEFT, MAP_TOP};
  qa_fx_render_job job;
  memset(&job, 0, sizeof(job));
  job.input.pixels = input;
  job.input.width = IN_W;
  job.input.height = IN_H;
  job.input.stride = IN_STRIDE;
  job.input.left = IN_LEFT;
  job.input.top = IN_TOP;
  job.output = out;
  job.output_stride = OUT_STRIDE;
  job.value_count = 2;
  job.values = values;
  job.layers = &layer;
  job.layer_count = 1;
  job.frame_index = frame_index;
  job.time = frame_index / 24.0;
  job.frame_rate = 24;
  job.scale = 1;
  return qa_fx_plugin_render(plugin, &job);
}

static void check_render(void *plugin, const char *who, double amount,
                         int with_map) {
  uint8_t got[IN_H * OUT_STRIDE];
  uint8_t want[IN_H * OUT_STRIDE];
  expected(amount, with_map, want);
  int32_t answer = render(plugin, amount, with_map, 3, got);
  CHECK(answer == QA_FX_OK, "%s: render(amount %g, map %d) answered %d", who,
        amount, with_map, answer);
  CHECK(memcmp(got, want, sizeof(got)) == 0,
        "%s: render(amount %g, map %d) differs from the spec's answer", who,
        amount, with_map);
}

// Every question, of one plugin. [description] is the native one's, which
// the WebAssembly twin must give back through its own memory.
static void check_plugin(void *plugin, const char *who,
                         const char *description) {
  char said[512];
  memset(said, 0, sizeof(said));
  int32_t length = qa_fx_plugin_describe(plugin, said, (int32_t)sizeof(said));
  CHECK(length == (int32_t)strlen(description) &&
            memcmp(said, description, (size_t)length) == 0,
        "%s: description %d bytes, \"%.40s…\"", who, length, said);
  // Too little room: the length still, and nothing past the room.
  char small[9];
  memset(small, 'x', sizeof(small));
  length = qa_fx_plugin_describe(plugin, small, 8);
  CHECK(length == (int32_t)strlen(description) && small[8] == 'x' &&
            memcmp(small, description, 8) == 0,
        "%s: a short room took %d and kept its end %c", who, length,
        small[8]);

  double values[8] = {80, 0, 0, 0, 0, 0, 0, 0};
  int32_t reach = qa_fx_plugin_reach(plugin, values, 2, 3, 3 / 24.0, 24, 1);
  CHECK(reach == 11, "%s: reach %d, the spec's 80 / 10 + 3 = 11", who, reach);

  check_render(plugin, who, 80, 1);
  check_render(plugin, who, 80, 0);
  check_render(plugin, who, 30, 1);
  // The same plugin asked again: the frame's room is reused, not leaked
  // into the answer.
  check_render(plugin, who, 80, 1);

  uint8_t out[IN_H * OUT_STRIDE];
  int32_t failed = render(plugin, -5, 1, 0, out);
  CHECK(failed == QA_FX_FAILED, "%s: a plugin's failure answered %d", who,
        failed);

  qa_fx_render_job empty;
  memset(&empty, 0, sizeof(empty));
  CHECK(qa_fx_plugin_render(plugin, &empty) == QA_FX_BAD_JOB,
        "%s: a job with no input was taken", who);
}

static void check_refusals(void) {
  char error[256];
  error[0] = 0;
  CHECK(qa_fx_plugin_open_native("no/such/plugin.dll", error,
                                 (int32_t)sizeof(error)) == NULL &&
            error[0] != 0,
        "a library that is not there opened");
  error[0] = 0;
  CHECK(qa_fx_plugin_open_native(QA_FX_SAMPLE_SPEC2, error,
                                 (int32_t)sizeof(error)) == NULL &&
            error[0] != 0,
        "a library of another spec version opened");
  error[0] = 0;
  CHECK(qa_fx_plugin_open_native(QA_FX_SAMPLE_NO_RENDER, error,
                                 (int32_t)sizeof(error)) == NULL &&
            error[0] != 0,
        "a library with no render opened");
  uint8_t garbage[8] = {1, 2, 3, 4, 5, 6, 7, 8};
  error[0] = 0;
  CHECK(qa_fx_plugin_open_wasm(garbage, sizeof(garbage), error,
                               (int32_t)sizeof(error)) == NULL &&
            error[0] != 0,
        "bytes that are no module opened");
}

#if QA_FX_WASM
// The sample's C, as WebAssembly text: one line of the C per few here.
// %s is the description (escaped) and the two %d its length.
static const char *twin_wat =
    "(module\n"
    // At most two pages: a host that took new room for each render would
    // run out of it long before the 400 renders check_twin asks for.
    " (memory (export \"memory\") 1 2)\n"
    " (global $bump (mut i32) (i32.const 4096))\n"
    " (data (i32.const 64) \"%s\")\n"
    " (func (export \"anicel_fx_spec\") (result i32) (i32.const 1))\n"
    " (func (export \"anicel_fx_alloc\") (param $size i32) (result i32)\n"
    "  (local $at i32) (local $end i32)\n"
    "  (local.set $at (global.get $bump))\n"
    "  (local.set $end (i32.and (i32.add (i32.add (local.get $at)\n"
    "   (local.get $size)) (i32.const 15)) (i32.const -16)))\n"
    "  (block $ok (loop $grow\n"
    "   (br_if $ok (i32.le_u (local.get $end)\n"
    "    (i32.mul (memory.size) (i32.const 65536))))\n"
    "   (if (i32.eq (memory.grow (i32.const 1)) (i32.const -1))\n"
    "    (then (return (i32.const 0))))\n"
    "   (br $grow)))\n"
    "  (global.set $bump (local.get $end))\n"
    "  (local.get $at))\n"
    " (func (export \"anicel_fx_describe\") (param $out i32) (param $cap i32)\n"
    "  (result i32)\n"
    "  (memory.copy (local.get $out) (i32.const 64)\n"
    "   (select (i32.const %d) (local.get $cap)\n"
    "    (i32.lt_u (i32.const %d) (local.get $cap))))\n"
    "  (i32.const %d))\n"
    " (func (export \"anicel_fx_reach\") (param $f i32) (result i32)\n"
    "  (i32.add\n"
    "   (i32.trunc_sat_f64_u (f64.div (f64.load (i32.add (local.get $f)\n"
    "    (i32.load offset=60 (local.get $f)))) (f64.const 10)))\n"
    "   (i32.load offset=96 (local.get $f))))\n"
    " (func $map_allows (param $f i32) (param $map i32) (param $x i32)\n"
    "  (param $y i32) (result i32) (local $mx i32) (local $my i32)\n"
    "  (if (i32.eqz (local.get $map)) (then (return (i32.const 1))))\n"
    "  (local.set $mx (i32.sub (local.get $x)\n"
    "   (i32.load offset=16 (local.get $map))))\n"
    "  (local.set $my (i32.sub (local.get $y)\n"
    "   (i32.load offset=20 (local.get $map))))\n"
    "  (if (i32.or (i32.or (i32.lt_s (local.get $mx) (i32.const 0))\n"
    "               (i32.lt_s (local.get $my) (i32.const 0)))\n"
    "       (i32.or (i32.ge_s (local.get $mx)\n"
    "                (i32.load offset=4 (local.get $map)))\n"
    "               (i32.ge_s (local.get $my)\n"
    "                (i32.load offset=8 (local.get $map)))))\n"
    "   (then (return (i32.const 0))))\n"
    "  (i32.gt_u (i32.load8_u offset=3 (i32.add (i32.add (local.get $f)\n"
    "    (i32.load (local.get $map))) (i32.add (i32.mul (local.get $my)\n"
    "    (i32.load offset=12 (local.get $map))) (i32.shl (local.get $mx)\n"
    "    (i32.const 2))))) (i32.const 127)))\n"
    " (func (export \"anicel_fx_render\") (param $f i32) (result i32)\n"
    "  (local $vals i32) (local $amount f64) (local $mapat i32)\n"
    "  (local $map i32) (local $w i32) (local $h i32) (local $x i32)\n"
    "  (local $y i32) (local $p i32) (local $q i32) (local $inv i32)\n"
    "  (local $a i32) (local $c i32)\n"
    "  (local.set $vals (i32.add (local.get $f)\n"
    "   (i32.load offset=60 (local.get $f))))\n"
    "  (local.set $amount (f64.load (local.get $vals)))\n"
    // The twin's own: far below zero it traps, as a broken module would.
    "  (if (f64.lt (local.get $amount) (f64.const -100)) (then unreachable))\n"
    "  (if (f64.lt (local.get $amount) (f64.const 0))\n"
    "   (then (return (i32.const 1))))\n"
    "  (local.set $mapat (i32.trunc_sat_f64_s\n"
    "   (f64.load offset=32 (local.get $vals))))\n"
    "  (if (i32.and (i32.ge_s (local.get $mapat) (i32.const 0))\n"
    "   (i32.lt_u (local.get $mapat) (i32.load offset=64 (local.get $f))))\n"
    "   (then (local.set $map (i32.add (i32.add (local.get $f)\n"
    "    (i32.load offset=68 (local.get $f)))\n"
    "    (i32.mul (local.get $mapat) (i32.const 24))))))\n"
    "  (local.set $w (i32.load offset=12 (local.get $f)))\n"
    "  (local.set $h (i32.load offset=16 (local.get $f)))\n"
    "  (block $ydone (loop $yl\n"
    "   (br_if $ydone (i32.ge_u (local.get $y) (local.get $h)))\n"
    "   (local.set $x (i32.const 0))\n"
    "   (block $xdone (loop $xl\n"
    "    (br_if $xdone (i32.ge_u (local.get $x) (local.get $w)))\n"
    "    (local.set $p (i32.add (i32.add (local.get $f)\n"
    "     (i32.load offset=8 (local.get $f))) (i32.add (i32.mul\n"
    "     (local.get $y) (i32.load offset=20 (local.get $f)))\n"
    "     (i32.shl (local.get $x) (i32.const 2)))))\n"
    "    (local.set $q (i32.add (i32.add (local.get $f)\n"
    "     (i32.load offset=32 (local.get $f))) (i32.add (i32.mul\n"
    "     (local.get $y) (i32.load offset=44 (local.get $f)))\n"
    "     (i32.shl (local.get $x) (i32.const 2)))))\n"
    "    (local.set $inv (i32.and (f64.ge (local.get $amount)\n"
    "     (f64.const 50)) (call $map_allows (local.get $f) (local.get $map)\n"
    "     (i32.add (i32.load offset=24 (local.get $f)) (local.get $x))\n"
    "     (i32.add (i32.load offset=28 (local.get $f)) (local.get $y)))))\n"
    "    (local.set $a (i32.load8_u offset=3 (local.get $p)))\n"
    "    (local.set $c (i32.const 0))\n"
    "    (block $cdone (loop $cl\n"
    "     (br_if $cdone (i32.ge_u (local.get $c) (i32.const 3)))\n"
    "     (i32.store8 (i32.add (local.get $q) (local.get $c))\n"
    "      (select (i32.sub (local.get $a) (i32.load8_u (i32.add\n"
    "       (local.get $p) (local.get $c)))) (i32.load8_u (i32.add\n"
    "       (local.get $p) (local.get $c))) (local.get $inv)))\n"
    "     (local.set $c (i32.add (local.get $c) (i32.const 1)))\n"
    "     (br $cl)))\n"
    "    (i32.store8 offset=3 (local.get $q) (local.get $a))\n"
    "    (local.set $x (i32.add (local.get $x) (i32.const 1)))\n"
    "    (br $xl)))\n"
    "   (local.set $y (i32.add (local.get $y) (i32.const 1)))\n"
    "   (br $yl)))\n"
    "  (i32.const 0)))\n";

// WebAssembly text's string escapes for a description: `"` and `\`.
static void escape(const char *from, char *to) {
  for (; *from; from++) {
    if (*from == '"' || *from == '\\') {
      *to++ = '\\';
    }
    *to++ = *from;
  }
  *to = 0;
}

static void *open_wat(const char *text, char *error, int32_t capacity) {
  wasm_byte_vec_t binary;
  wasmtime_error_t *wasm_error =
      wasmtime_wat2wasm(text, strlen(text), &binary);
  if (wasm_error != NULL) {
    wasm_byte_vec_t message;
    wasmtime_error_message(wasm_error, &message);
    printf("wat: %.*s\n", (int)message.size, message.data);
    wasm_byte_vec_delete(&message);
    wasmtime_error_delete(wasm_error);
    return NULL;
  }
  void *plugin = qa_fx_plugin_open_wasm((const uint8_t *)binary.data,
                                        (int64_t)binary.size, error,
                                        capacity);
  wasm_byte_vec_delete(&binary);
  return plugin;
}

static void check_twin(const char *description) {
  char escaped[1024];
  escape(description, escaped);
  int length = (int)strlen(description);
  size_t room = strlen(twin_wat) + strlen(escaped) + 64;
  char *text = (char *)malloc(room);
  snprintf(text, room, twin_wat, escaped, length, length, length);
  char error[512];
  error[0] = 0;
  void *twin = open_wat(text, error, (int32_t)sizeof(error));
  free(text);
  CHECK(twin != NULL, "the WebAssembly twin would not open: %s", error);
  if (twin == NULL) {
    return;
  }
  check_plugin(twin, "wasm", description);
  uint8_t out[IN_H * OUT_STRIDE];
  int32_t trapped = render(twin, -200, 1, 0, out);
  CHECK(trapped == QA_FX_TRAPPED, "wasm: a trap answered %d", trapped);
  // A trap is the render's, not the plugin's end.
  check_render(twin, "wasm after a trap", 80, 1);
  // The frame's room in the module is reused, not taken anew each time.
  int32_t kept = QA_FX_OK;
  for (int i = 0; i < 400 && kept == QA_FX_OK; i++) {
    kept = render(twin, 80, 1, 3, out);
  }
  CHECK(kept == QA_FX_OK, "wasm: the 400th render answered %d", kept);
  qa_fx_plugin_close(twin);

  error[0] = 0;
  CHECK(open_wat("(module (memory (export \"memory\") 1))", error,
                 (int32_t)sizeof(error)) == NULL &&
            error[0] != 0,
        "a module that exports no plugin opened");
  error[0] = 0;
  CHECK(open_wat("(module (memory (export \"memory\") 1)"
                 " (func (export \"anicel_fx_spec\") (result i32) i32.const 2)"
                 " (func (export \"anicel_fx_alloc\") (param i32) (result i32)"
                 "  i32.const 1024)"
                 " (func (export \"anicel_fx_describe\") (param i32 i32)"
                 "  (result i32) i32.const 0)"
                 " (func (export \"anicel_fx_reach\") (param i32) (result i32)"
                 "  i32.const 0)"
                 " (func (export \"anicel_fx_render\") (param i32) (result i32)"
                 "  i32.const 0))",
                 error, (int32_t)sizeof(error)) == NULL &&
            error[0] != 0,
        "a module of another spec version opened");

  // A module built on WASI's libc starts its runtime in `_initialize`:
  // this one names its spec only once started.
  error[0] = 0;
  void *started = open_wat(
      "(module (memory (export \"memory\") 1)"
      " (global $ready (mut i32) (i32.const 0))"
      " (func (export \"_initialize\") (global.set $ready (i32.const 1)))"
      " (func (export \"anicel_fx_spec\") (result i32) (global.get $ready))"
      " (func (export \"anicel_fx_alloc\") (param i32) (result i32)"
      "  i32.const 1024)"
      " (func (export \"anicel_fx_describe\") (param i32 i32) (result i32)"
      "  i32.const 0)"
      " (func (export \"anicel_fx_reach\") (param i32) (result i32)"
      "  i32.const 0)"
      " (func (export \"anicel_fx_render\") (param i32) (result i32)"
      "  i32.const 0))",
      error, (int32_t)sizeof(error));
  CHECK(started != NULL, "a module was not started first: %s", error);
  qa_fx_plugin_close(started);

  // WASI is there to link against and reaches nothing: the first folder a
  // host could open to a module is descriptor 3, and there is none (EBADF).
  error[0] = 0;
  void *sandboxed = open_wat(
      "(module (import \"wasi_snapshot_preview1\" \"fd_prestat_get\""
      "  (func $prestat (param i32 i32) (result i32)))"
      " (memory (export \"memory\") 1)"
      " (func (export \"anicel_fx_spec\") (result i32) i32.const 1)"
      " (func (export \"anicel_fx_alloc\") (param i32) (result i32)"
      "  i32.const 1024)"
      " (func (export \"anicel_fx_describe\") (param i32 i32) (result i32)"
      "  i32.const 0)"
      " (func (export \"anicel_fx_reach\") (param i32) (result i32)"
      "  (call $prestat (i32.const 3) (i32.const 512)))"
      " (func (export \"anicel_fx_render\") (param i32) (result i32)"
      "  i32.const 0))",
      error, (int32_t)sizeof(error));
  CHECK(sandboxed != NULL, "a module on WASI would not open: %s", error);
  if (sandboxed != NULL) {
    int32_t answer = qa_fx_plugin_reach(sandboxed, NULL, 0, 0, 0, 24, 1);
    CHECK(answer == 8, "a module saw a folder: fd_prestat_get(3) is %d",
          answer);
    qa_fx_plugin_close(sandboxed);
  }
}
#endif

int main(void) {
  make_pictures();
  char error[256];
  error[0] = 0;
  void *native = qa_fx_plugin_open_native(QA_FX_SAMPLE, error,
                                          (int32_t)sizeof(error));
  CHECK(native != NULL, "the sample library would not open: %s", error);
  char description[512];
  memset(description, 0, sizeof(description));
  if (native != NULL) {
    qa_fx_plugin_describe(native, description,
                          (int32_t)sizeof(description) - 1);
    check_plugin(native, "native", description);
    qa_fx_plugin_close(native);
  }
  check_refusals();
#if QA_FX_WASM
  check_twin(description);
#else
  printf("qa_fx_plugin_test: this build has no WebAssembly engine — the "
         "twin is not asked\n");
#endif
  if (failures == 0) {
    printf("qa_fx_plugin_test: OK\n");
    return 0;
  }
  printf("qa_fx_plugin_test: %d failure(s)\n", failures);
  return 1;
}
