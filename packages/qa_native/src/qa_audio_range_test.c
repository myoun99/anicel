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
//
// 🚨★★★**AND A MOVIE'S UNCOMPRESSED SOUND, WHICH THE ENGINE READS ITSELF**
// (section 12). Those movies are built here box by box, each the way a
// writer stores its samples, and each must decode exactly as a WAV of the
// same samples does — on every platform, Linux's included.

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "qa_framed_fixture.h"

#define QA_AUDIO_FORMAT_UNKNOWN 0
#define QA_AUDIO_FORMAT_WAV 1
#define QA_AUDIO_FORMAT_FLAC 2
#define QA_AUDIO_FORMAT_MP3 3
#define QA_AUDIO_FORMAT_MOVIE_PCM 6

extern int32_t qa_audio_decode_span(const char* path,
                                    int64_t offset,
                                    int64_t length,
                                    int32_t framed,
                                    float** out_samples,
                                    int64_t* out_frame_count,
                                    int32_t* out_channels,
                                    int32_t* out_sample_rate);

extern void qa_audio_decode_free(float* samples);

extern int32_t qa_audio_decode_span_window(const char* path,
                                           int64_t offset,
                                           int64_t length,
                                           int32_t framed,
                                           int64_t window_start,
                                           int64_t window_count,
                                           float** out_samples,
                                           int64_t* out_frame_count,
                                           int32_t* out_channels,
                                           int32_t* out_sample_rate);

typedef struct qa_audio_stream qa_audio_stream;

extern qa_audio_stream* qa_audio_stream_open(const char* path,
                                             int64_t offset,
                                             int64_t length,
                                             int32_t framed,
                                             int32_t* out_format,
                                             int32_t* out_channels,
                                             int32_t* out_sample_rate);

extern int64_t qa_audio_stream_read(qa_audio_stream* stream, float* out,
                                    int64_t frames);

extern void qa_audio_stream_close(qa_audio_stream* stream);

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

// ---------------------------------------------------------------------------
// Movies whose sound is uncompressed (section 12), written box by box.

/// One way a writer stores a movie's sound: the sample description's type,
/// version and the bits it says; how each sample is stored — its bytes, its
/// order, and its kind ('s' signed, 'u' offset binary, 'f' floating point);
/// where an `enda` of 1 is (0 nowhere, 1 in a `wave`, 2 the description's
/// own); a version-2 description's flags, and the frames it says a packet
/// holds (0: one).
typedef struct {
  const char* name;
  char type[5];
  int version;
  int bits;
  int sample_bytes;
  int big_endian;
  char kind;
  int enda;
  uint32_t flags;
  int channels;
  int rate;
  int packet_frames;
} movie_sound;

/// How a movie lays its sound out. [chunks] is the frames of each chunk in
/// order, ending at 0; [between] the bytes of something else before each
/// chunk, as a reel's picture sits between its sound's chunks. The movie box
/// comes first when [movie_first], as a movie made for streaming has it.
/// [frames_said] is what the size table counts (0: the chunks' frames), and
/// [chunks_said] what the chunk table counts (0: the chunks); [reference]
/// is the data reference the description names (0: the first), after
/// [others_first] references to another file; [no_dinf] leaves the data
/// information out; a sample lasts [tick] ticks (0: 1) of a media clock of
/// [scale] a second (0: the rate). The rest is wrong on purpose, for the
/// movies that must not be read: the data in another file ([elsewhere]),
/// [descriptions] descriptions (0: 1).
typedef struct {
  const movie_sound* sound;
  const int* chunks;
  int co64;
  int movie_first;
  int between;
  int size_one;
  int elsewhere;
  int tick;
  int descriptions;
  int frames_said;
  int reference;
  int no_dinf;
  int scale;
  int others_first;
  int chunks_said;
} movie_layout;

#define MOVIE_MAX_CHUNKS 2048
#define MOVIE_CAPACITY (160 * 1024)

/// The sound every movie holds: sample [index] as a fraction of full scale,
/// times 2^31 — each shape stores it at its own precision.
static int32_t movie_sound_sample(int64_t index) {
  return (int32_t)((uint32_t)index * 2654435761u + 0x9E3779B9u);
}

/// Sample [index] of that sound as [sound] stores it — little-endian — into
/// [out]; as a WAV holds it when [as_wav], whose 8-bit sound is offset
/// binary.
static void movie_sample_bytes(const movie_sound* sound, int64_t index,
                               int as_wav, uint8_t* out) {
  const int32_t full = movie_sound_sample(index);
  uint64_t bits = 0;
  if (sound->kind == 'f' && sound->sample_bytes == 4) {
    const float value = (float)full / 2147483648.0f;
    uint32_t word = 0;
    memcpy(&word, &value, sizeof(word));
    bits = word;
  } else if (sound->kind == 'f') {
    const double value = (double)full / 2147483648.0;
    memcpy(&bits, &value, sizeof(bits));
  } else if (sound->sample_bytes >= 4) {
    // As wide or wider: its 32 bits at the top of the sample.
    bits = (uint64_t)(uint32_t)full << (8 * sound->sample_bytes - 32);
  } else if (sound->sample_bytes > 0) {
    bits = (uint64_t)(int64_t)(full >> (32 - 8 * sound->sample_bytes));
    if (sound->sample_bytes == 1 && (sound->kind == 'u' || as_wav)) {
      bits ^= 0x80;
    }
  }
  for (int byte = 0; byte < sound->sample_bytes; byte += 1) {
    out[byte] = (uint8_t)(bits >> (8 * byte));
  }
}

typedef struct {
  uint8_t* bytes;
  size_t capacity;
  size_t length;
  size_t open[12];
  int depth;
  int overflow;
} movie_writer;

static void movie_put(movie_writer* writer, const void* bytes, size_t count) {
  if (writer->length + count > writer->capacity) {
    writer->overflow = 1;
    return;
  }
  memcpy(writer->bytes + writer->length, bytes, count);
  writer->length += count;
}

