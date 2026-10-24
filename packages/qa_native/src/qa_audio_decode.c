// Audio file decoding (audio program 2B) — WAV, FLAC and MP3 through the
// vendored dr_libs.
//
// A SEPARATE translation unit from qa_engine.c on purpose: the dr_libs
// implementations are ~27k lines between them, and folding that into the
// engine would slow every build of the hot loops and mix third-party
// warnings into ours.
//
// 🪦This USED to decode from memory and never from a path, because "handing
// C a `const char*` would drag in the whole Windows question of whether that
// path is UTF-8 or the local codepage, and a Korean filename would decide it
// the hard way". ⚠️THE HAZARD IS REAL AND THE REASON IS NOT ANY MORE: the
// video decoder answered that question — UTF-8 in, `MultiByteToWideChar`
// once, wide the rest of the way — and `qa_platform_path.h` is that answer
// as ONE piece of code both decoders call. A second copy of it here is the
// only way the Korean filename comes back.
//
// Why a path at all: a container inside the project file is a SPAN of one,
// and the whole point is not to hold the container in memory to decode it.
// A three-gigabyte movie whose sound we want cannot arrive as a `Uint8List`.
// 🪦This went on 「Memory stays a first-class origin — a FRAMED archive entry
// is not a contiguous range, so its bytes genuinely arrive assembled.」 It
// stopped being true on 2026-09-24: the library's one span reader reads a
// framed span itself (`qa_media_span.h`), so nothing arrives assembled.
//
// Nothing here is realtime. Decoding happens ONCE at import, which is the
// entire point of conforming — a variable-length codec cannot promise to
// finish inside an audio callback, and the callback cannot wait.

#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#if defined(_WIN32)
#define QA_EXPORT __declspec(dllexport)
#else
#define QA_EXPORT __attribute__((visibility("default")))
#endif

// System headers come BEFORE the vendored decoders: stb_vorbis defines
// short helper macros that must not be in scope when winnt.h/mfapi.h
// parse (the Media Foundation implementation itself sits further down).
#if defined(_WIN32)
#define COBJMACROS
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <mfapi.h>
#include <mfidl.h>
#include <mfreadwrite.h>
#elif defined(__APPLE__)
#include <AudioToolbox/AudioToolbox.h>
#elif defined(__ANDROID__)
#include <fcntl.h>
#include <unistd.h>
#endif

// ⚠️AFTER the block above, for the same reason the comment there gives: this
// TU decides COBJMACROS and WIN32_LEAN_AND_MEAN, and a header that reached
// windows.h first would settle both with the wrong answer.
#include "qa_media_span.h"
#include "qa_platform_path.h"

// One implementation of each, here and nowhere else.
#define DR_WAV_IMPLEMENTATION
#define DR_FLAC_IMPLEMENTATION
#define DR_MP3_IMPLEMENTATION

// ⛔Still off after the range open arrived, and now for a BETTER reason than
// 「we never decode from a path」: these three take read/seek callbacks, so
// they reach a file through the one cursor below and their own stdio
// backends would be a second way to do it — with `fopen` and a narrow path,
// which is exactly the encoding problem. stb_vorbis is the exception and
// says why where it is included.
#define DR_WAV_NO_STDIO
#define DR_FLAC_NO_STDIO
#define DR_MP3_NO_STDIO

#include "third_party/dr_libs/dr_flac.h"
#include "third_party/dr_libs/dr_mp3.h"
#include "third_party/dr_libs/dr_wav.h"

// ogg/vorbis — the one container the dr_libs family does not read. Same
// vendoring rules (see third_party/stb/PROVENANCE.md): unmodified, pinned,
// public domain.
//
// 🚨★★★**STDIO STAYS ON HERE AND NOWHERE ELSE, AND THAT IS NOT A RELAXATION.**
// stb_vorbis has no callback form: it reads a memory block or a `FILE*`, and
// `stb_vorbis_open_file_section` — a FILE positioned anywhere plus a length —
// IS the range API this file needs. Without it the vorbis attempt would be
// the one decoder that had to hold the whole container in memory, which is
// the entire thing a range open exists to avoid: a three-gigabyte movie would
// be read in full just to learn it is not an ogg.
//
// ⛔What the old `STB_VORBIS_NO_STDIO` was protecting is still protected, by
// construction rather than by absence: the FILE is opened HERE, through
// `qa_open_path_read`, which is `_wfopen` on Windows. The door that define
// closed was `stb_vorbis_open_filename` taking a `const char*` — poisoned
// below so it cannot be walked through by accident.
#include "third_party/stb/stb_vorbis.c"

// ⛔The one stdio entry that would reintroduce the Korean-filename bug: it
// takes a narrow path and hands it to `fopen`, which on Windows reads the
// machine's local codepage. A call fails to compile with a name that says
// why. ⚠️Defined AFTER the include so the library's own definition of it is
// untouched (vendored sources are never edited — see PROVENANCE.md).
#define stb_vorbis_open_filename \
  qa_stb_open_filename_is_poisoned_use_qa_open_path_read

// Which decoder produced the samples — reported back so the caller can say
// so in a log, and so a test can prove the right one was chosen.
#define QA_AUDIO_FORMAT_UNKNOWN 0
#define QA_AUDIO_FORMAT_WAV 1
#define QA_AUDIO_FORMAT_FLAC 2
#define QA_AUDIO_FORMAT_MP3 3
// The OS's own codec stack (Media Foundation / AudioToolbox / MediaCodec)
// carried the file — AAC/m4a and whatever else the platform licenses that
// dr_libs deliberately does not (the decided format table: dr_libs is the
// single realtime path, AAC rides the OS).
#define QA_AUDIO_FORMAT_OS 4
// ogg/vorbis through the vendored stb_vorbis (EXPORT-AUDIO round — the
// last format that used to lean on ffmpeg).
#define QA_AUDIO_FORMAT_VORBIS 5
// A movie's uncompressed sound, read here on every platform
// ([qa_movie_pcm_open]).
#define QA_AUDIO_FORMAT_MOVIE_PCM 6

// ---------------------------------------------------------------------------
// 🚨★★★**WHERE THE BYTES ARE — ONE CURSOR, ONE READER, NO SECOND DISPATCH.**
//
// A container is a SPAN of a file: a sound in the project file, a movie
// whose soundtrack we want, a loose file (a span from 0 to its length). The
// decoders all take read/seek callbacks, so there is one cursor, and it reads
// through the library's one span reader (`qa_media_span.h`) — which also
// reads a span the save FRAMED, decompressing a block at a time.
//
// 🪦There were two origins until 2026-09-24: this span, and the container
// assembled in memory. Memory existed only because a framed entry had no
// native reader, so Dart decompressed the whole thing and handed it over —
// the soundtrack of a carried movie arrived here as the whole movie in RAM.
// The span reader reads framed spans itself now, and the memory origin went
// with its reason. ⛔A `qa_audio_decode_memory` that came back would be the
// copy this repo keeps deleting.
//
// ⚠️Positions are RELATIVE TO THE CONTAINER, never to the file. A decoder
// that seeks to 0 must land on the container's first byte, not the archive's
// — which for a carried sound is thousands of bytes earlier, and reads as a
// corrupt file rather than as the arithmetic bug it is. The span reader is
// where that arithmetic lives, once.
typedef struct {
  /// The container, read through the one span reader.
  qa_media_span* span;
  /// Where the span came from. ⚠️Carried as well as the reader because some
  /// OS decoders below do not read through a callback: Media Foundation
  /// wants a byte stream it opens over the span itself, and the NDK
  /// extractor wants a descriptor. AudioToolbox and dr_libs read through
  /// the cursor.
  const char* path;
  int64_t base;
  int64_t stored_length;
  int32_t framed;
  /// How many bytes the CONTAINER has — for a framed span, the decoded
  /// length.
  int64_t size;
  /// Where the next read starts, 0..size.
  int64_t position;
} qa_audio_cursor;

/// Reads up to [want] bytes into [out], returning how many. Short at the end
/// of the container, and 0 past it — every decoder here treats that as EOF,
/// and a span that would not read is treated the same way rather than handed
/// on as bytes.
static size_t qa_cursor_read(void* user, void* out, size_t want) {
  qa_audio_cursor* cursor = (qa_audio_cursor*)user;
  if (cursor->position >= cursor->size) {
    return 0;
  }
  const int64_t read = qa_media_span_read(cursor->span, cursor->position, out,
                                          (int64_t)want);
  if (read <= 0) {
    return 0;
  }
  cursor->position += read;
  return (size_t)read;
}

/// Moves the cursor. [origin] is 0/1/2 — set, current, end — which is the
/// value every one of the three dr_libs enums uses for those names.
///
/// ⚠️Seeking exactly TO the end is legal (a decoder measuring the container
/// does it); past it is not.
static int qa_cursor_seek(void* user, int64_t offset, int origin) {
  qa_audio_cursor* cursor = (qa_audio_cursor*)user;
  int64_t target = offset;
  if (origin == 1) {
    target += cursor->position;
  } else if (origin == 2) {
    target += cursor->size;
  }
  if (target < 0 || target > cursor->size) {
    return 0;
  }
  cursor->position = target;
  return 1;
}

static int64_t qa_cursor_tell(void* user) {
  return ((const qa_audio_cursor*)user)->position;
}

// The three libraries want the same three functions under their own types.
// ⛔Not one function pointer cast three ways: that is undefined behaviour,
// and these adapters cost a jump the decode never notices.
static size_t qa_dr_read(void* user, void* out, size_t want) {
  return qa_cursor_read(user, out, want);
}

static drwav_bool32 qa_wav_seek(void* user, int offset,
                                drwav_seek_origin origin) {
  return (drwav_bool32)qa_cursor_seek(user, offset, (int)origin);
}

static drwav_bool32 qa_wav_tell(void* user, drwav_int64* cursor) {
  *cursor = (drwav_int64)qa_cursor_tell(user);
  return DRWAV_TRUE;
}

static drflac_bool32 qa_flac_seek(void* user, int offset,
                                  drflac_seek_origin origin) {
  return (drflac_bool32)qa_cursor_seek(user, offset, (int)origin);
}

static drflac_bool32 qa_flac_tell(void* user, drflac_int64* cursor) {
  *cursor = (drflac_int64)qa_cursor_tell(user);
  return DRFLAC_TRUE;
}

static drmp3_bool32 qa_mp3_seek(void* user, int offset,
                                drmp3_seek_origin origin) {
  return (drmp3_bool32)qa_cursor_seek(user, offset, (int)origin);
}

static drmp3_bool32 qa_mp3_tell(void* user, drmp3_int64* cursor) {
  *cursor = (drmp3_int64)qa_cursor_tell(user);
  return DRMP3_TRUE;
}

/// Puts the cursor back at the container's first byte.
///
/// 🚨Every attempt in the dispatch chain starts from zero. A decoder that
/// declined a container left the cursor wherever it gave up, and the next one
/// would then read from the middle and decline for the wrong reason.
static void qa_cursor_rewind(qa_audio_cursor* cursor) {
  cursor->position = 0;
}

/// Whether [head]'s second word is one of the boxes a QuickTime movie can
/// open with — `ftyp` is the ISO file's first box, and the older movies
/// start with whatever the editor wrote first.
///
/// ⚠️Not the question `qa_apple_container_type` (qa_video_apple.m) answers:
/// that one is handed a movie and names its kind. Two heads read, two
/// questions — a third reader is the time to make them one.
static int qa_audio_head_is_a_movie_box(const uint8_t* head) {
  static const char boxes[][4] = {
      {'f', 't', 'y', 'p'}, {'m', 'o', 'o', 'v'}, {'m', 'd', 'a', 't'},
      {'w', 'i', 'd', 'e'}, {'f', 'r', 'e', 'e'}, {'s', 'k', 'i', 'p'},
      {'p', 'n', 'o', 't'}};
  for (size_t index = 0; index < sizeof(boxes) / sizeof(boxes[0]);
       index += 1) {
    if (memcmp(head + 4, boxes[index], 4) == 0) {
      return 1;
    }
  }
  return 0;
}

/// Whether dr_mp3 may be handed [cursor]'s container, by its first bytes.
///
/// dr_mp3 is the one decoder in the chain that says yes to anything, so a
/// head that names another container keeps it away: dr_wav's own first words
/// (`RIFF` · `RIFX` · `RF64` · W64's `riff` · AIFF's `FORM`), FLAC's `fLaC`,
/// ogg's `OggS`, a QuickTime box (MP4 · MOV · M4A · 3GP). Nothing else is
/// gated: the other three recognize their own containers and refuse the
/// rest, so the chain already sends each of those heads to its decoder — and
/// a head nobody knows, an MP3's among them, runs the whole chain as before.
///
/// ⛔Not a mask of every bundled decoder per head, the user's table written
/// out row by row (「ID3 · MPEG sync → MP3」 and the rest). The rows for the
/// strict three would change nothing but one thing, and break it: dr_flac
/// skips an ID3 tag itself, so 「ID3 → dr_mp3 only」 takes a tagged FLAC away
/// from the one decoder that reads it. Every row of the table holds as it is.
static int qa_audio_mp3_may_try(qa_audio_cursor* cursor) {
  static const char other_containers[][4] = {
      {'R', 'I', 'F', 'F'}, {'R', 'I', 'F', 'X'}, {'R', 'F', '6', '4'},
      {'r', 'i', 'f', 'f'}, {'F', 'O', 'R', 'M'}, {'f', 'L', 'a', 'C'},
      {'O', 'g', 'g', 'S'}};
  // A head too short to read, or that would not read, stays zeros: no
  // container's, so the chain runs as it always did.
  uint8_t head[8] = {0};
  qa_media_span_read(cursor->span, 0, head, sizeof(head));
  for (size_t index = 0;
       index < sizeof(other_containers) / sizeof(other_containers[0]);
       index += 1) {
    if (memcmp(head, other_containers[index], 4) == 0) {
      return 0;
    }
  }
  return !qa_audio_head_is_a_movie_box(head);
}

