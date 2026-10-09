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
//
// 🚨★★★**AND WHO A CONTAINER'S HEAD LETS TRY** (section 7). dr_mp3 finds
// frames wherever they are — which is how a movie's uncompressed sound came
// back as noise — so that fixture is real MPEG frames, and the head written
// in front of them decides whether dr_mp3 may be asked. Portable for the same
// reason: whatever the platform's stack makes of those files, the answer
// checked is only that it is not dr_mp3's.

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "qa_framed_fixture.h"

#define QA_AUDIO_FORMAT_UNKNOWN 0
#define QA_AUDIO_FORMAT_WAV 1
#define QA_AUDIO_FORMAT_FLAC 2
#define QA_AUDIO_FORMAT_MP3 3

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

/// Checks a decode that is supposed to have produced the fixture, through the
/// decoder [want].
static void expect_fixture(const char* what, int32_t want, int32_t format,
                           float* samples, int64_t frames, int32_t channels,
                           int32_t rate) {
  char label[128];
  snprintf(label, sizeof(label), "%s: which decoder", what);
  expect_int(label, format, want);
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
    expect_fixture(what, QA_AUDIO_FORMAT_WAV, format, samples, frames,
                   channels, rate);
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

// ---------------------------------------------------------------------------
// Real MPEG frames: silent MPEG-1 Layer III, a header and zeros — no side
// information, so every granule decodes to silence and dr_mp3 reads them
// wherever they sit.

#define MP3_FRAMES 24
#define MP3_FRAME_BYTES 417  // 128 kbps at 44100 Hz, no padding

static size_t build_mp3_frames(uint8_t* out) {
  for (int frame = 0; frame < MP3_FRAMES; frame += 1) {
    uint8_t* at = out + frame * MP3_FRAME_BYTES;
    memset(at, 0, MP3_FRAME_BYTES);
    at[0] = 0xFF;
    at[1] = 0xFB;  // MPEG-1, Layer III, no CRC
    at[2] = 0x90;  // 128 kbps, 44100 Hz
  }
  return (size_t)MP3_FRAMES * MP3_FRAME_BYTES;
}

/// The same frames with the first turned into the tag LAME writes: `Info`
/// after the side information, then the LAME extension, whose bytes 21-23
/// carry the encoder delay (576, LAME's own) and the padding (0) — each
/// 12 bits, the padding stored with the decoder's 529 added.
static size_t build_tagged_mp3_frames(uint8_t* out) {
  const size_t bytes = build_mp3_frames(out);
  uint8_t* tag = out + 4 + 32;  // past the header and the side information
  memcpy(tag, "Info", 4);       // no fields after the flags
  memcpy(tag + 8, "LAME3.100", 9);
  tag[8 + 21] = 576 >> 4;
  tag[8 + 22] = (uint8_t)(((576 & 0x0F) << 4) | (529 >> 8));
  tag[8 + 23] = 529 & 0xFF;
  return bytes;
}

/// How many frames a decode of the MP3 frames should hand back: every
/// granule but [tag_frames] tag frames, less the 1,105 LAME's encoder and
/// the decoder put before the sound — taken off once, whoever says it.
#define MP3_SOUND_FRAMES(tag_frames) \
  ((int64_t)(MP3_FRAMES - (tag_frames)) * 1152 - 1105)

// ---------------------------------------------------------------------------
// The fixture again as a FLAC, VERBATIM subframes: nothing predicted, so what
// dr_flac hands back is the fixture itself. Both CRCs are real — dr_flac
// checks them.

#define FLAC_BLOCK 256
#define FLAC_BYTES                                                \
  (4 + 4 + 34 +                                                   \
   (FIXTURE_FRAMES / FLAC_BLOCK) *                                \
       (6 + FIXTURE_CHANNELS * (1 + FLAC_BLOCK * 2) + 2))

static uint8_t flac_crc8(const uint8_t* bytes, size_t count) {
  uint8_t crc = 0;
  for (size_t index = 0; index < count; index += 1) {
    crc ^= bytes[index];
    for (int bit = 0; bit < 8; bit += 1) {
      crc = (uint8_t)((crc & 0x80) ? (crc << 1) ^ 0x07 : crc << 1);
    }
  }
  return crc;
}

static uint16_t flac_crc16(const uint8_t* bytes, size_t count) {
  uint16_t crc = 0;
  for (size_t index = 0; index < count; index += 1) {
    crc ^= (uint16_t)(bytes[index] << 8);
    for (int bit = 0; bit < 8; bit += 1) {
      crc = (uint16_t)((crc & 0x8000) ? (crc << 1) ^ 0x8005 : crc << 1);
    }
  }
  return crc;
}

static size_t build_flac(uint8_t* out) {
  memcpy(out, "fLaC", 4);
  // The one metadata block — STREAMINFO, and the last.
  uint8_t* info = out + 4;
  memset(info, 0, 4 + 34);
  info[0] = 0x80;
  info[3] = 34;
  info[4 + 0] = FLAC_BLOCK >> 8;  // smallest block
  info[4 + 1] = FLAC_BLOCK & 0xFF;
  info[4 + 2] = FLAC_BLOCK >> 8;  // largest block
  info[4 + 3] = FLAC_BLOCK & 0xFF;
  // Rate (20 bits), channels - 1 (3), bits - 1 (5), total frames (36); the
  // frame sizes and the MD5 stay 0, which the format reads as 「unknown」.
  const uint64_t packed = ((uint64_t)FIXTURE_RATE << 44) |
                          ((uint64_t)(FIXTURE_CHANNELS - 1) << 41) |
                          ((uint64_t)15 << 36) | (uint64_t)FIXTURE_FRAMES;
  for (int byte = 0; byte < 8; byte += 1) {
    info[4 + 10 + byte] = (uint8_t)(packed >> (56 - 8 * byte));
  }
  uint8_t* at = info + 4 + 34;
  for (int block = 0; block < FIXTURE_FRAMES / FLAC_BLOCK; block += 1) {
    uint8_t* frame = at;
    frame[0] = 0xFF;
    frame[1] = 0xF8;  // sync, fixed block size
    frame[2] = 0x89;  // 256 frames, 44100 Hz
    frame[3] = 0x18;  // left and right, 16 bits
    frame[4] = (uint8_t)block;  // the frame number, one UTF-8 byte
    frame[5] = flac_crc8(frame, 5);
    at = frame + 6;
    for (int channel = 0; channel < FIXTURE_CHANNELS; channel += 1) {
      *at++ = 0x02;  // VERBATIM, no wasted bits
      for (int index = 0; index < FLAC_BLOCK; index += 1) {
        const uint16_t sample =
            (uint16_t)fixture_sample(block * FLAC_BLOCK + index, channel);
        *at++ = (uint8_t)(sample >> 8);
        *at++ = (uint8_t)(sample & 0xFF);
      }
    }
    const uint16_t crc = flac_crc16(frame, (size_t)(at - frame));
    *at++ = (uint8_t)(crc >> 8);
    *at++ = (uint8_t)(crc & 0xFF);
  }
  return (size_t)(at - out);
}

/// [head] and then [body], written as a whole file and decoded: which decoder
/// read it, and how many frames into [out_frames] when it is given — and,
/// unless [fixture] is UNKNOWN, whether that decoder was [fixture] and what
/// it read was the fixture, the check [what] names.
static int32_t decode_behind(const char* what, const uint8_t* head,
                             size_t head_bytes, const uint8_t* body,
                             size_t body_bytes, int32_t fixture,
                             int64_t* out_frames) {
  const char* path = "qa_audio_head_fixture.bin";
  FILE* file = fopen(path, "wb");
  if (file == NULL) {
    printf("FAIL fixture: could not write %s\n", path);
    g_failures += 1;
    return -1;
  }
  if (head_bytes > 0) {
    fwrite(head, 1, head_bytes, file);
  }
  fwrite(body, 1, body_bytes, file);
  fclose(file);
  float* samples = NULL;
  int64_t frames = 0;
  int32_t channels = 0;
  int32_t rate = 0;
  const int32_t format =
      qa_audio_decode_span(path, 0, (int64_t)(head_bytes + body_bytes), 0,
                           &samples, &frames, &channels, &rate);
  if (fixture != QA_AUDIO_FORMAT_UNKNOWN) {
    expect_fixture(what, fixture, format, samples, frames, channels, rate);
  }
  if (out_frames != NULL) {
    *out_frames = frames;
  }
  qa_audio_decode_free(samples);
  remove(path);
  return format;
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

  // 7. WHO A HEAD LETS TRY.
  {
    static uint8_t frames[MP3_FRAMES * MP3_FRAME_BYTES];
    const size_t frame_bytes = build_mp3_frames(frames);
    // The controls: these ARE an MP3 — bare, behind an ID3 tag, and behind a
    // head nobody knows, which still runs the whole chain. Without them, a
    // sniff that turned dr_mp3 away from everything would pass the rest.
    // ...and with no tag to say where its sound starts, each takes the
    // standard 1,105 off (section 9 has the tag that says it).
    static const uint8_t id3[10] = {'I', 'D', '3', 4, 0, 0, 0, 0, 0, 0};
    static const uint8_t nobody[16] = {0};
    static const struct {
      const char* name;
      const uint8_t* head;
      size_t bytes;
    } mp3s[] = {
        {"bare frames", NULL, 0},
        {"frames behind an ID3 tag", id3, sizeof(id3)},
        {"frames behind a head nobody knows", nobody, sizeof(nobody)},
    };
    for (size_t index = 0; index < sizeof(mp3s) / sizeof(mp3s[0]);
         index += 1) {
      char label[96];
      int64_t decoded = 0;
      snprintf(label, sizeof(label), "%s are an MP3", mp3s[index].name);
      expect_int(label,
                 decode_behind(NULL, mp3s[index].head, mp3s[index].bytes,
                               frames, frame_bytes, QA_AUDIO_FORMAT_UNKNOWN,
                               &decoded),
                 QA_AUDIO_FORMAT_MP3);
      snprintf(label, sizeof(label), "%s start 1,105 frames in",
               mp3s[index].name);
      expect_int(label, decoded, MP3_SOUND_FRAMES(0));
    }

    // The law: a head that names another container keeps dr_mp3 away from
    // it, whatever is inside.
    static const char movie_boxes[][5] = {"ftyp", "moov", "mdat", "wide",
                                          "free", "skip", "pnot"};
    for (size_t index = 0; index < sizeof(movie_boxes) / sizeof(movie_boxes[0]);
         index += 1) {
      uint8_t box[16] = {0, 0, 0, 16};
      memcpy(box + 4, movie_boxes[index], 4);
      char label[96];
      snprintf(label, sizeof(label),
               "frames in a movie that opens with `%s` are not dr_mp3's",
               movie_boxes[index]);
      expect_int(label,
                 decode_behind(NULL, box, sizeof(box), frames, frame_bytes,
                               QA_AUDIO_FORMAT_UNKNOWN, NULL) ==
                     QA_AUDIO_FORMAT_MP3,
                 0);
    }
    static const struct {
      const char* name;
      const char* head;
      size_t bytes;
    } others[] = {
        // ⚠️Literals split where a hex escape would run on into the name.
        {"an AVI's RIFF", "RIFF\x10\0\0\0" "AVI ", 12},
        {"a big-endian WAV's RIFX", "RIFX\0\0\0\x10" "WAVE", 12},
        {"an RF64", "RF64\xFF\xFF\xFF\xFF" "WAVE", 12},
        {"a W64's riff", "riff", 4},
        {"an AIFF's FORM", "FORM\0\0\0\x10" "AIFF", 12},
        {"FLAC's fLaC", "fLaC", 4},
        {"ogg's OggS", "OggS", 4},
    };
    for (size_t index = 0; index < sizeof(others) / sizeof(others[0]);
         index += 1) {
      char label[96];
      snprintf(label, sizeof(label), "frames behind %s are not dr_mp3's",
               others[index].name);
      expect_int(label,
                 decode_behind(NULL, (const uint8_t*)others[index].head,
                               others[index].bytes, frames, frame_bytes,
                               QA_AUDIO_FORMAT_UNKNOWN, NULL) ==
                     QA_AUDIO_FORMAT_MP3,
                 0);
    }
  }

  // 8. ...AND NO HEAD TAKES A FORMAT FROM ITS OWN DECODER. dr_flac skips an
  // ID3 tag itself, so a tagged FLAC is dr_flac's — a sniff that read 「ID3
  // means MP3」 would hand it to dr_mp3 alone, which cannot read it.
  {
    static uint8_t flac[FLAC_BYTES];
    const size_t flac_bytes = build_flac(flac);
    decode_behind("a FLAC", NULL, 0, flac, flac_bytes, QA_AUDIO_FORMAT_FLAC,
                  NULL);
    static const uint8_t id3[10] = {'I', 'D', '3', 4, 0, 0, 0, 0, 0, 0};
    decode_behind("a FLAC behind an ID3 tag", id3, sizeof(id3), flac,
                  flac_bytes, QA_AUDIO_FORMAT_FLAC, NULL);
  }

  // 9. WHERE THE SOUND STARTS, WHEN THE FILE SAYS SO. A LAME tag says the
  // 1,105 itself, and dr_mp3 takes it off as it reads — the engine must not
  // take the standard 1,105 off again. The tag's own frame is no sound.
  {
    static uint8_t tagged[MP3_FRAMES * MP3_FRAME_BYTES];
    const size_t tagged_bytes = build_tagged_mp3_frames(tagged);
    int64_t decoded = 0;
    expect_int("an MP3 with a LAME tag is an MP3",
               decode_behind(NULL, NULL, 0, tagged, tagged_bytes,
                             QA_AUDIO_FORMAT_UNKNOWN, &decoded),
               QA_AUDIO_FORMAT_MP3);
    expect_int("an MP3 with a LAME tag starts where the tag says, once",
               decoded, MP3_SOUND_FRAMES(1));
  }

  if (g_failures == 0) {
    printf("qa_audio_range: all checks passed\n");
    return 0;
  }
  printf("qa_audio_range: %d check(s) failed\n", g_failures);
  return 1;
}
