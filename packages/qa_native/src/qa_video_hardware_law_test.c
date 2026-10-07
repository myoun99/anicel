// The hardware law, run (card surface-engine-mp4-pieces-fail-to-finalize).
//
// What it keeps out of the hardware fails only on a machine whose encoder
// says yes and then gives up — the Intel one the law was measured on. Every
// other machine, CI's runners among them, passes the engine's movie tests
// with or without the law, so without this file nothing that runs off that
// one machine would notice it gone. The law has no platform in it, so this
// runs on every host.

#include "qa_video_hardware_law.h"

#include <stdio.h>

static int g_failures;

static void expect(const char* what, int32_t width, int32_t height, int hevc,
                   int want) {
  const int got = qa_video_hardware_may_encode(width, height, hevc);
  if (got == want) {
    return;
  }
  printf("FAIL %s: %dx%d %s got %s, want %s\n", what, width, height,
         hevc ? "HEVC" : "H.264", got ? "hardware" : "software",
         want ? "hardware" : "software");
  g_failures += 1;
}

int main(void) {
  // The sizes the engine's own fixtures write, and what failed on them.
  expect("the fixtures' movie", 64, 48, 0, 0);
  expect("tall instead of wide", 48, 64, 0, 0);
  expect("a long thin strip", 1920, 48, 0, 0);
  expect("a thin strip the other way", 48, 1920, 0, 0);

  // The first sizes that encoded on that machine, and the everyday ones.
  expect("one pixel past three macroblocks", 50, 50, 0, 1);
  expect("past it on both sides", 64, 64, 0, 1);
  expect("a full HD film", 1920, 1080, 0, 1);

  // HEVC has no software encoder on Windows — refusing it the hardware
  // would refuse it everything.
  expect("HEVC stays on the hardware", 64, 48, 1, 1);
  expect("HEVC at full HD", 1920, 1080, 1, 1);

  if (g_failures == 0) {
    printf("qa_video_hardware_law: all passed\n");
  }
  return g_failures == 0 ? 0 : 1;
}
