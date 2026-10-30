// The fx plugin host (qa_fx_plugin.h): opens a plugin from a native
// library or a WebAssembly module and asks it the spec's questions.
//
// ★ONE FRAME WRITER. A render lays one block — the frame, its values, its
// layers' places and every picture's pixels — and the frame names each part
// by its distance from itself (anicel_fx_plugin.h), so the same bytes are
// right wherever the block lies. A native plugin's block is this host's
// memory; a .wasm's is room the module gave (`anicel_fx_alloc`) in its
// linear memory. `lay_block` writes both; `call_*` is all that differs.
//
// 🗣️I-132-Q31 (유저 2026-10-30): Wasmtime 48 LTS — linked where the build
// found it (QA_FX_WASM); a build without it opens native plugins only and
// says so to a .wasm.
#include "qa_fx_plugin.h"

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "anicel_fx_plugin.h"

#if defined(_WIN32)
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#define QA_EXPORT __declspec(dllexport)
#else
#include <dlfcn.h>
#define QA_EXPORT __attribute__((visibility("default")))
#endif

#if QA_FX_WASM
#include <wasi.h>
#include <wasm.h>
#include <wasmtime.h>
#endif

typedef uint32_t (*spec_fn)(void);
typedef uint32_t (*describe_fn)(char *out, uint32_t capacity);
typedef uint32_t (*reach_fn)(const anicel_fx_frame *frame);
typedef int32_t (*render_fn)(anicel_fx_frame *frame);

enum { KIND_NATIVE = 1, KIND_WASM = 2 };

typedef struct qa_fx_plugin {
  int kind;
  // A native library and its four functions.
  void *library;
  describe_fn describe;
  reach_fn reach;
  render_fn render;
  uint8_t *block;
  size_t block_size;
#if QA_FX_WASM
  wasm_engine_t *engine;
  wasmtime_store_t *store;
  wasmtime_linker_t *linker;
  wasmtime_module_t *module;
  wasmtime_instance_t instance;
  wasmtime_memory_t memory;
  wasmtime_func_t f_describe;
  wasmtime_func_t f_reach;
  wasmtime_func_t f_render;
  wasmtime_func_t f_alloc;
  // The room the module gave for frames: grown, never handed back — a
  // module's allocator needs no free for a block it reuses.
  uint32_t wasm_block;
  uint32_t wasm_block_size;
#endif
} qa_fx_plugin;

static void say(char *error, int32_t capacity, const char *what) {
  if (error == NULL || capacity <= 0) {
    return;
  }
  snprintf(error, (size_t)capacity, "%s", what);
}

// ── the block ────────────────────────────────────────────────────────────

// Where each part of a render's block lies, from the frame (at 0).
typedef struct block_plan {
  size_t values;
  size_t layers;
  size_t input;
  size_t output;
  size_t layer_pixels_first;
  size_t total;
} block_plan;

static size_t align16(size_t at) { return (at + 15u) & ~(size_t)15u; }

static size_t picture_bytes(const qa_fx_picture *picture) {
  return (size_t)picture->width * (size_t)picture->height * 4u;
}

// Nothing past 4 GB: every place in the frame is a 32-bit distance.
static int plan_block(const qa_fx_render_job *job, block_plan *plan) {
  size_t at = align16(sizeof(anicel_fx_frame));
  plan->values = at;
  at = align16(at + (size_t)job->value_count * sizeof(anicel_fx_value));
  plan->layers = at;
  at = align16(at + (size_t)job->layer_count * sizeof(anicel_fx_image));
  plan->input = at;
  at = align16(at + picture_bytes(&job->input));
  plan->output = at;
  at = align16(at + picture_bytes(&job->input));
  plan->layer_pixels_first = at;
  for (int32_t i = 0; i < job->layer_count; i++) {
    at = align16(at + picture_bytes(&job->layers[i]));
  }
  plan->total = at;
  return at <= (size_t)UINT32_MAX ? 0 : -1;
}

static int picture_is_whole(const qa_fx_picture *picture) {
  return picture->pixels != NULL && picture->width > 0 &&
         picture->height > 0 && picture->stride >= picture->width * 4;
}

