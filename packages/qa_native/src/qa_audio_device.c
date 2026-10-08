// The output device and the transport (audio program 2C).
//
// This is where "audio is the master clock" becomes literal. The device
// pulls buffers on its own realtime thread; each pull mixes the next span
// of samples and advances a counter. The playback position IS that counter
// — the number of samples handed to the device — so it cannot drift from
// what is being heard. A free-running timer can; that is the defect this
// program started from.
//
// NON-NEGOTIABLE: no Dart runs in the callback. Dart uploads the schedule
// and the PCM, starts and stops the transport, and polls the position.
// Everything the callback touches is already resident C memory.
//
// The schedule lives in TWO slots (AUDIO-PRO R3): the callback reads the
// active one, a replacement builds in the standby one, and an atomic flip
// publishes it - so editing sound DURING playback is heard on the next
// mixed block. The control thread then waits (bounded - it is not the
// realtime side) for the callback to acknowledge the new slot before
// freeing the old arrays; the callback itself never waits, never locks,
// never frees.

#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#if defined(_WIN32)
#define QA_EXPORT __declspec(dllexport)
#else
#define QA_EXPORT __attribute__((visibility("default")))
#endif

// No decoding (conforms are already PCM), no generation, no engine graph.
// Each of those is code we would ship and never run. Capture is NOT
// compiled out: recording (AUDIO-PRO R5) opens a second, independent
// capture device on the same context.
#define MA_NO_ENCODING
#define MA_NO_DECODING
#define MA_NO_GENERATION
#define MA_NO_RESOURCE_MANAGER
#define MA_NO_NODE_GRAPH
#define MA_NO_ENGINE
#define MA_IMPLEMENTATION
#include "third_party/miniaudio/miniaudio.h"

// The mixer's types live in qa_engine.c; declared here rather than shared
// through a header because the project keeps one portable C file per
// concern and no headers of its own.
typedef struct {
  double gain;
  double pan_left;
  double pan_right;
  int64_t start_sample;
  int64_t end_sample;
  int64_t source_offset;
  int64_t fade_in_samples;
  int64_t fade_out_samples;
  int32_t source_index;
  int32_t fade_curve;
  int32_t envelope_offset;
  int32_t envelope_count;
} qa_audio_clip;

typedef struct {
  int64_t source_start;
  int64_t length;
  int32_t channels;
  int32_t reserved;
  const float* samples;
} qa_audio_source;

typedef struct {
  int64_t sample;
  double gain;
} qa_audio_envelope_key;

extern void qa_audio_mix(const qa_audio_clip* clips,
                         int32_t clip_count,
                         const qa_audio_source* sources,
                         int32_t source_count,
                         const qa_audio_envelope_key* envelope_keys,
                         int32_t envelope_key_count,
                         int64_t start_sample,
                         int32_t sample_count,
                         int32_t out_channels,
                         double* out);

// The mixer's exported layout probes (same shared library) — the local
// struct copies above must stay byte-identical to qa_engine.c's, and this
// is checked at open() rather than trusted (Fable audit 2026-07-21).
extern int32_t qa_audio_clip_sizeof(void);
extern int32_t qa_audio_source_sizeof(void);
extern int32_t qa_audio_envelope_key_sizeof(void);

// Transport fields shared between the realtime callback and the control
// thread go through miniaudio's atomics (Fable audit 2026-07-21): aligned
// 64-bit loads happen to be atomic on our 64-bit targets, but the C
// memory model calls the unfenced mix a data race, and the seq-cst pair
// also orders play()'s position/stop writes BEFORE playing becomes
// visible to the callback on weakly-ordered ARM.
static int64_t qa_transport_load_64(volatile ma_uint64* field) {
  return (int64_t)ma_atomic_load_64(field);
}

static void qa_transport_store_64(volatile ma_uint64* field, int64_t value) {
  ma_atomic_store_64(field, (ma_uint64)value);
}

static int32_t qa_transport_load_32(volatile ma_uint32* field) {
  return (int32_t)ma_atomic_load_32(field);
}

static void qa_transport_store_32(volatile ma_uint32* field, int32_t value) {
  ma_atomic_store_32(field, (ma_uint32)value);
}

#if !defined(_WIN32)
#include <time.h>
#endif

// The monotonic clock both ends of the clock's line read: the callback when
// it stamps a point, the reader when it asks how long ago that was. Never
// the wall clock — that one is set, and a line drawn across a setting jumps.
// (Safe on the realtime thread: neither call locks or allocates.)
static int64_t qa_clock_now_us(void) {
#if defined(_WIN32)
  static LARGE_INTEGER frequency;
  LARGE_INTEGER counter;
  if (frequency.QuadPart == 0) {
    QueryPerformanceFrequency(&frequency);
  }
  QueryPerformanceCounter(&counter);
  // Whole seconds and the remainder apart: the product of the counter and
  // a million overflows 64 bits within hours of uptime.
  return (int64_t)(counter.QuadPart / frequency.QuadPart) * 1000000 +
         (int64_t)(counter.QuadPart % frequency.QuadPart) * 1000000 /
             frequency.QuadPart;
#else
  struct timespec now;
  clock_gettime(CLOCK_MONOTONIC, &now);
  return (int64_t)now.tv_sec * 1000000 + (int64_t)now.tv_nsec / 1000;
#endif
}

