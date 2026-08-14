// The OS video DECODER: a movie file in, one RGBA frame out.
//
// Why this exists: every media surface in this app is built on "give me
// the picture at index N" — the transport bar, the preview, the cel bake —
// and a movie was the one source that could not answer. Placement of video
// has been refused by name since the import window was built, and this is
// the missing half.
//
// It is the encoder's mirror, deliberately: the export path already goes
// through each operating system's own codec stack rather than an ffmpeg
// binary a tablet does not have (see qa_video_encode.c), and decode is the
// same stack read backwards.
//
//   Windows  — Media Foundation's Source Reader, which also converts to
//              RGB32 for us (the advanced video processing attribute), so
//              our only pixel job is BGRA → RGBA and the stride.
//   Apple    — AVAssetReader (not yet; it belongs with the device that can
//              verify it).
//   Android  — NDK AMediaExtractor + AMediaCodec (likewise).
//
// Absence is an ANSWER, never a crash: qa_video_decode_supported() is 0 on
// a platform whose path is not written, and the app says "no decoder in
// this build" instead of failing as a corrupt file.
//
// One document at a time, like the export session. Scrubbing a preview is
// the driving case and it looks at one movie at a time; a second reader
// would double the memory a decode holds for no caller that exists.

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#if defined(_WIN32)
#define QA_EXPORT __declspec(dllexport)
#else
#define QA_EXPORT __attribute__((visibility("default")))
#endif

static char g_decode_error[256];

static void qa_decode_set_error(const char* message) {
  if (message == NULL) {
    g_decode_error[0] = '\0';
    return;
  }
  snprintf(g_decode_error, sizeof(g_decode_error), "%s", message);
}

QA_EXPORT const char* qa_video_decode_last_error(void) {
  return g_decode_error;
}

#if defined(_WIN32)

#define COBJMACROS
#include <windows.h>
#include <mfapi.h>
#include <mfidl.h>
#include <mfreadwrite.h>
#include <mferror.h>

typedef struct {
  IMFSourceReader* reader;
  int32_t width;
  int32_t height;
  int32_t fps_num;
  int32_t fps_den;
  int64_t duration_100ns;
  int64_t frame_count;
  // Negative in the media type means the picture is stored bottom-up; the
  // magnitude is the row pitch either way.
  int32_t stride;
  int32_t bottom_up;
  int32_t open;
  int32_t mf_started;
} qa_video_decode_state;

static qa_video_decode_state g_dec;

static void qa_video_decode_teardown(void) {
  if (g_dec.reader != NULL) {
    IMFSourceReader_Release(g_dec.reader);
    g_dec.reader = NULL;
  }
  if (g_dec.mf_started) {
    MFShutdown();
    g_dec.mf_started = 0;
  }
  g_dec.open = 0;
}

QA_EXPORT int32_t qa_video_decode_supported(void) { return 1; }

QA_EXPORT void qa_video_decode_close(void) { qa_video_decode_teardown(); }

