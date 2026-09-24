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

// A growing PCM accumulator for the OS decoders: they hand back audio in
// codec-sized chunks, and none of them says the total up front.
typedef struct {
  uint8_t* bytes;
  size_t size;
  size_t capacity;
} qa_pcm_accumulator;

static int qa_pcm_append(qa_pcm_accumulator* accumulator,
                         const void* data,
                         size_t size) {
  if (size == 0) {
    return 1;
  }
  if (accumulator->size + size > accumulator->capacity) {
    size_t next = accumulator->capacity == 0 ? 65536 : accumulator->capacity;
    while (next < accumulator->size + size) {
      next *= 2;
    }
    uint8_t* grown = (uint8_t*)realloc(accumulator->bytes, next);
    if (grown == NULL) {
      return 0;
    }
    accumulator->bytes = grown;
    accumulator->capacity = next;
  }
  memcpy(accumulator->bytes + accumulator->size, data, size);
  accumulator->size += size;
  return 1;
}

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

// ---------------------------------------------------------------------------
// The OS decoder (AAC/m4a and friends). One entry point per platform, all
// with the same contract as the dr_libs path: interleaved float32 at the
// file's own rate, malloc-owned (qa_audio_decode_free releases it — every
// path in this file frees through plain free()).
//
// Reached only AFTER dr_libs declined the container, so WAV/FLAC/MP3 keep
// their byte-pinned single decoder on every platform and only the formats
// dr_libs cannot read ride the platform's stack.
// ---------------------------------------------------------------------------

#if defined(_WIN32)

// The video decoder's span stream, shared rather than written twice — see
// qa_win_range_stream.c. ⛔A second `IMFByteStream` over a span is the one
// thing this must not become: it is 200 lines of hand-written COM, and two
// of those drift.
#include "qa_win_range_stream.h"