#define QA_DEVICE_MAX_BLOCK 8192

// One complete schedule: everything a mixed block reads (AUDIO-PRO R3
// made it a SLOT so a standby copy can build while the active one plays).
typedef struct {
  qa_audio_clip* clips;
  int32_t clip_count;
  qa_audio_source* sources;
  int32_t source_count;
  float* source_pcm;  // one owned block holding every source's samples
  int64_t source_pcm_floats;
  qa_audio_envelope_key* envelope_keys;  // the clips' shared key array
  int32_t envelope_key_count;
} qa_audio_schedule;

typedef struct {
  ma_device device;
  int32_t device_open;
  volatile ma_uint32 playing;

  // The transport. `position` counts samples HANDED TO THE DEVICE, which
  // is what makes it the clock: it advances only when audio actually
  // leaves, so it cannot run ahead of what is heard. Shared with the
  // realtime callback — every access goes through qa_transport_*.
  volatile ma_uint64 position;
  volatile ma_uint64 start_position;
  volatile ma_uint64 stop_position;  // exclusive; <= start means "no end"
  volatile ma_uint32 looping;

  // THE CLOCK'S LINE (2026-10-08). `position` is a STAIR: it climbs one
  // callback at a time, so read between two callbacks it says what was
  // handed at the last one — and the device has gone on playing since. A
  // picture that reads the stair changes its frame up to a step late, by a
  // different amount each frame (user: the late change is what bothers).
  //
  // So each callback also says WHEN it handed what it handed, and a reader
  // draws the line through the latest of those points: the samples handed
  // by then, plus the time gone by since at the device's rate. The line
  // meets the stair at every callback and does not fall behind between
  // them.
  //
  // `clock_serial` is the ARM (play, seek) the point belongs to. A callback
  // already in flight when the transport is armed again writes a point of
  // the old arm after the new one began; the reader drops a point whose
  // serial is not the transport's and reads the stair until the new arm's
  // first callback has spoken. A point with no time (0) is no point.
  //
  // One writer — the callback — and read whole through `clock_seq`: odd
  // while the three are being written, and a reader that saw it move reads
  // again.
  volatile ma_uint32 arm_serial;
  volatile ma_uint32 clock_seq;
  volatile ma_uint32 clock_serial;
  volatile ma_uint64 clock_position;
  volatile ma_uint64 clock_time_us;

  // The double-buffered schedule (AUDIO-PRO R3): the callback reads
  // slots[active_slot] and acknowledges through callback_slot; a live
  // replacement builds in the OTHER slot and flips. The old slot frees
  // only after the acknowledgment (or with the transport stopped).
  qa_audio_schedule slots[2];
  volatile ma_uint32 active_slot;
  volatile ma_uint32 callback_slot;
  // 1 while the callback body runs. With callback_slot this is what lets
  // the control thread PROVE the old slot is abandoned before freeing —
  // including the pre-R3 window where a stop lands mid-block and the
  // callback keeps reading the arrays until its block completes.
  volatile ma_uint32 callback_in_flight;

  // The last mixed block's PRE-CLIP bus peak per output side (float bits,
  // stored atomically) - the level meter's feed (AUDIO-PRO R2). Pre-clip
  // on purpose: a peak past 1.0 is exactly the "why does it sound
  // squashed" answer the meter exists to make visible.
  volatile ma_uint32 peak_left_bits;
  volatile ma_uint32 peak_right_bits;

  int32_t channels;
  int32_t sample_rate;
  double* scratch;  // the mix bus, sized once at open
} qa_audio_device_state;

static qa_audio_device_state g_audio;

// The callback's last word: what it has handed, when it was asked for it,
// and under which arm.
static void qa_audio_stamp_clock(ma_uint32 serial,
                                 int64_t position,
                                 int64_t time_us) {
  const ma_uint32 seq = ma_atomic_load_32(&g_audio.clock_seq);
  ma_atomic_store_32(&g_audio.clock_seq, seq + 1);
  ma_atomic_store_32(&g_audio.clock_serial, serial);
  ma_atomic_store_64(&g_audio.clock_position, (ma_uint64)position);
  ma_atomic_store_64(&g_audio.clock_time_us, (ma_uint64)time_us);
  ma_atomic_store_32(&g_audio.clock_seq, seq + 2);
}

// A new arm: the points written under the old one are no longer the
// transport's. Called by the control thread alone, with the callback
// silenced (play) or about to read a moved position (seek).
static void qa_audio_begin_arm(void) {
  ma_atomic_store_32(&g_audio.arm_serial,
                     ma_atomic_load_32(&g_audio.arm_serial) + 1);
}

// The context outlives devices (AUDIO-PRO R4): enumeration and open-by-
// index both need one, and re-creating it per open would re-probe the
// whole OS audio stack. 0 = none, 1 = default backends, 2 = null backend.
static ma_context g_context;
static int32_t g_context_kind;
static ma_device_info* g_playback_infos;
static ma_uint32 g_playback_count;
static ma_device_info* g_capture_infos;
static ma_uint32 g_capture_count;