QA_EXPORT int32_t qa_video_decode_open(const char* path) {
  qa_video_decode_teardown();
  qa_decode_set_error(NULL);
  if (path == NULL || path[0] == '\0') {
    qa_decode_set_error("no path");
    return 0;
  }

  wchar_t wide[1024];
  if (MultiByteToWideChar(CP_UTF8, 0, path, -1, wide,
                          (int)(sizeof(wide) / sizeof(wide[0]))) == 0) {
    qa_decode_set_error("path is not valid UTF-8");
    return 0;
  }

  if (FAILED(MFStartup(MF_VERSION, MFSTARTUP_LITE))) {
    qa_decode_set_error("MFStartup failed");
    return 0;
  }
  g_dec.mf_started = 1;

  // ENABLE_ADVANCED_VIDEO_PROCESSING is what lets us ask for RGB32 from a
  // source that is YUV — without it the reader refuses the format and the
  // caller would have to carry a colour converter of its own.
  IMFAttributes* attributes = NULL;
  if (FAILED(MFCreateAttributes(&attributes, 1))) {
    qa_decode_set_error("MFCreateAttributes failed");
    qa_video_decode_teardown();
    return 0;
  }
  IMFAttributes_SetUINT32(
      attributes, &MF_SOURCE_READER_ENABLE_ADVANCED_VIDEO_PROCESSING, TRUE);

  HRESULT hr = MFCreateSourceReaderFromURL(wide, attributes, &g_dec.reader);
  IMFAttributes_Release(attributes);
  if (FAILED(hr) || g_dec.reader == NULL) {
    qa_decode_set_error("this file has no readable video stream");
    qa_video_decode_teardown();
    return 0;
  }

  // Only the video stream: leaving audio selected makes ReadSample hand
  // back audio samples we would have to skip past on every seek.
  IMFSourceReader_SetStreamSelection(
      g_dec.reader, (DWORD)MF_SOURCE_READER_ALL_STREAMS, FALSE);
  IMFSourceReader_SetStreamSelection(
      g_dec.reader, (DWORD)MF_SOURCE_READER_FIRST_VIDEO_STREAM, TRUE);

  IMFMediaType* wanted = NULL;
  if (FAILED(MFCreateMediaType(&wanted))) {
    qa_decode_set_error("MFCreateMediaType failed");
    qa_video_decode_teardown();
    return 0;
  }
  IMFMediaType_SetGUID(wanted, &MF_MT_MAJOR_TYPE, &MFMediaType_Video);
  IMFMediaType_SetGUID(wanted, &MF_MT_SUBTYPE, &MFVideoFormat_RGB32);
  hr = IMFSourceReader_SetCurrentMediaType(
      g_dec.reader, (DWORD)MF_SOURCE_READER_FIRST_VIDEO_STREAM, NULL, wanted);
  IMFMediaType_Release(wanted);
  if (FAILED(hr)) {
    qa_decode_set_error("no RGB conversion for this codec");
    qa_video_decode_teardown();
    return 0;
  }

  IMFMediaType* current = NULL;
  if (FAILED(IMFSourceReader_GetCurrentMediaType(
          g_dec.reader, (DWORD)MF_SOURCE_READER_FIRST_VIDEO_STREAM,
          &current))) {
    qa_decode_set_error("the reader would not describe its output");
    qa_video_decode_teardown();
    return 0;
  }

  // MFGetAttributeSize and MFGetAttributeRatio are C++-only inlines in
  // mfapi.h — in C the pair is read as the packed UINT64 those helpers
  // unpack: high word first, low word second.
  UINT64 packed_size = 0;
  IMFMediaType_GetUINT64(current, &MF_MT_FRAME_SIZE, &packed_size);
  UINT32 width = (UINT32)(packed_size >> 32);
  UINT32 height = (UINT32)(packed_size & 0xFFFFFFFFULL);
  UINT64 packed_rate = 0;
  IMFMediaType_GetUINT64(current, &MF_MT_FRAME_RATE, &packed_rate);
  UINT32 fps_num = (UINT32)(packed_rate >> 32);
  UINT32 fps_den = (UINT32)(packed_rate & 0xFFFFFFFFULL);
  INT32 stride = 0;
  if (FAILED(IMFMediaType_GetUINT32(current, &MF_MT_DEFAULT_STRIDE,
                                    (UINT32*)&stride))) {
    stride = (INT32)(width * 4);
  }
  IMFMediaType_Release(current);

  if (width == 0 || height == 0) {
    qa_decode_set_error("the video stream has no frame size");
    qa_video_decode_teardown();
    return 0;
  }
  if (fps_num == 0 || fps_den == 0) {
    // A file with no declared rate still has frames; 24 is the honest
    // guess for the material this app takes in, and the caller can say so.
    fps_num = 24;
    fps_den = 1;
  }

  g_dec.width = (int32_t)width;
  g_dec.height = (int32_t)height;
  g_dec.fps_num = (int32_t)fps_num;
  g_dec.fps_den = (int32_t)fps_den;
  g_dec.bottom_up = stride < 0 ? 1 : 0;
  g_dec.stride = stride < 0 ? -stride : stride;

  PROPVARIANT duration;
  PropVariantInit(&duration);
  g_dec.duration_100ns = 0;
  if (SUCCEEDED(IMFSourceReader_GetPresentationAttribute(
          g_dec.reader, (DWORD)MF_SOURCE_READER_MEDIASOURCE, &MF_PD_DURATION,
          &duration))) {
    if (duration.vt == VT_UI8) {
      g_dec.duration_100ns = (int64_t)duration.uhVal.QuadPart;
    }
  }
  PropVariantClear(&duration);

  // 10,000,000 hundred-nanosecond ticks in a second.
  g_dec.frame_count =
      g_dec.duration_100ns <= 0
          ? 0
          : (g_dec.duration_100ns * (int64_t)fps_num) /
                ((int64_t)fps_den * 10000000LL);
  if (g_dec.frame_count < 1) {
    g_dec.frame_count = 1;
  }
  g_dec.open = 1;
  return 1;
}