static int job_is_whole(const qa_fx_render_job *job) {
  if (job == NULL || !picture_is_whole(&job->input) || job->output == NULL ||
      job->output_stride < job->input.width * 4 || job->value_count < 0 ||
      (job->value_count > 0 && job->values == NULL) || job->layer_count < 0 ||
      (job->layer_count > 0 && job->layers == NULL)) {
    return 0;
  }
  for (int32_t i = 0; i < job->layer_count; i++) {
    if (!picture_is_whole(&job->layers[i])) {
      return 0;
    }
  }
  return 1;
}

static void lay_image(anicel_fx_image *image, size_t pixels,
                      const qa_fx_picture *picture) {
  image->pixels = (uint32_t)pixels;
  image->width = (uint32_t)picture->width;
  image->height = (uint32_t)picture->height;
  image->stride = (uint32_t)picture->width * 4u;
  image->left = picture->left;
  image->top = picture->top;
}

static void copy_rows(uint8_t *to, size_t to_stride, const uint8_t *from,
                      size_t from_stride, size_t row_bytes, int32_t rows) {
  for (int32_t y = 0; y < rows; y++) {
    memcpy(to + (size_t)y * to_stride, from + (size_t)y * from_stride,
           row_bytes);
  }
}

static void lay_frame_head(anicel_fx_frame *frame,
                           const qa_fx_render_job *job) {
  memset(frame, 0, sizeof(*frame));
  frame->spec = ANICEL_FX_SPEC_VERSION;
  frame->format = ANICEL_FX_RGBA8_PREMULTIPLIED;
  frame->value_count = (uint32_t)job->value_count;
  frame->layer_count = (uint32_t)job->layer_count;
  frame->time = job->time;
  frame->frame_rate = job->frame_rate;
  frame->scale = job->scale;
  frame->frame_index = job->frame_index;
}

static void lay_values(uint8_t *base, size_t at, const double *values,
                       int32_t count) {
  if (count > 0) {
    memcpy(base + at, values, (size_t)count * sizeof(anicel_fx_value));
  }
}

// Writes the whole render into [base] (the frame's own address) by [plan].
static void lay_block(uint8_t *base, const block_plan *plan,
                      const qa_fx_render_job *job) {
  anicel_fx_frame *frame = (anicel_fx_frame *)base;
  lay_frame_head(frame, job);
  frame->values = (uint32_t)plan->values;
  frame->layers = (uint32_t)plan->layers;
  lay_values(base, plan->values, job->values, job->value_count);
  lay_image(&frame->input, plan->input, &job->input);
  lay_image(&frame->output, plan->output, &job->input);
  copy_rows(base + plan->input, (size_t)job->input.width * 4u,
            job->input.pixels, (size_t)job->input.stride,
            (size_t)job->input.width * 4u, job->input.height);
  memset(base + plan->output, 0, picture_bytes(&job->input));
  anicel_fx_image *layers = (anicel_fx_image *)(base + plan->layers);
  size_t at = plan->layer_pixels_first;
  for (int32_t i = 0; i < job->layer_count; i++) {
    const qa_fx_picture *layer = &job->layers[i];
    lay_image(&layers[i], at, layer);
    copy_rows(base + at, (size_t)layer->width * 4u, layer->pixels,
              (size_t)layer->stride, (size_t)layer->width * 4u,
              layer->height);
    at = align16(at + picture_bytes(layer));
  }
}

static void take_output(const uint8_t *base, const block_plan *plan,
                        const qa_fx_render_job *job) {
  copy_rows(job->output, (size_t)job->output_stride, base + plan->output,
            (size_t)job->input.width * 4u, (size_t)job->input.width * 4u,
            job->input.height);
}

// A reach's frame: the values alone, its images empty.
static size_t reach_block_size(int32_t value_count) {
  return align16(sizeof(anicel_fx_frame)) +
         (size_t)value_count * sizeof(anicel_fx_value);
}

static void lay_reach(uint8_t *base, const double *values,
                      int32_t value_count, int32_t frame_index, double time,
                      double frame_rate, double scale) {
  qa_fx_render_job job;
  memset(&job, 0, sizeof(job));
  job.value_count = value_count;
  job.frame_index = frame_index;
  job.time = time;
  job.frame_rate = frame_rate;
  job.scale = scale;
  anicel_fx_frame *frame = (anicel_fx_frame *)base;
  lay_frame_head(frame, &job);
  frame->values = (uint32_t)align16(sizeof(anicel_fx_frame));
  lay_values(base, frame->values, values, value_count);
}

// ── native ───────────────────────────────────────────────────────────────