static int qa_audio_ensure_context(int32_t backend) {
  const int32_t want = backend == 1 ? 2 : 1;
  if (g_context_kind == want) {
    return 1;
  }
  // Never yank the context out from under an open device.
  if (g_audio.device_open) {
    return g_context_kind != 0;
  }
  if (g_context_kind != 0) {
    ma_context_uninit(&g_context);
    g_context_kind = 0;
    g_playback_infos = NULL;
    g_playback_count = 0;
    g_capture_infos = NULL;
    g_capture_count = 0;
  }
  if (backend == 1) {
    ma_backend backends[1];
    backends[0] = ma_backend_null;
    if (ma_context_init(backends, 1, NULL, &g_context) != MA_SUCCESS) {
      return 0;
    }
  } else {
    // F-190 (user 2026-09-27: a Bluetooth headset plays every other app,
    // and this one out of the speaker). iOS keeps ONE audio session per
    // app, and the default config set it to PlayAndRecord (the voice take
    // needs the input) with DefaultToSpeaker and no Bluetooth — under
    // PlayAndRecord a headset is an allowed output only when the session
    // says AllowBluetoothA2DP, so everything went to the speaker. The
    // category stays; the options let the headset in. Only Apple's mobile
    // backend reads them: elsewhere this is the default config, and those
    // backends already follow the system's default device.
    ma_context_config config = ma_context_config_init();
    config.coreaudio.sessionCategory = ma_ios_session_category_play_and_record;
    config.coreaudio.sessionCategoryOptions =
        ma_ios_session_category_option_default_to_speaker |
        ma_ios_session_category_option_allow_bluetooth_a2dp;
    if (ma_context_init(NULL, 0, &config, &g_context) != MA_SUCCESS) {
      return 0;
    }
  }
  g_context_kind = want;
  return 1;
}

static int qa_audio_refresh_devices(void) {
  return ma_context_get_devices(&g_context, &g_playback_infos,
                                &g_playback_count, &g_capture_infos,
                                &g_capture_count) == MA_SUCCESS;
}

// Enumerates and returns how many devices [kind] has (0 = playback,
// 1 = capture), or -1 when the context cannot come up. Refreshes the
// cached list — call before qa_audio_device_describe.
QA_EXPORT int32_t qa_audio_device_count(int32_t kind, int32_t backend) {
  if (!qa_audio_ensure_context(backend)) {
    return -1;
  }
  if (!qa_audio_refresh_devices()) {
    return -1;
  }
  return (int32_t)(kind == 1 ? g_capture_count : g_playback_count);
}

// Copies device [index]'s UTF-8 name into [out_name] (NUL-terminated)
// and reports whether it is the system default. Returns the name's byte
// length, or -1 for a bad index/capacity. Reads the list the last
// qa_audio_device_count call cached.
QA_EXPORT int32_t qa_audio_device_describe(int32_t kind,
                                           int32_t index,
                                           char* out_name,
                                           int32_t capacity,
                                           int32_t* out_is_default) {
  const ma_device_info* infos = kind == 1 ? g_capture_infos : g_playback_infos;
  const ma_uint32 count = kind == 1 ? g_capture_count : g_playback_count;
  if (infos == NULL || index < 0 || (ma_uint32)index >= count ||
      out_name == NULL || capacity <= 1) {
    return -1;
  }
  const char* name = infos[index].name;
  int32_t length = 0;
  while (name[length] != '\0' && length < capacity - 1) {
    out_name[length] = name[length];
    length += 1;
  }
  out_name[length] = '\0';
  if (out_is_default != NULL) {
    *out_is_default = infos[index].isDefault ? 1 : 0;
  }
  return length;
}

