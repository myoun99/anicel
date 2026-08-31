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
//   Apple    — AVAssetReader, forwarded to qa_video_apple.m. It said
//              「AVAssetImageGenerator」 until 2026-09-01; the premise that
//              chose the generator — 「the only question this app asks is
//              the picture at frame N」 — stopped being true when the
//              viewer grew a play button.
//   Android  — NDK AMediaExtractor + AMediaCodec, resolved with dlsym, so
//              support is what libmediandk.so actually answers.
//
// 2026-08-25: the two lines above used to read "not yet" and "likewise".
// Both readers had been written; the stale note taught the next reader a
// limit that was not there. Decision comments are never deleted in this
// repo, and the other half of that rule is that a wrong one gets FIXED.
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

// ---------------------------------------------------------------------------
// 🚨★★★**THE LAW IS WRITTEN ONCE; THE PLATFORMS ONLY SAY HOW.**
//
// This file used to hold three whole decoders, and the same rules were
// spelled out in each of them. Measured 2026-08-31, before this split:
//
//   written THREE times  index<0 clamp · the capacity check · 「a document
//                        has at least one frame」 · 「no declared rate means
//                        24」 · frame_count = duration x rate · the info()
//                        getters
//   written TWICE        the 「already positioned, do not seek」 state
//                        machine (Windows and Android; APPLE HAD NONE, so a
//                        first play there paid a random access per frame)
//   written ONCE         the display rotation (Apple only, so upright phone
//                        video lay on its side everywhere else) and the rate
//                        as a FRACTION (Android read `frame-rate` as an
//                        int32 and pinned the denominator to 1, so 29.97
//                        became 30 and every target drifted)
//
// The last group is the point: a rule that exists in one backend is not a
// rule, it is an accident of who wrote that backend. Below, each platform
// implements four hooks and answers nothing else — and 「what is left」 is
// the honest platform surface: opening a container, repositioning, pulling
// one decoded picture, and converting its pixels.
//
// ⚠️None of this is reachable by any test today (2026-08-31: the CI job
// that touches this file COMPILES it and runs nothing, and the arithmetic
// above lived inside `#if` blocks Linux never even compiled). Pulling it out
// here is what makes a test possible at all.

/// What every backend fills in and the portable law reads back.
typedef struct {
  /// The size a CALLER sees — the picture the right way up. For a quarter
  /// turn this is the stored size with the sides swapped.
  int32_t width;
  int32_t height;
  /// The size the backend decodes into, before the display transform.
  int32_t stored_width;
  int32_t stored_height;
  /// The clockwise turn the container asks for: 0, 90, 180 or 270.
  ///
  /// 🚨★★★**A PHONE HOLDS ITS SENSOR SIDEWAYS AND WRITES THE TURN DOWN.**
  /// Video shot upright is stored 1920x1080 with a 90° rotation, and a
  /// decoder that ignores that hands back a picture lying on its side.
  /// Apple's image generator applied this for us and NOBODY ELSE DID —
  /// `qa_video_decode.c` did not contain the word 「rotation」 until now, so
  /// the same file played upright on an iPad and sideways on Windows and
  /// Android. That was not a decision anyone made; it was one backend's
  /// author knowing something the other two's did not.
  int32_t rotation;
  int32_t fps_num;
  int32_t fps_den;
  int64_t frame_count;
  /// The frame index the backend is positioned to deliver next, or -1 when
  /// that is not known. Sequential playback asks for exactly this one, and
  /// then no reposition is needed — see [qa_video_decode_frame].
  int64_t next_index;
  int32_t open;
} qa_decode_doc;

static qa_decode_doc g_doc;

/// Where a rotated frame is decoded before it is turned upright. Grown on
/// demand and kept across frames — a movie's size does not change, so this
/// allocates once per document at most. ⛔Freed on close, not per frame.
static uint8_t* g_rotate_scratch;
static int64_t g_rotate_scratch_bytes;

/// Whether this build has a reader at all. Android answers by `dlsym`, so
/// this is a hook rather than a constant.
static int32_t qa_backend_supported(void);

/// Opens [path] and fills the size/rate/length fields of [g_doc]. Reports
/// its own reason through [qa_decode_set_error] on failure.
///
/// ⚠️[offset]/[length] name a RANGE inside [path] rather than the whole
/// file — see [qa_video_decode_open_range]. A whole-file open passes
/// `0, 0`, and a backend that has a plain path form should use it: the OS
/// opening a file for itself beats anything wrapped around it.
static int32_t qa_backend_open(const char* path,
                               int64_t offset,
                               int64_t length);

/// Releases whatever [qa_backend_open] took. Called before every open and
/// on close; must tolerate never having opened anything.
static void qa_backend_close(void);

/// Positions the reader so the next [qa_backend_read] can reach [index].
/// ⛔NOT 「decode index」 — a seek lands on the sync frame at or before the
/// target on every one of these APIs, and the read below walks forward.
static int32_t qa_backend_reposition(int64_t index);

/// Decodes forward until the picture for [index] is in hand and writes it
/// to [rgba] as straight RGBA at the document's size.
static int32_t qa_backend_read(int64_t index, uint8_t* rgba);

