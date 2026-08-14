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

#else

// Every other platform, for now. The Apple and Android readers belong with
// the devices that can verify them, and a decoder nobody has run is worse
// than one that says it is not here.

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