// The realtime callback. memcpy and a weighted sum, nothing else: no
// allocation, no locks, no I/O, no Dart.
static void qa_audio_data_callback(ma_device* device,
                                   void* output,
                                   const void* input,
                                   ma_uint32 frame_count) {
  (void)device;
  (void)input;
  float* out = (float*)output;
  const int32_t channels = g_audio.channels;
  const size_t total = (size_t)frame_count * (size_t)channels;
  memset(out, 0, total * sizeof(float));

  // The arm BEFORE the look at `playing`: a callback that saw the old arm
  // and then finds a transport armed again stamps its point with the old
  // serial, and the reader drops it.
  const ma_uint32 arm = ma_atomic_load_32(&g_audio.arm_serial);
  const int64_t asked_at_us = qa_clock_now_us();
  if (!qa_transport_load_32(&g_audio.playing) || g_audio.scratch == NULL) {
    return;
  }
  // Everything below reads schedule arrays: bracketed by in_flight so the
  // control thread can wait out a block instead of freeing under it.
  qa_transport_store_32(&g_audio.callback_in_flight, 1);

  ma_uint32 done = 0;
  while (done < frame_count) {
    ma_uint32 block = frame_count - done;
    if (block > QA_DEVICE_MAX_BLOCK) {
      block = QA_DEVICE_MAX_BLOCK;
    }

    const int64_t start_position = qa_transport_load_64(&g_audio.start_position);
    const int64_t stop_position = qa_transport_load_64(&g_audio.stop_position);
    int64_t position = qa_transport_load_64(&g_audio.position);
    if (stop_position > start_position && position >= stop_position) {
      if (qa_transport_load_32(&g_audio.looping)) {
        position = start_position;
        qa_transport_store_64(&g_audio.position, position);
      } else {
        qa_transport_store_32(&g_audio.playing, 0);
        qa_transport_store_32(&g_audio.callback_in_flight, 0);
        return;
      }
    }
    // Never mix past the stop point in one block; the wrap has to land on
    // the sample, not the buffer boundary.
    if (stop_position > start_position) {
      const int64_t remaining = stop_position - position;
      if ((int64_t)block > remaining) {
        block = (ma_uint32)remaining;
      }
    }
    if (block == 0) {
      qa_transport_store_32(&g_audio.callback_in_flight, 0);
      return;
    }

    // Which schedule this block reads, acknowledged BEFORE mixing so the
    // control thread can prove the old slot has been abandoned.
    const ma_uint32 slot_index =
        (ma_uint32)qa_transport_load_32(&g_audio.active_slot) & 1u;
    qa_transport_store_32(&g_audio.callback_slot, (int32_t)slot_index);
    const qa_audio_schedule* schedule = &g_audio.slots[slot_index];

    qa_audio_mix(schedule->clips, schedule->clip_count, schedule->sources,
                 schedule->source_count, schedule->envelope_keys,
                 schedule->envelope_key_count, position, (int32_t)block,
                 channels, g_audio.scratch);

    const size_t written = (size_t)block * (size_t)channels;
    float* target = out + (size_t)done * (size_t)channels;
    double peak_left = 0.0;
    double peak_right = 0.0;
    for (size_t index = 0; index < written; index += 1) {
      double value = g_audio.scratch[index];
      // Meter feed BEFORE the clamp: the peak that matters is the one the
      // bus actually reached.
      const double magnitude = value < 0.0 ? -value : value;
      if (channels == 1 || (index % (size_t)channels) == 0) {
        if (magnitude > peak_left) {
          peak_left = magnitude;
        }
      } else if ((index % (size_t)channels) == 1) {
        if (magnitude > peak_right) {
          peak_right = magnitude;
        }
      }
      // The bus has headroom; the DEVICE does not. Clipping belongs here,
      // at the boundary, exactly as it does for the int16 path.
      if (value > 1.0) {
        value = 1.0;
      } else if (value < -1.0) {
        value = -1.0;
      }
      target[index] = (float)value;
    }
    {
      const float left = (float)peak_left;
      const float right = (float)(channels == 1 ? peak_left : peak_right);
      ma_uint32 left_bits;
      ma_uint32 right_bits;
      memcpy(&left_bits, &left, sizeof(left_bits));
      memcpy(&right_bits, &right, sizeof(right_bits));
      qa_transport_store_32(&g_audio.peak_left_bits, (int32_t)left_bits);
      qa_transport_store_32(&g_audio.peak_right_bits, (int32_t)right_bits);
    }

    qa_transport_store_64(&g_audio.position, position + (int64_t)block);
    done += block;
  }
  qa_audio_stamp_clock(arm, qa_transport_load_64(&g_audio.position),
                       asked_at_us);
  qa_transport_store_32(&g_audio.callback_in_flight, 0);
}

static void qa_audio_free_slot(qa_audio_schedule* slot) {
  free(slot->clips);
  free(slot->sources);
  free(slot->source_pcm);
  free(slot->envelope_keys);
  memset(slot, 0, sizeof(*slot));
}

static void qa_audio_free_schedule(void) {
  qa_audio_free_slot(&g_audio.slots[0]);
  qa_audio_free_slot(&g_audio.slots[1]);
}

