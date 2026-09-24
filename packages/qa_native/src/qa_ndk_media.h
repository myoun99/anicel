// The NDK media API, resolved ONCE for everything in this library that
// speaks to it — the video encoder, the video decoder and the audio decoder.
//
// 🚨★★★**THERE WERE THREE COPIES OF THIS TABLE, AND THEY DID NOT AGREE.**
// Each of the three dlopen'd libmediandk.so and dlsym'd its own table
// (found 2026-09-24, while giving the video decoder a custom source), and
// they disagreed exactly where it mattered:
//
//   · `AMediaCodec_queueInputBuffer` takes its offset as `long`
//     (`_off_t_compat`, which the NDK asserts is `sizeof(long)`) — 32 bits
//     on a 32-bit ARM device. Both video tables said `int64_t`, and on
//     armeabi-v7a a 64-bit argument there shifts every argument after it:
//     the codec was handed a SIZE of zero.
//   · An `AMediaDataSource` read callback is given an `off64_t`. The audio
//     table said `off_t`, which on the same devices reads the offset out of
//     the wrong registers.
//   · `AMEDIACODEC_INFO_OUTPUT_FORMAT_CHANGED` is -2 and
//     `..._OUTPUT_BUFFERS_CHANGED` is -3. The encoder said -1012 and -1014,
//     so the muxer was never told its tracks and never started.
//
// ⇒ One table, with the NDK's own types and values — checked against NDK
// 29's `NdkMediaCodec.h`, `NdkMediaExtractor.h`, `NdkMediaDataSource.h`,
// `NdkMediaFormat.h` and `NdkMediaMuxer.h`.
//
// ⛔STILL NO NDK MEDIA HEADERS. They hide every function newer than the
// build's minSdk (21), and a custom data source is API 28 — so the types
// are declared here and every function arrives through dlsym, where a
// missing one is an ANSWER (「this device cannot do that」) rather than a
// load failure.

#ifndef QA_NDK_MEDIA_H
#define QA_NDK_MEDIA_H

#if defined(__ANDROID__)

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <sys/types.h>

typedef struct AMediaExtractor AMediaExtractor;
typedef struct AMediaCodec AMediaCodec;
typedef struct AMediaFormat AMediaFormat;
typedef struct AMediaMuxer AMediaMuxer;
typedef struct AMediaDataSource AMediaDataSource;

/// `AMediaCodecBufferInfo`, field for field.
typedef struct {
  int32_t offset;
  int32_t size;
  int64_t presentationTimeUs;
  uint32_t flags;
} qa_ndk_buffer_info;

/// `AMEDIA_OK`.
#define QA_NDK_OK 0
/// `AMEDIACODEC_INFO_*` — what a dequeue answers instead of an index.
#define QA_NDK_INFO_TRY_AGAIN_LATER (-1)
#define QA_NDK_INFO_OUTPUT_FORMAT_CHANGED (-2)
#define QA_NDK_INFO_OUTPUT_BUFFERS_CHANGED (-3)
/// `AMEDIACODEC_BUFFER_FLAG_*`.
#define QA_NDK_FLAG_CODEC_CONFIG 2u
#define QA_NDK_FLAG_END_OF_STREAM 4u
/// `AMEDIACODEC_CONFIGURE_FLAG_ENCODE`.
#define QA_NDK_CONFIGURE_ENCODE 1u
/// `AMEDIAEXTRACTOR_SEEK_PREVIOUS_SYNC`.
#define QA_NDK_SEEK_PREVIOUS_SYNC 0

/// An `AMediaDataSource` read: [size] bytes at [offset] into [buffer], the
/// count read, 0 at the end, -1 on failure.
typedef ssize_t (*qa_ndk_read_at)(void* userdata,
                                  off64_t offset,
                                  void* buffer,
                                  size_t size);
typedef ssize_t (*qa_ndk_get_size)(void* userdata);
typedef void (*qa_ndk_close)(void* userdata);