// ---------------------------------------------------------------------------
// 🚨★★★**WHERE A SOUND STARTS — SAID ONCE, COUNTED IN ONE PLACE** (user
// 2026-10-09, board sound-lands-on-its-exact-sample-Q3 · Q4).
//
// An encoder puts frames of its own before the sound (priming), and a decoder
// hands them back unless something takes them off: half a frame of animation
// late at 48 kHz, more for Apple's encoder. What is taken off is decided
// here, from the file — a movie's edit list or the note iTunes leaves in it,
// an MP3's LAME tag — and where the format has no place to say it, from the
// format's standard delay (an MP3 without the tag: 1,105, LAME's own; AAC's:
// 1,024, one frame). A decoder that already took some off says how much,
// and only the rest is taken: dr_mp3 by the LAME tag. AudioToolbox, which
// trims by a packet table of its own, is told to trim nothing where this
// part reads the start, and says what it took of anything else.
//
// A MOVIE THAT SAYS NOTHING — no edit list on its sound track, and no note
// of iTunes' — takes the standard of its sound's format off too (user
// 2026-10-09, Q6: 「Q3 그대로 — 말하지 않는 MP4 · MOV 도 1,024 를 걷는다」),
// unless Media Foundation wrote it (Q7: 「윈도 기록기의 표지가 있으면 걷지
// 않는다」): its sink writer puts no edit list in and its sound is already
// in place — this app's own exports, 48 kHz and 44.1 kHz, and the test
// movie, measured 2026-10-09 — and it marks every movie it writes
// ([qa_media_foundation_mark]). The mark is the writer's own name for
// itself, not a guess from the sound.

/// Where a decoded sound starts and how long it runs, in frames of what the
/// decoder handed back.
typedef struct {
  /// Frames before the sound: what the file says, or its format's standard.
  int64_t lead;
  /// Of [lead], the frames the decoder already took off itself.
  int64_t taken;
  /// Frames of sound after the lead, or -1: everything that came.
  int64_t keep;
} qa_audio_start;

/// The standard delays, for a file that does not say its own. An MP3's is
/// LAME's: 576 encoder frames and the decoder's 529 — the sum dr_mp3 reads
/// out of a LAME tag (`+ 528 + 1`). AAC's is one frame — a bare ADTS
/// stream's, and a movie's that says nothing.
#define QA_MP3_STANDARD_LEAD 1105
#define QA_AAC_STANDARD_LEAD 1024

static uint64_t qa_big_endian(const uint8_t* bytes, int count) {
  uint64_t value = 0;
  for (int index = 0; index < count; index += 1) {
    value = (value << 8) | bytes[index];
  }
  return value;
}

/// A box of an ISO or QuickTime file: its type, where its body starts and
/// one past its end.
typedef struct {
  char type[4];
  int64_t body;
  int64_t end;
} qa_box;

/// The box at [at], when a whole one fits before [end].
///
/// ⛔A size of 0 — 「to the end of the file」, which the format allows the
/// last box — is no box here: Media Foundation refuses a movie whose movie
/// box says it (measured 2026-10-09), so a reading of it would be a branch
/// nothing here can ask, and such a movie keeps what the decoder gave.
static int qa_box_at(qa_media_span* span, int64_t at, int64_t end,
                     qa_box* box) {
  uint8_t head[16];
  if (end - at < 8 || qa_media_span_read(span, at, head, 8) != 8) {
    return 0;
  }
  uint64_t size = qa_big_endian(head, 4);
  int64_t header = 8;
  if (size == 1) {
    // A 64-bit size follows the type.
    if (end - at < 16 || qa_media_span_read(span, at + 8, head + 8, 8) != 8) {
      return 0;
    }
    size = qa_big_endian(head + 8, 8);
    header = 16;
  }
  if (size < (uint64_t)header || size > (uint64_t)(end - at)) {
    return 0;
  }
  memcpy(box->type, head + 4, 4);
  box->body = at + header;
  box->end = at + (int64_t)size;
  return 1;
}

/// The first box of [type] directly inside [start, end).
static int qa_box_find(qa_media_span* span, int64_t start, int64_t end,
                       const char* type, qa_box* found) {
  qa_box box;
  for (int64_t at = start; qa_box_at(span, at, end, &box); at = box.end) {
    if (memcmp(box.type, type, 4) == 0) {
      *found = box;
      return 1;
    }
  }
  return 0;
}

/// A movie header's (`mvhd`) or a media header's (`mdhd`) time scale — at
/// the same place in both: after the dates, which version 1 makes 64-bit.
static uint32_t qa_box_time_scale(qa_media_span* span, const qa_box* header) {
  uint8_t bytes[24];
  if (header->end - header->body < 24 ||
      qa_media_span_read(span, header->body, bytes, 24) != 24) {
    return 0;
  }
  const int at = bytes[0] == 1 ? 20 : 12;
  return (uint32_t)qa_big_endian(bytes + at, 4);
}

/// [value] ticks at [scale] as frames at [rate], to the nearest frame.
static int64_t qa_ticks_to_frames(int64_t value, uint32_t scale,
                                  int32_t rate) {
  return (int64_t)(((double)value * rate) / scale + 0.5);
}

/// A movie's first sound track — the one that answers, whatever it says:
/// its `trak` and `mdia` boxes, the media information and sample table in
/// them (`minf` · `stbl`), the movie's and the media's time scales (0: not
/// said), and the movie box they are in, whose user data iTunes leaves its
/// note in.
typedef struct {
  qa_box moov;
  qa_box trak;
  qa_box mdia;
  qa_box minf;
  qa_box stbl;
  uint32_t movie_scale;
  uint32_t media_scale;
} qa_movie_sound;

/// [size] bytes of movie's first sound track, into [sound] — 0 when it has
/// none.
static int qa_movie_first_sound(qa_media_span* span, int64_t size,
                                qa_movie_sound* sound) {
  qa_box moov;
  qa_box mvhd;
  if (!qa_box_find(span, 0, size, "moov", &moov) ||
      !qa_box_find(span, moov.body, moov.end, "mvhd", &mvhd)) {
    return 0;
  }
  qa_box trak;
  for (int64_t at = moov.body; qa_box_at(span, at, moov.end, &trak);
       at = trak.end) {
    qa_box mdia;
    qa_box hdlr;
    qa_box minf;
    qa_box stbl;
    qa_box mdhd;
    uint8_t handler[12];
    if (memcmp(trak.type, "trak", 4) == 0 &&
        qa_box_find(span, trak.body, trak.end, "mdia", &mdia) &&
        qa_box_find(span, mdia.body, mdia.end, "hdlr", &hdlr) &&
        qa_media_span_read(span, hdlr.body, handler, 12) == 12 &&
        memcmp(handler + 8, "soun", 4) == 0 &&
        qa_box_find(span, mdia.body, mdia.end, "minf", &minf) &&
        qa_box_find(span, minf.body, minf.end, "stbl", &stbl)) {
      sound->moov = moov;
      sound->trak = trak;
      sound->mdia = mdia;
      sound->minf = minf;
      sound->stbl = stbl;
      sound->movie_scale = qa_box_time_scale(span, &mvhd);
      sound->media_scale =
          qa_box_find(span, mdia.body, mdia.end, "mdhd", &mdhd)
              ? qa_box_time_scale(span, &mdhd)
              : 0;
      return 1;
    }
  }
  return 0;
}

/// What [sound]'s edit list says, at [rate] — [start]'s lead and keep — or
/// 0 when it has none.
///
/// The edit that says it is the first that plays media: a leading empty edit
/// (media time -1) holds the track back on the movie's timeline, which is
/// where the sound is PLACED, not where it starts — ⚠️not read here.
static int qa_movie_sound_edit(qa_media_span* span,
                               const qa_movie_sound* sound, int32_t rate,
                               qa_audio_start* start) {
  qa_box edts;
  qa_box elst;
  if (!qa_box_find(span, sound->trak.body, sound->trak.end, "edts", &edts) ||
      !qa_box_find(span, edts.body, edts.end, "elst", &elst)) {
    return 0;
  }
  const uint32_t media_scale = sound->media_scale;
  uint8_t list[8];
  if (sound->movie_scale == 0 || media_scale == 0 ||
      qa_media_span_read(span, elst.body, list, 8) != 8) {
    return 0;
  }
  const int wide = list[0] == 1;
  const int64_t entry_bytes = wide ? 20 : 12;
  const uint32_t entries = (uint32_t)qa_big_endian(list + 4, 4);
  for (uint32_t index = 0; index < entries; index += 1) {
    const int64_t at_entry = elst.body + 8 + (int64_t)index * entry_bytes;
    uint8_t entry[20];
    if (at_entry + entry_bytes > elst.end ||
        qa_media_span_read(span, at_entry, entry, entry_bytes) !=
            entry_bytes) {
      return 0;
    }
    const int64_t duration = (int64_t)qa_big_endian(entry, wide ? 8 : 4);
    const int64_t media_time =
        wide ? (int64_t)qa_big_endian(entry + 8, 8)
             : (int64_t)(int32_t)qa_big_endian(entry + 4, 4);
    if (media_time < 0) {
      continue;
    }
    start->lead = qa_ticks_to_frames(media_time, media_scale, rate);
    start->keep = duration > 0
                      ? qa_ticks_to_frames(duration, sound->movie_scale, rate)
                      : -1;
    return 1;
  }
  return 0;
}

/// The next word of hexadecimal in the [length] characters of [text] from
/// [*at], past the spaces before it — -1 when none is there.
static int64_t qa_hex_word(const char* text, int length, int* at) {
  while (*at < length && text[*at] == ' ') {
    *at += 1;
  }
  uint64_t value = 0;
  int digits = 0;
  for (; *at < length; *at += 1, digits += 1) {
    const char c = text[*at];
    const int digit = c >= '0' && c <= '9'   ? c - '0'
                      : c >= 'A' && c <= 'F' ? c - 'A' + 10
                      : c >= 'a' && c <= 'f' ? c - 'a' + 10
                                             : -1;
    if (digit < 0) {
      break;
    }
    value = value * 16 + (uint64_t)digit;
  }
  return digits > 0 && digits <= 16 && value <= (uint64_t)INT64_MAX
             ? (int64_t)value
             : -1;
}

/// What the note iTunes leaves in [sound]'s movie says — [start]'s lead and
/// keep — or 0 when it left none: an item of the movie's metadata (`udta` ·
/// `meta` · `ilst`) named `iTunSMPB`, whose text is words of hexadecimal —
/// 0, the frames before the sound, the frames padded after it, the sound's
/// own length — counted in frames as decoded. iTunes and Apple Music write
/// it, and qaac and fdkaac as they come (⚠️known, not measured here), with
/// no edit list: such a movie took AAC's 1,024 off where Apple's encoder
/// put 2,112 — 1,088 frames early, 25 ms at 44.1 kHz.
///
/// ⚠️Asked only of a sound track without an edit list: the edit list is the
/// format's own place to say it, and the one every player plays by (this
/// engine's choice, 2026-10-15 — board
/// itunes-gapless-note-is-what-an-m4a-says).
static int qa_movie_itunes_note(qa_media_span* span,
                                const qa_movie_sound* sound,
                                qa_audio_start* start) {
  qa_box udta;
  qa_box meta;
  qa_box ilst;
  uint8_t head[8];
  if (!qa_box_find(span, sound->moov.body, sound->moov.end, "udta", &udta) ||
      !qa_box_find(span, udta.body, udta.end, "meta", &meta) ||
      qa_media_span_read(span, meta.body, head, 8) != 8) {
    return 0;
  }
  // ISO's `meta` has four bytes of version and flags before its boxes and
  // QuickTime's none; either begins with its handler (`hdlr`).
  const int64_t boxes =
      memcmp(head + 4, "hdlr", 4) == 0 ? meta.body : meta.body + 4;
  if (!qa_box_find(span, boxes, meta.end, "ilst", &ilst)) {
    return 0;
  }
  qa_box item;
  for (int64_t at = ilst.body; qa_box_at(span, at, ilst.end, &item);
       at = item.end) {
    // An item of a writer's own (`----`) is the kind with a `name`: it holds
    // that and its `data`, each with four bytes of version and flags first —
    // and `data` four of locale after them, before its text.
    qa_box name;
    qa_box data;
    char said[8];
    if (!qa_box_find(span, item.body, item.end, "name", &name) ||
        name.end - name.body != 4 + 8 ||
        qa_media_span_read(span, name.body + 4, said, 8) != 8 ||
        memcmp(said, "iTunSMPB", 8) != 0 ||
        !qa_box_find(span, item.body, item.end, "data", &data)) {
      continue;
    }
    // The four words take 44 characters of it.
    char text[64];
    const int64_t from = data.body + 8;
    const int length = (int)(data.end - from < 64 ? data.end - from : 64);
    if (length <= 0 || qa_media_span_read(span, from, text, length) != length) {
      return 0;
    }
    int at_text = 0;
    int64_t words[4];
    for (int index = 0; index < 4; index += 1) {
      words[index] = qa_hex_word(text, length, &at_text);
      if (words[index] < 0) {
        return 0;
      }
    }
    start->lead = words[1];
    // A length of 0 says none, as an edit's duration of 0 does.
    start->keep = words[3] > 0 ? words[3] : -1;
    return 1;
  }
  return 0;
}