// Opens the output device. [backend] 0 = let miniaudio choose, 1 = the
// NULL backend, which runs the real callback on a real thread with no
// hardware — how the transport is tested on a CI runner with no sound card.
// [device_index] picks from the last enumeration (AUDIO-PRO R4); -1 = the
// system default. A stale or bad index FAILS rather than silently opening
// something else — the caller's fallback to default is an informed one.
//
// Returns the device's actual sample rate, or 0 on failure. The rate is
// returned rather than assumed because a device may refuse the one asked
// for, and conforming to the wrong rate would put every sound at the wrong
// speed.
QA_EXPORT int32_t qa_audio_device_open(int32_t sample_rate,
                                       int32_t channels,
                                       int32_t backend,
                                       int32_t device_index) {
  if (g_audio.device_open) {
    return g_audio.sample_rate;
  }
  if (sample_rate <= 0 || channels <= 0 || channels > 8) {
    return 0;
  }
  // The struct copies at the top of this file must stay byte-identical
  // to qa_engine.c's originals — checked, not trusted (both TUs link
  // into the one shared library, so the probes are callable here).
  if (qa_audio_clip_sizeof() != (int32_t)sizeof(qa_audio_clip) ||
      qa_audio_source_sizeof() != (int32_t)sizeof(qa_audio_source) ||
      qa_audio_envelope_key_sizeof() !=
          (int32_t)sizeof(qa_audio_envelope_key)) {
    return 0;
  }
  if (!qa_audio_ensure_context(backend)) {
    return 0;
  }

  ma_device_config config = ma_device_config_init(ma_device_type_playback);
  config.playback.format = ma_format_f32;
  config.playback.channels = (ma_uint32)channels;
  config.sampleRate = (ma_uint32)sample_rate;
  config.dataCallback = qa_audio_data_callback;
  if (device_index >= 0) {
    if (!qa_audio_refresh_devices() ||
        (ma_uint32)device_index >= g_playback_count) {
      return 0;
    }
    config.playback.pDeviceID = &g_playback_infos[device_index].id;
  }

  const ma_result result =
      ma_device_init(&g_context, &config, &g_audio.device);
  if (result != MA_SUCCESS) {
    return 0;
  }

  g_audio.channels = (int32_t)g_audio.device.playback.channels;
  g_audio.sample_rate = (int32_t)g_audio.device.sampleRate;
  g_audio.scratch = (double*)malloc((size_t)QA_DEVICE_MAX_BLOCK *
                                    (size_t)g_audio.channels * sizeof(double));
  if (g_audio.scratch == NULL) {
    ma_device_uninit(&g_audio.device);
    return 0;
  }
  g_audio.device_open = 1;
  qa_transport_store_32(&g_audio.playing, 0);
  qa_transport_store_64(&g_audio.position, 0);
  // A device just opened has no run: whatever the one before it left is
  // not its point.
  qa_audio_begin_arm();

  if (ma_device_start(&g_audio.device) != MA_SUCCESS) {
    free(g_audio.scratch);
    g_audio.scratch = NULL;
    ma_device_uninit(&g_audio.device);
    g_audio.device_open = 0;
    return 0;
  }
  return g_audio.sample_rate;
}

QA_EXPORT void qa_audio_device_close(void) {
  if (!g_audio.device_open) {
    return;
  }
  qa_transport_store_32(&g_audio.playing, 0);
  ma_device_uninit(&g_audio.device);
  free(g_audio.scratch);
  g_audio.scratch = NULL;
  qa_audio_free_schedule();
  g_audio.device_open = 0;
}

QA_EXPORT int32_t qa_audio_device_is_open(void) { return g_audio.device_open; }
QA_EXPORT int32_t qa_audio_device_sample_rate(void) { return g_audio.sample_rate; }
QA_EXPORT int32_t qa_audio_device_channels(void) { return g_audio.channels; }

// The device's own reported output latency in samples — what the picture
// has to be pulled forward by so it matches what is being heard. Whatever
// this cannot account for is the residual the user's A/V offset removes.
QA_EXPORT int64_t qa_audio_device_latency_samples(void) {
  if (!g_audio.device_open) {
    return 0;
  }
  return (int64_t)g_audio.device.playback.internalPeriodSizeInFrames *
         (int64_t)g_audio.device.playback.internalPeriods;
}

