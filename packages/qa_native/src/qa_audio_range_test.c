// Decoding a container that is a RANGE of a file, driven for real.
//
// 🚨★★★**WHAT THIS PROTECTS: `base + position`.** A sound inside the project
// file starts thousands of bytes into it, and a decoder handed the wrong
// origin does not fail loudly — it reads the archive's own header as audio and
// reports a corrupt file. The arithmetic is three lines and there is no way
// to eyeball it, so it is measured instead.
//
// 🧪The fixture is a WAV this file writes itself: dr_wav reads it on EVERY
// platform, so the same checks run on CI's Linux runner as on Windows and
// macOS — the range contract is portable even though three of the four
// decoders behind it are not.
//
// ⛔NOT a test of the OS codec stack. That one needs a real AAC file and a
// platform to decode it, and `qa_audio_os_decoder_test.dart` already does it
// from Dart, where the fixtures live.

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "qa_framed_fixture.h"

#define QA_AUDIO_FORMAT_UNKNOWN 0
#define QA_AUDIO_FORMAT_WAV 1

extern int32_t qa_audio_decode_span(const char* path,
                                    int64_t offset,
                                    int64_t length,
                                    int32_t framed,
                                    float** out_samples,
                                    int64_t* out_frame_count,
                                    int32_t* out_channels,
                                    int32_t* out_sample_rate);

extern void qa_audio_decode_free(float* samples);

static int g_failures;

static void expect_int(const char* what, long long got, long long want) {
  if (got == want) {
    return;
  }
  printf("FAIL %s: got %lld, want %lld\n", what, got, want);
  g_failures += 1;
}

static void expect_near(const char* what, double got, double want) {
  const double slack = 1.0 / 32768.0;
  if (got >= want - slack && got <= want + slack) {
    return;
  }
  printf("FAIL %s: got %f, want %f\n", what, got, want);
  g_failures += 1;
}

// ---------------------------------------------------------------------------
// The fixture: a 2-channel 44100Hz 16-bit WAV whose samples are a known
// pattern, so a decode that lands on the wrong bytes cannot look right.

#define FIXTURE_FRAMES 512
#define FIXTURE_CHANNELS 2
#define FIXTURE_RATE 44100
#define PREFIX_BYTES 1234
#define SUFFIX_BYTES 777

static int16_t fixture_sample(int frame, int channel) {
  return (int16_t)(((frame * 37) + (channel * 11)) % 30011 - 15000);
}

static void put_u16(uint8_t* at, uint16_t value) {
  at[0] = (uint8_t)(value & 0xFF);
  at[1] = (uint8_t)((value >> 8) & 0xFF);
}

/// Writes the WAV into [out] and returns how many bytes it took.
static size_t build_wav(uint8_t* out) {
  const uint32_t data_bytes =
      (uint32_t)(FIXTURE_FRAMES * FIXTURE_CHANNELS * 2);
  memcpy(out, "RIFF", 4);
  qa_fixture_put_u32(out + 4, 36 + data_bytes);
  memcpy(out + 8, "WAVEfmt ", 8);
  qa_fixture_put_u32(out + 16, 16);  // fmt chunk size
  put_u16(out + 20, 1);              // PCM
  put_u16(out + 22, FIXTURE_CHANNELS);
  qa_fixture_put_u32(out + 24, FIXTURE_RATE);
  // byte rate
  qa_fixture_put_u32(out + 28, FIXTURE_RATE * FIXTURE_CHANNELS * 2);
  put_u16(out + 32, FIXTURE_CHANNELS * 2);  // block align
  put_u16(out + 34, 16);                    // bits
  memcpy(out + 36, "data", 4);
  qa_fixture_put_u32(out + 40, data_bytes);
  uint8_t* at = out + 44;
  for (int frame = 0; frame < FIXTURE_FRAMES; frame += 1) {
    for (int channel = 0; channel < FIXTURE_CHANNELS; channel += 1) {
      put_u16(at, (uint16_t)fixture_sample(frame, channel));
      at += 2;
    }
  }
  return (size_t)(at - out);
}

/// Checks a decode that is supposed to have produced the fixture.
static void expect_fixture(const char* what, int32_t format, float* samples,
                           int64_t frames, int32_t channels, int32_t rate) {
  char label[128];
  snprintf(label, sizeof(label), "%s: is a WAV", what);
  expect_int(label, format, QA_AUDIO_FORMAT_WAV);
  snprintf(label, sizeof(label), "%s: frame count", what);
  expect_int(label, frames, FIXTURE_FRAMES);
  snprintf(label, sizeof(label), "%s: channels", what);
  expect_int(label, channels, FIXTURE_CHANNELS);
  snprintf(label, sizeof(label), "%s: sample rate", what);
  expect_int(label, rate, FIXTURE_RATE);
  if (samples == NULL || frames != FIXTURE_FRAMES ||
      channels != FIXTURE_CHANNELS) {
    return;
  }
  // 🚨The samples themselves, not just the header: a wrong base that still
  // found a RIFF header would pass everything above.
  for (int frame = 0; frame < FIXTURE_FRAMES; frame += 8) {
    for (int channel = 0; channel < FIXTURE_CHANNELS; channel += 1) {
      snprintf(label, sizeof(label), "%s: the samples are the fixture's", what);
      expect_near(label, samples[frame * FIXTURE_CHANNELS + channel],
                  fixture_sample(frame, channel) / 32768.0);
    }
  }
}