// Media Foundation source reader over the container's bytes (headers at the
// top of the file). MF inserts the AAC (or WMA, ...) decoder and its
// float converter for us; the output media type asks for float PCM and
// leaves rate/channels at the source's own, which is exactly the conform
// contract.
//
// 🚨MF opens a URL or a byte stream and nothing else, so the container
// arrives as the stream the video decoder already had — over the same span,
// plain or framed.
static int32_t qa_audio_decode_os(const qa_audio_cursor* src,
                                  float** out_samples,
                                  int64_t* out_frame_count,
                                  int32_t* out_channels,
                                  int32_t* out_sample_rate) {
  // Per-thread COM, balanced on exit; RPC_E_CHANGED_MODE means the thread
  // already runs an incompatible apartment — proceed without the balance.
  const HRESULT co = CoInitializeEx(NULL, COINIT_MULTITHREADED);
  const int co_balanced = SUCCEEDED(co);
  int32_t result = QA_AUDIO_FORMAT_UNKNOWN;
  int mf_started = 0;
  IMFByteStream* byte_stream = NULL;
  IMFSourceReader* reader = NULL;
  IMFMediaType* requested = NULL;
  IMFMediaType* actual = NULL;
  qa_pcm_accumulator pcm = {NULL, 0, 0};
  UINT32 channels = 0;
  UINT32 sample_rate = 0;

  // MFStartup is process-wide and refcounted; pairing it with MFShutdown
  // per decode keeps this self-contained (decodes are rare import-time
  // events, not a hot path).
  if (FAILED(MFStartup(MF_VERSION, MFSTARTUP_LITE))) {
    goto done;
  }
  mf_started = 1;

  byte_stream = qa_win_range_stream_create(src->path, src->base,
                                           src->stored_length, src->framed);
  if (byte_stream == NULL) {
    goto done;
  }
  if (FAILED(MFCreateSourceReaderFromByteStream(byte_stream, NULL, &reader))) {
    goto done;
  }
  if (FAILED(IMFSourceReader_SetStreamSelection(
          reader, (DWORD)MF_SOURCE_READER_ALL_STREAMS, FALSE)) ||
      FAILED(IMFSourceReader_SetStreamSelection(
          reader, (DWORD)MF_SOURCE_READER_FIRST_AUDIO_STREAM, TRUE))) {
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
          reader, (DWORD)MF_SOURCE_READER_FIRST_AUDIO_STREAM, NULL,
          requested))) {
    goto done;
  }
  if (FAILED(IMFSourceReader_GetCurrentMediaType(
          reader, (DWORD)MF_SOURCE_READER_FIRST_AUDIO_STREAM, &actual))) {
    goto done;
  }
  if (FAILED(IMFMediaType_GetUINT32(actual, &MF_MT_AUDIO_NUM_CHANNELS,
                                    &channels)) ||
      FAILED(IMFMediaType_GetUINT32(actual, &MF_MT_AUDIO_SAMPLES_PER_SECOND,
                                    &sample_rate)) ||
      channels == 0 || sample_rate == 0) {
    goto done;
  }

  for (;;) {
    DWORD flags = 0;
    IMFSample* sample = NULL;
    if (FAILED(IMFSourceReader_ReadSample(
            reader, (DWORD)MF_SOURCE_READER_FIRST_AUDIO_STREAM, 0, NULL,
            &flags, NULL, &sample))) {
      goto done;
    }
    if (sample != NULL) {
      IMFMediaBuffer* buffer = NULL;
      if (SUCCEEDED(IMFSample_ConvertToContiguousBuffer(sample, &buffer))) {
        BYTE* bytes = NULL;
        DWORD length = 0;
        if (SUCCEEDED(IMFMediaBuffer_Lock(buffer, &bytes, NULL, &length))) {
          const int appended = qa_pcm_append(&pcm, bytes, length);
          IMFMediaBuffer_Unlock(buffer);
          if (!appended) {
            IMFMediaBuffer_Release(buffer);
            IMFSample_Release(sample);
            goto done;
          }
        }
        IMFMediaBuffer_Release(buffer);
      }
      IMFSample_Release(sample);
    }
    if (flags & MF_SOURCE_READERF_ENDOFSTREAM) {
      break;
    }
  }

  if (pcm.size >= sizeof(float) * channels) {
    const int64_t frames = (int64_t)(pcm.size / (sizeof(float) * channels));
    *out_samples = (float*)pcm.bytes;  // malloc-owned; freed by the caller
    *out_frame_count = frames;
    *out_channels = (int32_t)channels;
    *out_sample_rate = (int32_t)sample_rate;
    pcm.bytes = NULL;
    result = QA_AUDIO_FORMAT_OS;
  }

done:
  free(pcm.bytes);
  if (actual != NULL) {
    IMFMediaType_Release(actual);
  }
  if (requested != NULL) {
    IMFMediaType_Release(requested);
  }
  if (reader != NULL) {
    IMFSourceReader_Release(reader);
  }
  if (byte_stream != NULL) {
    IMFByteStream_Release(byte_stream);
  }
  if (mf_started) {
    MFShutdown();
  }
  if (co_balanced) {
    CoUninitialize();
  }
  return result;
}

#elif defined(__APPLE__)

// AudioToolbox over memory callbacks (header at the top of the file).
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