/// Whether [sound] is MPEG-4 audio — its first sample description `mp4a`:
/// AAC, in every movie an animator hands this app (an MP3 carried that way
/// says so only deeper, in its decoder config, and is not looked for).
static int qa_movie_sound_is_aac(qa_media_span* span,
                                 const qa_movie_sound* sound) {
  qa_box stsd;
  uint8_t head[16];
  // After the sample description box's version, flags and count: the first
  // entry's size and its format.
  return qa_box_find(span, sound->stbl.body, sound->stbl.end, "stsd",
                     &stsd) &&
         stsd.end - stsd.body >= 16 &&
         qa_media_span_read(span, stsd.body, head, 16) == 16 &&
         memcmp(head + 12, "mp4a", 4) == 0;
}

/// The mark Media Foundation's sink writer leaves on every movie it writes:
/// a `uuid` box of the file's top level — straight after its `ftyp` on every
/// one measured — always this user type, the Windows version after it
/// (`10.0.26200.0` on the measured ones). Measured 2026-10-09 on this app's
/// exports and on the test movie; ffmpeg's movies carry none.
static const uint8_t qa_media_foundation_mark[16] = {
    0x5C, 0xA7, 0x08, 0xFB, 0x32, 0x8E, 0x42, 0x05,
    0xA8, 0x61, 0x65, 0x0E, 0xCA, 0x0A, 0x95, 0x96};

/// Whether Media Foundation wrote the [size] bytes of movie — by its mark.
static int qa_movie_written_by_media_foundation(qa_media_span* span,
                                                int64_t size) {
  qa_box box;
  for (int64_t at = 0; qa_box_at(span, at, size, &box); at = box.end) {
    uint8_t type[16];
    if (memcmp(box.type, "uuid", 4) == 0 && box.end - box.body >= 16 &&
        qa_media_span_read(span, box.body, type, 16) == 16 &&
        memcmp(type, qa_media_foundation_mark, 16) == 0) {
      return 1;
    }
  }
  return 0;
}

/// Whether [cursor]'s container is a bare ADTS stream — AAC with no box to
/// say anything in — by its first frame header, behind an ID3 tag or not.
static int qa_audio_is_adts(const qa_audio_cursor* cursor) {
  uint8_t head[10] = {0};
  qa_media_span_read(cursor->span, 0, head, sizeof(head));
  int64_t at = 0;
  if (memcmp(head, "ID3", 3) == 0) {
    // The tag's size is four 7-bit bytes, a footer ten more.
    at = 10 + (int64_t)(((head[6] & 0x7F) << 21) | ((head[7] & 0x7F) << 14) |
                        ((head[8] & 0x7F) << 7) | (head[9] & 0x7F)) +
         ((head[5] & 0x10) ? 10 : 0);
    memset(head, 0, sizeof(head));
    qa_media_span_read(cursor->span, at, head, 2);
  }
  // Twelve sync bits, then layer 00: an MPEG audio frame's layer is never 00.
  return head[0] == 0xFF && (head[1] & 0xF6) == 0xF0;
}

/// What the file says about a sound whose decoder does not read it — the OS
/// stack's, and a movie's uncompressed sound read here: the decoders that
/// know their own file (dr_mp3) said it as they read.
static void qa_audio_container_start(const qa_audio_cursor* cursor,
                                     int32_t rate, qa_audio_start* start) {
  uint8_t head[8] = {0};
  qa_media_span_read(cursor->span, 0, head, sizeof(head));
  qa_movie_sound sound;
  if (qa_audio_head_is_a_movie_box(head)) {
    // A movie says it in its edit list, or else in iTunes' note; one that
    // says nothing takes its format's standard, unless Media Foundation
    // wrote it (the law at the head of this part).
    if (qa_movie_first_sound(cursor->span, cursor->size, &sound) &&
        !qa_movie_sound_edit(cursor->span, &sound, rate, start) &&
        !qa_movie_itunes_note(cursor->span, &sound, start) &&
        !qa_movie_written_by_media_foundation(cursor->span, cursor->size) &&
        qa_movie_sound_is_aac(cursor->span, &sound)) {
      start->lead = QA_AAC_STANDARD_LEAD;
    }
  } else if (qa_audio_is_adts(cursor)) {
    start->lead = QA_AAC_STANDARD_LEAD;
  }
}

// ---------------------------------------------------------------------------
// 🚨★★★**A SOUND IS READ AS A STREAM — EVERY DECODER THROUGH ONE DOOR** (user
// 2026-10-10, board long-sound-conform-memory-Q1: 「지금 한다 — 전 플랫폼」).
//
// A decoder is opened once and read on: each hands back a block at a time,
// and the stream counts the lead off the front and stops at the sound's end
// ([qa_audio_stream_pass]) — the one place either is counted, whatever
// decoded the container. A conform is made from it a piece at a time, so a
// long sound is never held whole on its way in: 25 minutes of 44.1 kHz
// stereo used to be about 1.1 GB in the worker at once, an hour about 2.6 GB.
//
// A WINDOW is the same stream, passed over up to the window and read through
// it (user 2026-10-09, board sound-lands-on-its-exact-sample-Q5: a piece cut
// from a long reel holds the piece, not the reel — 24 minutes of 48 kHz
// stereo is 553 MB of floats, two hours 2.76 GB). It still decodes from the
// start, so a piece's samples are exactly the ones a whole decode has there,
// with no seek to land differently on each platform; only the window's frames
// are held, and the decoder stops once past it.

#if defined(_WIN32)

// The video decoder's span stream, shared rather than written twice — see
// qa_win_range_stream.c. ⛔A second `IMFByteStream` over a span is the one
// thing this must not become: it is 200 lines of hand-written COM, and two
// of those drift.
#include "qa_win_range_stream.h"
#include "qa_win_media_foundation.h"

typedef struct {
  int co_balanced;
  IMFByteStream* byte_stream;
  IMFSourceReader* reader;
  /// The reader said the stream ended, with the block handed back last.
  int ended;
} qa_os_decoder;

#elif defined(__APPLE__)

typedef struct {
  AudioFileID file;
  ExtAudioFileRef ext;
} qa_os_decoder;

#elif defined(__ANDROID__)

// The NDK media API is the library's ONE table (qa_ndk_media.h). This file
// resolved its own until 2026-09-24, and its custom-source read callback took
// the offset as `off_t` where the NDK passes `off64_t` — on a 32-bit ARM
// device the offset was read out of the wrong registers.
#include "qa_ndk_media.h"

typedef struct {
  const qa_ndk_media_api* ndk;
  AMediaExtractor* extractor;
  qa_ndk_served_span* served;
  AMediaCodec* codec;
  AMediaFormat* track_format;
  int descriptor;
  int started;
  /// What the codec last said it hands back.
  int32_t channels;
  int32_t sample_rate;
  int32_t pcm_encoding;
  int input_done;
  int output_done;
} qa_os_decoder;

#else

typedef struct {
  int unused;
} qa_os_decoder;

#endif

typedef struct {
  stb_vorbis* vorbis;
  FILE* section;
  uint8_t* assembled;
} qa_vorbis_decoder;

/// One table of a movie's sample table, read a batch of entries at a time:
/// the span keeps one block (`qa_media_span.c`), so a movie kept FRAMED
/// would decode the block its table is in again for every chunk of sound.
typedef struct {
  /// The first entry, how many there are, and how wide each is.
  int64_t at;
  uint32_t count;
  uint32_t entry_bytes;
  /// The entries read last: [batch_count] of them from [batch_first].
  uint32_t batch_first;
  uint32_t batch_count;
  uint8_t batch[4096];
} qa_movie_table;

/// How a movie stores a sample of uncompressed sound.
enum {
  QA_MOVIE_PCM_UNSIGNED = 1,
  QA_MOVIE_PCM_SIGNED,
  QA_MOVIE_PCM_FLOAT
};

/// A movie's uncompressed sound, read through its sample table a chunk at a
/// time.
typedef struct {
  /// Where each chunk starts (`stco` · `co64`), and the runs of chunks that
  /// hold the same number of frames (`stsc`).
  qa_movie_table offsets;
  qa_movie_table runs;
  /// The run in force (-1 before the first), its frames per chunk, and the
  /// chunk the next run starts at — counted from 1, as the table counts.
  int64_t run;
  uint32_t run_frames;
  uint32_t next_run_chunk;
  /// Chunks begun; where the one being read is up to, and its frames left.
  uint32_t chunks_begun;
  int64_t chunk_at;
  int64_t chunk_frames;
  /// Frames of the sound left: of the size table's count.
  int64_t frames_left;
  /// A sample's kind, bytes and byte order, and a frame's bytes.
  int kind;
  int sample_bytes;
  int big_endian;
  int64_t frame_bytes;
  /// Where a read lands before it is converted, and how many frames fit.
  uint8_t* raw;
  int64_t raw_frames;
} qa_movie_pcm_decoder;

typedef struct qa_audio_stream qa_audio_stream;

/// One decoder behind a stream.
typedef struct {
  /// The next block of what the decoder hands back, into the stream's block
  /// ([qa_audio_stream_block]): how many frames — 0 at the end, -1 where the
  /// decoder failed.
  int64_t (*next)(qa_audio_stream* stream);
  /// Lets the decoder go.
  void (*close)(qa_audio_stream* stream);
} qa_audio_backend;

struct qa_audio_stream {
  qa_media_span* span;
  /// The container, for the decoders that read through it. ⚠️They are handed
  /// its address, so a stream never moves.
  qa_audio_cursor cursor;
  /// The stream's own copy of the path the cursor names.
  char* path;
  int32_t format;
  int32_t channels;
  int32_t sample_rate;
  const qa_audio_backend* backend;
  union {
    drwav wav;
    drflac* flac;
    drmp3 mp3;
    qa_vorbis_decoder vorbis;
    qa_movie_pcm_decoder movie;
    qa_os_decoder os;
  } decoder;
  /// The block the decoder handed back last, and how far into it the stream
  /// has read.
  float* block;
  size_t block_capacity;
  int64_t block_frames;
  int64_t block_at;
  /// Frames still to pass before the sound: what the file says came first.
  int64_t lead;
  /// Frames of the sound still to come, or -1: all the decoder hands back.
  int64_t left;
};

/// Room for [frames] frames in [stream]'s block, or NULL when the memory ran
/// out.
static float* qa_audio_stream_block(qa_audio_stream* stream, int64_t frames) {
  const size_t wanted = (size_t)frames * (size_t)stream->channels;
  if (wanted > stream->block_capacity) {
    float* grown = (float*)realloc(stream->block, wanted * sizeof(float));
    if (grown == NULL) {
      return NULL;
    }
    stream->block = grown;
    stream->block_capacity = wanted;
  }
  return stream->block;
}

/// Moves [stream] on through up to [frames] frames of its sound — into [out],
/// or over them when [out] is NULL — and answers how many: short only at the
/// sound's end, -1 where the decoder failed.
static int64_t qa_audio_stream_pass(qa_audio_stream* stream, float* out,
                                    int64_t frames) {
  const size_t channels = (size_t)stream->channels;
  int64_t passed = 0;
  while (passed < frames && stream->left != 0) {
    if (stream->block_at == stream->block_frames) {
      const int64_t got = stream->backend->next(stream);
      if (got < 0) {
        return -1;
      }
      if (got == 0) {
        stream->left = 0;
        break;
      }
      stream->block_frames = got;
      stream->block_at = 0;
    }
    int64_t take = stream->block_frames - stream->block_at;
    if (stream->lead > 0) {
      const int64_t drop = take < stream->lead ? take : stream->lead;
      stream->block_at += drop;
      stream->lead -= drop;
      continue;
    }
    if (take > frames - passed) {
      take = frames - passed;
    }
    if (stream->left > 0 && take > stream->left) {
      take = stream->left;
    }
    if (out != NULL) {
      memcpy(out + (size_t)passed * channels,
             stream->block + (size_t)stream->block_at * channels,
             (size_t)take * channels * sizeof(float));
    }
    stream->block_at += take;
    passed += take;
    if (stream->left > 0) {
      stream->left -= take;
    }
  }
  return passed;
}