QA_EXPORT int32_t qa_video_decode_info(int32_t* width,
                                       int32_t* height,
                                       int64_t* frame_count,
                                       int32_t* fps_num,
                                       int32_t* fps_den) {
  if (!g_dec.open) {
    qa_decode_set_error("no document is open");
    return 0;
  }
  if (width != NULL) *width = g_dec.width;
  if (height != NULL) *height = g_dec.height;
  if (frame_count != NULL) *frame_count = g_dec.frame_count;
  if (fps_num != NULL) *fps_num = g_dec.fps_num;
  if (fps_den != NULL) *fps_den = g_dec.fps_den;
  return 1;
}

static void qa_video_copy_rgba(const uint8_t* source, uint8_t* out) {
  const int32_t width = g_dec.width;
  const int32_t height = g_dec.height;
  const int32_t pitch = g_dec.stride;
  for (int32_t y = 0; y < height; y += 1) {
    // A bottom-up buffer stores the LAST row first; reading it forwards is
    // how a decoded frame comes out upside down.
    const uint8_t* row =
        source + (int64_t)(g_dec.bottom_up ? (height - 1 - y) : y) * pitch;
    uint8_t* dst = out + (int64_t)y * width * 4;
    for (int32_t x = 0; x < width; x += 1) {
      // MFVideoFormat_RGB32 is BGRA in memory.
      dst[x * 4 + 0] = row[x * 4 + 2];
      dst[x * 4 + 1] = row[x * 4 + 1];
      dst[x * 4 + 2] = row[x * 4 + 0];
      dst[x * 4 + 3] = 255;
    }
  }
}

QA_EXPORT int32_t qa_video_decode_frame(int64_t index,
                                        uint8_t* rgba,
                                        int32_t capacity) {
  if (!g_dec.open) {
    qa_decode_set_error("no document is open");
    return 0;
  }
  if (rgba == NULL || capacity < g_dec.width * g_dec.height * 4) {
    qa_decode_set_error("frame buffer too small");
    return 0;
  }
  if (index < 0) {
    index = 0;
  }

  const int64_t frame_100ns =
      (10000000LL * (int64_t)g_dec.fps_den) / (int64_t)g_dec.fps_num;
  const int64_t target = index * frame_100ns;

  PROPVARIANT position;
  PropVariantInit(&position);
  position.vt = VT_I8;
  position.hVal.QuadPart = target;
  // A seek lands on the nearest KEYFRAME at or before the target, so the
  // reader then decodes forward to the frame that was asked for. That is
  // the whole reason this loop exists rather than one ReadSample.
  IMFSourceReader_SetCurrentPosition(g_dec.reader, &GUID_NULL, &position);
  PropVariantClear(&position);

  int32_t wrote = 0;
  for (int guard = 0; guard < 600; guard += 1) {
    DWORD flags = 0;
    LONGLONG timestamp = 0;
    IMFSample* sample = NULL;
    HRESULT hr = IMFSourceReader_ReadSample(
        g_dec.reader, (DWORD)MF_SOURCE_READER_FIRST_VIDEO_STREAM, 0, NULL,
        &flags, &timestamp, &sample);
    if (FAILED(hr)) {
      qa_decode_set_error("the reader failed mid-stream");
      break;
    }
    if (flags & MF_SOURCE_READERF_ENDOFSTREAM) {
      if (sample != NULL) {
        IMFSample_Release(sample);
      }
      qa_decode_set_error("past the end of the stream");
      break;
    }
    if (sample == NULL) {
      continue; // A gap or a format change: keep reading.
    }
    // Half a frame of slack: a timestamp lands ON the frame it belongs to,
    // and asking for exact equality misses on every source whose rate is
    // not an integer.
    if (timestamp + frame_100ns / 2 < target) {
      IMFSample_Release(sample);
      continue;
    }

    IMFMediaBuffer* buffer = NULL;
    if (SUCCEEDED(IMFSample_ConvertToContiguousBuffer(sample, &buffer))) {
      BYTE* data = NULL;
      DWORD length = 0;
      if (SUCCEEDED(IMFMediaBuffer_Lock(buffer, &data, NULL, &length))) {
        if ((int64_t)length >=
            (int64_t)g_dec.stride * (int64_t)g_dec.height) {
          qa_video_copy_rgba(data, rgba);
          wrote = 1;
        } else {
          qa_decode_set_error("the decoded frame was short");
        }
        IMFMediaBuffer_Unlock(buffer);
      }
      IMFMediaBuffer_Release(buffer);
    }
    IMFSample_Release(sample);
    break;
  }
  return wrote;
}

#elif defined(__APPLE__)
// ---------------------------------------------------------------------------
// Apple: AVAssetImageGenerator, implemented in qa_video_apple.m
// (Objective-C — the API is). This file only forwards, keeping the decode
// surface in one portable TU, exactly as the export half does.