static void movie_be(movie_writer* writer, uint64_t value, int count) {
  uint8_t bytes[8];
  for (int index = 0; index < count; index += 1) {
    bytes[index] = (uint8_t)(value >> (8 * (count - 1 - index)));
  }
  movie_put(writer, bytes, (size_t)count);
}

static void movie_zeros(movie_writer* writer, int count) {
  for (int index = 0; index < count; index += 1) {
    movie_be(writer, 0, 1);
  }
}

static void movie_begin(movie_writer* writer, const char* type) {
  writer->open[writer->depth] = writer->length;
  writer->depth += 1;
  movie_be(writer, 0, 4);
  movie_put(writer, type, 4);
}

static void movie_end(movie_writer* writer) {
  writer->depth -= 1;
  const size_t at = writer->open[writer->depth];
  if (writer->overflow) {
    return;
  }
  const uint32_t size = (uint32_t)(writer->length - at);
  for (int index = 0; index < 4; index += 1) {
    writer->bytes[at + index] = (uint8_t)(size >> (8 * (3 - index)));
  }
}

/// A header's matrix: the identity.
static void movie_matrix(movie_writer* writer) {
  static const uint32_t matrix[9] = {0x10000, 0, 0, 0, 0x10000,
                                     0,       0, 0, 0x40000000};
  for (int index = 0; index < 9; index += 1) {
    movie_be(writer, matrix[index], 4);
  }
}

static void movie_description(movie_writer* writer, const movie_sound* sound,
                              int reference) {
  movie_begin(writer, sound->type);
  movie_zeros(writer, 6);
  movie_be(writer, (uint64_t)(reference > 0 ? reference : 1), 2);
  movie_be(writer, (uint64_t)sound->version, 2);
  movie_zeros(writer, 6);  // revision, vendor
  if (sound->version == 2) {
    movie_be(writer, 3, 2);
    movie_be(writer, 16, 2);
    movie_be(writer, 0xFFFE, 2);
    movie_be(writer, 0, 2);
    movie_be(writer, 0x10000, 4);
    movie_be(writer, 72, 4);  // the description's own size
    const double rate = sound->rate;
    uint64_t rate_bits = 0;
    memcpy(&rate_bits, &rate, sizeof(rate_bits));
    movie_be(writer, rate_bits, 8);
    movie_be(writer, (uint64_t)sound->channels, 4);
    movie_be(writer, 0x7F000000, 4);
    movie_be(writer, (uint64_t)sound->bits, 4);
    movie_be(writer, sound->flags, 4);
    const int packet_frames =
        sound->packet_frames > 0 ? sound->packet_frames : 1;
    movie_be(writer,
             (uint64_t)(packet_frames * sound->channels * sound->sample_bytes),
             4);
    movie_be(writer, (uint64_t)packet_frames, 4);
  } else {
    movie_be(writer, (uint64_t)sound->channels, 2);
    movie_be(writer, (uint64_t)sound->bits, 2);
    movie_zeros(writer, 4);  // compression, packet size
    movie_be(writer, (uint64_t)sound->rate << 16, 4);
    if (sound->version == 1) {
      movie_be(writer, 1, 4);  // samples a packet
      movie_be(writer, (uint64_t)sound->sample_bytes, 4);
      movie_be(writer, (uint64_t)(sound->channels * sound->sample_bytes), 4);
      movie_be(writer, (uint64_t)sound->sample_bytes, 4);
    }
  }
  if (sound->enda == 1) {
    // ffmpeg's shape: the original format, the byte order, and an empty box
    // that ends the list.
    movie_begin(writer, "wave");
    movie_begin(writer, "frma");
    movie_put(writer, sound->type, 4);
    movie_end(writer);
    movie_begin(writer, "enda");
    movie_be(writer, 1, 2);
    movie_end(writer);
    movie_be(writer, 8, 4);
    movie_be(writer, 0, 4);
    movie_end(writer);
  } else if (sound->enda == 2) {
    movie_begin(writer, "enda");
    movie_be(writer, 1, 2);
    movie_end(writer);
  }
  movie_end(writer);
}

