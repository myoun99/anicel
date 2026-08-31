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
// Why a path at all: a container inside the project file is a RANGE of one,
// and the whole point is not to hold the container in memory to decode it.
// A three-gigabyte movie whose sound we want cannot arrive as a `Uint8List`.
// Memory stays a first-class origin — a FRAMED archive entry is not a
// contiguous range, so its bytes genuinely arrive assembled.
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
#include <shlwapi.h>
#include <mfapi.h>
#include <mfidl.h>
#include <mfreadwrite.h>
#elif defined(__APPLE__)
#include <AudioToolbox/AudioToolbox.h>
#elif defined(__ANDROID__)
#include <dlfcn.h>
#include <fcntl.h>
#include <unistd.h>
#endif

// ⚠️AFTER the block above, for the same reason the comment there gives: this
// TU decides COBJMACROS and WIN32_LEAN_AND_MEAN, and a header that reached
// windows.h first would settle both with the wrong answer.
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
// 🚨★★★**WHERE THE BYTES ARE — ONE CURSOR, TWO ORIGINS, NO SECOND DISPATCH.**
//
// A container arrives either assembled in memory or as a range of a file, and
// the naive shape is two of everything: two dispatch chains, two of each
// decoder's setup, two places to forget a format. The decoders all take
// read/seek callbacks, so instead there is one cursor and the origin is a
// field in it. ⛔A `qa_audio_decode_range` that repeated the chain would be
// exactly the copy this repo keeps deleting.
//
// ⚠️Positions are RELATIVE TO THE CONTAINER, never to the file. A decoder
// that seeks to 0 must land on the container's first byte, not the archive's
// — which for a carried sound is thousands of bytes earlier, and reads as a
// corrupt file rather than as the arithmetic bug it is.
typedef struct {
  /// Memory origin: the whole container. NULL when the origin is a file.
  const uint8_t* data;
  /// File origin: an open handle. NULL when the origin is memory.
  FILE* file;
  /// File origin: the same file's path, UTF-8. ⚠️Carried as well as the
  /// handle because the OS decoders below do not take a `FILE*`: Media
  /// Foundation wants a byte stream over a wide path, and the NDK extractor
  /// wants a descriptor. Only AudioToolbox reads through the handle.
  const char* path;
  /// File origin: where the container starts in that file.
  int64_t base;
  /// How many bytes the container has, either way.
  int64_t size;
  /// Where the next read starts, 0..size.
  int64_t position;
} qa_audio_cursor;