extern int32_t qa_video_apple_decode_open(const char* utf8_path,
                                          char* error,
                                          int32_t error_capacity);
extern int32_t qa_video_apple_decode_info(int32_t* width,
                                          int32_t* height,
                                          int64_t* frame_count,
                                          int32_t* fps_num,
                                          int32_t* fps_den);
extern int32_t qa_video_apple_decode_frame(int64_t index,
                                           uint8_t* rgba,
                                           int32_t capacity,
                                           char* error,
                                           int32_t error_capacity);
extern void qa_video_apple_decode_close(void);

QA_EXPORT int32_t qa_video_decode_supported(void) { return 1; }

QA_EXPORT int32_t qa_video_decode_open(const char* path) {
  return qa_video_apple_decode_open(path, g_decode_error,
                                    (int32_t)sizeof(g_decode_error));
}

QA_EXPORT int32_t qa_video_decode_info(int32_t* width,
                                       int32_t* height,
                                       int64_t* frame_count,
                                       int32_t* fps_num,
                                       int32_t* fps_den) {
  return qa_video_apple_decode_info(width, height, frame_count, fps_num,
                                    fps_den);
}

QA_EXPORT int32_t qa_video_decode_frame(int64_t index,
                                        uint8_t* rgba,
                                        int32_t capacity) {
  return qa_video_apple_decode_frame(index, rgba, capacity, g_decode_error,
                                     (int32_t)sizeof(g_decode_error));
}

QA_EXPORT void qa_video_decode_close(void) { qa_video_apple_decode_close(); }

#elif defined(__ANDROID__)
// ---------------------------------------------------------------------------
// Android: NDK AMediaExtractor + AMediaCodec, resolved with dlsym exactly
// like the encoder half — libmediandk.so ships on every API 21+ device,
// and a missing symbol is a capability answer rather than a crash.
//
// The colour conversion is ours here, which is the whole difficulty. A
// decoder hands back YUV in whichever layout the vendor's hardware likes,
// described by three numbers that are easy to assume and wrong to:
// STRIDE (bytes per luma row, ≥ width), SLICE HEIGHT (rows between the Y
// plane and the chroma that follows, ≥ height) and the colour format. The
// two that matter in practice are planar I420 and semi-planar NV12; both
// are handled, and anything else is refused by name instead of drawn as
// noise.

#include <dlfcn.h>
#include <stdbool.h>  // the release/advance signatures

// No NDK media headers, exactly like the encoder half: dlsym means no
// link dependency, and forward declarations mean no dependency on which
// NDK version the build has. The format keys are the same strings the
// headers define.
typedef struct AMediaExtractor AMediaExtractor;
typedef struct AMediaCodec AMediaCodec;
typedef struct AMediaFormat AMediaFormat;

typedef struct {
  int32_t offset;
  int32_t size;
  int64_t presentationTimeUs;
  uint32_t flags;
} qa_decode_buffer_info;

#define QA_AMEDIA_OK 0
#define QA_SEEK_PREVIOUS_SYNC 0
#define QA_BUFFER_FLAG_END_OF_STREAM 4
#define QA_KEY_MIME "mime"
#define QA_KEY_WIDTH "width"
#define QA_KEY_HEIGHT "height"
#define QA_KEY_FRAME_RATE "frame-rate"
#define QA_KEY_DURATION "durationUs"
#define QA_KEY_COLOR_FORMAT "color-format"
#define QA_KEY_STRIDE "stride"
#define QA_KEY_SLICE_HEIGHT "slice-height"

#define QA_COLOR_FORMAT_YUV420_PLANAR 19
#define QA_COLOR_FORMAT_YUV420_SEMIPLANAR 21
#define QA_COLOR_FORMAT_YUV420_FLEXIBLE 0x7F420888

