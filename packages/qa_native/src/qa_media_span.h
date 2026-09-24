// A medium stored in a SPAN of a file — as its own bytes, or framed in
// compressed blocks — read a window at a time. THE one reader of both, for
// every decoder in this library and for Dart.
//
// 🚨★★★**THERE WERE THREE READERS OF A PLAIN SPAN AND NONE OF A FRAMED ONE.**
// The audio decoder's cursor read `base + position` through a `FILE*`, the
// Windows byte stream through `ReadFile`, Apple's resource loader through
// `NSFileHandle` — the same three lines each time, and each file carried a
// comment warning that getting them wrong reads the archive's own header as
// media. A FRAMED span (a medium the save compressed in blocks, see
// `media_blob_codec.dart`) had no native reader at all, so every OS decoder
// needed the original file, and the sound of a carried movie was assembled
// whole in memory before anything could decode it (2026-09-24, board
// `carried-movie-compressed`: 유저 「압축 유지 + 풀면서 디코더에 먹이는
// 리더를 플랫폼마다 만든다」, 「최대한 통일할거 통일해줘」).
//
// ⛔Nothing here is shared between threads: one span serves one reader, and
// a platform that calls from more than one thread serializes around it.
//
// ⚠️THE FORMAT IS WRITTEN IN ONE PLACE, AND IT IS NOT HERE — the writer is
// `writeMediaBlob` in Dart. This reads what that writes, and
// `test/services/media/framed_media_reads_only_the_blocks_it_needs_test.dart`
// reads files that writer wrote through this, so the two cannot drift
// unseen:
//
//   u32  blockBytes   uncompressed bytes per block
//   u64  totalLength  uncompressed length of the whole medium
//   u32  blockCount
//   u32  ×blockCount  compressed length of each block, in order
//   then each block, a zstd frame
//
// all little-endian.

#ifndef QA_MEDIA_SPAN_H
#define QA_MEDIA_SPAN_H

#include <stdint.h>

// ⚠️On the DECLARATIONS: MSVC refuses a definition whose linkage differs
// from the declaration it already saw (C2375), and Dart reaches these by
// name, so the export has to be what every includer sees.
#if defined(_WIN32)
#define QA_SPAN_EXPORT __declspec(dllexport)
#else
#define QA_SPAN_EXPORT __attribute__((visibility("default")))
#endif

typedef struct qa_media_span qa_media_span;

/// The medium stored in `[offset, offset + length)` of [utf8_path] — its
/// own bytes when [framed] is 0, a framed blob of them when it is 1. NULL
/// when the span is not inside the file, or a framed header does not hold
/// together with the span it sits in.
QA_SPAN_EXPORT qa_media_span* qa_media_span_open(const char* utf8_path,
                                                 int64_t offset,
                                                 int64_t length,
                                                 int32_t framed);

/// How many bytes the MEDIUM has — for a framed span, the decoded length.
QA_SPAN_EXPORT int64_t qa_media_span_size(const qa_media_span* span);

/// Up to [want] bytes of the medium from [position] into [out]: how many
/// landed — short only at the end, 0 past it — or -1 when the file would not
/// read or a block would not decode.
QA_SPAN_EXPORT int64_t qa_media_span_read(qa_media_span* span,
                                          int64_t position,
                                          void* out,
                                          int64_t want);

QA_SPAN_EXPORT void qa_media_span_close(qa_media_span* span);

/// What a span has cost so far — blocks decoded, and stored bytes read
/// (the header included). For the tests that tell a reader that reads only
/// the blocks a window lands in from one that quietly reads them all.
QA_SPAN_EXPORT void qa_media_span_stats(const qa_media_span* span,
                                        int64_t* blocks_decoded,
                                        int64_t* stored_bytes_read);

#endif  // QA_MEDIA_SPAN_H
