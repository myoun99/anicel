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

static void expect_text(const char* what, const char* got, const char* want) {
  if (got != NULL && strcmp(got, want) == 0) {
    return;
  }
  printf("FAIL %s: got \"%s\", want \"%s\"\n", what, got == NULL ? "" : got,
         want);
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

  // 🚨★★★**THE COLOUR CONVERSION, WHICH HAD NEVER RUN ANYWHERE.** It sat
  // inside the `__ANDROID__` backend: compiled on every PR, executed on no
  // machine anybody has (card `android-decoder-branch-never-runs`). It is
  // pure arithmetic, so the only thing that kept it unproven was WHERE it
  // was written — the same story as the rotation above, which was an Apple
  // secret until the split.
  {
    // A 4x4 picture with room to be wrong in: the decoder is told the rows
    // are 8 bytes apart and the chroma starts 6 rows down, while the
    // picture is 4x4. ⛔The padding is the whole point — a vendor's
    // hardware hands back exactly this, and reading stride as width is the
    // classic way to get a green-striped frame.
    //
    // ⚠️FOUR rows and not two, because two gives the chroma a single row
    // and a single row never multiplies by the chroma stride. Measured:
    // with a 2x2 fixture, mutating `chroma_stride` SURVIVED — the axis was
    // never asked a question. A fixture that does not reach a term is not
    // a nail through it.
    const int32_t w = 4;
    const int32_t h = 4;
    const int32_t stride = 8;
    const int32_t slice = 6;
    // Y = 81, Cb = 90, Cr = 240 is BT.601 limited-range RED. The BOTTOM
    // half of the chroma is neutral, so the picture is red over grey and
    // the two chroma rows cannot be confused for one another.
    uint8_t planar[8 * 6 + 4 * 3 + 4 * 3];
    memset(planar, 0xAA, sizeof(planar));  // padding must never be read
    for (int32_t y = 0; y < h; y += 1) {
      for (int32_t x = 0; x < w; x += 1) {
        planar[y * stride + x] = 81;
      }
    }
    uint8_t* u = planar + stride * slice;
    uint8_t* v = u + (stride / 2) * (slice / 2);
    for (int32_t cx = 0; cx < w / 2; cx += 1) {
      u[cx] = 90;                      // top chroma row: red
      v[cx] = 240;
      u[(stride / 2) + cx] = 128;      // bottom chroma row: neutral
      v[(stride / 2) + cx] = 128;
    }

    uint8_t rgba[4 * 4 * 4];
    qa_yuv420_to_rgba(planar, w, h, stride, slice, 0, rgba);
    expect_int("planar red is red", rgba[0], 255);
    expect_int("planar red has no green", rgba[1], 0);
    expect_int("planar red has no blue", rgba[2], 0);
    expect_int("and it is opaque", rgba[3], 255);
    // The pixel FURTHEST from the origin proves both strides were walked:
    // reading stride as width would land this one in the padding, and
    // reading the chroma row wrong would give it the top half's red.
    const int32_t last = (3 * 4 + 3) * 4;
    expect_int("the bottom half is neutral grey, not red", rgba[last], 76);
    expect_int("as grey as it is red", rgba[last + 1], 76);
    expect_int("and blue to match", rgba[last + 2], 76);

    // NV12 says the same picture with the chroma interleaved. ⚠️Two
    // layouts, ONE answer — a backend that read the wrong one would hand
    // back a frame with the colours swapped rather than an obvious error.
    uint8_t semi[8 * 6 + 8 * 3];
    memset(semi, 0xAA, sizeof(semi));
    for (int32_t y = 0; y < h; y += 1) {
      for (int32_t x = 0; x < w; x += 1) {
        semi[y * stride + x] = 81;
      }
    }
    uint8_t* uv = semi + stride * slice;
    for (int32_t cx = 0; cx < w / 2; cx += 1) {
      uv[cx * 2] = 90;
      uv[cx * 2 + 1] = 240;
      uv[stride + cx * 2] = 128;
      uv[stride + cx * 2 + 1] = 128;
    }

    uint8_t rgba_semi[4 * 4 * 4];
    qa_yuv420_to_rgba(semi, w, h, stride, slice, 1, rgba_semi);
    for (int32_t i = 0; i < 4 * 4 * 4; i += 1) {
      expect_int("NV12 and I420 are the same picture", rgba_semi[i], rgba[i]);
    }

    // Black and white, to pin the LIMITED range: 16 is black and 235 is
    // white, and a converter written for full range would answer 0 and 255
    // to the wrong inputs.
    uint8_t flat[8 * 6 + 4 * 3 + 4 * 3];
    memset(flat, 128, sizeof(flat));  // neutral chroma everywhere
    for (int32_t y = 0; y < h; y += 1) {
      for (int32_t x = 0; x < w; x += 1) {
        flat[y * stride + x] = 16;
      }
    }
    qa_yuv420_to_rgba(flat, w, h, stride, slice, 0, rgba);
    expect_int("luma 16 is black", rgba[0], 0);
    for (int32_t y = 0; y < h; y += 1) {
      for (int32_t x = 0; x < w; x += 1) {
        flat[y * stride + x] = 235;
      }
    }
    qa_yuv420_to_rgba(flat, w, h, stride, slice, 0, rgba);
    expect_int("luma 235 is white", rgba[0], 255);
  }

  // 🚨★★★**THE TWO DIRECTIONS ARE ONE LAW** (`qa_yuv601.h`): what a writer
  // makes of a colour, the reader turns back into that colour. The Apple
  // writer let VideoToolbox pick its matrix instead and lost red in
  // proportion — 110 came back 101 — which is exactly what a round trip
  // catches (2026-09-25, board `trimmed-piece-apple-parity`). Both layouts,
  // and the padding an odd picture gets is WHITE, as exports always drew.
  {
    // A 3x1 picture in a 4x4 frame: the top-left 2x2 block takes its
    // chroma from picture pixel (0,0), and the bottom-right block is
    // padding through and through.
    const int32_t src_w = 3;
    const int32_t src_h = 1;
    const int32_t w = 4;
    const int32_t h = 4;
    static const uint8_t colours[][3] = {
        {20, 0, 0},  {110, 0, 0},  {200, 0, 0},   {230, 0, 0},
        {0, 170, 0}, {0, 0, 140},  {90, 160, 40}, {250, 250, 250},
    };
    for (size_t c = 0; c < sizeof(colours) / sizeof(colours[0]); c += 1) {
      uint8_t source[3 * 1 * 4];
      for (int32_t i = 0; i < src_w * src_h; i += 1) {
        source[i * 4 + 0] = colours[c][0];
        source[i * 4 + 1] = colours[c][1];
        source[i * 4 + 2] = colours[c][2];
        source[i * 4 + 3] = 255;
      }
      for (int semi = 0; semi <= 1; semi += 1) {
        uint8_t frame[4 * 4 * 3 / 2];
        uint8_t* chroma = frame + w * h;
        qa_yuv601_from_rgba(source, src_w, src_h, w, h, frame, w, chroma,
                            semi ? chroma + 1 : chroma + (w / 2) * (h / 2),
                            semi ? w : w / 2, semi ? 2 : 1);
        uint8_t back[4 * 4 * 4];
        qa_yuv420_to_rgba(frame, w, h, w, h, semi, back);
        for (int k = 0; k < 3; k += 1) {
          const int drift = (int)back[k] - (int)colours[c][k];
          if (drift < -2 || drift > 2) {
            expect_int("a colour comes back where it was written (±2)",
                       back[k], colours[c][k]);
          }
          expect_int("and the padding is white",
                     back[(3 * w + 3) * 4 + k], 255);
        }
      }
    }
  }

  // 🚨A RANGE IS CHECKED BEFORE ANY BACKEND SEES IT, and the two refusals
  // say different things. That distinction is the same one the viewer got
  // wrong in Dart — 「no decoder in this build」 for a file the decoder
  // simply would not read — and it is worth pinning on this side too.
  expect_int("a negative offset is refused",
             qa_video_decode_open_span("movie.anicel", -1, 10, 0), 0);
  expect_text("and says the range is wrong, not that a decoder is missing",
              qa_video_decode_last_error(),
              "that span is not inside the file");
  expect_int("a zero length is refused",
             qa_video_decode_open_span("movie.anicel", 0, 0, 0), 0);
  expect_text("same reason", qa_video_decode_last_error(),
              "that span is not inside the file");
  // ⚠️This build has the「no decoder」backend, so a WELL-FORMED range gets
  // past the check and is refused for the other reason. Both fail; only the
  // sentence tells them apart, which is the point.
  expect_int("a well-formed range reaches the backend",
             qa_video_decode_open_span("movie.anicel", 4096, 10, 0), 0);
  expect_text("and the backend's own reason is what comes back",
              qa_video_decode_last_error(), "no video decoder in this build");
  // A FRAMED span is asked of the backend's capability first — a device
  // that cannot serve its decoder a source (Android below 9) says THAT,
  // rather than failing the open as if the movie were broken.
  expect_int("this build cannot read a framed span",
             qa_video_decode_framed_supported(), 0);
  expect_int("so a framed span is refused at the door",
             qa_video_decode_open_span("movie.anicel", 4096, 10, 1), 0);
  expect_text("with the reason that is true",
              qa_video_decode_last_error(),
              "this device cannot read a movie kept compressed");

  if (g_failures == 0) {
    printf("qa_video_decode law: all checks passed\n");
    return 0;
  }
  printf("qa_video_decode law: %d check(s) failed\n", g_failures);
  return 1;
}