static void *open_library(const char *path) {
#if defined(_WIN32)
  int wide = MultiByteToWideChar(CP_UTF8, 0, path, -1, NULL, 0);
  if (wide <= 0) {
    return NULL;
  }
  wchar_t *name = (wchar_t *)malloc((size_t)wide * sizeof(wchar_t));
  if (name == NULL) {
    return NULL;
  }
  MultiByteToWideChar(CP_UTF8, 0, path, -1, name, wide);
  // The plugin's own folder first, for what it brings beside it.
  HMODULE library =
      LoadLibraryExW(name, NULL, LOAD_WITH_ALTERED_SEARCH_PATH);
  free(name);
  return (void *)library;
#else
  return dlopen(path, RTLD_NOW | RTLD_LOCAL);
#endif
}

static void *find_symbol(void *library, const char *name) {
#if defined(_WIN32)
  return (void *)GetProcAddress((HMODULE)library, name);
#else
  return dlsym(library, name);
#endif
}

static void close_library(void *library) {
#if defined(_WIN32)
  FreeLibrary((HMODULE)library);
#else
  dlclose(library);
#endif
}

static int native_room(qa_fx_plugin *plugin, size_t size) {
  if (plugin->block_size >= size) {
    return 0;
  }
  uint8_t *grown = (uint8_t *)realloc(plugin->block, size);
  if (grown == NULL) {
    return -1;
  }
  plugin->block = grown;
  plugin->block_size = size;
  return 0;
}

QA_EXPORT void *qa_fx_plugin_open_native(const char *path, char *error,
                                         int32_t error_capacity) {
  if (path == NULL) {
    say(error, error_capacity, "no path");
    return NULL;
  }
  void *library = open_library(path);
  if (library == NULL) {
    say(error, error_capacity, "the library would not load");
    return NULL;
  }
  spec_fn spec = (spec_fn)find_symbol(library, "anicel_fx_spec");
  describe_fn describe =
      (describe_fn)find_symbol(library, "anicel_fx_describe");
  reach_fn reach = (reach_fn)find_symbol(library, "anicel_fx_reach");
  render_fn render = (render_fn)find_symbol(library, "anicel_fx_render");
  if (spec == NULL || describe == NULL || reach == NULL || render == NULL) {
    say(error, error_capacity, "the library exports no fx plugin");
    close_library(library);
    return NULL;
  }
  if (spec() != ANICEL_FX_SPEC_VERSION) {
    say(error, error_capacity, "the plugin speaks another spec version");
    close_library(library);
    return NULL;
  }
  qa_fx_plugin *plugin = (qa_fx_plugin *)calloc(1, sizeof(qa_fx_plugin));
  if (plugin == NULL) {
    say(error, error_capacity, "no memory");
    close_library(library);
    return NULL;
  }
  plugin->kind = KIND_NATIVE;
  plugin->library = library;
  plugin->describe = describe;
  plugin->reach = reach;
  plugin->render = render;
  return plugin;
}

static int32_t native_describe(qa_fx_plugin *plugin, char *out,
                               int32_t capacity) {
  return (int32_t)plugin->describe(out, (uint32_t)capacity);
}

static int32_t native_reach(qa_fx_plugin *plugin, const double *values,
                            int32_t value_count, int32_t frame_index,
                            double time, double frame_rate, double scale) {
  if (native_room(plugin, reach_block_size(value_count)) != 0) {
    return QA_FX_NO_ROOM;
  }
  lay_reach(plugin->block, values, value_count, frame_index, time,
            frame_rate, scale);
  return (int32_t)plugin->reach((const anicel_fx_frame *)plugin->block);
}

static int32_t native_render(qa_fx_plugin *plugin,
                             const qa_fx_render_job *job,
                             const block_plan *plan) {
  if (native_room(plugin, plan->total) != 0) {
    return QA_FX_NO_ROOM;
  }
  lay_block(plugin->block, plan, job);
  if (plugin->render((anicel_fx_frame *)plugin->block) != 0) {
    return QA_FX_FAILED;
  }
  take_output(plugin->block, plan, job);
  return QA_FX_OK;
}

// ── WebAssembly ──────────────────────────────────────────────────────────

