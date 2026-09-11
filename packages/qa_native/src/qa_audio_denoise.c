// Voice-take noise suppression (recording program, RNNoise round).
//
// One exported call denoises a finished take in place. It is NOT a
// realtime stage: the capture thread never comes here — the session
// runs it once at stop, between the head trim and the gain bake, so a
// slow machine costs a beat after ⏺, never a dropped buffer.
//
// Single-TU bundle, the qa_audio_decode.c/dr_libs pattern: the vendored
// RNNoise sources compile HERE and nowhere else, so their warnings and
// their ~430 KB model table stay out of every other object file. We do
// not edit those files (third_party/rnnoise/PROVENANCE.md — updates
// must stay a straight overwrite at a pinned tag).
//
// RNNoise's contract, which this wrapper owns completely:
// - 48 kHz only. Any other rate returns 0 and touches nothing — the
//   Dart side either captured at 48 kHz on purpose or must skip.
// - Frames of 480 samples, mono, in 16-bit RANGE floats (±32768).
//   Our takes are ±1.0 interleaved float32, so the wrapper scales in,
//   deinterleaves per channel (one DenoiseState each — the model is
//   stateful), pads the tail frame with zeros, and scales back out.

// MSVC keeps M_PI behind this gate, and in a single TU the FIRST math.h
// wins — so the gate opens before any include (denoise.c needs M_PI).
#define _USE_MATH_DEFINES

#include <math.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#ifndef M_PI
#define M_PI 3.14159265358979323846
#endif

#if defined(_WIN32)
#define QA_EXPORT __declspec(dllexport)
#else
#define QA_EXPORT __attribute__((visibility("default")))
#endif

#include "third_party/rnnoise/include/rnnoise.h"

#include "third_party/rnnoise/src/kiss_fft.c"
#include "third_party/rnnoise/src/celt_lpc.c"
#include "third_party/rnnoise/src/pitch.c"
#include "third_party/rnnoise/src/rnn_data.c"
#include "third_party/rnnoise/src/rnn.c"
#include "third_party/rnnoise/src/rnn_reader.c"
// celt_lpc.c and denoise.c each define PITCH_BUF_SIZE — (768+960) and
// (PITCH_MAX_PERIOD+PITCH_FRAME_SIZE), the same 1728 spelled twice. Compiled
// apart they never meet; in this one translation unit the second spelling
// is a redefinition every compiler warns about (MSVC C4005). Dropping the
// first here keeps both vendored files verbatim.
#undef PITCH_BUF_SIZE
#include "third_party/rnnoise/src/denoise.c"

// The rate RNNoise's filterbank and model are built around.
#define QA_DENOISE_RATE 48000

// Suppresses noise in place on an interleaved float32 buffer.
//
// samples: frames*channels floats in ±1.0. frames counts PER-CHANNEL
// samples. Returns 1 when the buffer was processed, 0 when the input is
// unsupported (rate != 48 kHz, empty, or an allocation failed) — 0
// always means "untouched", so the caller can fall back to the raw take.
QA_EXPORT int32_t qa_audio_denoise_f32(float *samples,
                                       int64_t frames,
                                       int32_t channels,
                                       int32_t sample_rate) {
  if (samples == NULL || frames <= 0 || channels <= 0 ||
      sample_rate != QA_DENOISE_RATE) {
    return 0;
  }
  const int frame_size = rnnoise_get_frame_size();
  float *in = (float *)malloc((size_t)frame_size * sizeof(float));
  float *out = (float *)malloc((size_t)frame_size * sizeof(float));
  if (in == NULL || out == NULL) {
    free(in);
    free(out);
    return 0;
  }
  // Every channel's model is created BEFORE the first sample is touched.
  // Creating them one at a time as the loop went meant an allocation
  // failure on channel 2 returned 0 -- "untouched" -- after channel 1 had
  // already been rewritten in place, which is the one thing the contract
  // above promises never happens. Now a failure here has written nothing.
  DenoiseState **states =
      (DenoiseState **)calloc((size_t)channels, sizeof(DenoiseState *));
  if (states == NULL) {
    free(in);
    free(out);
    return 0;
  }
  int32_t ok = 1;
  for (int32_t channel = 0; channel < channels; channel += 1) {
    states[channel] = rnnoise_create(NULL);
    if (states[channel] == NULL) {
      ok = 0;
      break;
    }
  }
  if (!ok) {
    for (int32_t channel = 0; channel < channels; channel += 1) {
      if (states[channel] != NULL) {
        rnnoise_destroy(states[channel]);
      }
    }
    free(states);
    free(in);
    free(out);
    return 0;
  }

  for (int32_t channel = 0; channel < channels; channel += 1) {
    DenoiseState *state = states[channel];
    for (int64_t start = 0; start < frames; start += frame_size) {
      const int64_t valid = frames - start < frame_size ? frames - start
                                                        : frame_size;
      for (int64_t i = 0; i < valid; i += 1) {
        in[i] = samples[(start + i) * channels + channel] * 32768.0f;
      }
      // The tail frame pads with silence; only the valid part writes back.
      for (int64_t i = valid; i < frame_size; i += 1) {
        in[i] = 0.0f;
      }
      rnnoise_process_frame(state, out, in);
      for (int64_t i = 0; i < valid; i += 1) {
        samples[(start + i) * channels + channel] = out[i] * (1.0f / 32768.0f);
      }
    }
    rnnoise_destroy(state);
  }
  free(states);
  free(in);
  free(out);
  return 1;
}