/// The movie box of [layout], [frames] frames of sound in chunks at
/// [offsets] — [count] of them.
static void movie_box(movie_writer* writer, const movie_layout* layout,
                      const uint64_t* offsets, int count, int frames) {
  const movie_sound* sound = layout->sound;
  const int tick = layout->tick > 0 ? layout->tick : 1;
  movie_begin(writer, "moov");
  movie_begin(writer, "mvhd");
  movie_zeros(writer, 12);  // version, flags, created, modified
  movie_be(writer, (uint64_t)sound->rate, 4);
  movie_be(writer, (uint64_t)frames, 4);
  movie_be(writer, 0x10000, 4);  // played at 1.0
  movie_be(writer, 0x100, 2);    // at full volume
  movie_zeros(writer, 10);
  movie_matrix(writer);
  movie_zeros(writer, 24);  // preview, poster, selection, current
  movie_be(writer, 2, 4);   // the next track's number
  movie_end(writer);
  movie_begin(writer, "trak");
  movie_begin(writer, "tkhd");
  movie_be(writer, 0xF, 4);  // enabled, in the movie, preview and poster
  movie_zeros(writer, 8);
  movie_be(writer, 1, 4);
  movie_zeros(writer, 4);
  movie_be(writer, (uint64_t)frames, 4);
  movie_zeros(writer, 12);  // reserved, layer, alternate group
  movie_be(writer, 0x100, 2);
  movie_zeros(writer, 2);
  movie_matrix(writer);
  movie_zeros(writer, 8);  // width, height
  movie_end(writer);
  movie_begin(writer, "mdia");
  movie_begin(writer, "mdhd");
  movie_zeros(writer, 12);
  movie_be(writer, (uint64_t)(layout->scale > 0 ? layout->scale : sound->rate),
           4);
  movie_be(writer, (uint64_t)frames * (uint64_t)tick, 4);
  movie_zeros(writer, 4);  // language, quality
  movie_end(writer);
  movie_begin(writer, "hdlr");
  movie_zeros(writer, 4);
  movie_put(writer, "mhlrsoun", 8);
  movie_zeros(writer, 13);  // manufacturer, flags, mask, an empty name
  movie_end(writer);
  movie_begin(writer, "minf");
  movie_begin(writer, "smhd");
  movie_zeros(writer, 8);
  movie_end(writer);
  if (!layout->no_dinf) {
    movie_begin(writer, "dinf");
    movie_begin(writer, "dref");
    movie_zeros(writer, 4);
    movie_be(writer, (uint64_t)(layout->others_first + 1), 4);
    for (int index = 0; index <= layout->others_first; index += 1) {
      const int elsewhere = index < layout->others_first || layout->elsewhere;
      movie_begin(writer, "url ");
      // Flag 1 says the data is in this file; without it, the location
      // follows.
      movie_be(writer, elsewhere ? 0 : 1, 4);
      if (elsewhere) {
        movie_put(writer, "file:///elsewhere.mov", 22);
      }
      movie_end(writer);
    }
    movie_end(writer);
    movie_end(writer);
  }
  movie_begin(writer, "stbl");
  movie_begin(writer, "stsd");
  movie_zeros(writer, 4);
  const int descriptions = layout->descriptions > 0 ? layout->descriptions : 1;
  movie_be(writer, (uint64_t)descriptions, 4);
  for (int index = 0; index < descriptions; index += 1) {
    movie_description(writer, sound, layout->reference);
  }
  movie_end(writer);
  movie_begin(writer, "stts");
  movie_zeros(writer, 4);
  movie_be(writer, 1, 4);
  movie_be(writer, (uint64_t)frames, 4);
  movie_be(writer, (uint64_t)tick, 4);
  movie_end(writer);
  // The runs: chunks in a row holding the same frames are one entry.
  int runs = 0;
  for (int index = 0; index < count; index += 1) {
    runs += index == 0 || layout->chunks[index] != layout->chunks[index - 1];
  }
  movie_begin(writer, "stsc");
  movie_zeros(writer, 4);
  movie_be(writer, (uint64_t)runs, 4);
  for (int index = 0; index < count; index += 1) {
    if (index == 0 || layout->chunks[index] != layout->chunks[index - 1]) {
      movie_be(writer, (uint64_t)(index + 1), 4);
      movie_be(writer, (uint64_t)layout->chunks[index], 4);
      movie_be(writer, 1, 4);
    }
  }
  movie_end(writer);
  movie_begin(writer, "stsz");
  movie_zeros(writer, 4);
  movie_be(writer,
           layout->size_one
               ? 1
               : (uint64_t)(sound->channels * sound->sample_bytes),
           4);
  movie_be(writer, (uint64_t)frames, 4);
  movie_end(writer);
  movie_begin(writer, layout->co64 ? "co64" : "stco");
  movie_zeros(writer, 4);
  movie_be(writer,
           (uint64_t)(layout->chunks_said > 0 ? layout->chunks_said : count),
           4);
  for (int index = 0; index < count; index += 1) {
    movie_be(writer, offsets[index], layout->co64 ? 8 : 4);
  }
  movie_end(writer);
  movie_end(writer);  // stbl
  movie_end(writer);  // minf
  movie_end(writer);  // mdia
  movie_end(writer);  // trak
  movie_end(writer);  // moov
}

/// [layout]'s movie into [out] — its length, or 0 when it did not fit — and
/// the frames it says it has into [out_frames].
static size_t build_movie(const movie_layout* layout, uint8_t* out,
                          size_t capacity, int64_t* out_frames) {
  const movie_sound* sound = layout->sound;
  const int frame_bytes = sound->channels * sound->sample_bytes;
  int count = 0;
  int held = 0;
  while (count < MOVIE_MAX_CHUNKS && layout->chunks[count] > 0) {
    held += layout->chunks[count];
    count += 1;
  }
  const int frames = layout->frames_said > 0 ? layout->frames_said : held;
  movie_writer writer = {out, capacity, 0, {0}, 0, 0};
  movie_begin(&writer, "ftyp");
  movie_put(&writer, "qt  ", 4);
  movie_be(&writer, 0x200, 4);
  movie_put(&writer, "qt  ", 4);
  movie_end(&writer);
  movie_begin(&writer, "wide");
  movie_end(&writer);
  // Where the chunks land: from the sound box's body, each after the other
  // bytes before it.
  uint64_t offsets[MOVIE_MAX_CHUNKS];
  size_t sound_at = writer.length + 8;
  if (layout->movie_first) {
    // The movie box's size does not hang on the offsets it holds.
    static uint8_t measure[MOVIE_CAPACITY];
    movie_writer measuring = {measure, sizeof(measure), 0, {0}, 0, 0};
    memset(offsets, 0, sizeof(offsets));
    movie_box(&measuring, layout, offsets, count, frames);
    sound_at += measuring.length;
  }
  uint64_t at = sound_at;
  for (int index = 0; index < count; index += 1) {
    at += (uint64_t)layout->between;
    offsets[index] = at;
    at += (uint64_t)layout->chunks[index] * (uint64_t)frame_bytes;
  }
  if (layout->movie_first) {
    movie_box(&writer, layout, offsets, count, frames);
  }
  movie_begin(&writer, "mdat");
  int64_t frame = 0;
  for (int index = 0; index < count; index += 1) {
    for (int other = 0; other < layout->between; other += 1) {
      movie_be(&writer, (uint64_t)((other * 29 + index * 7 + 3) & 0xFF), 1);
    }
    for (int in_chunk = 0; in_chunk < layout->chunks[index]; in_chunk += 1) {
      for (int channel = 0; channel < sound->channels; channel += 1) {
        uint8_t sample[8];
        movie_sample_bytes(sound, frame * sound->channels + channel, 0,
                           sample);
        for (int byte = 0; byte < sound->sample_bytes; byte += 1) {
          const int from =
              sound->big_endian ? sound->sample_bytes - 1 - byte : byte;
          movie_be(&writer, sample[from], 1);
        }
      }
      frame += 1;
    }
  }
  movie_end(&writer);
  if (!layout->movie_first) {
    movie_box(&writer, layout, offsets, count, frames);
  }
  if (out_frames != NULL) {
    *out_frames = frames;
  }
  return writer.overflow ? 0 : writer.length;
}

