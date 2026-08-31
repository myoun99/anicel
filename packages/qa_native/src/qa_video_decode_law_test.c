// The decode LAW, run rather than compiled.
//
// 🚨★★★**BEFORE THIS FILE, CI RAN NO NATIVE CODE AT ALL** — the portability
// job built the library with gcc and clang and then printed `ls -la`. That
// was tolerable while every rule lived inside a `#if` block, because there
// was nothing a Linux runner could have executed anyway. Splitting the law
// out of the backends is what makes this file possible, and writing it is
// half the value of that split: the arithmetic below is exactly where the
// three decoders disagreed.
//
// It includes the translation unit rather than linking it, because the law
// is `static` — deliberately, since nothing outside that file may call it.
// On this platform the `#else` backend compiles, so the hooks resolve and
// the file is whole.

#include "qa_video_decode.c"

#include <stdio.h>

static int g_failures;

static void expect_int(const char* what, int64_t got, int64_t want) {
  if (got == want) {
    return;
  }
  printf("FAIL %s: got %lld, want %lld\n", what, (long long)got,
         (long long)want);
  g_failures += 1;
}

static void expect_rate(const char* what,
                        double rate,
                        int32_t want_num,
                        int32_t want_den) {
  int32_t num = 0;
  int32_t den = 0;
  qa_rate_to_fraction(rate, &num, &den);
  if (num == want_num && den == want_den) {
    return;
  }
  printf("FAIL %s: %g became %d/%d, want %d/%d\n", what, rate, num, den,
         want_num, want_den);
  g_failures += 1;
}

int main(void) {
  // 🚨THE ONE THAT WAS WRONG ON ANDROID. `frame-rate` was read as an int32
  // with the denominator pinned to 1, so these three became 30/1 and 24/1
  // and every target timestamp drifted with them.
  expect_rate("29.97 is 30000/1001", 29.97, 30000, 1001);
  expect_rate("23.976 is 24000/1001", 23.976, 24000, 1001);
  expect_rate("59.94 is 60000/1001", 59.94, 60000, 1001);
  // Integer rates stay integers — a 24fps source must not become 24024/1001.
  expect_rate("24 stays 24/1", 24.0, 24, 1);
  expect_rate("30 stays 30/1", 30.0, 30, 1);
  expect_rate("25 stays 25/1", 25.0, 25, 1);
  // ⛔A file with no declared rate still has frames. 24 is the honest guess,
  // and it is made HERE so all three backends make the same one.
  expect_rate("nothing declared is 24/1", 0.0, 24, 1);
  expect_rate("a negative rate is 24/1", -12.0, 24, 1);
  expect_rate("an absurd rate is 24/1", 100000.0, 24, 1);

  // 🚨A DOCUMENT THAT OPENED HAS A PICTURE IN IT. Every backend used to
  // clamp this itself, and a backend that forgot would have reported a
  // movie with zero frames — which reads as an empty file, not a short one.
  expect_int("two seconds at 24 is 48 frames",
             qa_frame_count_for(2000000, 1000000, 24, 1), 48);
  expect_int("a 1001-denominator rate counts in real time",
             qa_frame_count_for(1001000, 1000000, 30000, 1001), 30);
  expect_int("a duration of zero is still one frame",
             qa_frame_count_for(0, 1000000, 24, 1), 1);
  expect_int("a sliver shorter than a frame is still one frame",
             qa_frame_count_for(1000, 1000000, 24, 1), 1);
  expect_int("no rate is still one frame", qa_frame_count_for(5000000, 1000000, 0, 0), 1);

  // Half a frame of slack, in whatever ticks the backend counts. Exact
  // equality misses on every source whose rate is not an integer, which is
  // why this is a rule and not a `==`.
  expect_int("a sample past the target reaches it",
             qa_sample_reaches(1000, 900, 100), 1);
  expect_int("a sample exactly on the target reaches it",
             qa_sample_reaches(900, 900, 100), 1);
  expect_int("a sample within half a frame reaches it",
             qa_sample_reaches(860, 900, 100), 1);
  expect_int("a sample more than half a frame early does NOT",
             qa_sample_reaches(840, 900, 100), 0);

  // 🚨THE ONE THAT ONLY APPLE KNEW. A phone holds its sensor sideways and
  // writes the turn down; a decoder that ignores it hands back a picture on
  // its side. Negatives are how Android spells counter-clockwise.
  expect_int("no transform is no turn", qa_rotation_quarter(0), 0);
  expect_int("90 stays 90", qa_rotation_quarter(90), 90);
  expect_int("-90 is 270", qa_rotation_quarter(-90), 270);
  expect_int("360 folds to 0", qa_rotation_quarter(360), 0);
  expect_int("450 folds to 90", qa_rotation_quarter(450), 90);
  expect_int("-270 is 90", qa_rotation_quarter(-270), 90);

  // A 3x2 picture, so a quarter turn is visibly a DIFFERENT SHAPE and the
  // test would notice a rotation that only moved pixels around inside the
  // old one. Values are the pixel index, in the red channel.
  //   stored          0 1 2
  //                   3 4 5
  {
    uint8_t stored[3 * 2 * 4];
    for (int32_t i = 0; i < 6; i += 1) {
      stored[i * 4 + 0] = (uint8_t)i;
      stored[i * 4 + 1] = 0;
      stored[i * 4 + 2] = 0;
      stored[i * 4 + 3] = 255;
    }
    uint8_t out[3 * 2 * 4];

    // 90° clockwise — 2 columns become 2 rows, top-left goes to top-right:
    //   3 0
    //   4 1
    //   5 2
    const uint8_t want90[6] = {3, 0, 4, 1, 5, 2};
    qa_rotate_rgba(stored, 3, 2, 90, out);
    for (int32_t i = 0; i < 6; i += 1) {
      expect_int("90 turns the picture clockwise", out[i * 4], want90[i]);
    }

    // 180° — the whole thing reversed.
    const uint8_t want180[6] = {5, 4, 3, 2, 1, 0};
    qa_rotate_rgba(stored, 3, 2, 180, out);
    for (int32_t i = 0; i < 6; i += 1) {
      expect_int("180 reverses the picture", out[i * 4], want180[i]);
    }

    // 270° — the other quarter, and the inverse of 90.
    const uint8_t want270[6] = {2, 5, 1, 4, 0, 3};
    qa_rotate_rgba(stored, 3, 2, 270, out);
    for (int32_t i = 0; i < 6; i += 1) {
      expect_int("270 turns it the other way", out[i * 4], want270[i]);
    }

    // ⚠️And the alpha rides along. A rotation that moved only RGB would
    // pass every check above and hand back a transparent picture.
    qa_rotate_rgba(stored, 3, 2, 90, out);
    for (int32_t i = 0; i < 6; i += 1) {
      expect_int("every channel is carried, alpha included", out[i * 4 + 3],
                 255);
    }
  }

  if (g_failures == 0) {
    printf("qa_video_decode law: all checks passed\n");
    return 0;
  }
  printf("qa_video_decode law: %d check(s) failed\n", g_failures);
  return 1;
}