/// Opens [stream]'s container with one decoder: 1 when it opened — the stream
/// then holds it, with its format, channels and rate — and fills what it knows
/// of where the sound starts into [start].
typedef int (*qa_audio_opener)(qa_audio_stream* stream, qa_audio_start* start);

// ---------------------------------------------------------------------------
// The bundled decoders — dr_libs and stb_vorbis — on every platform.

/// Frames the bundled decoders are asked for at a time.
#define QA_BUNDLED_BLOCK_FRAMES 4096

static int64_t qa_wav_next(qa_audio_stream* stream) {
  float* block = qa_audio_stream_block(stream, QA_BUNDLED_BLOCK_FRAMES);
  return block == NULL ? -1
                       : (int64_t)drwav_read_pcm_frames_f32(
                             &stream->decoder.wav, QA_BUNDLED_BLOCK_FRAMES,
                             block);
}

static void qa_wav_close(qa_audio_stream* stream) {
  drwav_uninit(&stream->decoder.wav);
}

static const qa_audio_backend qa_wav_backend = {qa_wav_next, qa_wav_close};

static int qa_wav_open(qa_audio_stream* stream, qa_audio_start* start) {
  (void)start;
  drwav* wav = &stream->decoder.wav;
  if (!drwav_init(wav, qa_dr_read, qa_wav_seek, qa_wav_tell, &stream->cursor,
                  NULL)) {
    return 0;
  }
  if (wav->channels == 0) {
    drwav_uninit(wav);
    return 0;
  }
  stream->backend = &qa_wav_backend;
  stream->format = QA_AUDIO_FORMAT_WAV;
  stream->channels = (int32_t)wav->channels;
  stream->sample_rate = (int32_t)wav->sampleRate;
  return 1;
}

static int64_t qa_flac_next(qa_audio_stream* stream) {
  float* block = qa_audio_stream_block(stream, QA_BUNDLED_BLOCK_FRAMES);
  return block == NULL ? -1
                       : (int64_t)drflac_read_pcm_frames_f32(
                             stream->decoder.flac, QA_BUNDLED_BLOCK_FRAMES,
                             block);
}

static void qa_flac_close(qa_audio_stream* stream) {
  drflac_close(stream->decoder.flac);
}

static const qa_audio_backend qa_flac_backend = {qa_flac_next, qa_flac_close};

static int qa_flac_open(qa_audio_stream* stream, qa_audio_start* start) {
  (void)start;
  drflac* flac =
      drflac_open(qa_dr_read, qa_flac_seek, qa_flac_tell, &stream->cursor,
                  NULL);
  if (flac == NULL) {
    return 0;
  }
  if (flac->channels == 0) {
    drflac_close(flac);
    return 0;
  }
  stream->decoder.flac = flac;
  stream->backend = &qa_flac_backend;
  stream->format = QA_AUDIO_FORMAT_FLAC;
  stream->channels = (int32_t)flac->channels;
  stream->sample_rate = (int32_t)flac->sampleRate;
  return 1;
}

static int64_t qa_vorbis_next(qa_audio_stream* stream) {
  float* block = qa_audio_stream_block(stream, QA_BUNDLED_BLOCK_FRAMES);
  if (block == NULL) {
    return -1;
  }
  const int got = stb_vorbis_get_samples_float_interleaved(
      stream->decoder.vorbis.vorbis, stream->channels, block,
      QA_BUNDLED_BLOCK_FRAMES * stream->channels);
  return got > 0 ? (int64_t)got : 0;
}

static void qa_vorbis_close(qa_audio_stream* stream) {
  qa_vorbis_decoder* decoder = &stream->decoder.vorbis;
  if (decoder->vorbis != NULL) {
    stb_vorbis_close(decoder->vorbis);
  }
  if (decoder->section != NULL) {
    fclose(decoder->section);
  }
  free(decoder->assembled);
  memset(decoder, 0, sizeof(*decoder));
}

static const qa_audio_backend qa_vorbis_backend = {qa_vorbis_next,
                                                   qa_vorbis_close};

/// stb_vorbis over [stream]'s container.
///
/// ⚠️The one decoder with no callback form — memory or a `FILE*` — so the
/// span is handed over two ways. A PLAIN span is a FILE section: a position
/// plus a length, a range exactly. A FRAMED span has no FILE that holds the
/// container, so an ogg in one is assembled in memory — but only once its
/// first four bytes say it IS one (`OggS`, which stb_vorbis requires anyway):
/// asking every framed container in full would read a whole movie to learn
/// it is not an ogg. A carried ogg is nearly never framed at all — it is
/// already compressed, and a save frames only what shrinks.
static int qa_vorbis_open(qa_audio_stream* stream, qa_audio_start* start) {
  (void)start;
  const qa_audio_cursor* cursor = &stream->cursor;
  qa_vorbis_decoder* decoder = &stream->decoder.vorbis;
  memset(decoder, 0, sizeof(*decoder));
  if (cursor->size > 0x7FFFFFFF) {
    return 0;
  }
  int vorbis_error = 0;
  if (!cursor->framed) {
    // ⚠️The 2GB guard is stb's, not ours: it remembers where a section
    // started with `ftell`, whose `long` is 32 bits on Windows. Past that it
    // would read from the wrong place rather than fail, so the attempt is
    // skipped instead — an ogg carried past the 2GB mark of a project file
    // decodes as「not an ogg」, and no other format is affected.
    if (cursor->base <= 0x7FFFFFFF) {
      decoder->section = qa_open_path_read(cursor->path);
      if (decoder->section != NULL &&
          qa_seek_absolute(decoder->section, cursor->base)) {
        decoder->vorbis = stb_vorbis_open_file_section(
            decoder->section, 0, &vorbis_error, NULL, (unsigned)cursor->size);
      }
    }
  } else {
    uint8_t magic[4];
    if (qa_media_span_read(cursor->span, 0, magic, 4) == 4 &&
        memcmp(magic, "OggS", 4) == 0) {
      decoder->assembled = (uint8_t*)malloc((size_t)cursor->size);
      if (decoder->assembled != NULL &&
          qa_media_span_read(cursor->span, 0, decoder->assembled,
                             cursor->size) == cursor->size) {
        decoder->vorbis = stb_vorbis_open_memory(
            decoder->assembled, (int)cursor->size, &vorbis_error, NULL);
      }
    }
  }
  if (decoder->vorbis != NULL) {
    const stb_vorbis_info info = stb_vorbis_get_info(decoder->vorbis);
    if (info.channels > 0 && info.sample_rate > 0) {
      stream->backend = &qa_vorbis_backend;
      stream->format = QA_AUDIO_FORMAT_VORBIS;
      stream->channels = info.channels;
      stream->sample_rate = (int32_t)info.sample_rate;
      return 1;
    }
  }
  qa_vorbis_close(stream);
  return 0;
}

static int64_t qa_mp3_next(qa_audio_stream* stream) {
  float* block = qa_audio_stream_block(stream, QA_BUNDLED_BLOCK_FRAMES);
  return block == NULL ? -1
                       : (int64_t)drmp3_read_pcm_frames_f32(
                             &stream->decoder.mp3, QA_BUNDLED_BLOCK_FRAMES,
                             block);
}

static void qa_mp3_close(qa_audio_stream* stream) {
  drmp3_uninit(&stream->decoder.mp3);
}

static const qa_audio_backend qa_mp3_backend = {qa_mp3_next, qa_mp3_close};

static int qa_mp3_open(qa_audio_stream* stream, qa_audio_start* start) {
  if (!qa_audio_mp3_may_try(&stream->cursor)) {
    return 0;
  }
  drmp3* mp3 = &stream->decoder.mp3;
  if (!drmp3_init(mp3, qa_dr_read, qa_mp3_seek, qa_mp3_tell, NULL,
                  &stream->cursor, NULL)) {
    return 0;
  }
  if (mp3->channels == 0) {
    drmp3_uninit(mp3);
    return 0;
  }
  // dr_mp3 takes the delay a LAME tag says off itself, and that is heard
  // here as it opens: only a file whose tag said nothing gets the standard
  // one.
  const int64_t said = (int64_t)mp3->delayInPCMFrames;
  start->lead = said > 0 ? said : QA_MP3_STANDARD_LEAD;
  start->taken = said;
  stream->backend = &qa_mp3_backend;
  stream->format = QA_AUDIO_FORMAT_MP3;
  stream->channels = (int32_t)mp3->channels;
  stream->sample_rate = (int32_t)mp3->sampleRate;
  return 1;
}

// ---------------------------------------------------------------------------
// 🚨★★★**A MOVIE'S UNCOMPRESSED SOUND IS READ HERE, ON EVERY PLATFORM**
// (2026-10-16, board mac-reads-no-movie-pcm). AudioToolbox read nothing of
// the tests' PCM movie on the macOS CI runner (2026-10-15) where Media
// Foundation reads it to the sample, and a ProRes movie this app exports on
// a Mac carries its sound as PCM (`qa_video_apple.m`), as editors' reels do.
// Uncompressed sound needs no codec — it is bytes the movie's sample table
// lays out — so it is read here, into floats by dr_wav's conversions (what a
// WAV of the same samples gets), and no OS stack is asked for it. A movie's
// sound of any other kind (AAC, ALAC) still rides the OS stack, and where
// this one starts is the movie's to say, as for those
// ([qa_audio_container_start]).
//
// What is read is the layout ffmpeg's movie reader reads (⚠️known from it
// and from Apple's file format, not from a file of every writer):
//   - the first sound track, the one its start is read from, and its one
//     sample description: `twos` · `sowt` (signed, big- and little-endian,
//     8 to 32 bits), `raw ` (unsigned 8-bit), `in24` · `in32` · `fl32` ·
//     `fl64` (big-endian unless an `enda` says little), or `lpcm` (a
//     version-2 description, by its flags);
//   - a sample is a frame, whatever the size table says its size is (old
//     QuickTime wrote 1) — so every sample lasts one frame of the media's
//     clock, or it is not read;
//   - the chunks in order, each holding the frames its run of the
//     sample-to-chunk table says, as many as the size table counts.
// ⛔A movie whose data reference says its sound is in another file is not
// read: its offsets are that file's, and read here they would be noise. Nor
// is one whose description names a reference its list does not have.
//
// Media Foundation, which read these movies before, reads every shape and
// layout `qa_audio_range_test.c` builds to the same samples and refuses
// what it refuses (measured 2026-10-16), but:
//   - 8-bit sound by a convention of its own (up to 1/128 off what a WAV of
//     it gives), 32-bit integers a last bit off (2^-23), and a `twos` of 24
//     bits and an `enda` outside a `wave` as noise;
//   - a sound to the end of its chunks, past what the size table counts,
//     and a chunk cut short not at all, where this reads it to its last
//     whole frame as dr_wav reads a WAV cut short;
//   - what this reads, it does not: an `in24` in a version-2 description,
//     and a sound the second of two data references names, this file's;
//   - what this does not read, it does: samples two frames long, a sound
//     described two ways, an `lpcm` whose flags say its channels come one
//     after another (read as interleaved), or 24 bits in 32-bit words, or
//     two frames a packet, or unsigned 16 bits, and a `raw ` of 16 bits
//     (read little-endian — ffmpeg reads it big-endian, and Apple's format
//     says 8 bits). Those still ride it on Windows: the OS stack is asked
//     after this.

/// Entry [index] of [table]: its bytes, or NULL when it is not there or
/// would not read.
static const uint8_t* qa_movie_table_entry(qa_media_span* span,
                                           qa_movie_table* table,
                                           uint32_t index) {
  if (index >= table->count) {
    return NULL;
  }
  if (index < table->batch_first ||
      index - table->batch_first >= table->batch_count) {
    const uint32_t fit = (uint32_t)sizeof(table->batch) / table->entry_bytes;
    const uint32_t take =
        table->count - index < fit ? table->count - index : fit;
    const int64_t want = (int64_t)take * table->entry_bytes;
    table->batch_count = 0;
    if (qa_media_span_read(span,
                           table->at + (int64_t)index * table->entry_bytes,
                           table->batch, want) != want) {
      return NULL;
    }
    table->batch_first = index;
    table->batch_count = take;
  }
  return table->batch +
         (size_t)(index - table->batch_first) * table->entry_bytes;
}

/// The table [box] holds — its version and flags, a count, and then
/// [entry_bytes] an entry — into [table]: 0 when its entries do not fit in
/// it.
static int qa_movie_table_open(qa_media_span* span, const qa_box* box,
                               uint32_t entry_bytes, qa_movie_table* table) {
  uint8_t head[8];
  memset(table, 0, sizeof(*table));
  if (box->end - box->body < 8 ||
      qa_media_span_read(span, box->body, head, 8) != 8) {
    return 0;
  }
  table->at = box->body + 8;
  table->count = (uint32_t)qa_big_endian(head + 4, 4);
  table->entry_bytes = entry_bytes;
  return (int64_t)table->count * entry_bytes <= box->end - table->at;
}