/// The half of opening that is the same for a whole file and for a range.
static int32_t qa_decode_finish_open(const char* path,
                                     int64_t offset,
                                     int64_t length);

/// A rate as an exact fraction. 🚨**30000/1001 IS NOT 29.97**, and rounding
/// it is how a frame index drifts a second out over a long take — Apple
/// carried this and Android did not, which is the whole reason it is here
/// instead of in a backend.
static void qa_rate_to_fraction(double rate, int32_t* num, int32_t* den) {
  if (!(rate > 0.0) || rate != rate || rate > 1000.0) {
    // No usable rate. 24 is the honest guess for the material this app takes
    // in, and the caller can say so.
    *num = 24;
    *den = 1;
    return;
  }
  const double rounded = (double)(int32_t)(rate + 0.5);
  if (rate - rounded < 0.001 && rounded - rate < 0.001) {
    *num = (int32_t)rounded;
    *den = 1;
    return;
  }
  // The NTSC family: every non-integer rate this app meets is n/1.001.
  *num = (int32_t)(rate * 1001.0 + 0.5);
  *den = 1001;
}

/// How many frames a picture of [duration_ticks] holds at this rate — at
/// least one, because a document that opened has a picture in it.
///
/// 🚨**TICKS AND THEIR RATE, NOT SECONDS.** The first draft of this helper
/// took a `double` of seconds, and the law test caught what that costs
/// immediately: 1.001 seconds at 30000/1001 is EXACTLY thirty frames, and
/// in floating point it is 29.999999… which truncates to 29. A movie whose
/// duration is a whole number of frames would have reported one short —
/// the same class of miscount as 유저 2026-08-31's 「72프레임짜리 비디오인데
/// 73프레임째의 빈 화면」, only in the other direction. Media Foundation's
/// path had always done this in integers; passing through seconds would
/// have been a REGRESSION dressed as unification.
static int64_t qa_frame_count_for(int64_t duration_ticks,
                                  int64_t ticks_per_second,
                                  int32_t fps_num,
                                  int32_t fps_den) {
  if (duration_ticks <= 0 || ticks_per_second <= 0 || fps_den <= 0 ||
      fps_num <= 0) {
    return 1;
  }
  const int64_t count = (duration_ticks * (int64_t)fps_num) /
                        (ticks_per_second * (int64_t)fps_den);
  return count < 1 ? 1 : count;
}

/// Whether a sample at [stamp] has reached [target], with **half a frame of
/// slack**: a timestamp lands ON the frame it belongs to, and asking for
/// exact equality misses on every source whose rate is not an integer.
///
/// ⚠️Ticks, not seconds — each backend passes its own unit (Media Foundation
/// counts 100ns, MediaCodec counts µs) and the rule is the same either way.
static int32_t qa_sample_reaches(int64_t stamp,
                                 int64_t target,
                                 int64_t frame_ticks) {
  return stamp + frame_ticks / 2 >= target;
}

/// A rotation in degrees, folded into the four the containers can mean.
/// Negatives are how Android spells a counter-clockwise turn.
static int32_t qa_rotation_quarter(int32_t degrees) {
  int32_t turns = (degrees / 90) % 4;
  if (turns < 0) {
    turns += 4;
  }
  return turns * 90;
}

/// Copies [stored] (stored_w x stored_h, RGBA) into [out] turned clockwise
/// by [rotation], which must be one of 0/90/180/270.
///
/// ⚠️[out] is the DISPLAY size: for a quarter turn its width is stored_h.
/// ⛔Never in place — the source and destination differ in shape for the
/// quarter turns, and for 180 a same-buffer walk would overwrite the rows
/// it still has to read.
static void qa_rotate_rgba(const uint8_t* stored,
                           int32_t stored_w,
                           int32_t stored_h,
                           int32_t rotation,
                           uint8_t* out) {
  for (int32_t y = 0; y < stored_h; y += 1) {
    for (int32_t x = 0; x < stored_w; x += 1) {
      int32_t dx;
      int32_t dy;
      int32_t dw;
      switch (rotation) {
        case 90:
          // The top-left of the stored picture becomes the top-RIGHT.
          dx = stored_h - 1 - y;
          dy = x;
          dw = stored_h;
          break;
        case 180:
          dx = stored_w - 1 - x;
          dy = stored_h - 1 - y;
          dw = stored_w;
          break;
        case 270:
          dx = y;
          dy = stored_w - 1 - x;
          dw = stored_h;
          break;
        default:
          dx = x;
          dy = y;
          dw = stored_w;
          break;
      }
      const uint8_t* src = stored + ((int64_t)y * stored_w + x) * 4;
      uint8_t* dst = out + ((int64_t)dy * dw + dx) * 4;
      dst[0] = src[0];
      dst[1] = src[1];
      dst[2] = src[2];
      dst[3] = src[3];
    }
  }
}