typedef struct {
  void* handle;
  AMediaExtractor* (*extractor_new)(void);
  int32_t (*extractor_delete)(AMediaExtractor*);
  int32_t (*extractor_set_source)(AMediaExtractor*, const char*);
  size_t (*extractor_track_count)(AMediaExtractor*);
  AMediaFormat* (*extractor_track_format)(AMediaExtractor*, size_t);
  int32_t (*extractor_select_track)(AMediaExtractor*, size_t);
  int32_t (*extractor_seek_to)(AMediaExtractor*, int64_t,
                                      int32_t);
  ssize_t (*extractor_read_sample)(AMediaExtractor*, uint8_t*, size_t);
  int64_t (*extractor_sample_time)(AMediaExtractor*);
  bool (*extractor_advance)(AMediaExtractor*);
  AMediaCodec* (*codec_create_decoder)(const char*);
  int32_t (*codec_delete)(AMediaCodec*);
  int32_t (*codec_configure)(AMediaCodec*, const AMediaFormat*,
                                    void*, void*, uint32_t);
  int32_t (*codec_start)(AMediaCodec*);
  int32_t (*codec_stop)(AMediaCodec*);
  int32_t (*codec_flush)(AMediaCodec*);
  ssize_t (*codec_dequeue_input)(AMediaCodec*, int64_t);
  uint8_t* (*codec_input_buffer)(AMediaCodec*, size_t, size_t*);
  int32_t (*codec_queue_input)(AMediaCodec*, size_t, int64_t, size_t,
                                      uint64_t, uint32_t);
  ssize_t (*codec_dequeue_output)(AMediaCodec*, qa_decode_buffer_info*,
                                  int64_t);
  uint8_t* (*codec_output_buffer)(AMediaCodec*, size_t, size_t*);
  int32_t (*codec_release_output)(AMediaCodec*, size_t, bool);
  AMediaFormat* (*codec_output_format)(AMediaCodec*);
  bool (*format_get_int32)(AMediaFormat*, const char*, int32_t*);
  bool (*format_get_int64)(AMediaFormat*, const char*, int64_t*);
  bool (*format_get_string)(AMediaFormat*, const char*, const char**);
  int32_t (*format_delete)(AMediaFormat*);
} qa_ndk_decode_api;

static qa_ndk_decode_api g_ndk_dec;

static int qa_ndk_decode_load(void) {
  if (g_ndk_dec.handle != NULL) {
    return 1;
  }
  void* handle = dlopen("libmediandk.so", RTLD_NOW);
  if (handle == NULL) {
    return 0;
  }
#define QA_SYM(field, name)                          \
  *(void**)(&g_ndk_dec.field) = dlsym(handle, name); \
  if (g_ndk_dec.field == NULL) {                     \
    dlclose(handle);                                 \
    memset(&g_ndk_dec, 0, sizeof(g_ndk_dec));        \
    return 0;                                        \
  }
  QA_SYM(extractor_new, "AMediaExtractor_new")
  QA_SYM(extractor_delete, "AMediaExtractor_delete")
  QA_SYM(extractor_set_source, "AMediaExtractor_setDataSource")
  QA_SYM(extractor_track_count, "AMediaExtractor_getTrackCount")
  QA_SYM(extractor_track_format, "AMediaExtractor_getTrackFormat")
  QA_SYM(extractor_select_track, "AMediaExtractor_selectTrack")
  QA_SYM(extractor_seek_to, "AMediaExtractor_seekTo")
  QA_SYM(extractor_read_sample, "AMediaExtractor_readSampleData")
  QA_SYM(extractor_sample_time, "AMediaExtractor_getSampleTime")
  QA_SYM(extractor_advance, "AMediaExtractor_advance")
  QA_SYM(codec_create_decoder, "AMediaCodec_createDecoderByType")
  QA_SYM(codec_delete, "AMediaCodec_delete")
  QA_SYM(codec_configure, "AMediaCodec_configure")
  QA_SYM(codec_start, "AMediaCodec_start")
  QA_SYM(codec_stop, "AMediaCodec_stop")
  QA_SYM(codec_flush, "AMediaCodec_flush")
  QA_SYM(codec_dequeue_input, "AMediaCodec_dequeueInputBuffer")
  QA_SYM(codec_input_buffer, "AMediaCodec_getInputBuffer")
  QA_SYM(codec_queue_input, "AMediaCodec_queueInputBuffer")
  QA_SYM(codec_dequeue_output, "AMediaCodec_dequeueOutputBuffer")
  QA_SYM(codec_output_buffer, "AMediaCodec_getOutputBuffer")
  QA_SYM(codec_release_output, "AMediaCodec_releaseOutputBuffer")
  QA_SYM(codec_output_format, "AMediaCodec_getOutputFormat")
  QA_SYM(format_get_int32, "AMediaFormat_getInt32")
  QA_SYM(format_get_int64, "AMediaFormat_getInt64")
  QA_SYM(format_get_string, "AMediaFormat_getString")
  QA_SYM(format_delete, "AMediaFormat_delete")
#undef QA_SYM
  g_ndk_dec.handle = handle;
  return 1;
}

typedef struct {
  AMediaExtractor* extractor;
  AMediaCodec* codec;
  int32_t track;
  int32_t width;
  int32_t height;
  int32_t fps_num;
  int32_t fps_den;
  int64_t frame_count;
  int32_t open;
} qa_video_droid_decode;