/// A WAV of [frames] frames of the same sound [sound] stores — what a movie
/// of it must decode to.
static size_t build_wav_of(const movie_sound* sound, int64_t frames,
                           uint8_t* out, size_t capacity) {
  const int frame_bytes = sound->channels * sound->sample_bytes;
  const uint32_t data_bytes = (uint32_t)(frames * frame_bytes);
  if (44 + (size_t)data_bytes > capacity) {
    return 0;
  }
  memcpy(out, "RIFF", 4);
  qa_fixture_put_u32(out + 4, 36 + data_bytes);
  memcpy(out + 8, "WAVEfmt ", 8);
  qa_fixture_put_u32(out + 16, 16);
  put_u16(out + 20, sound->kind == 'f' ? 3 : 1);  // floating point, or PCM
  put_u16(out + 22, (uint16_t)sound->channels);
  qa_fixture_put_u32(out + 24, (uint32_t)sound->rate);
  qa_fixture_put_u32(out + 28, (uint32_t)(sound->rate * frame_bytes));
  put_u16(out + 32, (uint16_t)frame_bytes);
  put_u16(out + 34, (uint16_t)(8 * sound->sample_bytes));
  memcpy(out + 36, "data", 4);
  qa_fixture_put_u32(out + 40, data_bytes);
  for (int64_t index = 0; index < frames * sound->channels; index += 1) {
    movie_sample_bytes(sound, index, 1, out + 44 + index * sound->sample_bytes);
  }
  return 44 + (size_t)data_bytes;
}

/// [length] bytes of [bytes] written as a whole file — its path, or NULL
/// when it could not be written.
static const char* write_movie_fixture(const uint8_t* bytes, size_t length) {
  const char* path = "qa_audio_movie_fixture.bin";
  FILE* file = fopen(path, "wb");
  if (file == NULL) {
    printf("FAIL fixture: could not write %s\n", path);
    g_failures += 1;
    return NULL;
  }
  fwrite(bytes, 1, length, file);
  fclose(file);
  return path;
}

/// [length] bytes of [bytes] written as a whole file and decoded — which
/// decoder read them, the samples into [*samples] (freed by the caller with
/// qa_audio_decode_free), and the frames, channels and rate.
static int32_t decode_whole(const uint8_t* bytes, size_t length,
                            float** samples, int64_t* frames,
                            int32_t* channels, int32_t* rate) {
  *samples = NULL;
  *frames = 0;
  const char* path = write_movie_fixture(bytes, length);
  if (path == NULL) {
    return -1;
  }
  const int32_t format = qa_audio_decode_span(path, 0, (int64_t)length, 0,
                                              samples, frames, channels, rate);
  remove(path);
  return format;
}

/// Whether [movie] decodes — through the engine's own movie reader — to
/// exactly what a WAV of the same [frames] frames of [sound] decodes to.
static void expect_reads_as_its_wav(const char* what, const uint8_t* movie,
                                    size_t movie_bytes,
                                    const movie_sound* sound,
                                    int64_t frames) {
  static uint8_t wav[MOVIE_CAPACITY];
  char label[160];
  const size_t wav_bytes = build_wav_of(sound, frames, wav, sizeof(wav));
  float* want = NULL;
  float* got = NULL;
  int64_t want_frames = 0;
  int64_t got_frames = 0;
  int32_t want_channels = 0;
  int32_t got_channels = 0;
  int32_t want_rate = 0;
  int32_t got_rate = 0;
  snprintf(label, sizeof(label), "%s: its WAV is a WAV", what);
  expect_int(label,
             decode_whole(wav, wav_bytes, &want, &want_frames, &want_channels,
                          &want_rate),
             QA_AUDIO_FORMAT_WAV);
  snprintf(label, sizeof(label), "%s: read by the engine's movie reader",
           what);
  expect_int(label,
             decode_whole(movie, movie_bytes, &got, &got_frames, &got_channels,
                          &got_rate),
             QA_AUDIO_FORMAT_MOVIE_PCM);
  snprintf(label, sizeof(label), "%s: frames, channels and rate", what);
  expect_int(label,
             got_frames * 100000000LL + got_channels * 1000000LL + got_rate,
             frames * 100000000LL + sound->channels * 1000000LL +
                 sound->rate);
  snprintf(label, sizeof(label), "%s: its WAV says the same", what);
  expect_int(label, want_frames * 100 + want_channels,
             frames * 100 + sound->channels);
  if (want != NULL && got != NULL && got_frames == want_frames &&
      got_channels == want_channels) {
    int64_t differs = -1;
    for (int64_t index = 0; index < got_frames * got_channels; index += 1) {
      if (memcmp(&got[index], &want[index], sizeof(float)) != 0) {
        differs = index;
        break;
      }
    }
    snprintf(label, sizeof(label),
             "%s: the first sample that differs from its WAV's", what);
    expect_int(label, differs, -1);
  }
  qa_audio_decode_free(want);
  qa_audio_decode_free(got);
}