// Replaces the schedule — legal at ANY time (AUDIO-PRO R3). Stopped, it
// writes the active slot directly; playing, it builds in the standby
// slot, flips atomically (the callback adopts at its next block, so the
// edit is heard within one mix block), then waits — bounded, on THIS
// thread, never the realtime one — for the acknowledgment before freeing
// the old arrays.
//
// The PCM is COPIED into one owned block: the callback must never chase a
// pointer into Dart-managed memory that could move or be collected.
QA_EXPORT int32_t qa_audio_device_set_schedule(
    const qa_audio_clip* clips,
    int32_t clip_count,
    const qa_audio_source* sources,
    int32_t source_count,
    const float* pcm,
    int64_t pcm_floats,
    const int64_t* source_offsets,
    const qa_audio_envelope_key* envelope_keys,
    int32_t envelope_key_count) {
  if (clip_count < 0 || source_count < 0 || pcm_floats < 0 ||
      envelope_key_count < 0) {
    return 0;
  }

  // ALWAYS build into the standby slot and flip — even stopped, a
  // just-stopped callback can be mid-block in the active arrays for
  // another ~10ms, and the in-flight handshake below is what makes the
  // free provably safe in every case.
  const ma_uint32 active =
      (ma_uint32)qa_transport_load_32(&g_audio.active_slot) & 1u;
  const ma_uint32 target = active ^ 1u;
  qa_audio_schedule* slot = &g_audio.slots[target];
  // A previous bounded wait may have bailed and left this standby slot
  // allocated; freeing here is what makes that leak self-healing.
  qa_audio_free_slot(slot);

  if (clip_count > 0) {
    slot->clips =
        (qa_audio_clip*)malloc((size_t)clip_count * sizeof(qa_audio_clip));
    if (slot->clips == NULL) {
      return 0;
    }
    memcpy(slot->clips, clips, (size_t)clip_count * sizeof(qa_audio_clip));
    slot->clip_count = clip_count;
  }

  if (envelope_key_count > 0) {
    slot->envelope_keys = (qa_audio_envelope_key*)malloc(
        (size_t)envelope_key_count * sizeof(qa_audio_envelope_key));
    if (slot->envelope_keys == NULL) {
      qa_audio_free_slot(slot);
      return 0;
    }
    memcpy(slot->envelope_keys, envelope_keys,
           (size_t)envelope_key_count * sizeof(qa_audio_envelope_key));
    slot->envelope_key_count = envelope_key_count;
  }

  if (pcm_floats > 0) {
    slot->source_pcm = (float*)malloc((size_t)pcm_floats * sizeof(float));
    if (slot->source_pcm == NULL) {
      qa_audio_free_slot(slot);
      return 0;
    }
    memcpy(slot->source_pcm, pcm, (size_t)pcm_floats * sizeof(float));
    slot->source_pcm_floats = pcm_floats;
  }

  if (source_count > 0) {
    slot->sources =
        (qa_audio_source*)malloc((size_t)source_count * sizeof(qa_audio_source));
    if (slot->sources == NULL) {
      qa_audio_free_slot(slot);
      return 0;
    }
    memcpy(slot->sources, sources,
           (size_t)source_count * sizeof(qa_audio_source));
    // Repoint every source at our copy: the caller's `samples` pointers
    // describe ITS memory, and the offsets say where each block landed in
    // the flattened PCM.
    for (int32_t index = 0; index < source_count; index += 1) {
      const int64_t offset = source_offsets == NULL ? 0 : source_offsets[index];
      slot->sources[index].samples =
          (offset >= 0 && offset < pcm_floats) ? slot->source_pcm + offset
                                               : NULL;
    }
    slot->source_count = source_count;
  }

  // Publish, then prove the handoff before freeing the old arrays: the
  // old slot is abandoned once the callback either stamped the NEW slot
  // (it re-reads active_slot per block) or is simply not running
  // (in_flight 0 — covers stopped transports AND the just-stopped
  // mid-block window). Bounded wait on THIS thread, never the realtime
  // one; a stalled device thread leaves the old slot for the next swap's
  // self-healing free rather than risking a use-after-free.
  qa_transport_store_32(&g_audio.active_slot, (int32_t)target);
  for (int spin = 0; spin < 500; spin += 1) {
    const int in_flight = qa_transport_load_32(&g_audio.callback_in_flight);
    const ma_uint32 stamped =
        (ma_uint32)qa_transport_load_32(&g_audio.callback_slot) & 1u;
    if (!in_flight || stamped == target) {
      qa_audio_free_slot(&g_audio.slots[active]);
      break;
    }
    ma_sleep(1);
  }
  return 1;
}

// Starts playback at [start_sample]. [stop_sample] is exclusive; pass a
// value at or below the start for "no end".
QA_EXPORT int32_t qa_audio_device_play(int64_t start_sample,
                                       int64_t stop_sample,
                                       int32_t looping) {
  if (!g_audio.device_open) {
    return 0;
  }
  // A restart while audible: silence the callback FIRST so it never mixes
  // with a half-updated transport, then publish the fields, then arm. The
  // seq-cst stores double as the release fence playing needs on ARM.
  qa_transport_store_32(&g_audio.playing, 0);
  qa_audio_begin_arm();
  qa_transport_store_64(&g_audio.position, start_sample);
  qa_transport_store_64(&g_audio.start_position, start_sample);
  qa_transport_store_64(&g_audio.stop_position, stop_sample);
  qa_transport_store_32(&g_audio.looping, looping ? 1 : 0);
  qa_transport_store_32(&g_audio.playing, 1);
  return 1;
}

// The last mixed block's PRE-CLIP bus peak for [channel] (0 = left,
// 1 = right; a mono device mirrors left) - the level meter's read
// (AUDIO-PRO R2). >1.0 means the output stage is clipping.
QA_EXPORT double qa_audio_device_peak(int32_t channel) {
  const int32_t bits = qa_transport_load_32(
      channel == 1 ? &g_audio.peak_right_bits : &g_audio.peak_left_bits);
  float value;
  ma_uint32 raw = (ma_uint32)bits;
  memcpy(&value, &raw, sizeof(value));
  return (double)value;
}

QA_EXPORT void qa_audio_device_stop(void) {
  qa_transport_store_32(&g_audio.playing, 0);
  // The run is over, and its points with it. (A device that runs OUT by
  // itself is not stopped here: its last point stands, and the line runs
  // on through what its buffer still holds.)
  qa_audio_begin_arm();
  // A stopped transport meters silence - the bars must not freeze at the
  // last audible block.
  qa_transport_store_32(&g_audio.peak_left_bits, 0);
  qa_transport_store_32(&g_audio.peak_right_bits, 0);
}

QA_EXPORT int32_t qa_audio_device_is_playing(void) {
  return qa_transport_load_32(&g_audio.playing);
}

// Samples handed to the device so far — THE clock. The picture reads this
// and shows whatever frame it lands in; if rendering fell behind, frames
// are dropped rather than the sound being made to wait.
QA_EXPORT int64_t qa_audio_device_position(void) {
  return qa_transport_load_64(&g_audio.position);
}