static qa_video_droid_decode g_droid_dec;

QA_EXPORT void qa_video_decode_close(void) {
  if (g_droid_dec.codec != NULL) {
    g_ndk_dec.codec_stop(g_droid_dec.codec);
    g_ndk_dec.codec_delete(g_droid_dec.codec);
    g_droid_dec.codec = NULL;
  }
  if (g_droid_dec.extractor != NULL) {
    g_ndk_dec.extractor_delete(g_droid_dec.extractor);
    g_droid_dec.extractor = NULL;
  }
  g_droid_dec.open = 0;
}

QA_EXPORT int32_t qa_video_decode_supported(void) {
  return qa_ndk_decode_load();
}

QA_EXPORT int32_t qa_video_decode_open(const char* path) {
  qa_video_decode_close();
  qa_decode_set_error(NULL);
  if (!qa_ndk_decode_load()) {
    qa_decode_set_error("no video decoder in this build");
    return 0;
  }
  if (path == NULL || path[0] == '\0') {
    qa_decode_set_error("no path");
    return 0;
  }
  AMediaExtractor* extractor = g_ndk_dec.extractor_new();
  if (extractor == NULL) {
    qa_decode_set_error("could not open the container");
    return 0;
  }
  if (g_ndk_dec.extractor_set_source(extractor, path) != QA_AMEDIA_OK) {
    g_ndk_dec.extractor_delete(extractor);
    qa_decode_set_error("could not open the container");
    return 0;
  }

  const size_t tracks = g_ndk_dec.extractor_track_count(extractor);
  int32_t video_track = -1;
  AMediaFormat* format = NULL;
  const char* mime = NULL;
  for (size_t i = 0; i < tracks; i += 1) {
    AMediaFormat* candidate = g_ndk_dec.extractor_track_format(extractor, i);
    const char* candidate_mime = NULL;
    if (candidate != NULL &&
        g_ndk_dec.format_get_string(candidate, QA_KEY_MIME,
                                    &candidate_mime) &&
        candidate_mime != NULL && strncmp(candidate_mime, "video/", 6) == 0) {
      video_track = (int32_t)i;
      format = candidate;
      mime = candidate_mime;
      break;
    }
    if (candidate != NULL) {
      g_ndk_dec.format_delete(candidate);
    }
  }
  if (video_track < 0 || format == NULL || mime == NULL) {
    g_ndk_dec.extractor_delete(extractor);
    qa_decode_set_error("this file has no readable video stream");
    return 0;
  }

  int32_t width = 0;
  int32_t height = 0;
  int32_t rate = 0;
  int64_t duration_us = 0;
  g_ndk_dec.format_get_int32(format, QA_KEY_WIDTH, &width);
  g_ndk_dec.format_get_int32(format, QA_KEY_HEIGHT, &height);
  g_ndk_dec.format_get_int32(format, QA_KEY_FRAME_RATE, &rate);
  g_ndk_dec.format_get_int64(format, QA_KEY_DURATION, &duration_us);

  AMediaCodec* codec = g_ndk_dec.codec_create_decoder(mime);
  if (codec == NULL ||
      g_ndk_dec.codec_configure(codec, format, NULL, NULL, 0) != QA_AMEDIA_OK ||
      g_ndk_dec.codec_start(codec) != QA_AMEDIA_OK) {
    if (codec != NULL) {
      g_ndk_dec.codec_delete(codec);
    }
    g_ndk_dec.format_delete(format);
    g_ndk_dec.extractor_delete(extractor);
    qa_decode_set_error("no decoder for this codec");
    return 0;
  }
  g_ndk_dec.format_delete(format);
  g_ndk_dec.extractor_select_track(extractor, (size_t)video_track);

  if (width <= 0 || height <= 0) {
    g_ndk_dec.codec_delete(codec);
    g_ndk_dec.extractor_delete(extractor);
    qa_decode_set_error("the video stream has no frame size");
    return 0;
  }
  if (rate <= 0) {
    rate = 24;
  }
  g_droid_dec.extractor = extractor;
  g_droid_dec.codec = codec;
  g_droid_dec.track = video_track;
  g_droid_dec.width = width;
  g_droid_dec.height = height;
  g_droid_dec.fps_num = rate;
  g_droid_dec.fps_den = 1;
  g_droid_dec.frame_count =
      duration_us <= 0 ? 1 : (duration_us * (int64_t)rate) / 1000000LL;
  if (g_droid_dec.frame_count < 1) {
    g_droid_dec.frame_count = 1;
  }
  g_droid_dec.open = 1;
  return 1;
}