/// Whether every sample the time table [stts] times lasts one frame at
/// [rate] of a media clock of [scale] — as a sample of uncompressed sound
/// does.
static int qa_movie_samples_are_frames(qa_media_span* span,
                                       const qa_box* stts, uint32_t scale,
                                       int32_t rate) {
  qa_movie_table times;
  if (!qa_movie_table_open(span, stts, 8, &times)) {
    return 0;
  }
  for (uint32_t index = 0; index < times.count; index += 1) {
    const uint8_t* entry = qa_movie_table_entry(span, &times, index);
    if (entry == NULL ||
        qa_big_endian(entry + 4, 4) * (uint64_t)rate != scale) {
      return 0;
    }
  }
  return 1;
}

/// Whether the extensions of a sample description — [from] to [end] — say
/// its samples are little-endian: an `enda` of 1, the description's own or
/// in its `wave`.
static int qa_movie_pcm_says_little(qa_media_span* span, int64_t from,
                                    int64_t end) {
  qa_box enda;
  qa_box wave;
  uint8_t value[2];
  if (!qa_box_find(span, from, end, "enda", &enda) &&
      !(qa_box_find(span, from, end, "wave", &wave) &&
        qa_box_find(span, wave.body, wave.end, "enda", &enda))) {
    return 0;
  }
  return enda.end - enda.body >= 2 &&
         qa_media_span_read(span, enda.body, value, 2) == 2 && value[1] == 1;
}

/// How the sample description [entry] says its samples are stored, into
/// [pcm], with its [channels], [rate] and data [reference]: 0 when it is not
/// uncompressed sound this reads.
static int qa_movie_pcm_describe(qa_media_span* span, const qa_box* entry,
                                 qa_movie_pcm_decoder* pcm,
                                 int32_t* channels, int32_t* rate,
                                 uint32_t* reference) {
  // Six reserved bytes and the data reference; the description's version,
  // revision and vendor; then its own fields, which version 2 rewrote.
  uint8_t field[64];
  const int64_t have = entry->end - entry->body;
  const int64_t want = have < 64 ? have : 64;
  if (have < 28 || qa_media_span_read(span, entry->body, field, want) !=
                       want) {
    return 0;
  }
  *reference = (uint32_t)qa_big_endian(field + 6, 2);
  const uint32_t version = (uint32_t)qa_big_endian(field + 8, 2);
  uint32_t bits = 0;
  uint32_t flags = 0;
  int64_t extensions = 0;
  if (version == 2 && have >= 64) {
    uint64_t rate_bits = qa_big_endian(field + 32, 8);
    double hertz = 0;
    memcpy(&hertz, &rate_bits, sizeof(hertz));
    const uint32_t count = (uint32_t)qa_big_endian(field + 40, 4);
    // ⚠️No more channels than a version-0 description can say: the count is
    // 32 bits here, and a broken one would size every block.
    if (!(hertz >= 1.0 && hertz <= 2147483647.0) || count == 0 ||
        count > 65535) {
      return 0;
    }
    *rate = (int32_t)(hertz + 0.5);
    *channels = (int32_t)count;
    bits = (uint32_t)qa_big_endian(field + 48, 4);
    flags = (uint32_t)qa_big_endian(field + 52, 4);
    extensions = entry->body + 64;
  } else if (version == 0 || (version == 1 && have >= 44)) {
    *channels = (int32_t)qa_big_endian(field + 16, 2);
    bits = (uint32_t)qa_big_endian(field + 18, 2);
    *rate = (int32_t)(qa_big_endian(field + 24, 4) >> 16);
    extensions = entry->body + (version == 1 ? 44 : 28);
    if (*channels == 0 || *rate == 0) {
      return 0;
    }
  } else {
    return 0;
  }

  // The formats a description names: how each stores a sample — its bytes
  // (0: the description's bits say), and its byte order (-1: big unless an
  // `enda` says little).
  static const struct {
    char type[4];
    int kind;
    int sample_bytes;
    int big_endian;
  } formats[] = {
      {{'t', 'w', 'o', 's'}, QA_MOVIE_PCM_SIGNED, 0, 1},
      {{'s', 'o', 'w', 't'}, QA_MOVIE_PCM_SIGNED, 0, 0},
      {{'r', 'a', 'w', ' '}, QA_MOVIE_PCM_UNSIGNED, 1, 0},
      {{'i', 'n', '2', '4'}, QA_MOVIE_PCM_SIGNED, 3, -1},
      {{'i', 'n', '3', '2'}, QA_MOVIE_PCM_SIGNED, 4, -1},
      {{'f', 'l', '3', '2'}, QA_MOVIE_PCM_FLOAT, 4, -1},
      {{'f', 'l', '6', '4'}, QA_MOVIE_PCM_FLOAT, 8, -1},
  };
  pcm->kind = 0;
  for (size_t index = 0; index < sizeof(formats) / sizeof(formats[0]);
       index += 1) {
    if (memcmp(entry->type, formats[index].type, 4) == 0) {
      pcm->kind = formats[index].kind;
      pcm->sample_bytes = formats[index].sample_bytes != 0
                              ? formats[index].sample_bytes
                              : (int)(bits / 8);
      pcm->big_endian =
          formats[index].big_endian >= 0
              ? formats[index].big_endian
              : !qa_movie_pcm_says_little(span, extensions, entry->end);
      // `raw ` is 8-bit; the others' bits are their names'.
      if (formats[index].sample_bytes == 1 && bits != 8) {
        return 0;
      }
      if (formats[index].sample_bytes == 0 && bits % 8 != 0) {
        return 0;
      }
    }
  }
  if (memcmp(entry->type, "lpcm", 4) == 0 && version == 2) {
    // Core Audio's flags: float 1, big-endian 2, signed 4, and 32 for one
    // channel after another rather than frames, which this does not read.
    // A packet is one frame of the samples packed, or it is not read: its
    // bytes say both.
    const uint64_t packet_bytes = qa_big_endian(field + 56, 4);
    pcm->kind = (flags & 1)   ? QA_MOVIE_PCM_FLOAT
                : (flags & 4) ? QA_MOVIE_PCM_SIGNED
                              : QA_MOVIE_PCM_UNSIGNED;
    pcm->sample_bytes = (int)(bits / 8);
    pcm->big_endian = (flags & 2) != 0;
    if ((flags & 32) || bits % 8 != 0 ||
        packet_bytes != (uint64_t)*channels * (bits / 8)) {
      return 0;
    }
  }
  switch (pcm->kind) {
    case QA_MOVIE_PCM_UNSIGNED:
      return pcm->sample_bytes == 1;
    case QA_MOVIE_PCM_SIGNED:
      return pcm->sample_bytes >= 1 && pcm->sample_bytes <= 4;
    case QA_MOVIE_PCM_FLOAT:
      return pcm->sample_bytes == 4 || pcm->sample_bytes == 8;
    default:
      return 0;
  }
}

/// Whether [sound]'s data reference [index] — counted from 1 — says its
/// samples are in this movie's own file: flag 1, 「self reference」. A
/// movie with no data references at all is read as holding its own sound,
/// and one whose description names a reference its list does not have is
/// not read — as Media Foundation reads both (measured 2026-10-16).
static int qa_movie_holds_its_sound(qa_media_span* span,
                                    const qa_movie_sound* sound,
                                    uint32_t index) {
  qa_box dinf;
  qa_box dref;
  qa_box entry;
  if (!qa_box_find(span, sound->minf.body, sound->minf.end, "dinf",
                   &dinf) ||
      !qa_box_find(span, dinf.body, dinf.end, "dref", &dref)) {
    return 1;
  }
  uint32_t number = 1;
  for (int64_t at = dref.body + 8; qa_box_at(span, at, dref.end, &entry);
       at = entry.end, number += 1) {
    uint8_t flags[4];
    if (number == index) {
      return entry.end - entry.body >= 4 &&
             qa_media_span_read(span, entry.body, flags, 4) == 4 &&
             (flags[3] & 1) != 0;
    }
  }
  return 0;
}

/// Begins [pcm]'s next chunk: 0 when there is none, or its table would not
/// read.
static int qa_movie_pcm_next_chunk(qa_media_span* span,
                                   qa_movie_pcm_decoder* pcm) {
  if (pcm->chunks_begun >= pcm->offsets.count) {
    return 0;
  }
  const uint32_t number = pcm->chunks_begun + 1;
  while (number >= pcm->next_run_chunk) {
    pcm->run += 1;
    const uint8_t* run =
        qa_movie_table_entry(span, &pcm->runs, (uint32_t)pcm->run);
    if (run == NULL) {
      return 0;
    }
    pcm->run_frames = (uint32_t)qa_big_endian(run + 4, 4);
    pcm->next_run_chunk = UINT32_MAX;
    if ((uint32_t)pcm->run + 1 < pcm->runs.count) {
      const uint8_t* next =
          qa_movie_table_entry(span, &pcm->runs, (uint32_t)pcm->run + 1);
      if (next == NULL) {
        return 0;
      }
      pcm->next_run_chunk = (uint32_t)qa_big_endian(next, 4);
    }
  }
  const uint8_t* offset =
      qa_movie_table_entry(span, &pcm->offsets, pcm->chunks_begun);
  if (offset == NULL) {
    return 0;
  }
  const uint64_t at = qa_big_endian(offset, (int)pcm->offsets.entry_bytes);
  if (at > (uint64_t)INT64_MAX) {
    return 0;
  }
  pcm->chunk_at = (int64_t)at;
  pcm->chunk_frames = pcm->run_frames;
  pcm->chunks_begun += 1;
  return 1;
}

/// [count] samples just read into [pcm]'s raw block, as floats into [out]
/// — by dr_wav's conversions, which a WAV of the same samples gets.
/// ⚠️They are put in this machine's order first, and every machine this
/// ships on is little-endian (x86-64, ARM64).
static void qa_movie_pcm_convert(qa_movie_pcm_decoder* pcm, float* out,
                                 size_t count) {
  uint8_t* raw = pcm->raw;
  const size_t bytes = (size_t)pcm->sample_bytes;
  if (pcm->big_endian) {
    for (size_t index = 0; index < count; index += 1) {
      uint8_t* sample = raw + index * bytes;
      for (size_t low = 0, high = bytes - 1; low < high;
           low += 1, high -= 1) {
        const uint8_t byte = sample[low];
        sample[low] = sample[high];
        sample[high] = byte;
      }
    }
  }
  if (pcm->kind == QA_MOVIE_PCM_FLOAT) {
    if (bytes == 4) {
      memcpy(out, raw, count * sizeof(float));
    } else {
      drwav_f64_to_f32(out, (const double*)raw, count);
    }
    return;
  }
  switch (bytes) {
    case 1:
      // dr_wav reads 8-bit sound as a WAV holds it, offset binary.
      if (pcm->kind == QA_MOVIE_PCM_SIGNED) {
        for (size_t index = 0; index < count; index += 1) {
          raw[index] ^= 0x80;
        }
      }
      drwav_u8_to_f32(out, raw, count);
      break;
    case 2:
      drwav_s16_to_f32(out, (const drwav_int16*)raw, count);
      break;
    case 3:
      drwav_s24_to_f32(out, raw, count);
      break;
    default:
      drwav_s32_to_f32(out, (const drwav_int32*)raw, count);
      break;
  }
}

static int64_t qa_movie_pcm_next(qa_audio_stream* stream) {
  qa_movie_pcm_decoder* pcm = &stream->decoder.movie;
  if (pcm->frames_left == 0) {
    return 0;
  }
  while (pcm->chunk_frames == 0) {
    if (!qa_movie_pcm_next_chunk(stream->span, pcm)) {
      return 0;
    }
  }
  int64_t frames = pcm->chunk_frames;
  if (frames > pcm->raw_frames) {
    frames = pcm->raw_frames;
  }
  if (frames > pcm->frames_left) {
    frames = pcm->frames_left;
  }
  float* block = qa_audio_stream_block(stream, frames);
  if (block == NULL) {
    return -1;
  }
  const int64_t want = frames * pcm->frame_bytes;
  const int64_t got =
      qa_media_span_read(stream->span, pcm->chunk_at, pcm->raw, want);
  if (got < want) {
    // A movie cut short ends where its bytes do, as dr_wav ends a WAV.
    frames = got > 0 ? got / pcm->frame_bytes : 0;
    pcm->frames_left = frames;
  }
  qa_movie_pcm_convert(pcm, block, (size_t)(frames * stream->channels));
  pcm->chunk_at += frames * pcm->frame_bytes;
  pcm->chunk_frames -= frames;
  pcm->frames_left -= frames;
  return frames;
}

static void qa_movie_pcm_close(qa_audio_stream* stream) {
  free(stream->decoder.movie.raw);
  stream->decoder.movie.raw = NULL;
}

static const qa_audio_backend qa_movie_pcm_backend = {qa_movie_pcm_next,
                                                      qa_movie_pcm_close};