// Moves the transport without restarting anything: because the mixer
// builds a mix rather than starting clips, seeking is just changing where
// the next block is read from. A seek racing an in-flight callback block
// can lose to that block's own position advance — a bounded, few-ms
// staleness the next seek or block absorbs; the atomic store only rules
// out torn values.
QA_EXPORT void qa_audio_device_seek(int64_t sample) {
  qa_audio_begin_arm();
  qa_transport_store_64(&g_audio.position, sample);
}

// The latest point of the clock's line, for the arm the transport is in:
// out2[0] = the samples handed when that callback returned, out2[1] = when
// it was asked for them, on qa_audio_clock_now_us's clock. 0 = no callback
// has spoken since the transport was last armed: there is only the stair
// (qa_audio_device_position) to read.
QA_EXPORT int32_t qa_audio_device_clock(int64_t* out2) {
  if (out2 == NULL) {
    return 0;
  }
  for (int attempt = 0; attempt < 16; attempt += 1) {
    const ma_uint32 before = ma_atomic_load_32(&g_audio.clock_seq);
    if (before & 1u) {
      continue;
    }
    const ma_uint32 serial = ma_atomic_load_32(&g_audio.clock_serial);
    const int64_t position =
        (int64_t)ma_atomic_load_64(&g_audio.clock_position);
    const int64_t time_us = (int64_t)ma_atomic_load_64(&g_audio.clock_time_us);
    if (ma_atomic_load_32(&g_audio.clock_seq) != before) {
      continue;
    }
    if (time_us == 0 || serial != ma_atomic_load_32(&g_audio.arm_serial)) {
      return 0;
    }
    out2[0] = position;
    out2[1] = time_us;
    return 1;
  }
  return 0;
}

// The time now on the clock the line's points are stamped with.
QA_EXPORT int64_t qa_audio_clock_now_us(void) {
  return qa_clock_now_us();
}

// ---------------------------------------------------------------------------
// Capture (AUDIO-PRO R5): the guide-voice recorder's device side.
//
// A second, independent device on the same context — playback is never
// touched, which is what lets recording run DURING playback (the guide
// voice use case: watch the cut, speak the line).
//
// The realtime rule holds on this side too: the capture callback only
// copies into a preallocated ring. Dart drains the ring from a control-
// thread timer; if it ever falls behind the ring absorbs seconds of it,
// and a true overflow is COUNTED rather than hidden — a recording with
// dropped frames must say so, not play back subtly shorter.

// Seconds of audio the ring holds. Dart drains every few tens of ms; this
// is three orders of magnitude of slack, sized in samples at open.
#define QA_CAPTURE_RING_SECONDS 8

typedef struct {
  ma_device device;
  int32_t open;
  int32_t channels;
  int32_t sample_rate;
  float* ring;             // ring_capacity floats, written by the callback
  int64_t ring_capacity;   // in floats; always a whole number of frames
  // Monotonic totals in floats — never wrapped, so available space and
  // data are plain subtractions. Written on one side each (SPSC).
  volatile ma_uint64 write_total;
  volatile ma_uint64 read_total;
  volatile ma_uint64 dropped_frames;
} qa_capture_state;

static qa_capture_state g_capture;

static void qa_audio_capture_callback(ma_device* device,
                                      void* output,
                                      const void* input,
                                      ma_uint32 frame_count) {
  (void)device;
  (void)output;
  if (input == NULL || g_capture.ring == NULL) {
    return;
  }
  const float* in = (const float*)input;
  const int64_t channels = (int64_t)g_capture.channels;
  int64_t floats = (int64_t)frame_count * channels;

  const int64_t written = (int64_t)ma_atomic_load_64(&g_capture.write_total);
  const int64_t read = (int64_t)ma_atomic_load_64(&g_capture.read_total);
  const int64_t space = g_capture.ring_capacity - (written - read);
  if (floats > space) {
    // Whole frames only: a partial frame in the ring would shift every
    // later sample by a channel and turn the take into garbage.
    const int64_t keep_frames = space / channels;
    const int64_t drop = frame_count - keep_frames;
    ma_atomic_store_64(&g_capture.dropped_frames,
                       (ma_uint64)((int64_t)ma_atomic_load_64(
                                       &g_capture.dropped_frames) +
                                   drop));
    floats = keep_frames * channels;
  }
  int64_t offset = written % g_capture.ring_capacity;
  int64_t first = g_capture.ring_capacity - offset;
  if (first > floats) {
    first = floats;
  }
  memcpy(g_capture.ring + offset, in, (size_t)first * sizeof(float));
  if (floats > first) {
    memcpy(g_capture.ring, in + first,
           (size_t)(floats - first) * sizeof(float));
  }
  // Publish AFTER the copy: the reader must never see an index that
  // covers bytes still being written.
  ma_atomic_store_64(&g_capture.write_total, (ma_uint64)(written + floats));
}