QA_EXPORT int32_t qa_video_decode_info(int32_t* width,
                                       int32_t* height,
                                       int64_t* frame_count,
                                       int32_t* fps_num,
                                       int32_t* fps_den) {
  if (!g_droid_dec.open) {
    qa_decode_set_error("no document is open");
    return 0;
  }
  if (width != NULL) *width = g_droid_dec.width;
  if (height != NULL) *height = g_droid_dec.height;
  if (frame_count != NULL) *frame_count = g_droid_dec.frame_count;
  if (fps_num != NULL) *fps_num = g_droid_dec.fps_num;
  if (fps_den != NULL) *fps_den = g_droid_dec.fps_den;
  return 1;
}

/// YUV420 → RGBA. [stride] is bytes per luma row and [slice] the rows
/// between the Y plane and the chroma after it; assuming either equals the
/// picture size is the classic way to get a green-striped frame on one
/// vendor's hardware and a correct one on another's.
static void qa_droid_yuv_to_rgba(const uint8_t* data,
                                 int32_t stride,
                                 int32_t slice,
                                 int semi_planar,
                                 uint8_t* rgba) {
  const int32_t width = g_droid_dec.width;
  const int32_t height = g_droid_dec.height;
  const uint8_t* y_plane = data;
  const uint8_t* u_plane = data + (int64_t)stride * slice;
  const uint8_t* v_plane =
      semi_planar ? u_plane + 1
                  : u_plane + ((int64_t)stride / 2) * (slice / 2);
  const int32_t chroma_stride = semi_planar ? stride : stride / 2;
  const int32_t chroma_step = semi_planar ? 2 : 1;

  for (int32_t y = 0; y < height; y += 1) {
    const uint8_t* y_row = y_plane + (int64_t)y * stride;
    const int32_t cy = y / 2;
    for (int32_t x = 0; x < width; x += 1) {
      const int32_t cx = x / 2;
      const int32_t luma = (int32_t)y_row[x] - 16;
      const int32_t cb =
          (int32_t)u_plane[(int64_t)cy * chroma_stride + cx * chroma_step] -
          128;
      const int32_t cr =
          (int32_t)v_plane[(int64_t)cy * chroma_stride + cx * chroma_step] -
          128;
      // BT.601 limited range, the same matrix the encoder half writes.
      int32_t r = (298 * luma + 409 * cr + 128) >> 8;
      int32_t g = (298 * luma - 100 * cb - 208 * cr + 128) >> 8;
      int32_t b = (298 * luma + 516 * cb + 128) >> 8;
      r = r < 0 ? 0 : (r > 255 ? 255 : r);
      g = g < 0 ? 0 : (g > 255 ? 255 : g);
      b = b < 0 ? 0 : (b > 255 ? 255 : b);
      uint8_t* out = rgba + ((int64_t)y * width + x) * 4;
      out[0] = (uint8_t)r;
      out[1] = (uint8_t)g;
      out[2] = (uint8_t)b;
      out[3] = 255;
    }
  }
}