/// Which decoder opens [layout]'s movie — for the movies that must not be
/// read as PCM by the engine.
///
/// ⚠️Asked of the stream as it opens, not of a whole decode: a decode can
/// fail for its own reasons (a sound too wide to hold whole), and a decode
/// that fails reads like a movie refused.
static int32_t movie_format(const movie_layout* layout) {
  static uint8_t movie[MOVIE_CAPACITY];
  const size_t bytes = build_movie(layout, movie, sizeof(movie), NULL);
  if (bytes == 0) {
    // ⚠️Nothing read is not a movie refused.
    printf("FAIL fixture: a movie did not fit in its buffer\n");
    g_failures += 1;
    return -1;
  }
  const char* path = write_movie_fixture(movie, bytes);
  if (path == NULL) {
    return -1;
  }
  int32_t format = QA_AUDIO_FORMAT_UNKNOWN;
  int32_t channels = 0;
  int32_t rate = 0;
  qa_audio_stream* stream = qa_audio_stream_open(path, 0, (int64_t)bytes, 0,
                                                 &format, &channels, &rate);
  qa_audio_stream_close(stream);
  remove(path);
  return format;
}

/// The sound most writers store — ffmpeg's `.mov` of 16-bit stereo.
static const movie_sound kMovieSowt = {
    "sowt", "sowt", 0, 16, 2, 0, 's', 0, 0, 2, 48000};

/// A reel's sound: chunks of three sizes between other bytes.
static const int kMovieReelChunks[] = {250, 250, 70, 250, 30, 0};