#if QA_FX_WASM
static void say_wasm(char *error, int32_t capacity, const char *doing,
                     wasmtime_error_t *wasm_error, wasm_trap_t *trap) {
  wasm_byte_vec_t message;
  message.size = 0;
  message.data = NULL;
  if (wasm_error != NULL) {
    wasmtime_error_message(wasm_error, &message);
    wasmtime_error_delete(wasm_error);
  } else if (trap != NULL) {
    wasm_trap_message(trap, &message);
    wasm_trap_delete(trap);
  }
  if (error != NULL && capacity > 0) {
    snprintf(error, (size_t)capacity, "%s: %.*s", doing, (int)message.size,
             message.data == NULL ? "" : message.data);
  }
  wasm_byte_vec_delete(&message);
}

static int find_export(qa_fx_plugin *plugin, const char *name,
                       wasmtime_extern_kind_t kind, wasmtime_extern_t *out) {
  wasmtime_context_t *context = wasmtime_store_context(plugin->store);
  return wasmtime_instance_export_get(context, &plugin->instance, name,
                                      strlen(name), out) &&
                 out->kind == kind
             ? 0
             : -1;
}

static void close_wasm(qa_fx_plugin *plugin) {
  if (plugin->module != NULL) {
    wasmtime_module_delete(plugin->module);
  }
  if (plugin->linker != NULL) {
    wasmtime_linker_delete(plugin->linker);
  }
  if (plugin->store != NULL) {
    wasmtime_store_delete(plugin->store);
  }
  if (plugin->engine != NULL) {
    wasm_engine_delete(plugin->engine);
  }
}

// Calls [func] with i32 [args]; its one i32 result goes to [result].
static int32_t call_i32(qa_fx_plugin *plugin, const wasmtime_func_t *func,
                        const int32_t *args, size_t arg_count,
                        int32_t *result) {
  wasmtime_val_t in[2];
  wasmtime_val_t out;
  for (size_t i = 0; i < arg_count; i++) {
    in[i].kind = WASMTIME_I32;
    in[i].of.i32 = args[i];
  }
  wasm_trap_t *trap = NULL;
  wasmtime_context_t *context = wasmtime_store_context(plugin->store);
  wasmtime_error_t *wasm_error =
      wasmtime_func_call(context, func, in, arg_count, &out, 1, &trap);
  if (wasm_error != NULL || trap != NULL) {
    say_wasm(NULL, 0, "", wasm_error, trap);
    return QA_FX_TRAPPED;
  }
  if (out.kind != WASMTIME_I32) {
    return QA_FX_TRAPPED;
  }
  *result = out.of.i32;
  return QA_FX_OK;
}

static uint8_t *wasm_memory(qa_fx_plugin *plugin, size_t *size) {
  wasmtime_context_t *context = wasmtime_store_context(plugin->store);
  *size = wasmtime_memory_data_size(context, &plugin->memory);
  return wasmtime_memory_data(context, &plugin->memory);
}

// Room for [size] bytes in the module, from its allocator, kept for the
// next call.
static int wasm_room(qa_fx_plugin *plugin, uint32_t size) {
  if (plugin->wasm_block_size >= size) {
    return 0;
  }
  int32_t args[1] = {(int32_t)size};
  int32_t at = 0;
  if (call_i32(plugin, &plugin->f_alloc, args, 1, &at) != QA_FX_OK ||
      at == 0) {
    return -1;
  }
  size_t memory_size = 0;
  wasm_memory(plugin, &memory_size);
  if ((size_t)(uint32_t)at + size > memory_size) {
    return -1;
  }
  plugin->wasm_block = (uint32_t)at;
  plugin->wasm_block_size = size;
  return 0;
}