QA_EXPORT int32_t qa_video_decode_frame(int64_t index,
                                        uint8_t* rgba,
                                        int32_t capacity) {
  if (!g_droid_dec.open) {
    qa_decode_set_error("no document is open");
    return 0;
  }
  if (rgba == NULL ||
      capacity < g_droid_dec.width * g_droid_dec.height * 4) {
    qa_decode_set_error("frame buffer too small");
    return 0;
  }
  if (index < 0) {
    index = 0;
  }
  const int64_t target_us =
      (index * 1000000LL * (int64_t)g_droid_dec.fps_den) /
      (int64_t)g_droid_dec.fps_num;
  const int64_t frame_us =
      (1000000LL * (int64_t)g_droid_dec.fps_den) /
      (int64_t)g_droid_dec.fps_num;

  // The extractor seeks to a SYNC frame at or before the target; the codec
  // then decodes forward. Flushing first is what stops the frames from
  // before the seek coming out of the other end.
  g_ndk_dec.extractor_seek_to(g_droid_dec.extractor, target_us,
                              QA_SEEK_PREVIOUS_SYNC);
  g_ndk_dec.codec_flush(g_droid_dec.codec);

  int32_t wrote = 0;
  int input_done = 0;
  for (int guard = 0; guard < 900 && !wrote; guard += 1) {
    if (!input_done) {
      const ssize_t in_index =
          g_ndk_dec.codec_dequeue_input(g_droid_dec.codec, 2000);
      if (in_index >= 0) {
        size_t in_size = 0;
        uint8_t* in_buffer = g_ndk_dec.codec_input_buffer(
            g_droid_dec.codec, (size_t)in_index, &in_size);
        const ssize_t read = g_ndk_dec.extractor_read_sample(
            g_droid_dec.extractor, in_buffer, in_size);
        if (read <= 0) {
          g_ndk_dec.codec_queue_input(g_droid_dec.codec, (size_t)in_index, 0,
                                      0, 0, QA_BUFFER_FLAG_END_OF_STREAM);
          input_done = 1;
        } else {
          const int64_t sample_time =
              g_ndk_dec.extractor_sample_time(g_droid_dec.extractor);
          g_ndk_dec.codec_queue_input(g_droid_dec.codec, (size_t)in_index, 0,
                                      (size_t)read, (uint64_t)sample_time, 0);
          g_ndk_dec.extractor_advance(g_droid_dec.extractor);
        }
      }
    }

    qa_decode_buffer_info info;
    const ssize_t out_index =
        g_ndk_dec.codec_dequeue_output(g_droid_dec.codec, &info, 2000);
    if (out_index < 0) {
      continue; // Try again, or a format change we read below.
    }
    // Half a frame of slack, for the same reason the Windows path has it.
    if (info.presentationTimeUs + frame_us / 2 < target_us) {
      g_ndk_dec.codec_release_output(g_droid_dec.codec, (size_t)out_index,
                                     false);
      continue;
    }
    size_t out_size = 0;
    uint8_t* out_buffer = g_ndk_dec.codec_output_buffer(
        g_droid_dec.codec, (size_t)out_index, &out_size);
    AMediaFormat* out_format =
        g_ndk_dec.codec_output_format(g_droid_dec.codec);
    int32_t colour = QA_COLOR_FORMAT_YUV420_FLEXIBLE;
    int32_t stride = g_droid_dec.width;
    int32_t slice = g_droid_dec.height;
    if (out_format != NULL) {
      g_ndk_dec.format_get_int32(out_format, QA_KEY_COLOR_FORMAT,
                                 &colour);
      g_ndk_dec.format_get_int32(out_format, QA_KEY_STRIDE,
                                 &stride);
      g_ndk_dec.format_get_int32(out_format, QA_KEY_SLICE_HEIGHT,
                                 &slice);
      g_ndk_dec.format_delete(out_format);
    }
    if (stride < g_droid_dec.width) {
      stride = g_droid_dec.width;
    }
    if (slice < g_droid_dec.height) {
      slice = g_droid_dec.height;
    }
    if (out_buffer != NULL &&
        (colour == QA_COLOR_FORMAT_YUV420_PLANAR ||
         colour == QA_COLOR_FORMAT_YUV420_SEMIPLANAR ||
         colour == QA_COLOR_FORMAT_YUV420_FLEXIBLE)) {
      qa_droid_yuv_to_rgba(
          out_buffer, stride, slice,
          colour == QA_COLOR_FORMAT_YUV420_SEMIPLANAR ? 1 : 0, rgba);
      wrote = 1;
    } else {
      qa_decode_set_error("this device's decoder uses a colour format we "
                          "do not read");
    }
    g_ndk_dec.codec_release_output(g_droid_dec.codec, (size_t)out_index,
                                   false);
    break;
  }
  if (!wrote && g_decode_error[0] == '\0') {
    qa_decode_set_error("that frame could not be read");
  }
  return wrote;
}

#else

// Linux and anything else: no OS reader this app can lean on. The answer
// is 0, and the window says "no decoder in this build" rather than failing
// as a corrupt file.

QA_EXPORT int32_t qa_video_decode_supported(void) { return 0; }

QA_EXPORT int32_t qa_video_decode_open(const char* path) {
  (void)path;
  qa_decode_set_error("no video decoder in this build");
  return 0;
}

QA_EXPORT int32_t qa_video_decode_info(int32_t* width,
                                       int32_t* height,
                                       int64_t* frame_count,
                                       int32_t* fps_num,
                                       int32_t* fps_den) {
  (void)width;
  (void)height;
  (void)frame_count;
  (void)fps_num;
  (void)fps_den;
  qa_decode_set_error("no video decoder in this build");
  return 0;
}

QA_EXPORT int32_t qa_video_decode_frame(int64_t index,
                                        uint8_t* rgba,
                                        int32_t capacity) {
  (void)index;
  (void)rgba;
  (void)capacity;
  qa_decode_set_error("no video decoder in this build");
  return 0;
}

QA_EXPORT void qa_video_decode_close(void) {}

#endif