/// The most a read of a movie's sound lands at once, in bytes — a frame of
/// the widest description is 65,535 samples of 8.
#define QA_MOVIE_PCM_READ_BYTES (1 << 20)

static int qa_movie_pcm_open(qa_audio_stream* stream, qa_audio_start* start) {
  (void)start;
  qa_media_span* span = stream->span;
  qa_movie_pcm_decoder* pcm = &stream->decoder.movie;
  memset(pcm, 0, sizeof(*pcm));
  uint8_t head[8] = {0};
  qa_media_span_read(span, 0, head, sizeof(head));
  qa_movie_sound sound;
  qa_box stsd;
  qa_box entry;
  uint8_t counts[12];
  // One sample description: a sound stored two ways is not one stream.
  if (!qa_audio_head_is_a_movie_box(head) ||
      !qa_movie_first_sound(span, stream->cursor.size, &sound) ||
      !qa_box_find(span, sound.stbl.body, sound.stbl.end, "stsd", &stsd) ||
      stsd.end - stsd.body < 8 ||
      qa_media_span_read(span, stsd.body, counts, 8) != 8 ||
      qa_big_endian(counts + 4, 4) != 1 ||
      !qa_box_at(span, stsd.body + 8, stsd.end, &entry)) {
    return 0;
  }
  int32_t channels = 0;
  int32_t rate = 0;
  uint32_t reference = 0;
  qa_box stts;
  qa_box stsz;
  qa_box stsc;
  qa_box chunks;
  const qa_box* stbl = &sound.stbl;
  if (!qa_movie_pcm_describe(span, &entry, pcm, &channels, &rate,
                             &reference) ||
      !qa_movie_holds_its_sound(span, &sound, reference) ||
      !qa_box_find(span, stbl->body, stbl->end, "stts", &stts) ||
      !qa_movie_samples_are_frames(span, &stts, sound.media_scale, rate) ||
      !qa_box_find(span, stbl->body, stbl->end, "stsz", &stsz) ||
      stsz.end - stsz.body < 12 ||
      qa_media_span_read(span, stsz.body, counts, 12) != 12 ||
      !qa_box_find(span, stbl->body, stbl->end, "stsc", &stsc) ||
      !qa_movie_table_open(span, &stsc, 12, &pcm->runs)) {
    return 0;
  }
  const int wide = qa_box_find(span, stbl->body, stbl->end, "co64", &chunks);
  if ((!wide && !qa_box_find(span, stbl->body, stbl->end, "stco", &chunks)) ||
      !qa_movie_table_open(span, &chunks, wide ? 8 : 4, &pcm->offsets)) {
    return 0;
  }
  // The size table's count is the sound's frames; its sizes are not read.
  pcm->frames_left = (int64_t)qa_big_endian(counts + 8, 4);
  pcm->run = -1;
  pcm->frame_bytes = (int64_t)channels * pcm->sample_bytes;
  pcm->raw_frames = QA_MOVIE_PCM_READ_BYTES / pcm->frame_bytes;
  if (pcm->raw_frames > QA_BUNDLED_BLOCK_FRAMES) {
    pcm->raw_frames = QA_BUNDLED_BLOCK_FRAMES;
  }
  pcm->raw = (uint8_t*)malloc((size_t)(pcm->raw_frames * pcm->frame_bytes));
  if (pcm->raw == NULL) {
    return 0;
  }
  stream->backend = &qa_movie_pcm_backend;
  stream->format = QA_AUDIO_FORMAT_MOVIE_PCM;
  stream->channels = channels;
  stream->sample_rate = rate;
  return 1;
}

// ---------------------------------------------------------------------------
// The OS decoder (AAC/m4a and friends). One per platform, all with the same
// contract as the bundled ones: interleaved float32 at the file's own rate,
// a block at a time.
//
// Reached only AFTER every decoder here declined the container, so
// WAV/FLAC/MP3 keep their byte-pinned single decoder on every platform and
// only what nothing here reads rides the platform's stack — a movie's sound
// that is not uncompressed among it (a QuickTime movie's head keeps dr_mp3
// away: see `qa_audio_mp3_may_try`).
// ---------------------------------------------------------------------------

#if defined(_WIN32)

// Media Foundation source reader over the container's bytes (headers at the
// top of the file). MF inserts the AAC (or WMA, ...) decoder and its
// float converter for us; the output media type asks for float PCM and
// leaves rate/channels at the source's own, which is exactly the conform
// contract.
//
// 🚨MF opens a URL or a byte stream and nothing else, so the container
// arrives as the stream the video decoder already had — over the same span,
// plain or framed.
//
// It takes nothing off the front: an edit list's 1,024 came back as 1,024
// frames before the sound (measured 2026-10-09).

/// [sample]'s frames into [stream]'s block: how many — 0 when it holds none
/// that can be handed over, -1 when the memory ran out.
static int64_t qa_os_take_sample(qa_audio_stream* stream,
                                 IMFSample* sample) {
  IMFMediaBuffer* buffer = NULL;
  int64_t frames = 0;
  if (SUCCEEDED(IMFSample_ConvertToContiguousBuffer(sample, &buffer))) {
    BYTE* bytes = NULL;
    DWORD length = 0;
    if (SUCCEEDED(IMFMediaBuffer_Lock(buffer, &bytes, NULL, &length))) {
      const size_t frame_bytes = sizeof(float) * (size_t)stream->channels;
      frames = (int64_t)(length / frame_bytes);
      if (frames > 0) {
        float* block = qa_audio_stream_block(stream, frames);
        if (block == NULL) {
          frames = -1;
        } else {
          memcpy(block, bytes, (size_t)frames * frame_bytes);
        }
      }
      IMFMediaBuffer_Unlock(buffer);
    }
    IMFMediaBuffer_Release(buffer);
  }
  return frames;
}

static int64_t qa_os_next(qa_audio_stream* stream) {
  qa_os_decoder* os = &stream->decoder.os;
  while (!os->ended) {
    DWORD flags = 0;
    IMFSample* sample = NULL;
    if (FAILED(IMFSourceReader_ReadSample(
            os->reader, (DWORD)MF_SOURCE_READER_FIRST_AUDIO_STREAM, 0, NULL,
            &flags, NULL, &sample))) {
      return -1;
    }
    if (flags & MF_SOURCE_READERF_ENDOFSTREAM) {
      os->ended = 1;
    }
    int64_t frames = 0;
    if (sample != NULL) {
      frames = qa_os_take_sample(stream, sample);
      IMFSample_Release(sample);
    }
    if (frames != 0) {
      return frames;
    }
  }
  return 0;
}

static void qa_os_close(qa_audio_stream* stream) {
  qa_os_decoder* os = &stream->decoder.os;
  if (os->reader != NULL) {
    IMFSourceReader_Release(os->reader);
  }
  if (os->byte_stream != NULL) {
    IMFByteStream_Release(os->byte_stream);
  }
  if (os->co_balanced) {
    CoUninitialize();
  }
  memset(os, 0, sizeof(*os));
}

static const qa_audio_backend qa_os_backend = {qa_os_next, qa_os_close};

/// ⚠️A stream is read and closed on the thread that opened it: COM's
/// apartment is the thread's, and the balance is struck on close. The conform
/// opens, reads and closes one inside a single synchronous build.
static int qa_os_open(qa_audio_stream* stream, qa_audio_start* start) {
  (void)start;
  const qa_audio_cursor* src = &stream->cursor;
  qa_os_decoder* os = &stream->decoder.os;
  memset(os, 0, sizeof(*os));
  // Per-thread COM, balanced on close; RPC_E_CHANGED_MODE means the thread
  // already runs an incompatible apartment — proceed without the balance.
  os->co_balanced = SUCCEEDED(CoInitializeEx(NULL, COINIT_MULTITHREADED));
  IMFMediaType* requested = NULL;
  IMFMediaType* actual = NULL;
  UINT32 channels = 0;
  UINT32 sample_rate = 0;
  int opened = 0;

  if (!qa_win_media_foundation_up()) {
    goto done;
  }

  os->byte_stream = qa_win_range_stream_create(src->path, src->base,
                                               src->stored_length, src->framed);
  if (os->byte_stream == NULL) {
    goto done;
  }
  if (FAILED(MFCreateSourceReaderFromByteStream(os->byte_stream, NULL,
                                                &os->reader))) {
    goto done;
  }
  if (FAILED(IMFSourceReader_SetStreamSelection(
          os->reader, (DWORD)MF_SOURCE_READER_ALL_STREAMS, FALSE)) ||
      FAILED(IMFSourceReader_SetStreamSelection(
          os->reader, (DWORD)MF_SOURCE_READER_FIRST_AUDIO_STREAM, TRUE))) {
    goto done;
  }
  if (FAILED(MFCreateMediaType(&requested)) ||
      FAILED(IMFMediaType_SetGUID(requested, &MF_MT_MAJOR_TYPE,
                                  &MFMediaType_Audio)) ||
      FAILED(IMFMediaType_SetGUID(requested, &MF_MT_SUBTYPE,
                                  &MFAudioFormat_Float))) {
    goto done;
  }
  if (FAILED(IMFSourceReader_SetCurrentMediaType(
          os->reader, (DWORD)MF_SOURCE_READER_FIRST_AUDIO_STREAM, NULL,
          requested))) {
    goto done;
  }
  if (FAILED(IMFSourceReader_GetCurrentMediaType(
          os->reader, (DWORD)MF_SOURCE_READER_FIRST_AUDIO_STREAM, &actual))) {
    goto done;
  }
  if (FAILED(IMFMediaType_GetUINT32(actual, &MF_MT_AUDIO_NUM_CHANNELS,
                                    &channels)) ||
      FAILED(IMFMediaType_GetUINT32(actual, &MF_MT_AUDIO_SAMPLES_PER_SECOND,
                                    &sample_rate)) ||
      channels == 0 || sample_rate == 0) {
    goto done;
  }
  stream->backend = &qa_os_backend;
  stream->format = QA_AUDIO_FORMAT_OS;
  stream->channels = (int32_t)channels;
  stream->sample_rate = (int32_t)sample_rate;
  opened = 1;

done:
  if (actual != NULL) {
    IMFMediaType_Release(actual);
  }
  if (requested != NULL) {
    IMFMediaType_Release(requested);
  }
  if (!opened) {
    qa_os_close(stream);
  }
  return opened;
}

#elif defined(__APPLE__)

// AudioToolbox over the cursor's callbacks (header at the top of the file).
// ExtAudioFile fronts the OS codec (AAC, ALAC, ...) and converts to the
// client format we ask for: float32 interleaved at the file's own rate
// and channel count.
// 🚨AudioToolbox was ALREADY callback-shaped, so a range costs nothing here:
// the callbacks stop reading out of a memory block and start reading out of
// the container, wherever it happens to live. That is the whole Apple half
// of「decode a movie's sound without holding the movie」.
static OSStatus qa_blob_read(void* user, SInt64 position, UInt32 request,
                             void* buffer, UInt32* actual) {
  qa_audio_cursor* cursor = (qa_audio_cursor*)user;
  if (position < 0 || position >= cursor->size) {
    *actual = 0;
    return position > cursor->size ? kAudioFileEndOfFileError : noErr;
  }
  cursor->position = (int64_t)position;
  *actual = (UInt32)qa_cursor_read(cursor, buffer, (size_t)request);
  return noErr;
}

static SInt64 qa_blob_size(void* user) {
  return (SInt64)((const qa_audio_cursor*)user)->size;
}

/// Frames AudioToolbox is asked for at a time.
#define QA_APPLE_BLOCK_FRAMES 16384

static int64_t qa_os_next(qa_audio_stream* stream) {
  float* block = qa_audio_stream_block(stream, QA_APPLE_BLOCK_FRAMES);
  if (block == NULL) {
    return -1;
  }
  const UInt32 frame_bytes = (UInt32)(sizeof(float) * stream->channels);
  AudioBufferList list;
  list.mNumberBuffers = 1;
  list.mBuffers[0].mNumberChannels = (UInt32)stream->channels;
  list.mBuffers[0].mDataByteSize = QA_APPLE_BLOCK_FRAMES * frame_bytes;
  list.mBuffers[0].mData = block;
  UInt32 frames = QA_APPLE_BLOCK_FRAMES;
  if (ExtAudioFileRead(stream->decoder.os.ext, &frames, &list) != noErr) {
    return -1;
  }
  return (int64_t)frames;
}

static void qa_os_close(qa_audio_stream* stream) {
  qa_os_decoder* os = &stream->decoder.os;
  if (os->ext != NULL) {
    ExtAudioFileDispose(os->ext);
  }
  if (os->file != NULL) {
    AudioFileClose(os->file);
  }
  memset(os, 0, sizeof(*os));
}

static const qa_audio_backend qa_os_backend = {qa_os_next, qa_os_close};