static int32_t qa_audio_decode_os(const qa_audio_cursor* src,
                                  float** out_samples,
                                  int64_t* out_frame_count,
                                  int32_t* out_channels,
                                  int32_t* out_sample_rate) {
  // ⚠️A COPY, because the callbacks move the cursor and this function was
  // handed a read-only view of the caller's.
  qa_audio_cursor blob = *src;
  AudioFileID file = NULL;
  ExtAudioFileRef ext = NULL;
  qa_pcm_accumulator pcm = {NULL, 0, 0};
  int32_t result = QA_AUDIO_FORMAT_UNKNOWN;

  if (AudioFileOpenWithCallbacks(&blob, qa_blob_read, NULL, qa_blob_size,
                                 NULL, 0, &file) != noErr) {
    return QA_AUDIO_FORMAT_UNKNOWN;
  }
  if (ExtAudioFileWrapAudioFileID(file, false, &ext) != noErr) {
    AudioFileClose(file);
    return QA_AUDIO_FORMAT_UNKNOWN;
  }

  AudioStreamBasicDescription source;
  memset(&source, 0, sizeof(source));
  UInt32 property_size = sizeof(source);
  if (ExtAudioFileGetProperty(ext, kExtAudioFileProperty_FileDataFormat,
                              &property_size, &source) != noErr ||
      source.mChannelsPerFrame == 0 || source.mSampleRate <= 0) {
    goto done;
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
  if (ExtAudioFileSetProperty(ext, kExtAudioFileProperty_ClientDataFormat,
                              sizeof(client), &client) != noErr) {
    goto done;
  }

  enum { kChunkFrames = 16384 };
  float* chunk = (float*)malloc((size_t)kChunkFrames * client.mBytesPerFrame);
  if (chunk == NULL) {
    goto done;
  }
  for (;;) {
    AudioBufferList list;
    list.mNumberBuffers = 1;
    list.mBuffers[0].mNumberChannels = client.mChannelsPerFrame;
    list.mBuffers[0].mDataByteSize = kChunkFrames * client.mBytesPerFrame;
    list.mBuffers[0].mData = chunk;
    UInt32 frames = kChunkFrames;
    if (ExtAudioFileRead(ext, &frames, &list) != noErr) {
      free(chunk);
      goto done;
    }
    if (frames == 0) {
      break;
    }
    if (!qa_pcm_append(&pcm, chunk, (size_t)frames * client.mBytesPerFrame)) {
      free(chunk);
      goto done;
    }
  }
  free(chunk);

  if (pcm.size >= sizeof(float) * client.mChannelsPerFrame) {
    *out_samples = (float*)pcm.bytes;
    *out_frame_count =
        (int64_t)(pcm.size / (sizeof(float) * client.mChannelsPerFrame));
    *out_channels = (int32_t)client.mChannelsPerFrame;
    *out_sample_rate = (int32_t)source.mSampleRate;
    pcm.bytes = NULL;
    result = QA_AUDIO_FORMAT_OS;
  }

done:
  free(pcm.bytes);
  if (ext != NULL) {
    ExtAudioFileDispose(ext);
  }
  if (file != NULL) {
    AudioFileClose(file);
  }
  return result;
}

#elif defined(__ANDROID__)

// NDK MediaCodec + MediaExtractor, resolved with dlsym rather than linked
// (the library's one table, qa_ndk_media.h): dlsym returning NULL on an
// older device IS the graceful capability check — no weak-symbol machinery,
// no crash, the file just reports undecodable and rides the fallback.
//
// 🚨★★★**THE FLOOR IS API 21 AGAIN, AND IT USED TO BE 28.**
// The comment here said the AMediaDataSource entry points were「API 23+」.
// They are `__INTRODUCED_IN(28)`, they were REQUIRED symbols, and one missing
// symbol rejects the whole library below — so on Android 5.0 through 8.1,
// with a `minSdk` of 21, the OS codec path was not degraded, it was ABSENT.
// wav/flac/mp3/ogg kept working through the bundled decoders and every AAC
// file — every m4a, every movie's soundtrack — came back「no decoder
// recognized this file」. Nobody saw an error; a waveform simply never drew.
//
// The fix is the one the video decoder already found:
// `AMediaExtractor_setDataSourceFd(fd, offset, length)` is API 21 and takes a
// RANGE, which is both what every supported device can open and exactly the
// shape a container inside the project file needs. So the descriptor form is
// now the required one, and the data-source form is OPTIONAL — kept only
// because a framed archive entry arrives assembled in memory and has no
// range to point at. ⛔It must never go back to being required.
// The NDK media API is the library's ONE table (qa_ndk_media.h). This file
// resolved its own until 2026-09-24, and its custom-source read callback took
// the offset as `off_t` where the NDK passes `off64_t` — on a 32-bit ARM
// device the offset was read out of the wrong registers.
#include "qa_ndk_media.h"

static int32_t qa_audio_decode_os(const qa_audio_cursor* src,
                                  float** out_samples,
                                  int64_t* out_frame_count,
                                  int32_t* out_channels,
                                  int32_t* out_sample_rate) {
  const qa_ndk_media_api* ndk = qa_ndk_media();
  if (!qa_ndk_media_decodes(ndk)) {
    return QA_AUDIO_FORMAT_UNKNOWN;
  }

  int32_t result = QA_AUDIO_FORMAT_UNKNOWN;
  AMediaExtractor* extractor = NULL;
  qa_ndk_served_span* served = NULL;
  AMediaCodec* codec = NULL;
  AMediaFormat* track_format = NULL;
  qa_pcm_accumulator pcm = {NULL, 0, 0};
  int descriptor = -1;
  int32_t channels = 0;
  int32_t sample_rate = 0;
  int32_t pcm_encoding = 2;  // ENCODING_PCM_16BIT — MediaCodec's default

  extractor = ndk->extractor_new();
  if (extractor == NULL) {
    goto done;
  }
  if (!src->framed) {
    // The API-21 form, and the one every supported device has.
    descriptor = open(src->path, O_RDONLY);
    if (descriptor < 0) {
      goto done;
    }
    if (ndk->extractor_set_source_fd(extractor, descriptor,
                                     (off64_t)src->base,
                                     (off64_t)src->stored_length) != 0) {
      goto done;
    }
  } else {
    // A FRAMED span: its stored bytes are not the container, so it is served
    // through a source of our own. ⛔Absent below API 28, and that is an
    // ANSWER: undecodable, the same one the caller already handles, not a
    // crash and not a required symbol.
    served = qa_ndk_served_span_open(ndk, src->path, src->base,
                                     src->stored_length, 1);
    if (served == NULL ||
        ndk->extractor_set_source_custom(
            extractor, qa_ndk_served_span_source(served)) != 0) {
      goto done;
    }
  }

  const size_t tracks = ndk->extractor_track_count(extractor);
  const char* mime = NULL;
  size_t audio_track = (size_t)-1;
  for (size_t index = 0; index < tracks; index += 1) {
    AMediaFormat* format = ndk->extractor_track_format(extractor, index);
    if (format == NULL) {
      continue;
    }
    const char* candidate = NULL;
    if (ndk->format_get_string(format, "mime", &candidate) && candidate != NULL &&
        strncmp(candidate, "audio/", 6) == 0) {
      audio_track = index;
      mime = candidate;
      track_format = format;  // keep alive: `mime` points into it
      break;
    }
    ndk->format_delete(format);
  }
  if (audio_track == (size_t)-1 || track_format == NULL) {
    goto done;
  }
  ndk->format_get_int32(track_format, "sample-rate", &sample_rate);
  ndk->format_get_int32(track_format, "channel-count", &channels);
  if (ndk->extractor_select_track(extractor, audio_track) != 0) {
    goto done;
  }

  codec = ndk->codec_create_decoder(mime);
  if (codec == NULL ||
      ndk->codec_configure(codec, track_format, NULL, NULL, 0) != 0 ||
      ndk->codec_start(codec) != 0) {
    goto done;
  }

  int input_done = 0;
  int output_done = 0;
  int idle_spins = 0;
  while (!output_done && idle_spins < 10000) {
    int progressed = 0;
    if (!input_done) {
      const ssize_t in_index = ndk->codec_dequeue_input(codec, 10000);
      if (in_index >= 0) {
        size_t capacity = 0;
        uint8_t* in_buffer = ndk->codec_input_buffer(codec, (size_t)in_index,
                                                 &capacity);
        const ssize_t sample_size =
            in_buffer == NULL
                ? -1
                : ndk->extractor_read_sample(extractor, in_buffer, capacity);
        if (sample_size < 0) {
          ndk->codec_queue_input(codec, (size_t)in_index, 0, 0, 0,
                                QA_NDK_FLAG_END_OF_STREAM);
          input_done = 1;
        } else {
          ndk->codec_queue_input(codec, (size_t)in_index, 0,
                                (size_t)sample_size,
                                (uint64_t)ndk->extractor_sample_time(extractor),
                                0);
          ndk->extractor_advance(extractor);
        }
        progressed = 1;
      }
    }
    qa_ndk_buffer_info info;
    memset(&info, 0, sizeof(info));
    const ssize_t out_index = ndk->codec_dequeue_output(codec, &info, 10000);
    if (out_index >= 0) {
      if (info.size > 0) {
        size_t capacity = 0;
        uint8_t* out_buffer = ndk->codec_output_buffer(codec, (size_t)out_index,
                                                   &capacity);
        if (out_buffer == NULL ||
            !qa_pcm_append(&pcm, out_buffer + info.offset,
                           (size_t)info.size)) {
          ndk->codec_release_output(codec, (size_t)out_index, 0);
          goto done;
        }
      }
      ndk->codec_release_output(codec, (size_t)out_index, 0);
      if (info.flags & QA_NDK_FLAG_END_OF_STREAM) {
        output_done = 1;
      }
      progressed = 1;
    } else if (out_index == QA_NDK_INFO_OUTPUT_FORMAT_CHANGED) {
      AMediaFormat* output_format = ndk->codec_output_format(codec);
      if (output_format != NULL) {
        ndk->format_get_int32(output_format, "sample-rate", &sample_rate);
        ndk->format_get_int32(output_format, "channel-count", &channels);
        ndk->format_get_int32(output_format, "pcm-encoding", &pcm_encoding);
        ndk->format_delete(output_format);
      }
      progressed = 1;
    } else if (out_index == QA_NDK_INFO_OUTPUT_BUFFERS_CHANGED) {
      progressed = 1;
    }
    idle_spins = progressed ? 0 : idle_spins + 1;
  }
  ndk->codec_stop(codec);

  if (!output_done || channels <= 0 || sample_rate <= 0 || pcm.size == 0) {
    goto done;
  }

  // ENCODING_PCM_FLOAT (4) passes through; the default 16-bit converts by
  // the same /32768 convention every other decode path uses.
  if (pcm_encoding == 4) {
    const int64_t total = (int64_t)(pcm.size / sizeof(float));
    *out_samples = (float*)pcm.bytes;
    *out_frame_count = total / channels;
    pcm.bytes = NULL;
  } else {
    const int64_t total = (int64_t)(pcm.size / sizeof(int16_t));
    float* converted = (float*)malloc((size_t)total * sizeof(float));
    if (converted == NULL) {
      goto done;
    }
    const int16_t* raw = (const int16_t*)pcm.bytes;
    for (int64_t index = 0; index < total; index += 1) {
      converted[index] = (float)raw[index] / 32768.0f;
    }
    *out_samples = converted;
    *out_frame_count = total / channels;
  }
  *out_channels = channels;
  *out_sample_rate = sample_rate;
  result = QA_AUDIO_FORMAT_OS;

done:
  free(pcm.bytes);
  if (codec != NULL) {
    ndk->codec_delete(codec);
  }
  if (track_format != NULL) {
    ndk->format_delete(track_format);
  }
  if (extractor != NULL) {
    ndk->extractor_delete(extractor);
  }
  // After the extractor, which reads through it for as long as it lives.
  qa_ndk_served_span_free(ndk, served);
  // ⚠️After the extractor, not before: it reads through this descriptor for
  // as long as it lives, and closing first turns a decode into a read error
  // somewhere with no name on it.
  if (descriptor >= 0) {
    close(descriptor);
  }
  return result;
}

#else

// No OS codec stack to lean on (CI's Linux runner — not a shipping
// platform). dr_libs formats keep working; everything else reports
// undecodable and rides the caller's fallback.
static int32_t qa_audio_decode_os(const qa_audio_cursor* src,
                                  float** out_samples,
                                  int64_t* out_frame_count,
                                  int32_t* out_channels,
                                  int32_t* out_sample_rate) {
  (void)src;
  (void)out_samples;
  (void)out_frame_count;
  (void)out_channels;
  (void)out_sample_rate;
  return QA_AUDIO_FORMAT_UNKNOWN;
}

#endif

// Decodes a whole container — wherever its bytes are — to interleaved
// float32 at its OWN sample rate. Resampling to the project rate is a
// separate step: it is a quality decision, and burying it here would make it
// invisible.
//
// Format is detected by TRYING each decoder rather than sniffing magic
// bytes — a WAV with a junk chunk before `fmt `, or an MP3 with a fat ID3
// tag, defeats a naive sniff, and each library already knows how to
// recognize its own container.
//
// Returns the QA_AUDIO_FORMAT_* that succeeded, or 0 when nothing could
// read it. On success the caller owns *out_samples and must release it
// with qa_audio_decode_free.
/// stb_vorbis over [cursor]'s container, or UNKNOWN.
///
/// ⚠️The one decoder with no callback form — memory or a `FILE*` — so the
/// span is handed over two ways. A PLAIN span is a FILE section: a position
/// plus a length, a range exactly. A FRAMED span has no FILE that holds the
/// container, so an ogg in one is assembled in memory — but only once its
/// first four bytes say it IS one (`OggS`, which stb_vorbis requires anyway):
/// asking every framed container in full would read a whole movie to learn
/// it is not an ogg. A carried ogg is nearly never framed at all — it is
/// already compressed, and a save frames only what shrinks.
static int32_t qa_audio_decode_vorbis(qa_audio_cursor* cursor,
                                      float** out_samples,
                                      int64_t* out_frame_count,
                                      int32_t* out_channels,
                                      int32_t* out_sample_rate) {
  if (cursor->size > 0x7FFFFFFF) {
    return QA_AUDIO_FORMAT_UNKNOWN;
  }
  int vorbis_error = 0;
  stb_vorbis* vorbis = NULL;
  FILE* section = NULL;
  uint8_t* assembled = NULL;
  if (!cursor->framed) {
    // ⚠️The 2GB guard is stb's, not ours: it remembers where a section
    // started with `ftell`, whose `long` is 32 bits on Windows. Past that it
    // would read from the wrong place rather than fail, so the attempt is
    // skipped instead — an ogg carried past the 2GB mark of a project file
    // decodes as「not an ogg」, and no other format is affected.
    if (cursor->base <= 0x7FFFFFFF) {
      section = qa_open_path_read(cursor->path);
      if (section != NULL && qa_seek_absolute(section, cursor->base)) {
        vorbis = stb_vorbis_open_file_section(section, 0, &vorbis_error, NULL,
                                              (unsigned)cursor->size);
      }
    }
  } else {
    uint8_t magic[4];
    if (qa_media_span_read(cursor->span, 0, magic, 4) == 4 &&
        memcmp(magic, "OggS", 4) == 0) {
      assembled = (uint8_t*)malloc((size_t)cursor->size);
      if (assembled != NULL &&
          qa_media_span_read(cursor->span, 0, assembled, cursor->size) ==
              cursor->size) {
        vorbis = stb_vorbis_open_memory(assembled, (int)cursor->size,
                                        &vorbis_error, NULL);
      }
    }
  }
  int32_t result = QA_AUDIO_FORMAT_UNKNOWN;
  if (vorbis != NULL) {
    const stb_vorbis_info info = stb_vorbis_get_info(vorbis);
    if (info.channels > 0 && info.sample_rate > 0) {
      qa_pcm_accumulator pcm = {NULL, 0, 0};
      enum { kVorbisChunkFrames = 4096 };
      float* chunk = (float*)malloc(
          (size_t)kVorbisChunkFrames * info.channels * sizeof(float));
      int healthy = chunk != NULL;
      while (healthy) {
        const int frames = stb_vorbis_get_samples_float_interleaved(
            vorbis, info.channels, chunk, kVorbisChunkFrames * info.channels);
        if (frames <= 0) {
          break;
        }
        if (!qa_pcm_append(&pcm, chunk,
                           (size_t)frames * info.channels * sizeof(float))) {
          healthy = 0;
        }
      }
      free(chunk);
      if (healthy && pcm.size >= sizeof(float) * (size_t)info.channels) {
        *out_samples = (float*)pcm.bytes;
        *out_frame_count =
            (int64_t)(pcm.size / (sizeof(float) * (size_t)info.channels));
        *out_channels = info.channels;
        *out_sample_rate = (int32_t)info.sample_rate;
        result = QA_AUDIO_FORMAT_VORBIS;
      } else {
        free(pcm.bytes);
      }
    }
    stb_vorbis_close(vorbis);
  }
  if (section != NULL) {
    fclose(section);
  }
  free(assembled);
  return result;
}

static int32_t qa_audio_decode_cursor(
    qa_audio_cursor* cursor,
    float** out_samples,
    int64_t* out_frame_count,
    int32_t* out_channels,
    int32_t* out_sample_rate) {
  unsigned int channels = 0;
  unsigned int sample_rate = 0;

  {
    drwav_uint64 frames = 0;
    qa_cursor_rewind(cursor);
    float* samples = drwav_open_and_read_pcm_frames_f32(
        qa_dr_read, qa_wav_seek, qa_wav_tell, cursor, &channels, &sample_rate,
        &frames, NULL);
    if (samples != NULL) {
      *out_samples = samples;
      *out_frame_count = (int64_t)frames;
      *out_channels = (int32_t)channels;
      *out_sample_rate = (int32_t)sample_rate;
      return QA_AUDIO_FORMAT_WAV;
    }
  }
  {
    drflac_uint64 frames = 0;
    qa_cursor_rewind(cursor);
    float* samples = drflac_open_and_read_pcm_frames_f32(
        qa_dr_read, qa_flac_seek, qa_flac_tell, cursor, &channels, &sample_rate,
        &frames, NULL);
    if (samples != NULL) {
      *out_samples = samples;
      *out_frame_count = (int64_t)frames;
      *out_channels = (int32_t)channels;
      *out_sample_rate = (int32_t)sample_rate;
      return QA_AUDIO_FORMAT_FLAC;
    }
  }
  // Vorbis sits BEFORE mp3 on purpose: the OggS magic makes stb_vorbis a
  // strict recognizer, while dr_mp3's frame-sync scan is the most
  // permissive of the bunch — it must always try LAST of the bundled
  // decoders or it will happily "decode" someone else's container.
  {
    const int32_t vorbis = qa_audio_decode_vorbis(
        cursor, out_samples, out_frame_count, out_channels, out_sample_rate);
    if (vorbis != QA_AUDIO_FORMAT_UNKNOWN) {
      return vorbis;
    }
  }
  {
    drmp3_config config;
    memset(&config, 0, sizeof(config));
    drmp3_uint64 frames = 0;
    qa_cursor_rewind(cursor);
    float* samples = drmp3_open_and_read_pcm_frames_f32(
        qa_dr_read, qa_mp3_seek, qa_mp3_tell, cursor, &config, &frames, NULL);
    if (samples != NULL) {
      *out_samples = samples;
      *out_frame_count = (int64_t)frames;
      *out_channels = (int32_t)config.channels;
      *out_sample_rate = (int32_t)config.sampleRate;
      return QA_AUDIO_FORMAT_MP3;
    }
  }
  // Nothing dr_libs reads: hand the container to the OS codec stack
  // (AAC/m4a per the decided format table). The OS path allocates with
  // malloc, so the one qa_audio_decode_free below releases either origin.
  qa_cursor_rewind(cursor);
  return qa_audio_decode_os(cursor, out_samples, out_frame_count, out_channels,
                            out_sample_rate);
}

/// The output slots, emptied before a decode fills them — or 0 when one is
/// missing.
static int32_t qa_audio_decode_begin(float** out_samples,
                                     int64_t* out_frame_count,
                                     int32_t* out_channels,
                                     int32_t* out_sample_rate) {
  if (out_samples == NULL || out_frame_count == NULL || out_channels == NULL ||
      out_sample_rate == NULL) {
    return 0;
  }
  *out_samples = NULL;
  *out_frame_count = 0;
  *out_channels = 0;
  *out_sample_rate = 0;
  return 1;
}

/// A container stored in `[offset, offset + length)` of [path] — as it is,
/// or FRAMED (compressed in blocks) when [framed]: the shape a sound inside
/// the project file has, the shape a staged copy has, and the shape a movie
/// whose soundtrack we want has whether it is carried or referenced.
///
/// 🚨★★★**THE POINT IS WHAT IS NOT HERE: a `Uint8List`.** The conform used to
/// read the whole container into memory before a decoder was handed anything,
/// which is why a three-gigabyte reference movie could not be asked for its
/// sound at all — and a FRAMED one still arrived that way until 2026-09-24.
/// Nothing on this path holds more than a decode buffer and one block.
///
/// [offset] `0` with [length] the file's own size is a whole file, and that
/// is the ordinary case — a span is not an archive-only idea.
QA_EXPORT int32_t qa_audio_decode_span(
    const char* path,
    int64_t offset,
    int64_t length,
    int32_t framed,
    float** out_samples,
    int64_t* out_frame_count,
    int32_t* out_channels,
    int32_t* out_sample_rate) {
  if (!qa_audio_decode_begin(out_samples, out_frame_count, out_channels,
                             out_sample_rate)) {
    return QA_AUDIO_FORMAT_UNKNOWN;
  }
  if (path == NULL || offset < 0 || length <= 0) {
    return QA_AUDIO_FORMAT_UNKNOWN;
  }
  // ⛔A span that runs past the end is refused rather than clamped — the
  // span reader's own rule: a short container decodes as a corrupt file,
  // which is a much worse answer than 「that span is not in there」.
  qa_media_span* span = qa_media_span_open(path, offset, length, framed);
  if (span == NULL) {
    return QA_AUDIO_FORMAT_UNKNOWN;
  }
  qa_audio_cursor cursor;
  memset(&cursor, 0, sizeof(cursor));
  cursor.span = span;
  cursor.path = path;
  cursor.base = offset;
  cursor.stored_length = length;
  cursor.framed = framed ? 1 : 0;
  cursor.size = qa_media_span_size(span);
  const int32_t result = qa_audio_decode_cursor(
      &cursor, out_samples, out_frame_count, out_channels, out_sample_rate);
  qa_media_span_close(span);
  return result;
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

// The decoders the build actually carries — the loader can report what a
// given binary supports instead of failing mysteriously on a format that
// was compiled out.
QA_EXPORT int32_t qa_audio_decode_formats(void) {
  int32_t formats = (1 << QA_AUDIO_FORMAT_WAV) | (1 << QA_AUDIO_FORMAT_FLAC) |
                    (1 << QA_AUDIO_FORMAT_MP3) | (1 << QA_AUDIO_FORMAT_VORBIS);
#if defined(_WIN32) || defined(__APPLE__) || defined(__ANDROID__)
  formats |= 1 << QA_AUDIO_FORMAT_OS;
#endif
  return formats;
}