// 🚨**QA_DECODE_LAW_ONLY: the law without a platform under it.**
//
// `qa_video_decode_law_test.c` includes this translation unit to reach the
// rules above, which are `static` on purpose. Without this it drags in
// whichever backend the HOST has — and then the test needs that platform's
// libraries to link: Media Foundation on Windows, and on Apple a separate
// `.m` it cannot see at all (CI found that one, having compiled the Windows
// half green). ⛔The answer is not a longer link list per host. The law is
// the same everywhere, so the test that proves it must compile the same
// everywhere; below, the「no decoder in this build」backend is what it gets.
#if defined(_WIN32) && !defined(QA_DECODE_LAW_ONLY)

#define COBJMACROS
#include <windows.h>
#include <mfapi.h>
#include <mfidl.h>
#include <mfreadwrite.h>
#include <mferror.h>

/// ⚠️What is left here is the PLATFORM's own state — the reader itself and
/// how Media Foundation lays out its rows. Size, rate, length and 「where am
/// I positioned」 moved to [g_doc], where every backend answers the same way.
typedef struct {
  IMFSourceReader* reader;
  // Negative in the media type means the picture is stored bottom-up; the
  // magnitude is the row pitch either way.
  int32_t stride;
  int32_t bottom_up;
  int32_t mf_started;
} qa_video_decode_state;

static qa_video_decode_state g_dec;

static int32_t qa_backend_supported(void) { return 1; }

static void qa_backend_close(void) {
  if (g_dec.reader != NULL) {
    IMFSourceReader_Release(g_dec.reader);
    g_dec.reader = NULL;
  }
  if (g_dec.mf_started) {
    MFShutdown();
    g_dec.mf_started = 0;
  }
  memset(&g_dec, 0, sizeof(g_dec));
}

static int32_t qa_backend_open(const char* path,
                               int64_t offset,
                               int64_t length) {
  wchar_t wide[1024];
  // 🔜**A RANGE NEEDS AN `IMFByteStream`, AND THIS BACKEND HAS NONE YET.**
  //
  // Media Foundation opens a URL or a byte stream, and there is no built-in
  // stream over a SUB-RANGE of a file: `MFCreateFile` covers the whole
  // thing. What is missing is a small `IMFByteStream` that clamps to
  // [offset, offset+length) — a COM object written by hand in C, which is
  // its own piece of work rather than a line in this one.
  //
  // ⛔Refused by name rather than opened wrong: a whole-archive open would
  // hand the reader a ZIP and let it fail somewhere less legible.
  (void)offset;
  if (length > 0) {
    qa_decode_set_error(
        "this build cannot open a movie from inside another file");
    return 0;
  }
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
    qa_backend_close();
    return 0;
  }
  IMFAttributes_SetUINT32(
      attributes, &MF_SOURCE_READER_ENABLE_ADVANCED_VIDEO_PROCESSING, TRUE);

  HRESULT hr = MFCreateSourceReaderFromURL(wide, attributes, &g_dec.reader);
  IMFAttributes_Release(attributes);
  if (FAILED(hr) || g_dec.reader == NULL) {
    qa_decode_set_error("this file has no readable video stream");
    qa_backend_close();
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
    qa_backend_close();
    return 0;
  }
  IMFMediaType_SetGUID(wanted, &MF_MT_MAJOR_TYPE, &MFMediaType_Video);
  IMFMediaType_SetGUID(wanted, &MF_MT_SUBTYPE, &MFVideoFormat_RGB32);
  hr = IMFSourceReader_SetCurrentMediaType(
      g_dec.reader, (DWORD)MF_SOURCE_READER_FIRST_VIDEO_STREAM, NULL, wanted);
  IMFMediaType_Release(wanted);
  if (FAILED(hr)) {
    qa_decode_set_error("no RGB conversion for this codec");
    qa_backend_close();
    return 0;
  }

  IMFMediaType* current = NULL;
  if (FAILED(IMFSourceReader_GetCurrentMediaType(
          g_dec.reader, (DWORD)MF_SOURCE_READER_FIRST_VIDEO_STREAM,
          &current))) {
    qa_decode_set_error("the reader would not describe its output");
    qa_backend_close();
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
  // 🚨MF_MT_VIDEO_ROTATION is an MFVideoRotationFormat, whose values ARE the
  // clockwise angle in degrees. Absent means none, which is what a file
  // with no transform says — and what every file said to this reader until
  // now, because nothing here asked.
  UINT32 rotation = 0;
  if (FAILED(IMFMediaType_GetUINT32(current, &MF_MT_VIDEO_ROTATION,
                                    &rotation))) {
    rotation = 0;
  }
  IMFMediaType_Release(current);

  // ⛔The size and rate checks that stood here are gone, not relaxed: the
  // portable open makes both, for every backend, in one place.
  g_doc.stored_width = (int32_t)width;
  g_doc.stored_height = (int32_t)height;
  g_doc.rotation = (int32_t)rotation;
  // Media Foundation hands the rate over as a ratio already, so this is the
  // one backend that has nothing to reconstruct.
  g_doc.fps_num = (int32_t)fps_num;
  g_doc.fps_den = (int32_t)fps_den;
  g_dec.bottom_up = stride < 0 ? 1 : 0;
  g_dec.stride = stride < 0 ? -stride : stride;

  // The VIDEO STREAM's duration, and the presentation's only as a
  // fallback.
  //
  // 🚨★★★**THE PRESENTATION IS AS LONG AS ITS LONGEST TRACK, AND THAT IS
  // ALMOST NEVER THE VIDEO.** AAC frames are 1024 samples, so an MP4's
  // audio ends a few tens of milliseconds past the last picture — and the
  // count below turned that overshoot into a frame that has no picture in
  // it. 유저 2026-08-31: 「72프레임짜리 비디오인데 73프레임째의 빈 화면이
  // 생성되어있음」.
  //
  // ⚠️They also saw it differ by platform — 「아이패드에선 73번째 프레임이
  // 존재하는데 윈도우에선 흰화면」 — and that is the SAME bug wearing two
  // failure modes: Media Foundation has no sample past the video's end and
  // hands back nothing (white), while AVFoundation's image generator
  // clamps and hands back the last picture again. Asking the video track
  // is what makes the two agree, so it is done on both sides.
  PROPVARIANT duration;
  PropVariantInit(&duration);
  int64_t duration_100ns = 0;
  if (SUCCEEDED(IMFSourceReader_GetPresentationAttribute(
          g_dec.reader, (DWORD)MF_SOURCE_READER_FIRST_VIDEO_STREAM,
          &MF_PD_DURATION, &duration)) &&
      duration.vt == VT_UI8 && (int64_t)duration.uhVal.QuadPart > 0) {
    duration_100ns = (int64_t)duration.uhVal.QuadPart;
  }
  PropVariantClear(&duration);
  if (duration_100ns <= 0) {
    // ⛔Not every source answers per stream. Falling back to the
    // presentation keeps the old behaviour for those rather than counting
    // zero frames, which would be a worse bug than the one above.
    PropVariantInit(&duration);
    if (SUCCEEDED(IMFSourceReader_GetPresentationAttribute(
            g_dec.reader, (DWORD)MF_SOURCE_READER_MEDIASOURCE, &MF_PD_DURATION,
            &duration))) {
      if (duration.vt == VT_UI8) {
        duration_100ns = (int64_t)duration.uhVal.QuadPart;
      }
    }
    PropVariantClear(&duration);
  }

  // 10,000,000 hundred-nanosecond ticks in a second. ⛔The 「at least one
  // frame」 clamp is NOT repeated here — [qa_frame_count_for] carries it for
  // every backend, which is the only way three of them can agree.
  g_doc.frame_count = qa_frame_count_for(duration_100ns, 10000000LL,
                                         g_doc.fps_num, g_doc.fps_den);
  return 1;
}