/// Whether [qa_audio_container_start] reads where [cursor]'s sound starts —
/// a movie's, or a bare ADTS stream's. Any other container's start is its
/// decoder's to say.
static int qa_audio_start_is_read_here(const qa_audio_cursor* cursor) {
  uint8_t head[8] = {0};
  qa_media_span_read(cursor->span, 0, head, sizeof(head));
  return qa_audio_head_is_a_movie_box(head) || qa_audio_is_adts(cursor);
}

static int qa_os_open(qa_audio_stream* stream, qa_audio_start* start) {
  qa_os_decoder* os = &stream->decoder.os;
  memset(os, 0, sizeof(*os));
  if (AudioFileOpenWithCallbacks(&stream->cursor, qa_blob_read, NULL,
                                 qa_blob_size, NULL, 0, &os->file) != noErr) {
    return 0;
  }
  if (ExtAudioFileWrapAudioFileID(os->file, false, &os->ext) != noErr) {
    qa_os_close(stream);
    return 0;
  }

  // 🚨AudioToolbox trims a file's priming off ITSELF, by a packet table it
  // keeps — for a movie that says nothing, Apple's own assumption, 2,112
  // (the macOS CI runner, 2026-10-15: the m4a without its edit list began
  // on its sine's 1,088th frame, and the movie Media Foundation wrote, 22
  // packets, came back 22 × 1,024 − 2,112 with its mark or without). This
  // app's law there is its format's standard, or nothing (Q6 · Q7), so where
  // this file reads the start the trimming is turned off at both ends — 0
  // overrides what the file stores (ExtendedAudioFile.h) — before the client
  // format, so the decoder is made with it (user 2026-10-09, Q4: 「OS 가
  // 스스로 걷는 플랫폼에서는 그 걷기를 끄거나, 끌 수 없으면 걷은 만큼을 알아내
  // 맞춘다」).
  if (qa_audio_start_is_read_here(&stream->cursor)) {
    AudioFilePacketTableInfo none;
    memset(&none, 0, sizeof(none));
    ExtAudioFileSetProperty(os->ext, kExtAudioFileProperty_PacketTable,
                            sizeof(none), &none);
  }

  AudioStreamBasicDescription source;
  memset(&source, 0, sizeof(source));
  UInt32 property_size = sizeof(source);
  if (ExtAudioFileGetProperty(os->ext, kExtAudioFileProperty_FileDataFormat,
                              &property_size, &source) != noErr ||
      source.mChannelsPerFrame == 0 || source.mSampleRate <= 0) {
    qa_os_close(stream);
    return 0;
  }

  AudioStreamBasicDescription client;
  memset(&client, 0, sizeof(client));
  client.mSampleRate = source.mSampleRate;
  client.mFormatID = kAudioFormatLinearPCM;
  client.mFormatFlags = kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked;
  client.mChannelsPerFrame = source.mChannelsPerFrame;
  client.mBitsPerChannel = 32;
  client.mFramesPerPacket = 1;
  client.mBytesPerFrame = 4 * client.mChannelsPerFrame;
  client.mBytesPerPacket = client.mBytesPerFrame;
  if (ExtAudioFileSetProperty(os->ext, kExtAudioFileProperty_ClientDataFormat,
                              sizeof(client), &client) != noErr) {
    qa_os_close(stream);
    return 0;
  }

  // What it still trims — a container whose start is its decoder's to say
  // (a CAF's own packet table), or an override it would not take — it says,
  // the value it reads with, and only the rest is counted.
  {
    AudioFilePacketTableInfo table;
    UInt32 table_size = sizeof(table);
    memset(&table, 0, sizeof(table));
    if (ExtAudioFileGetProperty(os->ext, kExtAudioFileProperty_PacketTable,
                                &table_size, &table) == noErr &&
        table.mPrimingFrames > 0) {
      start->taken = table.mPrimingFrames;
    }
  }
  stream->backend = &qa_os_backend;
  stream->format = QA_AUDIO_FORMAT_OS;
  stream->channels = (int32_t)client.mChannelsPerFrame;
  stream->sample_rate = (int32_t)source.mSampleRate;
  return 1;
}

#elif defined(__ANDROID__)

// NDK MediaCodec + MediaExtractor, resolved with dlsym rather than linked
// (the library's one table, qa_ndk_media.h): a NULL there is an answer — the
// file reports undecodable and rides the fallback — never a crash.
//
// 🚨★★★**A REQUIRED SYMBOL THE DEVICE LACKED ONCE COST EVERY AAC FILE.**
// The comment here said the AMediaDataSource entry points were「API 23+」.
// They are `__INTRODUCED_IN(28)`, they were REQUIRED symbols, and one missing
// symbol rejects the whole library below — so on Android 5.0 through 8.1,
// with a `minSdk` of 21, the OS codec path was not degraded, it was ABSENT.
// wav/flac/mp3/ogg kept working through the bundled decoders and every AAC
// file — every m4a, every movie's soundtrack — came back「no decoder
// recognized this file」. Nobody saw an error; a waveform simply never drew.
//
// The fix was the one the video decoder had found: a plain span opens by
// descriptor — `AMediaExtractor_setDataSourceFd(fd, offset, length)` is API
// 21 and takes a RANGE, exactly the shape a container inside the project
// file needs — and the data source was made OPTIONAL. A FRAMED span opens
// through it (qa_ndk_served_span), since its stored bytes are not the
// container.
// ↩️It is required again since 2026-10-24, when the app's floor rose to
// Android 10 (minSdk 29, board skia-devices-out-of-release): every device
// served has it, so it is part of [qa_ndk_media_decodes] and the AAC loss
// above has no device left to happen on.
//
// MediaCodec hands back every frame it decoded — it takes nothing off the
// front: the extractor's `encoder-delay` is a note for the player, not a
// cut. ⚠️Not measured on a device — and neither is the stream: the first
// device to conform a long sound is the first to run this loop a block at a
// time (user 2026-10-10 chose it all the same, Q1 A).

/// The output buffer at [index] into [stream]'s block: how many frames — 0
/// when it holds none that can be handed over yet, -1 when the memory ran
/// out. ENCODING_PCM_FLOAT (4) passes through; the default 16-bit converts
/// by the same /32768 convention every other decode path uses.
///
/// ⚠️The channels and the rate are the codec's last word when the first block
/// comes, and that block fixes them: what came before them is not counted,
/// as before the stream (the window began at the first output).
static int64_t qa_os_take_output(qa_audio_stream* stream, ssize_t index,
                                 const qa_ndk_buffer_info* info) {
  qa_os_decoder* os = &stream->decoder.os;
  if (stream->channels <= 0 || stream->sample_rate <= 0) {
    if (os->channels <= 0 || os->sample_rate <= 0) {
      return 0;
    }
    stream->channels = os->channels;
    stream->sample_rate = os->sample_rate;
  }
  size_t capacity = 0;
  uint8_t* bytes = os->ndk->codec_output_buffer(os->codec, (size_t)index,
                                                &capacity);
  if (bytes == NULL) {
    return -1;
  }
  bytes += info->offset;
  const int is_float = os->pcm_encoding == 4;
  const size_t frame_bytes = (size_t)stream->channels *
                             (is_float ? sizeof(float) : sizeof(int16_t));
  const int64_t frames = (int64_t)((size_t)info->size / frame_bytes);
  if (frames <= 0) {
    return 0;
  }
  float* block = qa_audio_stream_block(stream, frames);
  if (block == NULL) {
    return -1;
  }
  const int64_t samples = frames * stream->channels;
  if (is_float) {
    memcpy(block, bytes, (size_t)samples * sizeof(float));
  } else {
    const int16_t* raw = (const int16_t*)bytes;
    for (int64_t at = 0; at < samples; at += 1) {
      block[at] = (float)raw[at] / 32768.0f;
    }
  }
  return frames;
}

/// Feeds the codec one sample from the extractor, when it has room: whether
/// that moved anything.
static int qa_os_feed(qa_os_decoder* os) {
  const qa_ndk_media_api* ndk = os->ndk;
  const ssize_t in_index = ndk->codec_dequeue_input(os->codec, 10000);
  if (in_index < 0) {
    return 0;
  }
  size_t capacity = 0;
  uint8_t* in_buffer =
      ndk->codec_input_buffer(os->codec, (size_t)in_index, &capacity);
  const ssize_t sample_size =
      in_buffer == NULL
          ? -1
          : ndk->extractor_read_sample(os->extractor, in_buffer, capacity);
  if (sample_size < 0) {
    ndk->codec_queue_input(os->codec, (size_t)in_index, 0, 0, 0,
                           QA_NDK_FLAG_END_OF_STREAM);
    os->input_done = 1;
  } else {
    ndk->codec_queue_input(os->codec, (size_t)in_index, 0,
                           (size_t)sample_size,
                           (uint64_t)ndk->extractor_sample_time(os->extractor),
                           0);
    ndk->extractor_advance(os->extractor);
  }
  return 1;
}

static int64_t qa_os_next(qa_audio_stream* stream) {
  qa_os_decoder* os = &stream->decoder.os;
  const qa_ndk_media_api* ndk = os->ndk;
  int idle_spins = 0;
  while (!os->output_done && idle_spins < 10000) {
    int progressed = !os->input_done && qa_os_feed(os);
    qa_ndk_buffer_info info;
    memset(&info, 0, sizeof(info));
    const ssize_t out_index =
        ndk->codec_dequeue_output(os->codec, &info, 10000);
    if (out_index >= 0) {
      const int64_t frames =
          info.size > 0 ? qa_os_take_output(stream, out_index, &info) : 0;
      ndk->codec_release_output(os->codec, (size_t)out_index, 0);
      if (info.flags & QA_NDK_FLAG_END_OF_STREAM) {
        os->output_done = 1;
      }
      if (frames != 0) {
        return frames;
      }
      progressed = 1;
    } else if (out_index == QA_NDK_INFO_OUTPUT_FORMAT_CHANGED) {
      AMediaFormat* output_format = ndk->codec_output_format(os->codec);
      if (output_format != NULL) {
        ndk->format_get_int32(output_format, "sample-rate", &os->sample_rate);
        ndk->format_get_int32(output_format, "channel-count", &os->channels);
        ndk->format_get_int32(output_format, "pcm-encoding",
                              &os->pcm_encoding);
        ndk->format_delete(output_format);
      }
      progressed = 1;
    } else if (out_index == QA_NDK_INFO_OUTPUT_BUFFERS_CHANGED) {
      progressed = 1;
    }
    idle_spins = progressed ? 0 : idle_spins + 1;
  }
  // Done is the end of the stream; a codec that stopped answering before it
  // is a decode that failed.
  return os->output_done ? 0 : -1;
}

static void qa_os_close(qa_audio_stream* stream) {
  qa_os_decoder* os = &stream->decoder.os;
  const qa_ndk_media_api* ndk = os->ndk;
  if (os->codec != NULL) {
    if (os->started) {
      ndk->codec_stop(os->codec);
    }
    ndk->codec_delete(os->codec);
  }
  if (os->track_format != NULL) {
    ndk->format_delete(os->track_format);
  }
  if (os->extractor != NULL) {
    ndk->extractor_delete(os->extractor);
  }
  // After the extractor, which reads through it for as long as it lives.
  qa_ndk_served_span_free(ndk, os->served);
  // ⚠️After the extractor, not before: it reads through this descriptor for
  // as long as it lives, and closing first turns a decode into a read error
  // somewhere with no name on it.
  if (os->descriptor >= 0) {
    close(os->descriptor);
  }
  memset(os, 0, sizeof(*os));
  os->descriptor = -1;
}

static const qa_audio_backend qa_os_backend = {qa_os_next, qa_os_close};

static int qa_os_open(qa_audio_stream* stream, qa_audio_start* start) {
  (void)start;
  const qa_audio_cursor* src = &stream->cursor;
  qa_os_decoder* os = &stream->decoder.os;
  memset(os, 0, sizeof(*os));
  os->descriptor = -1;
  os->pcm_encoding = 2;  // ENCODING_PCM_16BIT — MediaCodec's default
  os->ndk = qa_ndk_media();
  const qa_ndk_media_api* ndk = os->ndk;
  if (!qa_ndk_media_decodes(ndk)) {
    return 0;
  }

  os->extractor = ndk->extractor_new();
  if (os->extractor == NULL) {
    goto fail;
  }
  if (!src->framed) {
    // The extractor's own front door for a range of a file.
    os->descriptor = open(src->path, O_RDONLY);
    if (os->descriptor < 0 ||
        ndk->extractor_set_source_fd(os->extractor, os->descriptor,
                                     (off64_t)src->base,
                                     (off64_t)src->stored_length) != 0) {
      goto fail;
    }
  } else {
    // A FRAMED span: its stored bytes are not the container, so it is served
    // through a source of our own.
    os->served = qa_ndk_served_span_open(ndk, src->path, src->base,
                                         src->stored_length, 1);
    if (os->served == NULL ||
        ndk->extractor_set_source_custom(
            os->extractor, qa_ndk_served_span_source(os->served)) != 0) {
      goto fail;
    }
  }

  const size_t tracks = ndk->extractor_track_count(os->extractor);
  const char* mime = NULL;
  size_t audio_track = (size_t)-1;
  for (size_t index = 0; index < tracks; index += 1) {
    AMediaFormat* format = ndk->extractor_track_format(os->extractor, index);
    if (format == NULL) {
      continue;
    }
    const char* candidate = NULL;
    if (ndk->format_get_string(format, "mime", &candidate) &&
        candidate != NULL && strncmp(candidate, "audio/", 6) == 0) {
      audio_track = index;
      mime = candidate;
      os->track_format = format;  // keep alive: `mime` points into it
      break;
    }
    ndk->format_delete(format);
  }
  if (audio_track == (size_t)-1 || os->track_format == NULL) {
    goto fail;
  }
  ndk->format_get_int32(os->track_format, "sample-rate", &os->sample_rate);
  ndk->format_get_int32(os->track_format, "channel-count", &os->channels);
  if (ndk->extractor_select_track(os->extractor, audio_track) != 0) {
    goto fail;
  }

  os->codec = ndk->codec_create_decoder(mime);
  if (os->codec == NULL ||
      ndk->codec_configure(os->codec, os->track_format, NULL, NULL, 0) != 0 ||
      ndk->codec_start(os->codec) != 0) {
    goto fail;
  }
  os->started = 1;
  stream->backend = &qa_os_backend;
  stream->format = QA_AUDIO_FORMAT_OS;
  // The block fixes them ([qa_os_take_output]).
  stream->channels = 0;
  stream->sample_rate = 0;
  return 1;

fail:
  qa_os_close(stream);
  return 0;
}