/// Reads up to [want] bytes into [out], returning how many. Short at the end
/// of the container, and 0 past it — every decoder here treats that as EOF.
static size_t qa_cursor_read(void* user, void* out, size_t want) {
  qa_audio_cursor* cursor = (qa_audio_cursor*)user;
  if (cursor->position >= cursor->size) {
    return 0;
  }
  const int64_t left = cursor->size - cursor->position;
  size_t take = want;
  if ((int64_t)take > left) {
    take = (size_t)left;
  }
  if (cursor->data != NULL) {
    memcpy(out, cursor->data + cursor->position, take);
  } else {
    if (!qa_seek_absolute(cursor->file, cursor->base + cursor->position)) {
      return 0;
    }
    take = fread(out, 1, take, cursor->file);
  }
  cursor->position += (int64_t)take;
  return take;
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

// The video decoder's range stream, shared rather than written twice — see
// qa_win_range_stream.c. ⛔A second `IMFByteStream` over a range is the one
// thing this must not become: it is 200 lines of hand-written COM whose
// whole job is `base + position`, and two of those drift.
extern IMFByteStream* qa_win_range_stream_create(const wchar_t* path,
                                                 int64_t offset,
                                                 int64_t length);

// Media Foundation source reader over the container's bytes (headers at the
// top of the file). MF inserts the AAC (or WMA, ...) decoder and its
// float converter for us; the output media type asks for float PCM and
// leaves rate/channels at the source's own, which is exactly the conform
// contract.
//
// 🚨MF opens a URL or a byte stream and nothing else, which is why BOTH
// origins arrive here as an `IMFByteStream` and everything after the open is
// one code path: memory gets `SHCreateMemStream`, a file range gets the
// stream the video decoder already had.
static int32_t qa_audio_decode_os(const qa_audio_cursor* src,
                                  float** out_samples,
                                  int64_t* out_frame_count,
                                  int32_t* out_channels,
                                  int32_t* out_sample_rate) {
  const uint8_t* data = src->data;
  const int64_t size = src->size;
  if (data != NULL && size > 0x7FFFFFFF) {
    return QA_AUDIO_FORMAT_UNKNOWN;  // SHCreateMemStream takes a UINT.
  }
  // Per-thread COM, balanced on exit; RPC_E_CHANGED_MODE means the thread
  // already runs an incompatible apartment — proceed without the balance.
  const HRESULT co = CoInitializeEx(NULL, COINIT_MULTITHREADED);
  const int co_balanced = SUCCEEDED(co);
  int32_t result = QA_AUDIO_FORMAT_UNKNOWN;
  int mf_started = 0;
  IStream* stream = NULL;
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

  if (data != NULL) {
    stream = SHCreateMemStream(data, (UINT)size);
    if (stream == NULL) {
      goto done;
    }
    if (FAILED(MFCreateMFByteStreamOnStream(stream, &byte_stream))) {
      goto done;
    }
  } else {
    wchar_t wide[1024];
    if (!qa_widen_path(src->path, wide,
                       (int)(sizeof(wide) / sizeof(wide[0])))) {
      goto done;
    }
    byte_stream = qa_win_range_stream_create(wide, src->base, size);
    if (byte_stream == NULL) {
      goto done;
    }
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
  if (stream != NULL) {
    IStream_Release(stream);
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
// (dlfcn.h at the top of the file): dlsym returning NULL on an older device
// IS the graceful capability check — no weak-symbol machinery, no crash, the
// file just reports undecodable and rides the fallback.
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
typedef struct AMediaExtractor AMediaExtractor;
typedef struct AMediaDataSource AMediaDataSource;
typedef struct AMediaFormat AMediaFormat;
typedef struct AMediaCodec AMediaCodec;

typedef struct {
  int32_t offset;
  int32_t size;
  int64_t presentationTimeUs;
  uint32_t flags;
} qa_codec_buffer_info;  // mirrors AMediaCodecBufferInfo

#define QA_MEDIA_EOS_FLAG 4              // AMEDIACODEC_BUFFER_FLAG_END_OF_STREAM
#define QA_MEDIA_INFO_TRY_AGAIN (-1)     // AMEDIACODEC_INFO_TRY_AGAIN_LATER
#define QA_MEDIA_INFO_FORMAT_CHANGED (-2)
#define QA_MEDIA_INFO_BUFFERS_CHANGED (-3)

typedef struct {
  void* library;
  AMediaExtractor* (*extractor_new)(void);
  int (*extractor_delete)(AMediaExtractor*);
  /// API 21 — the floor, and the reason this build runs on Android 5.0.
  int (*extractor_set_data_source_fd)(AMediaExtractor*, int, off64_t, off64_t);
  /// API 28 — OPTIONAL, see the section comment. NULL on an older device.
  int (*extractor_set_data_source_custom)(AMediaExtractor*, AMediaDataSource*);
  size_t (*extractor_track_count)(AMediaExtractor*);
  AMediaFormat* (*extractor_track_format)(AMediaExtractor*, size_t);
  int (*extractor_select_track)(AMediaExtractor*, size_t);
  ssize_t (*extractor_read_sample)(AMediaExtractor*, uint8_t*, size_t);
  int64_t (*extractor_sample_time)(AMediaExtractor*);
  int (*extractor_advance)(AMediaExtractor*);
  AMediaDataSource* (*source_new)(void);
  void (*source_delete)(AMediaDataSource*);
  void (*source_set_userdata)(AMediaDataSource*, void*);
  void (*source_set_read_at)(AMediaDataSource*,
                             ssize_t (*)(void*, off_t, void*, size_t));
  void (*source_set_get_size)(AMediaDataSource*, ssize_t (*)(void*));
  int (*format_delete)(AMediaFormat*);
  int (*format_get_string)(AMediaFormat*, const char*, const char**);
  int (*format_get_int32)(AMediaFormat*, const char*, int32_t*);
  AMediaCodec* (*codec_create_decoder)(const char*);
  int (*codec_delete)(AMediaCodec*);
  int (*codec_configure)(AMediaCodec*, const AMediaFormat*, void*, void*,
                         uint32_t);
  int (*codec_start)(AMediaCodec*);
  int (*codec_stop)(AMediaCodec*);
  ssize_t (*codec_dequeue_input)(AMediaCodec*, int64_t);
  uint8_t* (*codec_get_input)(AMediaCodec*, size_t, size_t*);
  int (*codec_queue_input)(AMediaCodec*, size_t, off_t, size_t, uint64_t,
                           uint32_t);
  ssize_t (*codec_dequeue_output)(AMediaCodec*, qa_codec_buffer_info*,
                                  int64_t);
  uint8_t* (*codec_get_output)(AMediaCodec*, size_t, size_t*);
  int (*codec_release_output)(AMediaCodec*, size_t, int);
  AMediaFormat* (*codec_output_format)(AMediaCodec*);
} qa_ndk_media;

static int qa_ndk_media_load(qa_ndk_media* ndk) {
  memset(ndk, 0, sizeof(*ndk));
  ndk->library = dlopen("libmediandk.so", RTLD_NOW);
  if (ndk->library == NULL) {
    return 0;
  }
#define QA_SYM(field, name)                          \
  *(void**)(&ndk->field) = dlsym(ndk->library, name); \
  if (ndk->field == NULL) {                          \
    dlclose(ndk->library);                           \
    ndk->library = NULL;                             \
    return 0;                                        \
  }
  QA_SYM(extractor_new, "AMediaExtractor_new")
  QA_SYM(extractor_delete, "AMediaExtractor_delete")
  QA_SYM(extractor_set_data_source_fd, "AMediaExtractor_setDataSourceFd")
  QA_SYM(extractor_track_count, "AMediaExtractor_getTrackCount")
  QA_SYM(extractor_track_format, "AMediaExtractor_getTrackFormat")
  QA_SYM(extractor_select_track, "AMediaExtractor_selectTrack")
  QA_SYM(extractor_read_sample, "AMediaExtractor_readSampleData")
  QA_SYM(extractor_sample_time, "AMediaExtractor_getSampleTime")
  QA_SYM(extractor_advance, "AMediaExtractor_advance")
  // ⛔OPTIONAL — API 28. Resolved with the plain dlsym, NOT with QA_SYM:
  // making these required is what silenced AAC on every Android below 9.
  // The memory origin checks them before use; the range origin never needs
  // them. See the section comment.
#define QA_SYM_OPTIONAL(field, name) \
  *(void**)(&ndk->field) = dlsym(ndk->library, name);
  QA_SYM_OPTIONAL(extractor_set_data_source_custom,
                  "AMediaExtractor_setDataSourceCustom")
  QA_SYM_OPTIONAL(source_new, "AMediaDataSource_new")
  QA_SYM_OPTIONAL(source_delete, "AMediaDataSource_delete")
  QA_SYM_OPTIONAL(source_set_userdata, "AMediaDataSource_setUserdata")
  QA_SYM_OPTIONAL(source_set_read_at, "AMediaDataSource_setReadAt")
  QA_SYM_OPTIONAL(source_set_get_size, "AMediaDataSource_setGetSize")
#undef QA_SYM_OPTIONAL
  QA_SYM(format_delete, "AMediaFormat_delete")
  QA_SYM(format_get_string, "AMediaFormat_getString")
  QA_SYM(format_get_int32, "AMediaFormat_getInt32")
  QA_SYM(codec_create_decoder, "AMediaCodec_createDecoderByType")
  QA_SYM(codec_delete, "AMediaCodec_delete")
  QA_SYM(codec_configure, "AMediaCodec_configure")
  QA_SYM(codec_start, "AMediaCodec_start")
  QA_SYM(codec_stop, "AMediaCodec_stop")
  QA_SYM(codec_dequeue_input, "AMediaCodec_dequeueInputBuffer")
  QA_SYM(codec_get_input, "AMediaCodec_getInputBuffer")
  QA_SYM(codec_queue_input, "AMediaCodec_queueInputBuffer")
  QA_SYM(codec_dequeue_output, "AMediaCodec_dequeueOutputBuffer")
  QA_SYM(codec_get_output, "AMediaCodec_getOutputBuffer")
  QA_SYM(codec_release_output, "AMediaCodec_releaseOutputBuffer")
  QA_SYM(codec_output_format, "AMediaCodec_getOutputFormat")
#undef QA_SYM
  return 1;
}

typedef struct {
  const uint8_t* data;
  int64_t size;
} qa_audio_blob;

static ssize_t qa_blob_read_at(void* user, off_t offset, void* buffer,
                               size_t size) {
  qa_audio_cursor* cursor = (qa_audio_cursor*)user;
  if (offset < 0 || offset >= cursor->size) {
    return -1;  // EOS per the AMediaDataSource contract
  }
  cursor->position = (int64_t)offset;
  return (ssize_t)qa_cursor_read(cursor, buffer, size);
}

static ssize_t qa_blob_get_size(void* user) {
  return (ssize_t)((const qa_audio_cursor*)user)->size;
}

static int32_t qa_audio_decode_os(const qa_audio_cursor* src,
                                  float** out_samples,
                                  int64_t* out_frame_count,
                                  int32_t* out_channels,
                                  int32_t* out_sample_rate) {
  qa_ndk_media ndk;
  if (!qa_ndk_media_load(&ndk)) {
    return QA_AUDIO_FORMAT_UNKNOWN;
  }

  // ⚠️A COPY — the read callback moves the cursor, and this was handed a
  // read-only view of the caller's.
  qa_audio_cursor blob = *src;
  int32_t result = QA_AUDIO_FORMAT_UNKNOWN;
  AMediaExtractor* extractor = NULL;
  AMediaDataSource* source = NULL;
  AMediaCodec* codec = NULL;
  AMediaFormat* track_format = NULL;
  qa_pcm_accumulator pcm = {NULL, 0, 0};
  int descriptor = -1;
  int32_t channels = 0;
  int32_t sample_rate = 0;
  int32_t pcm_encoding = 2;  // ENCODING_PCM_16BIT — MediaCodec's default

  extractor = ndk.extractor_new();
  if (extractor == NULL) {
    goto done;
  }
  if (src->data == NULL) {
    // The API-21 form, and the one every supported device has.
    descriptor = open(src->path, O_RDONLY);
    if (descriptor < 0) {
      goto done;
    }
    if (ndk.extractor_set_data_source_fd(extractor, descriptor,
                                         (off64_t)src->base,
                                         (off64_t)src->size) != 0) {
      goto done;
    }
  } else {
    // Assembled bytes with no range to point at — a framed archive entry.
    // ⛔Absent below API 28, and that is an ANSWER: undecodable, the same
    // one the caller already handles, not a crash and not a required symbol.
    if (ndk.source_new == NULL || ndk.extractor_set_data_source_custom == NULL) {
      goto done;
    }
    source = ndk.source_new();
    if (source == NULL) {
      goto done;
    }
    ndk.source_set_userdata(source, &blob);
    ndk.source_set_read_at(source, qa_blob_read_at);
    ndk.source_set_get_size(source, qa_blob_get_size);
    if (ndk.extractor_set_data_source_custom(extractor, source) != 0) {
      goto done;
    }
  }

  const size_t tracks = ndk.extractor_track_count(extractor);
  const char* mime = NULL;
  size_t audio_track = (size_t)-1;
  for (size_t index = 0; index < tracks; index += 1) {
    AMediaFormat* format = ndk.extractor_track_format(extractor, index);
    if (format == NULL) {
      continue;
    }
    const char* candidate = NULL;
    if (ndk.format_get_string(format, "mime", &candidate) && candidate != NULL &&
        strncmp(candidate, "audio/", 6) == 0) {
      audio_track = index;
      mime = candidate;
      track_format = format;  // keep alive: `mime` points into it
      break;
    }
    ndk.format_delete(format);
  }
  if (audio_track == (size_t)-1 || track_format == NULL) {
    goto done;
  }
  ndk.format_get_int32(track_format, "sample-rate", &sample_rate);
  ndk.format_get_int32(track_format, "channel-count", &channels);
  if (ndk.extractor_select_track(extractor, audio_track) != 0) {
    goto done;
  }

  codec = ndk.codec_create_decoder(mime);
  if (codec == NULL ||
      ndk.codec_configure(codec, track_format, NULL, NULL, 0) != 0 ||
      ndk.codec_start(codec) != 0) {
    goto done;
  }

  int input_done = 0;
  int output_done = 0;
  int idle_spins = 0;
  while (!output_done && idle_spins < 10000) {
    int progressed = 0;
    if (!input_done) {
      const ssize_t in_index = ndk.codec_dequeue_input(codec, 10000);
      if (in_index >= 0) {
        size_t capacity = 0;
        uint8_t* in_buffer = ndk.codec_get_input(codec, (size_t)in_index,
                                                 &capacity);
        const ssize_t sample_size =
            in_buffer == NULL
                ? -1
                : ndk.extractor_read_sample(extractor, in_buffer, capacity);
        if (sample_size < 0) {
          ndk.codec_queue_input(codec, (size_t)in_index, 0, 0, 0,
                                QA_MEDIA_EOS_FLAG);
          input_done = 1;
        } else {
          ndk.codec_queue_input(codec, (size_t)in_index, 0,
                                (size_t)sample_size,
                                (uint64_t)ndk.extractor_sample_time(extractor),
                                0);
          ndk.extractor_advance(extractor);
        }
        progressed = 1;
      }
    }
    qa_codec_buffer_info info;
    memset(&info, 0, sizeof(info));
    const ssize_t out_index = ndk.codec_dequeue_output(codec, &info, 10000);
    if (out_index >= 0) {
      if (info.size > 0) {
        size_t capacity = 0;
        uint8_t* out_buffer = ndk.codec_get_output(codec, (size_t)out_index,
                                                   &capacity);
        if (out_buffer == NULL ||
            !qa_pcm_append(&pcm, out_buffer + info.offset,
                           (size_t)info.size)) {
          ndk.codec_release_output(codec, (size_t)out_index, 0);
          goto done;
        }
      }
      ndk.codec_release_output(codec, (size_t)out_index, 0);
      if (info.flags & QA_MEDIA_EOS_FLAG) {
        output_done = 1;
      }
      progressed = 1;
    } else if (out_index == QA_MEDIA_INFO_FORMAT_CHANGED) {
      AMediaFormat* output_format = ndk.codec_output_format(codec);
      if (output_format != NULL) {
        ndk.format_get_int32(output_format, "sample-rate", &sample_rate);
        ndk.format_get_int32(output_format, "channel-count", &channels);
        ndk.format_get_int32(output_format, "pcm-encoding", &pcm_encoding);
        ndk.format_delete(output_format);
      }
      progressed = 1;
    } else if (out_index == QA_MEDIA_INFO_BUFFERS_CHANGED) {
      progressed = 1;
    }
    idle_spins = progressed ? 0 : idle_spins + 1;
  }
  ndk.codec_stop(codec);

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
    ndk.codec_delete(codec);
  }
  if (track_format != NULL) {
    ndk.format_delete(track_format);
  }
  if (extractor != NULL) {
    ndk.extractor_delete(extractor);
  }
  if (source != NULL) {
    ndk.source_delete(source);
  }
  // ⚠️After the extractor, not before: it reads through this descriptor for
  // as long as it lives, and closing first turns a decode into a read error
  // somewhere with no name on it.
  if (descriptor >= 0) {
    close(descriptor);
  }
  dlclose(ndk.library);
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
  //
  // ⚠️The one decoder with no callback form: memory or a `FILE*`, so the two
  // origins are two OPENS and everything after them is shared. The FILE form
  // is `_section`, which is a position plus a length — a range, exactly.
  if (cursor->size <= 0x7FFFFFFF) {
    int vorbis_error = 0;
    stb_vorbis* vorbis = NULL;
    if (cursor->data != NULL) {
      vorbis = stb_vorbis_open_memory(cursor->data, (int)cursor->size,
                                      &vorbis_error, NULL);
    } else if (cursor->base <= 0x7FFFFFFF &&
               qa_seek_absolute(cursor->file, cursor->base)) {
      // ⚠️The 2GB guard is stb's, not ours: it remembers where a section
      // started with `ftell`, whose `long` is 32 bits on Windows. Past that
      // it would read from the wrong place rather than fail, so the attempt
      // is skipped instead — an ogg carried past the 2GB mark of a project
      // file decodes as「not an ogg」, and no other format is affected.
      vorbis = stb_vorbis_open_file_section(cursor->file, 0, &vorbis_error,
                                            NULL, (unsigned)cursor->size);
    }
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
              vorbis, info.channels, chunk,
              kVorbisChunkFrames * info.channels);
          if (frames <= 0) {
            break;
          }
          if (!qa_pcm_append(&pcm, chunk,
                             (size_t)frames * info.channels * sizeof(float))) {
            healthy = 0;
          }
        }
        free(chunk);
        stb_vorbis_close(vorbis);
        if (healthy && pcm.size >= sizeof(float) * (size_t)info.channels) {
          *out_samples = (float*)pcm.bytes;
          *out_frame_count =
              (int64_t)(pcm.size / (sizeof(float) * (size_t)info.channels));
          *out_channels = info.channels;
          *out_sample_rate = (int32_t)info.sample_rate;
          return QA_AUDIO_FORMAT_VORBIS;
        }
        free(pcm.bytes);
      } else {
        stb_vorbis_close(vorbis);
      }
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

/// The two entry points, and the ONLY difference between them is where the
/// bytes are. ⛔Neither repeats the chain above.
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

/// A container the caller already holds. ⚠️Still needed after the range form
/// arrived: a FRAMED archive entry is stored in pieces, so its bytes are
/// genuinely assembled before anyone can decode them.
QA_EXPORT int32_t qa_audio_decode_memory(
    const uint8_t* data,
    int64_t size,
    float** out_samples,
    int64_t* out_frame_count,
    int32_t* out_channels,
    int32_t* out_sample_rate) {
  if (!qa_audio_decode_begin(out_samples, out_frame_count, out_channels,
                             out_sample_rate)) {
    return QA_AUDIO_FORMAT_UNKNOWN;
  }
  if (data == NULL || size <= 0) {
    return QA_AUDIO_FORMAT_UNKNOWN;
  }
  qa_audio_cursor cursor;
  memset(&cursor, 0, sizeof(cursor));
  cursor.data = data;
  cursor.size = size;
  return qa_audio_decode_cursor(&cursor, out_samples, out_frame_count,
                                out_channels, out_sample_rate);
}

/// A container that is [length] bytes of [path] starting at [offset] — the
/// shape a sound inside the project file has, and the shape a movie whose
/// soundtrack we want has whether it is carried or referenced.
///
/// 🚨★★★**THE POINT IS WHAT IS NOT HERE: a `Uint8List`.** The conform used to
/// read the whole container into memory before a decoder was handed anything,
/// which is why a three-gigabyte reference movie could not be asked for its
/// sound at all. Nothing on this path holds more than a decode buffer.
///
/// [offset] `0` with [length] the file's own size is a whole file, and that
/// is the ordinary case — a range is not an archive-only idea.
QA_EXPORT int32_t qa_audio_decode_range(
    const char* path,
    int64_t offset,
    int64_t length,
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
  FILE* file = qa_open_path_read(path);
  if (file == NULL) {
    return QA_AUDIO_FORMAT_UNKNOWN;
  }
  // ⛔A range that runs past the end is refused rather than clamped: a short
  // container decodes as a corrupt file, which is a much worse answer than
  // 「that range is not in there」.
  int32_t result = QA_AUDIO_FORMAT_UNKNOWN;
  const int64_t total = qa_file_size(file);
  if (total >= 0 && offset + length <= total) {
    qa_audio_cursor cursor;
    memset(&cursor, 0, sizeof(cursor));
    cursor.file = file;
    cursor.path = path;
    cursor.base = offset;
    cursor.size = length;
    result = qa_audio_decode_cursor(&cursor, out_samples, out_frame_count,
                                    out_channels, out_sample_rate);
  }
  fclose(file);
  return result;
}

// Releases a buffer from qa_audio_decode_memory. All three libraries route
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