QA_EXPORT void *qa_fx_plugin_open_wasm(const uint8_t *bytes, int64_t length,
                                       char *error, int32_t error_capacity) {
  if (bytes == NULL || length <= 0) {
    say(error, error_capacity, "no module");
    return NULL;
  }
  qa_fx_plugin *plugin = (qa_fx_plugin *)calloc(1, sizeof(qa_fx_plugin));
  if (plugin == NULL) {
    say(error, error_capacity, "no memory");
    return NULL;
  }
  plugin->kind = KIND_WASM;
  plugin->engine = wasm_engine_new();
  plugin->store = wasmtime_store_new(plugin->engine, NULL, NULL);
  wasmtime_context_t *context = wasmtime_store_context(plugin->store);
  // WASI with nothing behind it — no folder, no network, no environment —
  // so a module built against WASI's libc runs, and reaches nothing
  // (I-132-Q5: 「앱은 샌드박스로 돌려 플러그인이 파일 · 네트워크를 못 건드린다」).
  wasmtime_error_t *wasm_error =
      wasmtime_context_set_wasi(context, wasi_config_new());
  if (wasm_error != NULL) {
    say_wasm(error, error_capacity, "WASI", wasm_error, NULL);
    close_wasm(plugin);
    free(plugin);
    return NULL;
  }
  plugin->linker = wasmtime_linker_new(plugin->engine);
  wasm_error = wasmtime_linker_define_wasi(plugin->linker);
  if (wasm_error == NULL) {
    wasm_error = wasmtime_module_new(plugin->engine, bytes, (size_t)length,
                                     &plugin->module);
  }
  wasm_trap_t *trap = NULL;
  if (wasm_error == NULL) {
    wasm_error = wasmtime_linker_instantiate(plugin->linker, context,
                                             plugin->module,
                                             &plugin->instance, &trap);
  }
  if (wasm_error != NULL || trap != NULL) {
    say_wasm(error, error_capacity, "the module would not start", wasm_error,
             trap);
    close_wasm(plugin);
    free(plugin);
    return NULL;
  }
  wasmtime_extern_t found;
  // A reactor module (WASI's libc) starts its runtime here.
  if (find_export(plugin, "_initialize", WASMTIME_EXTERN_FUNC, &found) == 0) {
    wasm_error =
        wasmtime_func_call(context, &found.of.func, NULL, 0, NULL, 0, &trap);
    if (wasm_error != NULL || trap != NULL) {
      say_wasm(error, error_capacity, "_initialize", wasm_error, trap);
      close_wasm(plugin);
      free(plugin);
      return NULL;
    }
  }
  wasmtime_extern_t spec;
  wasmtime_extern_t memory;
  wasmtime_extern_t describe;
  wasmtime_extern_t reach;
  wasmtime_extern_t render;
  wasmtime_extern_t alloc;
  if (find_export(plugin, "anicel_fx_spec", WASMTIME_EXTERN_FUNC, &spec) ||
      find_export(plugin, "memory", WASMTIME_EXTERN_MEMORY, &memory) ||
      find_export(plugin, "anicel_fx_describe", WASMTIME_EXTERN_FUNC,
                  &describe) ||
      find_export(plugin, "anicel_fx_reach", WASMTIME_EXTERN_FUNC, &reach) ||
      find_export(plugin, "anicel_fx_render", WASMTIME_EXTERN_FUNC,
                  &render) ||
      find_export(plugin, "anicel_fx_alloc", WASMTIME_EXTERN_FUNC, &alloc)) {
    say(error, error_capacity, "the module exports no fx plugin");
    close_wasm(plugin);
    free(plugin);
    return NULL;
  }
  plugin->memory = memory.of.memory;
  plugin->f_describe = describe.of.func;
  plugin->f_reach = reach.of.func;
  plugin->f_render = render.of.func;
  plugin->f_alloc = alloc.of.func;
  int32_t version = 0;
  if (call_i32(plugin, &spec.of.func, NULL, 0, &version) != QA_FX_OK ||
      (uint32_t)version != ANICEL_FX_SPEC_VERSION) {
    say(error, error_capacity, "the plugin speaks another spec version");
    close_wasm(plugin);
    free(plugin);
    return NULL;
  }
  return plugin;
}

static int32_t wasm_describe(qa_fx_plugin *plugin, char *out,
                             int32_t capacity) {
  if (wasm_room(plugin, (uint32_t)capacity) != 0) {
    return QA_FX_NO_ROOM;
  }
  int32_t args[2] = {(int32_t)plugin->wasm_block, capacity};
  int32_t length = 0;
  int32_t asked = call_i32(plugin, &plugin->f_describe, args, 2, &length);
  if (asked != QA_FX_OK) {
    return asked;
  }
  size_t memory_size = 0;
  uint8_t *memory = wasm_memory(plugin, &memory_size);
  int32_t written = length < capacity ? length : capacity;
  if (written > 0) {
    memcpy(out, memory + plugin->wasm_block, (size_t)written);
  }
  return length;
}

static int32_t wasm_reach(qa_fx_plugin *plugin, const double *values,
                          int32_t value_count, int32_t frame_index,
                          double time, double frame_rate, double scale) {
  if (wasm_room(plugin, (uint32_t)reach_block_size(value_count)) != 0) {
    return QA_FX_NO_ROOM;
  }
  size_t memory_size = 0;
  uint8_t *memory = wasm_memory(plugin, &memory_size);
  lay_reach(memory + plugin->wasm_block, values, value_count, frame_index,
            time, frame_rate, scale);
  int32_t args[1] = {(int32_t)plugin->wasm_block};
  int32_t reach = 0;
  int32_t asked = call_i32(plugin, &plugin->f_reach, args, 1, &reach);
  return asked == QA_FX_OK ? reach : asked;
}