#else

// No OS codec stack to lean on (CI's Linux runner — not a shipping
// platform). dr_libs formats keep working; everything else reports
// undecodable and rides the caller's fallback.
static int qa_os_open(qa_audio_stream* stream, qa_audio_start* start) {
  (void)stream;
  (void)start;
  return 0;
}

#endif

// ---------------------------------------------------------------------------
// Opening a container — whichever decoder reads it.

/// Opens [stream]'s container with the first decoder that reads it: 1 when
/// one did.
///
/// Format is detected by TRYING each decoder rather than sniffing magic
/// bytes — a WAV with a junk chunk before `fmt `, or an MP3 with a fat ID3
/// tag, defeats a naive sniff, and each library already knows how to
/// recognize its own container.
///
/// 🚨★★★**THE TRYING STAYS — THE CONTAINER'S FIRST BYTES SAY WHETHER dr_mp3
/// MAY TRY** (user 2026-10-09, board sound-lands-on-its-exact-sample-Q2:
/// 「파일 머리를 먼저 본다」). dr_mp3's frame-sync scan finds frames in the
/// quiet stretches of uncompressed sound, whose small negative samples are
/// `FF Fx` bytes: a 30-minute H.264 + PCM reel came back as a tenth of a
/// second of noise (2026-10-06), and the OS stack, which reads that file
/// exactly, was never asked — it can only come after dr_mp3, and dr_mp3 said
/// yes. Trying dr_mp3 last of the bundled decoders was the old guard, and it
/// was not enough. Neither objection above reaches the sniff: it reads only a
/// container's own magic at its first byte, never a chunk inside it, and an
/// MP3's head — an ID3 tag or a frame — is one it leaves alone.
///
/// Vorbis sits BEFORE mp3 on purpose: the OggS magic makes stb_vorbis a
/// strict recognizer, while dr_mp3's frame-sync scan is the most permissive
/// of the bunch — it must always try LAST of the bundled decoders or it will
/// happily "decode" someone else's container. Then a movie's uncompressed
/// sound, which needs no codec ([qa_movie_pcm_open]); and for whatever none
/// of these reads — dr_mp3 perhaps never asked — the OS codec stack (AAC/m4a
/// per the decided format table).
///
/// A decoder READ the container when it opened and handed something back —
/// the one rule, whatever is asked of the stream after. One that opens and
/// hands back nothing falls through to the next.
static int qa_audio_stream_begin(qa_audio_stream* stream) {
  static const qa_audio_opener openers[] = {
      qa_wav_open, qa_flac_open,      qa_vorbis_open,
      qa_mp3_open, qa_movie_pcm_open, qa_os_open};
  for (size_t index = 0; index < sizeof(openers) / sizeof(openers[0]);
       index += 1) {
    // No file a bundled decoder reads puts frames of its own before its
    // sound but an MP3, whose opener counts its lead.
    qa_audio_start start = {0, 0, -1};
    // 🚨Every attempt in the dispatch chain starts from zero (see
    // qa_cursor_rewind).
    qa_cursor_rewind(&stream->cursor);
    if (!openers[index](stream, &start)) {
      continue;
    }
    const int64_t got = stream->backend->next(stream);
    if (got <= 0) {
      stream->backend->close(stream);
      stream->backend = NULL;
      continue;
    }
    stream->block_frames = got;
    stream->block_at = 0;
    // The OS stack's sound starts where the file says, and only the file
    // knows — as a movie's uncompressed sound does: its rate is the
    // decoder's last word by the first block.
    if (stream->format == QA_AUDIO_FORMAT_OS ||
        stream->format == QA_AUDIO_FORMAT_MOVIE_PCM) {
      qa_audio_container_start(&stream->cursor, stream->sample_rate, &start);
    }
    const int64_t lead = start.lead - start.taken;
    stream->lead = lead > 0 ? lead : 0;
    stream->left = start.keep;
    return 1;
  }
  return 0;
}

QA_EXPORT void qa_audio_stream_close(qa_audio_stream* stream) {
  if (stream == NULL) {
    return;
  }
  if (stream->backend != NULL) {
    stream->backend->close(stream);
  }
  free(stream->block);
  if (stream->span != NULL) {
    qa_media_span_close(stream->span);
  }
  free(stream->path);
  free(stream);
}

/// The sound of a container stored in `[offset, offset + length)` of [path] —
/// as it is, or FRAMED (compressed in blocks) when [framed] — opened to be
/// read on: interleaved float32 at its OWN rate, frame 0 its first (what the
/// file says came before it is not counted). Resampling to the project rate
/// is a separate step: it is a quality decision, and burying it here would
/// make it invisible.
///
/// NULL when nothing could read it; [qa_audio_stream_close] lets it go.
/// [out_format] says which QA_AUDIO_FORMAT_* read it.
///
/// [offset] `0` with [length] the file's own size is a whole file, and that
/// is the ordinary case — a span is not an archive-only idea.
///
/// 🚨★★★**THE POINT IS WHAT IS NOT HERE: a `Uint8List`.** The conform used to
/// read the whole container into memory before a decoder was handed anything,
/// which is why a three-gigabyte reference movie could not be asked for its
/// sound at all — and a FRAMED one still arrived that way until 2026-09-24.
/// Nothing on this path holds more than a decode block and one span block.
QA_EXPORT qa_audio_stream* qa_audio_stream_open(const char* path,
                                                int64_t offset,
                                                int64_t length,
                                                int32_t framed,
                                                int32_t* out_format,
                                                int32_t* out_channels,
                                                int32_t* out_sample_rate) {
  if (out_format == NULL || out_channels == NULL || out_sample_rate == NULL) {
    return NULL;
  }
  *out_format = QA_AUDIO_FORMAT_UNKNOWN;
  *out_channels = 0;
  *out_sample_rate = 0;
  if (path == NULL || offset < 0 || length <= 0) {
    return NULL;
  }
  qa_audio_stream* stream =
      (qa_audio_stream*)calloc(1, sizeof(qa_audio_stream));
  if (stream == NULL) {
    return NULL;
  }
  // ⛔A span that runs past the end is refused rather than clamped — the
  // span reader's own rule: a short container decodes as a corrupt file,
  // which is a much worse answer than 「that span is not in there」.
  stream->span = qa_media_span_open(path, offset, length, framed);
  const size_t path_bytes = strlen(path) + 1;
  stream->path = (char*)malloc(path_bytes);
  if (stream->span == NULL || stream->path == NULL) {
    qa_audio_stream_close(stream);
    return NULL;
  }
  memcpy(stream->path, path, path_bytes);
  stream->cursor.span = stream->span;
  stream->cursor.path = stream->path;
  stream->cursor.base = offset;
  stream->cursor.stored_length = length;
  stream->cursor.framed = framed ? 1 : 0;
  stream->cursor.size = qa_media_span_size(stream->span);
  if (!qa_audio_stream_begin(stream)) {
    qa_audio_stream_close(stream);
    return NULL;
  }
  *out_format = stream->format;
  *out_channels = stream->channels;
  *out_sample_rate = stream->sample_rate;
  return stream;
}

/// Up to [frames] more frames of [stream]'s sound into [out]: how many —
/// short only at the sound's end, 0 past it, -1 where the decoder failed.
QA_EXPORT int64_t qa_audio_stream_read(qa_audio_stream* stream, float* out,
                                       int64_t frames) {
  if (stream == NULL || out == NULL || frames < 0) {
    return -1;
  }
  return qa_audio_stream_pass(stream, out, frames);
}

/// The container's [window_count] frames of sound from frame [window_start]
/// — the sound's own frames at the container's own rate, frame 0 its first —
/// and only those held (user 2026-10-09, sound-lands-on-its-exact-sample-Q5:
/// a piece cut from a long reel holds the piece, not the reel). -1: to the
/// end. 0: none — the rate and the channels, which a caller needs before it
/// can name its frames: ask for nothing, then for what that says to ask. A
/// window past the end is no frames, not a failure.
///
/// Returns the QA_AUDIO_FORMAT_* that read it, or 0 when nothing could. On
/// success the caller owns *out_samples (NULL when no frames came) and
/// releases it with qa_audio_decode_free.
QA_EXPORT int32_t qa_audio_decode_span_window(
    const char* path,
    int64_t offset,
    int64_t length,
    int32_t framed,
    int64_t window_start,
    int64_t window_count,
    float** out_samples,
    int64_t* out_frame_count,
    int32_t* out_channels,
    int32_t* out_sample_rate) {
  if (out_samples == NULL || out_frame_count == NULL || out_channels == NULL ||
      out_sample_rate == NULL) {
    return QA_AUDIO_FORMAT_UNKNOWN;
  }
  *out_samples = NULL;
  *out_frame_count = 0;
  *out_channels = 0;
  *out_sample_rate = 0;
  if (window_start < 0) {
    return QA_AUDIO_FORMAT_UNKNOWN;
  }
  int32_t format = QA_AUDIO_FORMAT_UNKNOWN;
  int32_t channels = 0;
  int32_t rate = 0;
  qa_audio_stream* stream = qa_audio_stream_open(path, offset, length, framed,
                                                 &format, &channels, &rate);
  if (stream == NULL) {
    return QA_AUDIO_FORMAT_UNKNOWN;
  }
  float* kept = NULL;
  int64_t kept_frames = 0;
  int64_t capacity = 0;
  int healthy = window_count == 0 ||
                qa_audio_stream_pass(stream, NULL, window_start) >= 0;
  while (healthy && window_count != 0 &&
         (window_count < 0 || kept_frames < window_count)) {
    int64_t want = QA_BUNDLED_BLOCK_FRAMES * 16;
    if (window_count >= 0 && want > window_count - kept_frames) {
      want = window_count - kept_frames;
    }
    if (kept_frames + want > capacity) {
      int64_t next = capacity == 0 ? want : capacity;
      while (next < kept_frames + want) {
        next *= 2;
      }
      float* grown = (float*)realloc(
          kept, (size_t)next * (size_t)channels * sizeof(float));
      if (grown == NULL) {
        healthy = 0;
        break;
      }
      kept = grown;
      capacity = next;
    }
    const int64_t got = qa_audio_stream_pass(
        stream, kept + (size_t)kept_frames * (size_t)channels, want);
    if (got < 0) {
      healthy = 0;
    } else if (got == 0) {
      break;
    }
    kept_frames += got > 0 ? got : 0;
  }
  qa_audio_stream_close(stream);
  if (!healthy) {
    free(kept);
    return QA_AUDIO_FORMAT_UNKNOWN;
  }
  // A window past the sound's end kept nothing, and that is an answer.
  if (kept_frames == 0) {
    free(kept);
    kept = NULL;
  }
  *out_samples = kept;
  *out_frame_count = kept_frames;
  *out_channels = channels;
  *out_sample_rate = rate;
  return format;
}

/// The whole sound of the container — [qa_audio_decode_span_window] from
/// frame 0 to the end.
QA_EXPORT int32_t qa_audio_decode_span(
    const char* path,
    int64_t offset,
    int64_t length,
    int32_t framed,
    float** out_samples,
    int64_t* out_frame_count,
    int32_t* out_channels,
    int32_t* out_sample_rate) {
  return qa_audio_decode_span_window(path, offset, length, framed, 0, -1,
                                     out_samples, out_frame_count,
                                     out_channels, out_sample_rate);
}

// Releases a buffer from qa_audio_decode_span. All three libraries route
// their frees through the same default allocator, so drwav_free is correct
// for any of them — but going through one named entry point keeps the
// caller from having to know that.
QA_EXPORT void qa_audio_decode_free(float* samples) {
  if (samples != NULL) {
    drwav_free(samples, NULL);
  }
}