/// Decodes the span and checks it against the fixture — or, when [expect] is
/// UNKNOWN, checks that it was refused.
static void decode_and_check(const char* what, const char* path,
                             int64_t offset, int64_t length, int32_t framed,
                             int32_t expect) {
  float* samples = NULL;
  int64_t frames = 0;
  int32_t channels = 0;
  int32_t rate = 0;
  const int32_t format = qa_audio_decode_span(
      path, offset, length, framed, &samples, &frames, &channels, &rate);
  if (expect == QA_AUDIO_FORMAT_WAV) {
    expect_fixture(what, format, samples, frames, channels, rate);
  } else {
    expect_int(what, format == QA_AUDIO_FORMAT_WAV ? 1 : 0, 0);
  }
  qa_audio_decode_free(samples);
}

/// Junk, then [body] of [bytes], then junk — the shape a carried sound has,
/// and the shape that catches a missing base.
static int write_between_junk(const char* path, const uint8_t* body,
                              size_t bytes) {
  FILE* file = fopen(path, "wb");
  if (file == NULL) {
    printf("FAIL fixture: could not write %s\n", path);
    g_failures += 1;
    return 0;
  }
  for (int i = 0; i < PREFIX_BYTES; i += 1) {
    fputc((i * 13 + 7) & 0xFF, file);
  }
  fwrite(body, 1, bytes, file);
  for (int i = 0; i < SUFFIX_BYTES; i += 1) {
    fputc((i * 29 + 3) & 0xFF, file);
  }
  fclose(file);
  return 1;
}

int main(void) {
  static uint8_t wav[44 + FIXTURE_FRAMES * FIXTURE_CHANNELS * 2];
  const size_t wav_bytes = build_wav(wav);

  // 1. THE SPAN. The whole point.
  const char* path = "qa_audio_range_fixture.bin";
  if (write_between_junk(path, wav, wav_bytes)) {
    decode_and_check("a container inside a file", path, PREFIX_BYTES,
                     (int64_t)wav_bytes, 0, QA_AUDIO_FORMAT_WAV);

    // 4. THE WRONG ORIGIN IS NOT A WAV. Starting where the junk starts must
    // not decode — this is the assertion a missing `base` dies on.
    decode_and_check("junk at the front does not decode as a WAV", path, 0,
                     (int64_t)wav_bytes, 0, QA_AUDIO_FORMAT_UNKNOWN);

    // 5. PAST THE END IS REFUSED, not clamped: a container cut short decodes
    // as a corrupt file, which hides the fact that the span was wrong.
    decode_and_check("a span past the end is refused", path, PREFIX_BYTES,
                     (int64_t)(wav_bytes + SUFFIX_BYTES + 1), 0,
                     QA_AUDIO_FORMAT_UNKNOWN);

    // 6. Nothing to decode is an ANSWER, not a crash.
    decode_and_check("a zero length is refused", path, PREFIX_BYTES, 0, 0,
                     QA_AUDIO_FORMAT_UNKNOWN);
    remove(path);
  }
  decode_and_check("a missing file is refused", "qa_no_such_file.bin", 0, 16,
                   0, QA_AUDIO_FORMAT_UNKNOWN);

  // 2. THE SAME CONTAINER, FRAMED. One law, however the save stored it — if
  // these disagree, the framed path is a second decoder wearing the first
  // one's name. Small blocks, so the container spans several of them.
  {
    const char* framed = "qa_audio_framed_fixture.bin";
    FILE* file = fopen(framed, "wb");
    uint32_t lengths[QA_FIXTURE_MAX_BLOCKS];
    int64_t blob = -1;
    if (file != NULL) {
      for (int i = 0; i < PREFIX_BYTES; i += 1) {
        fputc((i * 13 + 7) & 0xFF, file);
      }
      blob = qa_fixture_write_framed(file, wav, (int64_t)wav_bytes, 256,
                                     lengths);
      for (int i = 0; i < SUFFIX_BYTES; i += 1) {
        fputc((i * 29 + 3) & 0xFF, file);
      }
      fclose(file);
    }
    if (blob > 0) {
      decode_and_check("the same container, framed", framed, PREFIX_BYTES,
                       blob, 1, QA_AUDIO_FORMAT_WAV);
      // ⛔Read as if it were plain, the blocks are not a container.
      decode_and_check("framed bytes read as plain are not a WAV", framed,
                       PREFIX_BYTES, blob, 0, QA_AUDIO_FORMAT_UNKNOWN);
    } else {
      printf("FAIL fixture: could not write %s\n", framed);
      g_failures += 1;
    }
    remove(framed);
  }

  // 3. A WHOLE FILE IS JUST A SPAN. The ordinary case has to work through
  // the same door, or every caller needs to know which one it is.
  {
    const char* plain = "qa_audio_plain_fixture.wav";
    FILE* file = fopen(plain, "wb");
    if (file != NULL) {
      fwrite(wav, 1, wav_bytes, file);
      fclose(file);
      decode_and_check("a whole file", plain, 0, (int64_t)wav_bytes, 0,
                       QA_AUDIO_FORMAT_WAV);
      remove(plain);
    } else {
      printf("FAIL fixture: could not write %s\n", plain);
      g_failures += 1;
    }
  }

  if (g_failures == 0) {
    printf("qa_audio_range: all checks passed\n");
    return 0;
  }
  printf("qa_audio_range: %d check(s) failed\n", g_failures);
  return 1;
}