static int32_t wasm_render(qa_fx_plugin *plugin, const qa_fx_render_job *job,
                           const block_plan *plan) {
  if (wasm_room(plugin, (uint32_t)plan->total) != 0) {
    return QA_FX_NO_ROOM;
  }
  size_t memory_size = 0;
  uint8_t *memory = wasm_memory(plugin, &memory_size);
  lay_block(memory + plugin->wasm_block, plan, job);
  int32_t args[1] = {(int32_t)plugin->wasm_block};
  int32_t answer = 0;
  int32_t asked = call_i32(plugin, &plugin->f_render, args, 1, &answer);
  if (asked != QA_FX_OK) {
    return asked;
  }
  if (answer != 0) {
    return QA_FX_FAILED;
  }
  // The render may have grown the memory: read its address again.
  memory = wasm_memory(plugin, &memory_size);
  take_output(memory + plugin->wasm_block, plan, job);
  return QA_FX_OK;
}
#else
QA_EXPORT void *qa_fx_plugin_open_wasm(const uint8_t *bytes, int64_t length,
                                       char *error, int32_t error_capacity) {
  (void)bytes;
  (void)length;
  say(error, error_capacity, "this build has no WebAssembly engine");
  return NULL;
}
#endif

// ── the four questions ───────────────────────────────────────────────────

// The description's length in bytes; up to [capacity] of it in [out].
QA_EXPORT int32_t qa_fx_plugin_describe(void *handle, char *out,
                                        int32_t capacity) {
  qa_fx_plugin *plugin = (qa_fx_plugin *)handle;
  if (plugin == NULL || out == NULL || capacity <= 0) {
    return QA_FX_BAD_JOB;
  }
#if QA_FX_WASM
  if (plugin->kind == KIND_WASM) {
    return wasm_describe(plugin, out, capacity);
  }
#endif
  return native_describe(plugin, out, capacity);
}

// How far past its input the effect reaches for these values, in pixels.
QA_EXPORT int32_t qa_fx_plugin_reach(void *handle, const double *values,
                                     int32_t value_count, int32_t frame_index,
                                     double time, double frame_rate,
                                     double scale) {
  qa_fx_plugin *plugin = (qa_fx_plugin *)handle;
  if (plugin == NULL || value_count < 0 ||
      (value_count > 0 && values == NULL)) {
    return QA_FX_BAD_JOB;
  }
#if QA_FX_WASM
  if (plugin->kind == KIND_WASM) {
    return wasm_reach(plugin, values, value_count, frame_index, time,
                      frame_rate, scale);
  }
#endif
  return native_reach(plugin, values, value_count, frame_index, time,
                      frame_rate, scale);
}

QA_EXPORT int32_t qa_fx_plugin_render(void *handle,
                                      const qa_fx_render_job *job) {
  qa_fx_plugin *plugin = (qa_fx_plugin *)handle;
  block_plan plan;
  if (plugin == NULL || !job_is_whole(job) || plan_block(job, &plan) != 0) {
    return QA_FX_BAD_JOB;
  }
#if QA_FX_WASM
  if (plugin->kind == KIND_WASM) {
    return wasm_render(plugin, job, &plan);
  }
#endif
  return native_render(plugin, job, &plan);
}

QA_EXPORT void qa_fx_plugin_close(void *handle) {
  qa_fx_plugin *plugin = (qa_fx_plugin *)handle;
  if (plugin == NULL) {
    return;
  }
#if QA_FX_WASM
  if (plugin->kind == KIND_WASM) {
    close_wasm(plugin);
  }
#endif
  if (plugin->library != NULL) {
    close_library(plugin->library);
  }
  free(plugin->block);
  free(plugin);
}

// The job's size as this build lays it, for the Dart struct that mirrors
// it (as `qa_dab_spec_sizeof` is).
QA_EXPORT int32_t qa_fx_render_job_sizeof(void) {
  return (int32_t)sizeof(qa_fx_render_job);
}

QA_EXPORT int32_t qa_fx_picture_sizeof(void) {
  return (int32_t)sizeof(qa_fx_picture);
}