// Opens the capture device and starts delivering into the ring.
// [sample_rate] is the project rate — miniaudio converts from the device's
// native rate, so what lands in the ring needs no conform. Channels are
// whatever the device natively has (a mono mic records mono; a stereo
// interface records stereo) — read qa_audio_capture_channels after open.
// [device_index] follows the R4 contract: -1 = system default, a bad index
// FAILS rather than opening something else.
//
// Returns the delivered sample rate (== sample_rate) or 0 on failure —
// which on macOS/iOS/Android includes "no microphone permission".
QA_EXPORT int32_t qa_audio_capture_start(int32_t sample_rate,
                                         int32_t backend,
                                         int32_t device_index) {
  if (g_capture.open || sample_rate <= 0) {
    return 0;
  }
  if (!qa_audio_ensure_context(backend)) {
    return 0;
  }

  ma_device_config config = ma_device_config_init(ma_device_type_capture);
  config.capture.format = ma_format_f32;
  config.capture.channels = 0;  // 0 = the device's native channel count
  config.sampleRate = (ma_uint32)sample_rate;
  config.dataCallback = qa_audio_capture_callback;
  if (device_index >= 0) {
    if (!qa_audio_refresh_devices() ||
        (ma_uint32)device_index >= g_capture_count) {
      return 0;
    }
    config.capture.pDeviceID = &g_capture_infos[device_index].id;
  }

  if (ma_device_init(&g_context, &config, &g_capture.device) != MA_SUCCESS) {
    return 0;
  }
  g_capture.channels = (int32_t)g_capture.device.capture.channels;
  g_capture.sample_rate = (int32_t)g_capture.device.sampleRate;
  g_capture.ring_capacity = (int64_t)g_capture.sample_rate *
                            (int64_t)g_capture.channels *
                            QA_CAPTURE_RING_SECONDS;
  g_capture.ring =
      (float*)malloc((size_t)g_capture.ring_capacity * sizeof(float));
  if (g_capture.ring == NULL) {
    ma_device_uninit(&g_capture.device);
    return 0;
  }
  ma_atomic_store_64(&g_capture.write_total, 0);
  ma_atomic_store_64(&g_capture.read_total, 0);
  ma_atomic_store_64(&g_capture.dropped_frames, 0);
  // Open BEFORE start: the callback checks ring != NULL, and start makes
  // it live immediately.
  g_capture.open = 1;
  if (ma_device_start(&g_capture.device) != MA_SUCCESS) {
    g_capture.open = 0;
    ma_device_uninit(&g_capture.device);
    free(g_capture.ring);
    g_capture.ring = NULL;
    return 0;
  }
  return g_capture.sample_rate;
}

// Drains up to [max_floats] from the ring into [out]; returns how many
// floats were copied. Control thread only — this is the far end of the
// SPSC ring, never the callback's.
QA_EXPORT int32_t qa_audio_capture_read(float* out, int32_t max_floats) {
  if (!g_capture.open || out == NULL || max_floats <= 0) {
    return 0;
  }
  const int64_t written = (int64_t)ma_atomic_load_64(&g_capture.write_total);
  const int64_t read = (int64_t)ma_atomic_load_64(&g_capture.read_total);
  int64_t available = written - read;
  if (available > max_floats) {
    available = max_floats;
  }
  if (available <= 0) {
    return 0;
  }
  int64_t offset = read % g_capture.ring_capacity;
  int64_t first = g_capture.ring_capacity - offset;
  if (first > available) {
    first = available;
  }
  memcpy(out, g_capture.ring + offset, (size_t)first * sizeof(float));
  if (available > first) {
    memcpy(out + first, g_capture.ring,
           (size_t)(available - first) * sizeof(float));
  }
  ma_atomic_store_64(&g_capture.read_total, (ma_uint64)(read + available));
  return (int32_t)available;
}

// Stops the device. ma_device_uninit joins the device thread, so after it
// returns the callback cannot be running — freeing the ring is safe.
// Call qa_audio_capture_read for the tail BEFORE stopping.
QA_EXPORT void qa_audio_capture_stop(void) {
  if (!g_capture.open) {
    return;
  }
  ma_device_uninit(&g_capture.device);
  free(g_capture.ring);
  g_capture.ring = NULL;
  g_capture.open = 0;
}

QA_EXPORT int32_t qa_audio_capture_is_open(void) { return g_capture.open; }
QA_EXPORT int32_t qa_audio_capture_channels(void) { return g_capture.channels; }
QA_EXPORT int32_t qa_audio_capture_sample_rate(void) {
  return g_capture.sample_rate;
}

// Frames the ring had to drop because the reader fell behind. Nonzero
// means the take is DAMAGED — the recorder must tell the user, not save
// a silently shortened file.
QA_EXPORT int64_t qa_audio_capture_dropped_frames(void) {
  return (int64_t)ma_atomic_load_64(&g_capture.dropped_frames);
}

// The capture path's own buffering, in samples — how far behind "now" the
// newest delivered sample is. Small (typically 10-30 ms) and NOT applied
// automatically; the recorder decides what alignment means.
QA_EXPORT int64_t qa_audio_capture_latency_samples(void) {
  if (!g_capture.open) {
    return 0;
  }
  return (int64_t)g_capture.device.capture.internalPeriodSizeInFrames *
         (int64_t)g_capture.device.capture.internalPeriods;
}
