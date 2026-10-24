// What the video decoder and the audio decoder share of the NDK media API:
// a medium stored in a span of a file, served to MediaExtractor as a source
// of our own. Everything else they and the encoder call comes from the
// NDK's own headers (<media/NdkMedia*.h>) and libmediandk.so.
//
// 🚨★★★**THERE WERE THREE COPIES OF THE NDK MEDIA TABLE, AND THEY DID NOT
// AGREE.** Each of the three dlopen'd libmediandk.so and dlsym'd its own
// table (found 2026-09-24, while giving the video decoder a custom source),
// and they disagreed exactly where it mattered:
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
// They became ONE table that day, its types and values copied by hand from
// NDK 29's headers. ↩️The table — every function by dlsym, the types
// declared here — existed because the headers hid every function newer
// than the build's minSdk, which was 21 while a custom data source is
// API 28. That premise went on 2026-10-24 with the floor (Android 10,
// minSdk 29, board skia-devices-out-of-release): the headers hide nothing
// these callers use, so they include them and link libmediandk.so, and
// every type above is now the compiler's to check rather than a copy's to
// get wrong.
// ⚠️Linked, the whole engine needs libmediandk.so to load. Every device the
// app serves has it — a public NDK library since API 21, and everything
// called here is API 29 or older.

#ifndef QA_NDK_MEDIA_H
#define QA_NDK_MEDIA_H

#if defined(__ANDROID__)

#include <stdint.h>

#include <media/NdkMediaDataSource.h>

/// A medium stored in a span of a file (qa_media_span.h), served to an
/// extractor as a source of our own — how a FRAMED span, whose stored bytes
/// are not the container, reaches MediaExtractor at all.
///
/// ⚠️ONE serving for the video decoder and the audio decoder: each needed
/// exactly this, and the lock below is the part a second copy forgets.
typedef struct qa_ndk_served_span qa_ndk_served_span;

/// NULL when the span will not open.
qa_ndk_served_span* qa_ndk_served_span_open(const char* utf8_path,
                                            int64_t offset,
                                            int64_t length,
                                            int32_t framed);

/// What to hand `AMediaExtractor_setDataSourceCustom`.
AMediaDataSource* qa_ndk_served_span_source(const qa_ndk_served_span* served);

/// ⚠️Only AFTER the extractor it was handed to is deleted: the extractor
/// reads through it for as long as it lives. NULL is ignored.
void qa_ndk_served_span_free(qa_ndk_served_span* served);

#endif  // __ANDROID__

#endif  // QA_NDK_MEDIA_H