/// Every entry point any caller here uses. ⚠️Any of them may be NULL on a
/// device whose libmediandk.so predates it — ask the capability you need
/// ([qa_ndk_media_decodes] and its siblings), never a single field.
typedef struct {
  AMediaExtractor* (*extractor_new)(void);
  int32_t (*extractor_delete)(AMediaExtractor*);
  int32_t (*extractor_set_source)(AMediaExtractor*, const char*);
  /// API 21 — the only byte-range open every supported device has.
  int32_t (*extractor_set_source_fd)(AMediaExtractor*,
                                     int,
                                     off64_t,
                                     off64_t);
  /// API 28 — an arbitrary source. NULL below Android 9.
  int32_t (*extractor_set_source_custom)(AMediaExtractor*, AMediaDataSource*);
  size_t (*extractor_track_count)(AMediaExtractor*);
  AMediaFormat* (*extractor_track_format)(AMediaExtractor*, size_t);
  int32_t (*extractor_select_track)(AMediaExtractor*, size_t);
  int32_t (*extractor_seek_to)(AMediaExtractor*, int64_t, int32_t);
  ssize_t (*extractor_read_sample)(AMediaExtractor*, uint8_t*, size_t);
  int64_t (*extractor_sample_time)(AMediaExtractor*);
  bool (*extractor_advance)(AMediaExtractor*);

  AMediaCodec* (*codec_create_decoder)(const char*);
  AMediaCodec* (*codec_create_encoder)(const char*);
  int32_t (*codec_delete)(AMediaCodec*);
  int32_t (*codec_configure)(AMediaCodec*,
                             const AMediaFormat*,
                             void* surface,
                             void* crypto,
                             uint32_t flags);
  int32_t (*codec_start)(AMediaCodec*);
  int32_t (*codec_stop)(AMediaCodec*);
  int32_t (*codec_flush)(AMediaCodec*);
  ssize_t (*codec_dequeue_input)(AMediaCodec*, int64_t);
  uint8_t* (*codec_input_buffer)(AMediaCodec*, size_t, size_t*);
  /// 🚨The offset is `long` — see the head of this file.
  int32_t (*codec_queue_input)(AMediaCodec*,
                               size_t index,
                               long offset,
                               size_t size,
                               uint64_t time,
                               uint32_t flags);
  ssize_t (*codec_dequeue_output)(AMediaCodec*, qa_ndk_buffer_info*, int64_t);
  uint8_t* (*codec_output_buffer)(AMediaCodec*, size_t, size_t*);
  int32_t (*codec_release_output)(AMediaCodec*, size_t, bool);
  AMediaFormat* (*codec_output_format)(AMediaCodec*);

  AMediaFormat* (*format_new)(void);
  int32_t (*format_delete)(AMediaFormat*);
  bool (*format_get_int32)(AMediaFormat*, const char*, int32_t*);
  bool (*format_get_int64)(AMediaFormat*, const char*, int64_t*);
  /// Optional even where it exists: a missing float getter costs an exact
  /// frame rate, never the decoder.
  bool (*format_get_float)(AMediaFormat*, const char*, float*);
  bool (*format_get_string)(AMediaFormat*, const char*, const char**);
  void (*format_set_string)(AMediaFormat*, const char*, const char*);
  void (*format_set_int32)(AMediaFormat*, const char*, int32_t);

  AMediaMuxer* (*muxer_new)(int, int32_t);
  ssize_t (*muxer_add_track)(AMediaMuxer*, const AMediaFormat*);
  int32_t (*muxer_start)(AMediaMuxer*);
  int32_t (*muxer_stop)(AMediaMuxer*);
  int32_t (*muxer_delete)(AMediaMuxer*);
  int32_t (*muxer_write)(AMediaMuxer*,
                         size_t,
                         const uint8_t*,
                         const qa_ndk_buffer_info*);

  /// API 28, all of them. NULL below Android 9.
  AMediaDataSource* (*source_new)(void);
  void (*source_delete)(AMediaDataSource*);
  void (*source_set_userdata)(AMediaDataSource*, void*);
  void (*source_set_read_at)(AMediaDataSource*, qa_ndk_read_at);
  void (*source_set_get_size)(AMediaDataSource*, qa_ndk_get_size);
  void (*source_set_close)(AMediaDataSource*, qa_ndk_close);
} qa_ndk_media_api;

/// The table, or NULL when libmediandk.so will not open. Resolved once, on
/// whichever thread asks first; safe from any thread after that.
const qa_ndk_media_api* qa_ndk_media(void);

/// Whether [api] can pull samples out of a container and decode them.
int qa_ndk_media_decodes(const qa_ndk_media_api* api);

/// Whether [api] can encode and mux a file.
int qa_ndk_media_encodes(const qa_ndk_media_api* api);

/// Whether [api] can read a container from a source this library serves —
/// Android 9 and later.
int qa_ndk_media_reads_custom(const qa_ndk_media_api* api);

/// A medium stored in a span of a file (qa_media_span.h), served to an
/// extractor as a source of our own — how a FRAMED span, whose stored bytes
/// are not the container, reaches MediaExtractor at all. Needs
/// [qa_ndk_media_reads_custom].
///
/// ⚠️ONE serving for the video decoder and the audio decoder: each needed
/// exactly this, and the lock below is the part a second copy forgets.
typedef struct qa_ndk_served_span qa_ndk_served_span;

/// NULL when the span will not open or the device cannot serve a source.
qa_ndk_served_span* qa_ndk_served_span_open(const qa_ndk_media_api* api,
                                            const char* utf8_path,
                                            int64_t offset,
                                            int64_t length,
                                            int32_t framed);

/// What to hand `AMediaExtractor_setDataSourceCustom`.
AMediaDataSource* qa_ndk_served_span_source(const qa_ndk_served_span* served);

/// ⚠️Only AFTER the extractor it was handed to is deleted: the extractor
/// reads through it for as long as it lives. NULL is ignored.
void qa_ndk_served_span_free(const qa_ndk_media_api* api,
                             qa_ndk_served_span* served);

#endif  // __ANDROID__

#endif  // QA_NDK_MEDIA_H