/// The reel's movie into [out] (MOVIE_CAPACITY) — its length.
static size_t build_reel_movie(uint8_t* out) {
  const movie_layout reel = {
      .sound = &kMovieSowt, .chunks = kMovieReelChunks, .between = 77};
  return build_movie(&reel, out, MOVIE_CAPACITY, NULL);
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

  // 10. A WINDOW IS THE WHOLE DECODE'S OWN FRAMES — only those held. Every
  // decoder decodes from the start and keeps the window, so the frames must
  // be the whole decode's, not merely like them; past the end is silence
  // (no frames, still the format); nothing at all is the probe that says the
  // rate.
  {
    static uint8_t mp3[MP3_FRAMES * MP3_FRAME_BYTES];
    static uint8_t flac[FLAC_BYTES];
    static uint8_t reel[MOVIE_CAPACITY];
    const struct {
      const char* name;
      const uint8_t* body;
      size_t bytes;
      int32_t format;
    } sounds[] = {
        {"a WAV", wav, wav_bytes, QA_AUDIO_FORMAT_WAV},
        {"a FLAC", flac, build_flac(flac), QA_AUDIO_FORMAT_FLAC},
        {"an MP3", mp3, build_mp3_frames(mp3), QA_AUDIO_FORMAT_MP3},
        {"a movie's PCM in a reel's chunks", reel, build_reel_movie(reel),
         QA_AUDIO_FORMAT_MOVIE_PCM},
    };
    const char* path = "qa_audio_window_fixture.bin";
    for (size_t index = 0; index < sizeof(sounds) / sizeof(sounds[0]);
         index += 1) {
      FILE* file = fopen(path, "wb");
      if (file == NULL) {
        printf("FAIL fixture: could not write %s\n", path);
        g_failures += 1;
        break;
      }
      fwrite(sounds[index].body, 1, sounds[index].bytes, file);
      fclose(file);
      const int64_t length = (int64_t)sounds[index].bytes;
      float* whole = NULL;
      int64_t whole_frames = 0;
      int32_t channels = 0;
      int32_t rate = 0;
      qa_audio_decode_span(path, 0, length, 0, &whole, &whole_frames,
                           &channels, &rate);

      char label[128];
      const struct {
        const char* name;
        int64_t start;
        int64_t count;
        int64_t frames;
      } windows[] = {
          {"inside", 100, 50, 50},
          {"running past the end", whole_frames - 10, 50, 10},
          {"past the end", whole_frames + 5, 50, 0},
          {"the probe", 0, 0, 0},
      };
      for (size_t at = 0; at < sizeof(windows) / sizeof(windows[0]);
           at += 1) {
        float* samples = NULL;
        int64_t frames = -1;
        int32_t window_channels = 0;
        int32_t window_rate = 0;
        const int32_t format = qa_audio_decode_span_window(
            path, 0, length, 0, windows[at].start, windows[at].count,
            &samples, &frames, &window_channels, &window_rate);
        snprintf(label, sizeof(label), "%s, a window %s: which decoder",
                 sounds[index].name, windows[at].name);
        expect_int(label, format, sounds[index].format);
        snprintf(label, sizeof(label), "%s, a window %s: frames",
                 sounds[index].name, windows[at].name);
        expect_int(label, frames, windows[at].frames);
        snprintf(label, sizeof(label), "%s, a window %s: rate",
                 sounds[index].name, windows[at].name);
        expect_int(label, window_rate, rate);
        snprintf(label, sizeof(label), "%s, a window %s: channels",
                 sounds[index].name, windows[at].name);
        expect_int(label, window_channels, channels);
        if (samples != NULL && whole != NULL && frames == windows[at].frames) {
          int same = 1;
          for (int64_t sample = 0; sample < frames * channels; sample += 1) {
            if (samples[sample] !=
                whole[windows[at].start * channels + sample]) {
              same = 0;
              break;
            }
          }
          snprintf(label, sizeof(label),
                   "%s, a window %s: the whole decode's own frames",
                   sounds[index].name, windows[at].name);
          expect_int(label, same, 1);
        }
        qa_audio_decode_free(samples);
      }
      qa_audio_decode_free(whole);
    }
    remove(path);
  }

  // 11. A STREAM READ A PIECE AT A TIME IS THE WHOLE DECODE. A conform is
  // made from the stream as it reads on, so the pieces — of any size, across
  // the decoders' own blocks — must be the whole decode's frames exactly,
  // the lead counted once (an MP3's standard one, a LAME tag's), and nothing
  // past the end.
  {
    static uint8_t mp3[MP3_FRAMES * MP3_FRAME_BYTES];
    static uint8_t tagged[MP3_FRAMES * MP3_FRAME_BYTES];
    static uint8_t flac[FLAC_BYTES];
    static uint8_t reel[MOVIE_CAPACITY];
    const struct {
      const char* name;
      const uint8_t* body;
      size_t bytes;
      int32_t format;
    } sounds[] = {
        {"a WAV", wav, wav_bytes, QA_AUDIO_FORMAT_WAV},
        {"a FLAC", flac, build_flac(flac), QA_AUDIO_FORMAT_FLAC},
        {"an MP3", mp3, build_mp3_frames(mp3), QA_AUDIO_FORMAT_MP3},
        {"an MP3 with a LAME tag", tagged, build_tagged_mp3_frames(tagged),
         QA_AUDIO_FORMAT_MP3},
        {"a movie's PCM in a reel's chunks", reel, build_reel_movie(reel),
         QA_AUDIO_FORMAT_MOVIE_PCM},
    };
    static const int64_t pieces[] = {1, 7, 333, 4096, 5000, 2};
    const char* path = "qa_audio_stream_fixture.bin";
    for (size_t index = 0; index < sizeof(sounds) / sizeof(sounds[0]);
         index += 1) {
      FILE* file = fopen(path, "wb");
      if (file == NULL) {
        printf("FAIL fixture: could not write %s\n", path);
        g_failures += 1;
        break;
      }
      fwrite(sounds[index].body, 1, sounds[index].bytes, file);
      fclose(file);
      const int64_t length = (int64_t)sounds[index].bytes;
      float* whole = NULL;
      int64_t whole_frames = 0;
      int32_t channels = 0;
      int32_t rate = 0;
      qa_audio_decode_span(path, 0, length, 0, &whole, &whole_frames,
                           &channels, &rate);

      char label[128];
      int32_t format = 0;
      int32_t stream_channels = 0;
      int32_t stream_rate = 0;
      qa_audio_stream* stream = qa_audio_stream_open(
          path, 0, length, 0, &format, &stream_channels, &stream_rate);
      snprintf(label, sizeof(label), "%s, as a stream: which decoder",
               sounds[index].name);
      expect_int(label, format, sounds[index].format);
      snprintf(label, sizeof(label), "%s, as a stream: channels and rate",
               sounds[index].name);
      expect_int(label, stream_channels * 1000000LL + stream_rate,
                 channels * 1000000LL + rate);
      if (stream != NULL && whole != NULL && channels > 0) {
        // A piece of room past the whole, so a stream that runs on shows.
        float* read = (float*)malloc((size_t)(whole_frames + 5000) *
                                     (size_t)channels * sizeof(float));
        int64_t frames = 0;
        for (size_t piece = 0; read != NULL; piece += 1) {
          const int64_t want =
              pieces[piece % (sizeof(pieces) / sizeof(*pieces))];
          const int64_t got =
              qa_audio_stream_read(stream, read + frames * channels, want);
          if (got <= 0 || frames + got > whole_frames) {
            frames += got > 0 ? got : 0;
            break;
          }
          frames += got;
        }
        snprintf(label, sizeof(label), "%s, as a stream: frames",
                 sounds[index].name);
        expect_int(label, frames, whole_frames);
        int same = read != NULL && frames == whole_frames;
        for (int64_t sample = 0; same && sample < frames * channels;
             sample += 1) {
          same = read[sample] == whole[sample];
        }
        snprintf(label, sizeof(label),
                 "%s, as a stream: the whole decode's own frames",
                 sounds[index].name);
        expect_int(label, same, 1);
        float spare[16];
        snprintf(label, sizeof(label), "%s, as a stream: nothing past the end",
                 sounds[index].name);
        expect_int(label, qa_audio_stream_read(stream, spare, 4), 0);
        free(read);
      }
      qa_audio_stream_close(stream);
      qa_audio_decode_free(whole);
    }
    remove(path);
    int32_t format = -1;
    int32_t stream_channels = -1;
    int32_t stream_rate = -1;
    expect_int("a missing file opens no stream",
               qa_audio_stream_open("qa_no_such_file.bin", 0, 16, 0, &format,
                                    &stream_channels, &stream_rate) == NULL,
               1);
    expect_int("and says nothing about one", format + stream_channels +
                                                 stream_rate,
               0);
  }

  // 12. A MOVIE'S UNCOMPRESSED SOUND IS READ HERE, AS A WAV OF THE SAME
  // SAMPLES IS (board mac-reads-no-movie-pcm) — every way a writer stores
  // it, laid out as a reel lays it out, and nothing that is not it.
  {
    static const movie_sound sounds[] = {
        {"ffmpeg's 16-bit: sowt, version 0", "sowt", 0, 16, 2, 0, 's', 0, 0,
         2, 48000},
        {"16-bit big-endian: twos", "twos", 0, 16, 2, 1, 's', 0, 0, 2, 44100},
        {"8-bit signed: twos", "twos", 0, 8, 1, 1, 's', 0, 0, 1, 22050},
        {"8-bit offset binary: raw", "raw ", 0, 8, 1, 0, 'u', 0, 0, 2, 22050},
        {"24-bit big-endian: twos, by its bits as ffmpeg reads them", "twos",
         0, 24, 3, 1, 's', 0, 0, 2, 48000},
        // ffmpeg writes 16 bits for these and reads them by their names.
        {"ffmpeg's 24-bit: in24, version 1, an enda in its wave", "in24", 1,
         16, 3, 0, 's', 1, 0, 2, 48000},
        {"24-bit big-endian: in24 without an enda", "in24", 0, 24, 3, 1, 's',
         0, 0, 2, 48000},
        {"ffmpeg's 32-bit: in32, version 1, an enda in its wave", "in32", 1,
         16, 4, 0, 's', 1, 0, 2, 48000},
        {"32-bit float: fl32 with an enda of its own", "fl32", 1, 32, 4, 0,
         'f', 2, 0, 2, 48000},
        {"32-bit float big-endian: fl32", "fl32", 0, 32, 4, 1, 'f', 0, 0, 2,
         48000},
        {"fl32, version 0, an enda of its own", "fl32", 0, 32, 4, 0, 'f', 2, 0,
         2, 48000},
        {"in24 in a version-2 description, an enda in its wave", "in24", 2, 24,
         3, 0, 's', 1, 0, 2, 48000},
        {"64-bit float: fl64, an enda in its wave", "fl64", 1, 64, 8, 0, 'f',
         1, 0, 2, 48000},
        // Core Audio's flags: float 1, big-endian 2, signed 4, packed 8.
        {"ffmpeg past 65,535 Hz: lpcm, 24-bit at 96 kHz", "lpcm", 2, 24, 3, 0,
         's', 0, 4 | 8, 2, 96000},
        {"lpcm, 32-bit float big-endian", "lpcm", 2, 32, 4, 1, 'f', 0,
         1 | 2 | 8, 2, 48000},
        {"lpcm, 16-bit in six channels", "lpcm", 2, 16, 2, 0, 's', 0, 4 | 8, 6,
         48000},
        {"lpcm, 16-bit big-endian", "lpcm", 2, 16, 2, 1, 's', 0, 2 | 4 | 8, 2,
         48000},
        {"lpcm, unsigned 8-bit", "lpcm", 2, 8, 1, 0, 'u', 0, 8, 2, 22050},
    };
    static uint8_t movie[MOVIE_CAPACITY];
    for (size_t index = 0; index < sizeof(sounds) / sizeof(sounds[0]);
         index += 1) {
      const movie_layout layout = {.sound = &sounds[index],
                                   .chunks = kMovieReelChunks,
                                   .between = 77};
      int64_t frames = 0;
      const size_t bytes = build_movie(&layout, movie, sizeof(movie), &frames);
      expect_reads_as_its_wav(sounds[index].name, movie, bytes, &sounds[index],
                              frames);
    }

    // Longer than one read of the reader's; and a reel of so many chunks,
    // each a run of its own, that both tables are read in more than one
    // batch.
    static const int one_chunk[] = {5000, 0};
    static int long_reel[1501];
    for (int index = 0; index < 1500; index += 1) {
      long_reel[index] = 1 + index % 2;
    }
    const struct {
      const char* name;
      movie_layout layout;
    } layouts[] = {
        {"one chunk longer than a read",
         {.sound = &kMovieSowt, .chunks = one_chunk}},
        {"a reel of 1,500 chunks, each a run of its own",
         {.sound = &kMovieSowt, .chunks = long_reel, .between = 7}},
        {"a reel's chunks at 64-bit offsets",
         {.sound = &kMovieSowt, .chunks = kMovieReelChunks, .between = 77,
          .co64 = 1}},
        {"a reel's chunks behind the movie box",
         {.sound = &kMovieSowt, .chunks = kMovieReelChunks, .between = 77,
          .movie_first = 1}},
        {"a size table that says 1 a sample, as old QuickTime wrote",
         {.sound = &kMovieSowt, .chunks = kMovieReelChunks, .between = 77,
          .size_one = 1}},
        // The size table's count is the sound's frames, whatever its chunks
        // hold past it.
        {"a size table that counts fewer frames than the chunks hold",
         {.sound = &kMovieSowt, .chunks = kMovieReelChunks, .between = 77,
          .frames_said = 840}},
        {"a movie without data information",
         {.sound = &kMovieSowt, .chunks = kMovieReelChunks, .between = 77,
          .no_dinf = 1}},
        {"the second of two data references, this file's",
         {.sound = &kMovieSowt, .chunks = kMovieReelChunks, .between = 77,
          .reference = 2, .others_first = 1}},
        // A sample is a frame of the media's clock, whatever it ticks at.
        {"a media clock twice the rate, a sample two ticks of it",
         {.sound = &kMovieSowt, .chunks = kMovieReelChunks, .between = 77,
          .tick = 2, .scale = 96000}},
    };
    for (size_t index = 0; index < sizeof(layouts) / sizeof(layouts[0]);
         index += 1) {
      int64_t frames = 0;
      const size_t bytes =
          build_movie(&layouts[index].layout, movie, sizeof(movie), &frames);
      expect_reads_as_its_wav(layouts[index].name, movie, bytes, &kMovieSowt,
                              frames);
    }

    // Kept FRAMED, the sound and its tables lie in blocks apart.
    {
      const size_t bytes = build_reel_movie(movie);
      const char* framed = "qa_audio_movie_framed.bin";
      FILE* file = fopen(framed, "wb");
      uint32_t lengths[QA_FIXTURE_MAX_BLOCKS];
      int64_t blob = -1;
      if (file != NULL) {
        blob = qa_fixture_write_framed(file, movie, (int64_t)bytes, 512,
                                       lengths);
        fclose(file);
      }
      float* plain = NULL;
      float* samples = NULL;
      int64_t plain_frames = 0;
      int64_t frames = 0;
      int32_t channels = 0;
      int32_t rate = 0;
      decode_whole(movie, bytes, &plain, &plain_frames, &channels, &rate);
      expect_int("a movie kept framed: the engine's to read",
                 blob > 0 ? qa_audio_decode_span(framed, 0, blob, 1, &samples,
                                                 &frames, &channels, &rate)
                          : -1,
                 QA_AUDIO_FORMAT_MOVIE_PCM);
      int same = samples != NULL && plain != NULL && frames == plain_frames;
      for (int64_t index = 0; same && index < frames * 2; index += 1) {
        same = samples[index] == plain[index];
      }
      expect_int("a movie kept framed: the frames it has plain", same, 1);
      qa_audio_decode_free(samples);
      qa_audio_decode_free(plain);
      remove(framed);
    }

    // A movie cut short ends where its bytes do, as dr_wav ends a WAV cut
    // short: 101 bytes off the reel's last chunk of 30 frames leave 4 whole.
    {
      const movie_layout streaming = {.sound = &kMovieSowt,
                                      .chunks = kMovieReelChunks,
                                      .between = 77,
                                      .movie_first = 1};
      int64_t frames = 0;
      const size_t bytes =
          build_movie(&streaming, movie, sizeof(movie), &frames);
      float* whole = NULL;
      float* cut = NULL;
      int64_t whole_frames = 0;
      int64_t cut_frames = 0;
      int32_t channels = 0;
      int32_t rate = 0;
      decode_whole(movie, bytes, &whole, &whole_frames, &channels, &rate);
      expect_int("a movie cut short: still the engine's to read",
                 decode_whole(movie, bytes - 101, &cut, &cut_frames, &channels,
                              &rate),
                 QA_AUDIO_FORMAT_MOVIE_PCM);
      expect_int("a movie cut short: ends where its bytes do", cut_frames,
                 frames - 26);
      int same = whole != NULL && cut != NULL && cut_frames <= whole_frames;
      for (int64_t index = 0; same && index < cut_frames * 2; index += 1) {
        same = cut[index] == whole[index];
      }
      expect_int("a movie cut short: what it holds is read", same, 1);
      qa_audio_decode_free(whole);
      qa_audio_decode_free(cut);
    }

    // ⛔What is not uncompressed sound in this file is not read as it: noise
    // where the samples are elsewhere, or are not frames, or change their
    // shape; and what a codec must read stays the OS stack's.
    static const movie_sound shapes_refused[] = {
        {"AAC", "mp4a", 0, 16, 2, 0, 's', 0, 0, 2, 48000},
        {"lpcm with one channel after another", "lpcm", 2, 16, 2, 0, 's', 0,
         4 | 8 | 32, 2, 48000},
        // Aligned high (16) in words wider than its bits.
        {"lpcm with 24 bits in 32-bit words", "lpcm", 2, 24, 4, 0, 's', 0,
         4 | 16, 2, 48000},
        {"lpcm with two frames a packet", "lpcm", 2, 16, 2, 0, 's', 0, 4 | 8, 2,
         48000, 2},
        {"lpcm of 12 bits in a byte a sample", "lpcm", 2, 12, 1, 0, 's', 0,
         4 | 8, 2, 48000},
        // Sound dr_wav has no conversion for.
        {"lpcm of unsigned 16 bits", "lpcm", 2, 16, 2, 0, 'u', 0, 8, 2, 48000},
        {"lpcm of 64-bit integers", "lpcm", 2, 64, 8, 0, 's', 0, 4 | 8, 2,
         48000},
        {"a twos of 12 bits", "twos", 0, 12, 2, 1, 's', 0, 0, 2, 48000},
        {"a raw of 16 bits", "raw ", 0, 16, 2, 1, 's', 0, 0, 2, 48000},
        // Nothing to size a frame by, or to play it at.
        {"a twos of no bits", "twos", 0, 0, 0, 1, 's', 0, 0, 2, 48000},
        {"a sound of no channels", "sowt", 0, 16, 2, 0, 's', 0, 0, 0, 48000},
        {"a sound at 0 Hz", "sowt", 0, 16, 2, 0, 's', 0, 0, 2, 0},
        {"lpcm of no channels", "lpcm", 2, 16, 2, 0, 's', 0, 4 | 8, 0, 48000},
        {"lpcm at 0 Hz", "lpcm", 2, 16, 2, 0, 's', 0, 4 | 8, 2, 0},
    };
    for (size_t index = 0;
         index < sizeof(shapes_refused) / sizeof(shapes_refused[0]);
         index += 1) {
      const movie_layout layout = {.sound = &shapes_refused[index],
                                   .chunks = kMovieReelChunks,
                                   .between = 77};
      char label[128];
      snprintf(label, sizeof(label), "%s is not the engine's movie PCM",
               shapes_refused[index].name);
      expect_int(label, movie_format(&layout) == QA_AUDIO_FORMAT_MOVIE_PCM,
                 0);
    }
    // ⚠️No more channels than a version-0 description can say.
    static const movie_sound too_wide = {
        "lpcm", "lpcm", 2, 16, 2, 0, 's', 0, 4 | 8, 65536, 48000};
    static const int one_frame[] = {1, 0};
    const struct {
      const char* name;
      movie_layout layout;
    } refused[] = {
        {"a movie whose sound is in another file",
         {.sound = &kMovieSowt, .chunks = kMovieReelChunks, .between = 77,
          .elsewhere = 1}},
        // Media Foundation's reading: no sound where the list says none.
        {"a description naming a reference the list does not have",
         {.sound = &kMovieSowt, .chunks = kMovieReelChunks, .between = 77,
          .reference = 2}},
        // Ahead of its sound, as the table that ends a file would end any
        // read past it.
        {"a chunk table that counts more chunks than it holds",
         {.sound = &kMovieSowt, .chunks = kMovieReelChunks, .between = 77,
          .movie_first = 1, .chunks_said = 6}},
        {"a sound whose samples last two ticks of a clock at its rate",
         {.sound = &kMovieSowt, .chunks = kMovieReelChunks, .between = 77,
          .tick = 2}},
        {"a sound described two ways",
         {.sound = &kMovieSowt, .chunks = kMovieReelChunks, .between = 77,
          .descriptions = 2}},
        {"lpcm of 65,536 channels", {.sound = &too_wide, .chunks = one_frame}},
    };
    for (size_t index = 0; index < sizeof(refused) / sizeof(refused[0]);
         index += 1) {
      char label[128];
      snprintf(label, sizeof(label), "%s is not the engine's movie PCM",
               refused[index].name);
      expect_int(label,
                 movie_format(&refused[index].layout) ==
                     QA_AUDIO_FORMAT_MOVIE_PCM,
                 0);
    }
  }

  if (g_failures == 0) {
    printf("qa_audio_range: all checks passed\n");
    return 0;
  }
  printf("qa_audio_range: %d check(s) failed\n", g_failures);
  return 1;
}
