// The transport against a move that lands while a block mixes, run rather
// than waited for (a-seek-lost-to-the-block-in-flight, 2026-10-23).
//
// 🚨★★★**WHAT THIS PROTECTS: a seek or a play that lands mid-block STANDS.**
// The race is real time — the device's thread mixing while the control
// thread moves the transport — and a test on a real device met it once in
// many runs under load (960 where the seek put 33600). Here the mixer is
// this file's, and it makes the move ITSELF, between the callback reading
// the position and the callback writing it back: the window, every time.
//
// It includes the translation unit rather than linking it, because the
// callback is `static`. No device is opened — the callback is called as the
// device would call it — and only miniaudio's null backend is compiled, so
// the file is the same on every host CI has.

#define MA_ENABLE_ONLY_SPECIFIC_BACKENDS
#define MA_ENABLE_NULL
#include "qa_audio_device.c"

#include <stdio.h>

// The mixer qa_engine.c would be: every sample it mixes is [kMixed], and the
// first time it runs after [g_between] is set, it runs that — the control
// thread's move, landed while the block mixes.
static const double kMixed = 0.25;
static void (*g_between)(void);

void qa_audio_mix(const qa_audio_clip* clips,
                  int32_t clip_count,
                  const qa_audio_source* sources,
                  int32_t source_count,
                  const qa_audio_envelope_key* envelope_keys,
                  int32_t envelope_key_count,
                  int64_t start_sample,
                  int32_t sample_count,
                  int32_t out_channels,
                  double* out) {
  (void)clips;
  (void)clip_count;
  (void)sources;
  (void)source_count;
  (void)envelope_keys;
  (void)envelope_key_count;
  (void)start_sample;
  for (int32_t index = 0; index < sample_count * out_channels; index += 1) {
    out[index] = kMixed;
  }
  void (*between)(void) = g_between;
  g_between = NULL;
  if (between != NULL) {
    between();
  }
}

int32_t qa_audio_clip_sizeof(void) { return (int32_t)sizeof(qa_audio_clip); }
int32_t qa_audio_source_sizeof(void) {
  return (int32_t)sizeof(qa_audio_source);
}
int32_t qa_audio_envelope_key_sizeof(void) {
  return (int32_t)sizeof(qa_audio_envelope_key);
}

static int g_failures;

static void expect_int(const char* what, int64_t got, int64_t want) {
  if (got == want) {
    return;
  }
  printf("FAIL %s: got %lld, want %lld\n", what, (long long)got,
         (long long)want);
  g_failures += 1;
}

#define kFrames 480
static float g_out[QA_DEVICE_MAX_BLOCK + kFrames];

// One pull of [frames] by the device, and how many of its samples were
// mixed rather than silent.
static int64_t pull(ma_uint32 frames) {
  qa_audio_data_callback(NULL, g_out, NULL, frames);
  int64_t mixed = 0;
  for (ma_uint32 index = 0; index < frames; index += 1) {
    if (g_out[index] != 0.0f) {
      mixed += 1;
    }
  }
  return mixed;
}

static void seek_to_frame_7(void) { qa_audio_device_seek(33600); }
static void play_from_96000(void) { qa_audio_device_play(96000, 0, 0, 0); }
static void play_again_from_0(void) { qa_audio_device_play(0, 8192, 0, 0); }

int main(void) {
  // A mono transport with a mix bus, as qa_audio_device_open leaves it.
  g_audio.channels = 1;
  g_audio.sample_rate = 48000;
  g_audio.scratch =
      (double*)malloc((size_t)QA_DEVICE_MAX_BLOCK * sizeof(double));
  g_audio.device_open = 1;

  // 🚨THE ONE A TEST MET UNDER LOAD. Moved to frame 7 while a block mixed,
  // the transport went back to the block's end — the sound played on from
  // where it had been, and the picture, tied to it, stood still.
  qa_audio_device_play(0, 0, 0, 0);
  expect_int("premise: a run's block is handed", pull(kFrames), kFrames);
  g_between = seek_to_frame_7;
  expect_int("the block mixed from the place the seek left is not handed",
             pull(kFrames), 0);
  expect_int("the seek stands", qa_audio_device_position(), 33600);
  expect_int("the run goes on from it", pull(kFrames), kFrames);
  expect_int("…counted from there", qa_audio_device_position(),
             33600 + kFrames);

  // The same window for a play: a press of play while a block mixes.
  g_between = play_from_96000;
  pull(kFrames);
  expect_int("a play that lands mid-block stands",
             qa_audio_device_position(), 96000);
  expect_int("…and its run is playing", qa_audio_device_is_playing(), 1);

  // 🚨A RUN THAT RAN OUT ENDS ONLY ITSELF. Played again from the same place
  // while the run's last block mixed, the position reads as that block left
  // it — but the run that ran out is not the run now playing, and it must
  // not switch that one off.
  qa_audio_device_play(0, 8192, 0, 0);
  g_between = play_again_from_0;
  pull(QA_DEVICE_MAX_BLOCK + kFrames);
  expect_int("the run played again is still playing",
             qa_audio_device_is_playing(), 1);

  // What the claim must not change: a run still runs out, loops, and hands
  // its lead silent.
  qa_audio_device_play(0, 2 * kFrames, 0, 0);
  pull(kFrames);
  pull(kFrames);
  pull(kFrames);
  expect_int("a run that reaches its stop ends", qa_audio_device_is_playing(),
             0);
  qa_audio_device_play(0, 2 * kFrames, 1, 0);
  pull(kFrames);
  pull(kFrames);
  pull(kFrames);
  expect_int("a loop wraps to its start", qa_audio_device_position(),
             kFrames);
  qa_audio_device_play(1000, 0, 0, kFrames);
  expect_int("a lead is handed silent", pull(kFrames), 0);
  expect_int("…and counted", qa_audio_device_position(), 1000);

  // 🚨A PLAYER'S END SILENCES ONLY ITS OWN RUN (board
  // a-cue-ending-silences-a-viewer-sound-it-did-not-make): another's run
  // taken onto the device since plays on.
  const int32_t cue = qa_audio_device_play(0, 0, 0, 0);
  const int32_t viewer = qa_audio_device_play(5000, 0, 0, 0);
  expect_int("premise: every run is its own", cue != viewer && cue != 0, 1);
  qa_audio_device_stop_run(cue);
  expect_int("another's run plays on", qa_audio_device_is_playing(), 1);
  qa_audio_device_stop_run(viewer);
  expect_int("its own run stops", qa_audio_device_is_playing(), 0);
  g_audio.peak_left_bits = 7;
  qa_audio_device_stop_run(cue);
  expect_int("a device playing nothing is stopped as before — its meter too",
             g_audio.peak_left_bits, 0);

  free(g_audio.scratch);
  if (g_failures > 0) {
    printf("%d failure(s)\n", g_failures);
    return 1;
  }
  printf("qa_audio_transport: all passed\n");
  return 0;
}