static void qa_video_copy_rgba(const uint8_t* source, uint8_t* out) {
  const int32_t width = g_doc.stored_width;
  const int32_t height = g_doc.stored_height;
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

/// The presentation time of [index] in Media Foundation's 100ns ticks.
static int64_t qa_win_target(int64_t index) {
  return index * ((10000000LL * (int64_t)g_doc.fps_den) /
                  (int64_t)g_doc.fps_num);
}

static int32_t qa_backend_reposition(int64_t index) {
  PROPVARIANT position;
  PropVariantInit(&position);
  position.vt = VT_I8;
  position.hVal.QuadPart = qa_win_target(index);
  IMFSourceReader_SetCurrentPosition(g_dec.reader, &GUID_NULL, &position);
  PropVariantClear(&position);
  return 1;
}

static int32_t qa_backend_read(int64_t index, uint8_t* rgba) {
  const int64_t frame_100ns =
      (10000000LL * (int64_t)g_doc.fps_den) / (int64_t)g_doc.fps_num;
  const int64_t target = qa_win_target(index);

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
    if (!qa_sample_reaches((int64_t)timestamp, target, frame_100ns)) {
      IMFSample_Release(sample);
      continue;
    }

    IMFMediaBuffer* buffer = NULL;
    if (SUCCEEDED(IMFSample_ConvertToContiguousBuffer(sample, &buffer))) {
      BYTE* data = NULL;
      DWORD length = 0;
      if (SUCCEEDED(IMFMediaBuffer_Lock(buffer, &data, NULL, &length))) {
        if ((int64_t)length >=
            (int64_t)g_dec.stride * (int64_t)g_doc.stored_height) {
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

#elif defined(__APPLE__) && !defined(QA_DECODE_LAW_ONLY)
// ---------------------------------------------------------------------------
// Apple: AVAssetImageGenerator, implemented in qa_video_apple.m
// (Objective-C — the API is). This file only forwards, keeping the decode
// surface in one portable TU, exactly as the export half does.

extern int32_t qa_video_apple_decode_open(const char* utf8_path,
                                          char* error,
                                          int32_t error_capacity);
extern int32_t qa_video_apple_decode_info(int32_t* stored_width,
                                          int32_t* stored_height,
                                          int32_t* rotation,
                                          int64_t* duration_us,
                                          double* nominal_rate);
extern int32_t qa_video_apple_decode_reposition(int64_t index,
                                                int32_t fps_num,
                                                int32_t fps_den,
                                                char* error,
                                                int32_t error_capacity);
extern int32_t qa_video_apple_decode_read(
    int64_t index,
    int32_t fps_num,
    int32_t fps_den,
    uint8_t* rgba,
    int32_t capacity,
    int32_t (*reaches_target)(int64_t stamp_us,
                              int64_t target_us,
                              int64_t frame_us),
    char* error,
    int32_t error_capacity);
extern void qa_video_apple_decode_close(void);

static int32_t qa_backend_supported(void) { return 1; }

static void qa_backend_close(void) { qa_video_apple_decode_close(); }

static int32_t qa_backend_open(const char* path,
                               int64_t offset,
                               int64_t length) {
  // 🔜**A RANGE NEEDS AN `AVAssetResourceLoader`, AND THIS BACKEND HAS NONE
  // YET.** `AVURLAsset` takes a URL and nothing else: there is no offset to
  // give it. Apple's answer is a custom scheme plus a resource-loader
  // delegate that serves the bytes — its own piece of work, and one no
  // local compiler here can even check.
  //
  // ⛔Refused by name rather than opened wrong.
  (void)offset;
  if (length > 0) {
    qa_decode_set_error(
        "this build cannot open a movie from inside another file");
    return 0;
  }
  if (!qa_video_apple_decode_open(path, g_decode_error,
                                  (int32_t)sizeof(g_decode_error))) {
    return 0;
  }
  int64_t duration_us = 0;
  double nominal_rate = 0.0;
  if (!qa_video_apple_decode_info(&g_doc.stored_width, &g_doc.stored_height,
                                  &g_doc.rotation, &duration_us,
                                  &nominal_rate)) {
    return 0;
  }
  // ⚠️The rate and the count are worked out HERE, from what the backend
  // knows — this file used to carry its own copy of both, and the count's
  // copy took seconds as a double, which is how a whole number of frames
  // comes back one short.
  qa_rate_to_fraction(nominal_rate, &g_doc.fps_num, &g_doc.fps_den);
  g_doc.frame_count = qa_frame_count_for(duration_us, 1000000LL,
                                         g_doc.fps_num, g_doc.fps_den);
  return 1;
}

/// 🚨**REPOSITIONING IS BUILDING A NEW READER.** An `AVAssetReader` walks
/// forward over the range it was started with and cannot be rewound — so
/// this is a real cost, paid once per jump, and the law's 「already
/// positioned」 rule is what keeps a play from paying it per frame.
static int32_t qa_backend_reposition(int64_t index) {
  return qa_video_apple_decode_reposition(index, g_doc.fps_num, g_doc.fps_den,
                                          g_decode_error,
                                          (int32_t)sizeof(g_decode_error));
}

/// The slack rule goes DOWN to the backend rather than being spelled again
/// inside it — Objective-C cannot see a `static` in this file, and a second
/// copy of 「half a frame」 is exactly what this round exists to remove.
static int32_t qa_sample_reaches_hook(int64_t stamp,
                                      int64_t target,
                                      int64_t frame_ticks) {
  return qa_sample_reaches(stamp, target, frame_ticks);
}

static int32_t qa_backend_read(int64_t index, uint8_t* rgba) {
  // ⚠️STORED size: this writes the picture the file holds, and the law
  // turns it upright afterwards.
  return qa_video_apple_decode_read(
      index, g_doc.fps_num, g_doc.fps_den, rgba,
      g_doc.stored_width * g_doc.stored_height * 4, qa_sample_reaches_hook,
      g_decode_error, (int32_t)sizeof(g_decode_error));
}

#elif defined(__ANDROID__) && !defined(QA_DECODE_LAW_ONLY)
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
#include <fcntl.h>
#include <sys/types.h>
#include <unistd.h>
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
/// MediaFormat.KEY_ROTATION. ⚠️Set on the EXTRACTOR's track format, not on
/// the codec's output — the codec has already forgotten it.
#define QA_KEY_ROTATION "rotation-degrees"

#define QA_COLOR_FORMAT_YUV420_PLANAR 19
#define QA_COLOR_FORMAT_YUV420_SEMIPLANAR 21
#define QA_COLOR_FORMAT_YUV420_FLEXIBLE 0x7F420888

typedef struct {
  void* handle;
  AMediaExtractor* (*extractor_new)(void);
  int32_t (*extractor_delete)(AMediaExtractor*);
  int32_t (*extractor_set_source)(AMediaExtractor*, const char*);
  /// ⚠️`__INTRODUCED_IN(21)` — the ONLY byte-range open every supported
  /// Android device has. `setDataSourceCustom` (an arbitrary source) is
  /// `(28)`, and this app's `minSdk` is 21.
  int32_t (*extractor_set_source_fd)(AMediaExtractor*, int, off64_t, off64_t);
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
  /// ⚠️May be NULL — resolved separately from the required set below.
  bool (*format_get_float)(AMediaFormat*, const char*, float*);
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
  QA_SYM(extractor_set_source_fd, "AMediaExtractor_setDataSourceFd")
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
  // ⚠️OPTIONAL, unlike everything above: a missing float getter costs the
  // exact frame rate, not the decoder. `QA_SYM` refuses the whole library
  // when a symbol is absent, and refusing to play video at all because one
  // rate would be rounded is the wrong trade — absence is an ANSWER here
  // too, and [qa_backend_open] falls back to the int32 spelling.
  *(void**)(&g_ndk_dec.format_get_float) =
      dlsym(handle, "AMediaFormat_getFloat");
  g_ndk_dec.handle = handle;
  return 1;
}

/// ⚠️The PLATFORM's own state only — size, rate, length and 「where am I
/// positioned」 live in [g_doc], where all three backends answer alike.
typedef struct {
  AMediaExtractor* extractor;
  AMediaCodec* codec;
  int32_t track;
} qa_video_droid_decode;

static qa_video_droid_decode g_droid_dec;

static void qa_backend_close(void) {
  if (g_droid_dec.codec != NULL) {
    g_ndk_dec.codec_stop(g_droid_dec.codec);
    g_ndk_dec.codec_delete(g_droid_dec.codec);
    g_droid_dec.codec = NULL;
  }
  if (g_droid_dec.extractor != NULL) {
    g_ndk_dec.extractor_delete(g_droid_dec.extractor);
    g_droid_dec.extractor = NULL;
  }
  memset(&g_droid_dec, 0, sizeof(g_droid_dec));
}

static int32_t qa_backend_supported(void) { return qa_ndk_decode_load(); }

static int32_t qa_backend_open(const char* path,
                               int64_t offset,
                               int64_t length) {
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
  // A RANGE opens by descriptor; a whole file opens by path. Both are the
  // extractor's own front doors — nothing is wrapped, copied or unpacked.
  int32_t sourced;
  if (length > 0) {
    const int fd = open(path, O_RDONLY);
    if (fd < 0) {
      g_ndk_dec.extractor_delete(extractor);
      qa_decode_set_error("could not open the container");
      return 0;
    }
    sourced = g_ndk_dec.extractor_set_source_fd(extractor, fd, (off64_t)offset,
                                                (off64_t)length);
    // ⚠️CLOSED EITHER WAY. `setDataSourceFd` dups what it needs, so holding
    // this open would leak one descriptor per movie opened.
    close(fd);
  } else {
    sourced = g_ndk_dec.extractor_set_source(extractor, path);
  }
  if (sourced != QA_AMEDIA_OK) {
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
  float rate_f = 0.0f;
  int64_t duration_us = 0;
  g_ndk_dec.format_get_int32(format, QA_KEY_WIDTH, &width);
  g_ndk_dec.format_get_int32(format, QA_KEY_HEIGHT, &height);
  g_ndk_dec.format_get_int32(format, QA_KEY_FRAME_RATE, &rate);
  // ⚠️READ BEFORE THE FORMAT IS RELEASED, and as a FLOAT — see the rate
  // conversion below for why the int32 alone was wrong.
  if (g_ndk_dec.format_get_float != NULL) {
    g_ndk_dec.format_get_float(format, QA_KEY_FRAME_RATE, &rate_f);
  }
  g_ndk_dec.format_get_int64(format, QA_KEY_DURATION, &duration_us);
  // Absent on a file with no transform, which is most of them — and what
  // every file looked like to this reader before the law asked.
  int32_t rotation = 0;
  g_ndk_dec.format_get_int32(format, QA_KEY_ROTATION, &rotation);

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

  // ⛔The size check that stood here is gone, not relaxed — the portable
  // open makes it for every backend.
  g_droid_dec.extractor = extractor;
  g_droid_dec.codec = codec;
  g_droid_dec.track = video_track;
  g_doc.stored_width = width;
  g_doc.stored_height = height;
  g_doc.rotation = rotation;
  // 🚨★★★**29.97 IS NOT 30, AND THIS BACKEND USED TO SAY IT WAS.**
  //
  // `frame-rate` was read with `format_get_int32` alone and the denominator
  // was pinned to 1, so an NTSC-rate source became 29 or 30 — and every
  // `target_us` below, plus the frame COUNT, drifted with it. Apple has
  // carried the fraction since it was written; this backend simply never
  // asked. The float getter is the same `dlsym` shape as everything else
  // here (`AMediaFormat_getFloat`, API 21), and the conversion is the
  // portable one both backends now share.
  // ⚠️Some extractors store the key as an int32 and the float getter then
  // refuses it; the integer is still the honest answer for those.
  qa_rate_to_fraction(rate_f > 0.0f ? (double)rate_f : (double)rate,
                      &g_doc.fps_num, &g_doc.fps_den);
  g_doc.frame_count = qa_frame_count_for(duration_us, 1000000LL,
                                         g_doc.fps_num, g_doc.fps_den);
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
  const int32_t width = g_doc.stored_width;
  const int32_t height = g_doc.stored_height;
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

/// The presentation time of [index] in MediaCodec's microseconds.
static int64_t qa_droid_target(int64_t index) {
  return (index * 1000000LL * (int64_t)g_doc.fps_den) /
         (int64_t)g_doc.fps_num;
}

/// ⛔The flush goes WITH the seek. Flushing without seeking would throw away
/// the very frames the codec is holding for us, which is the whole saving.
static int32_t qa_backend_reposition(int64_t index) {
  g_ndk_dec.extractor_seek_to(g_droid_dec.extractor, qa_droid_target(index),
                              QA_SEEK_PREVIOUS_SYNC);
  g_ndk_dec.codec_flush(g_droid_dec.codec);
  return 1;
}

static int32_t qa_backend_read(int64_t index, uint8_t* rgba) {
  const int64_t target_us = qa_droid_target(index);
  const int64_t frame_us =
      (1000000LL * (int64_t)g_doc.fps_den) / (int64_t)g_doc.fps_num;

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
    if (!qa_sample_reaches((int64_t)info.presentationTimeUs, target_us,
                           frame_us)) {
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
    int32_t stride = g_doc.stored_width;
    int32_t slice = g_doc.stored_height;
    if (out_format != NULL) {
      g_ndk_dec.format_get_int32(out_format, QA_KEY_COLOR_FORMAT,
                                 &colour);
      g_ndk_dec.format_get_int32(out_format, QA_KEY_STRIDE,
                                 &stride);
      g_ndk_dec.format_get_int32(out_format, QA_KEY_SLICE_HEIGHT,
                                 &slice);
      g_ndk_dec.format_delete(out_format);
    }
    if (stride < g_doc.stored_width) {
      stride = g_doc.stored_width;
    }
    if (slice < g_doc.stored_height) {
      slice = g_doc.stored_height;
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
//
// ⚠️This branch is the one the portability CI compiles, so it is also where
// the shared law above gets its only compiler. That is not an accident any
// more — it is why the law lives outside the `#if`.

static int32_t qa_backend_supported(void) { return 0; }

static int32_t qa_backend_open(const char* path,
                               int64_t offset,
                               int64_t length) {
  (void)path;
  (void)offset;
  (void)length;
  qa_decode_set_error("no video decoder in this build");
  return 0;
}

static void qa_backend_close(void) {}

static int32_t qa_backend_reposition(int64_t index) {
  (void)index;
  return 0;
}

static int32_t qa_backend_read(int64_t index, uint8_t* rgba) {
  (void)index;
  (void)rgba;
  return 0;
}

#endif

// ---------------------------------------------------------------------------
// The portable law. Every backend above answers the four hooks and nothing
// below is written twice.

QA_EXPORT int32_t qa_video_decode_supported(void) {
  return qa_backend_supported();
}

QA_EXPORT void qa_video_decode_close(void) {
  qa_backend_close();
  free(g_rotate_scratch);
  g_rotate_scratch = NULL;
  g_rotate_scratch_bytes = 0;
  memset(&g_doc, 0, sizeof(g_doc));
  // ⛔A closed reader is positioned nowhere. Zeroing above leaves this 0,
  // which names frame 0 — the one index a stale「next」could wrongly claim.
  g_doc.next_index = -1;
}

/// 🚨★★★**A MOVIE INSIDE THE PROJECT FILE IS A RANGE, NOT A PATH.**
///
/// A carried video's bytes live in the `.anicel` the project travels as, so
/// there is no path pointing at the movie — and until this existed, losing
/// the original meant losing the ability to view it, in a file that plainly
/// contained it (card `carried-video-cannot-be-viewed`).
///
/// ⛔The alternative was unpacking it to a temp file, which leaves a COPY
/// (유저 2026-08-27: 「사본 남으면 진짜 용서안할게」).
///
/// ⚠️**THE RANGE MUST BE THE MOVIE'S OWN BYTES, contiguous and unmodified.**
/// That is not a convenience: Android below API 28 has no arbitrary byte
/// source at all — `AMediaExtractor_setDataSourceFd` is `__INTRODUCED_IN(21)`
/// and `setDataSourceCustom` is `(28)`, while this app's `minSdk` is 21 —
/// so 「a file descriptor and a range」 is the only shape every supported
/// device can open. The archive side keeps such entries addressable for
/// exactly this reason.
QA_EXPORT int32_t qa_video_decode_open_range(const char* path,
                                             int64_t offset,
                                             int64_t length) {
  qa_video_decode_close();
  qa_decode_set_error(NULL);
  if (path == NULL || path[0] == '\0') {
    qa_decode_set_error("no path");
    return 0;
  }
  if (offset < 0 || length <= 0) {
    qa_decode_set_error("that range is not inside the file");
    return 0;
  }
  return qa_decode_finish_open(path, offset, length);
}

QA_EXPORT int32_t qa_video_decode_open(const char* path) {
  qa_video_decode_close();
  qa_decode_set_error(NULL);
  if (path == NULL || path[0] == '\0') {
    qa_decode_set_error("no path");
    return 0;
  }
  return qa_decode_finish_open(path, 0, 0);
}

/// Everything both opens do once the backend has answered — one copy, so
/// 「open a file」 and 「open a range in a file」 cannot drift into meaning
/// different things about rotation, rate or length.
static int32_t qa_decode_finish_open(const char* path,
                                     int64_t offset,
                                     int64_t length) {
  if (!qa_backend_open(path, offset, length)) {
    qa_video_decode_close();
    return 0;
  }
  if (g_doc.stored_width <= 0 || g_doc.stored_height <= 0) {
    qa_decode_set_error("the video stream has no frame size");
    qa_video_decode_close();
    return 0;
  }
  // The display size is the law's answer, not each backend's. A quarter
  // turn swaps the sides; a half turn does not.
  g_doc.rotation = qa_rotation_quarter(g_doc.rotation);
  const int32_t quarter = g_doc.rotation == 90 || g_doc.rotation == 270;
  g_doc.width = quarter ? g_doc.stored_height : g_doc.stored_width;
  g_doc.height = quarter ? g_doc.stored_width : g_doc.stored_height;
  if (g_doc.fps_num <= 0 || g_doc.fps_den <= 0) {
    g_doc.fps_num = 24;
    g_doc.fps_den = 1;
  }
  if (g_doc.frame_count < 1) {
    g_doc.frame_count = 1;
  }
  g_doc.next_index = -1;
  g_doc.open = 1;
  return 1;
}

QA_EXPORT int32_t qa_video_decode_info(int32_t* width,
                                       int32_t* height,
                                       int64_t* frame_count,
                                       int32_t* fps_num,
                                       int32_t* fps_den) {
  if (!g_doc.open) {
    qa_decode_set_error("no document is open");
    return 0;
  }
  if (width != NULL) *width = g_doc.width;
  if (height != NULL) *height = g_doc.height;
  if (frame_count != NULL) *frame_count = g_doc.frame_count;
  if (fps_num != NULL) *fps_num = g_doc.fps_num;
  if (fps_den != NULL) *fps_den = g_doc.fps_den;
  return 1;
}

QA_EXPORT int32_t qa_video_decode_frame(int64_t index,
                                        uint8_t* rgba,
                                        int32_t capacity) {
  if (!g_doc.open) {
    qa_decode_set_error("no document is open");
    return 0;
  }
  if (rgba == NULL || capacity < g_doc.width * g_doc.height * 4) {
    qa_decode_set_error("frame buffer too small");
    return 0;
  }
  if (index < 0) {
    index = 0;
  }

  // 🚨★★★**PLAYING FORWARD DOES NOT SEEK.**
  //
  // A reposition lands on the nearest KEYFRAME at or before the target and
  // the backend then decodes forward, which is why [qa_backend_read] is a
  // walk rather than one sample. Doing it for EVERY frame made sequential
  // playback quadratic in the GOP: frame n re-decoded everything since its
  // keyframe, so a 48-frame GOP cost 24 decodes per displayed frame on
  // average.
  //
  // 유저 2026-08-31 saw both ends of that: 「첫 재생때 아마 파일이 제대로
  // 로드안되서 흰 화면이 엄청나게 깜빡이면서 재생됨. 두번째 재생부터 점점
  // 나아짐」 — the viewer advances the playhead on a wall clock and draws
  // whatever raster has landed, so a decoder that cannot keep up shows white
  // until the cache is warm — and 「재생하고있는데 화면이 첫 프레임 그림에서
  // 전혀안바뀜」, which is the same thing when it never catches up at all.
  //
  // The backend is already positioned to deliver the frame after the one it
  // just gave, so asking for that frame needs no reposition at all.
  if (index != g_doc.next_index && !qa_backend_reposition(index)) {
    g_doc.next_index = -1;
    return 0;
  }
  // ⛔Cleared BEFORE the read, not after a success. A failed or abandoned
  // read leaves the backend somewhere this function cannot name, and a stale
  //「next」would then skip the reposition that would have recovered it.
  g_doc.next_index = -1;
  // ⛔The turn is applied HERE, once, for every backend — not by whichever
  // backend's author happened to know about it. A backend decodes into
  // STORED orientation and says nothing more about it.
  //
  // ⚠️The scratch exists only when there is a turn: an upright video is the
  // overwhelming case and it must not pay a whole-frame copy for the
  // sideways one.
  uint8_t* target = rgba;
  if (g_doc.rotation != 0) {
    const int64_t needed =
        (int64_t)g_doc.stored_width * g_doc.stored_height * 4;
    if (g_rotate_scratch_bytes < needed) {
      uint8_t* grown = (uint8_t*)realloc(g_rotate_scratch, (size_t)needed);
      if (grown == NULL) {
        qa_decode_set_error("out of memory turning the frame upright");
        return 0;
      }
      g_rotate_scratch = grown;
      g_rotate_scratch_bytes = needed;
    }
    target = g_rotate_scratch;
  }
  if (!qa_backend_read(index, target)) {
    return 0;
  }
  if (g_doc.rotation != 0) {
    qa_rotate_rgba(target, g_doc.stored_width, g_doc.stored_height,
                   g_doc.rotation, rgba);
  }
  // Positioned on the frame AFTER this one, so the next request for it can
  // skip the reposition entirely.
  g_doc.next_index = index + 1;
  return 1;
}
