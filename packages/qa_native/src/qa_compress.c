// The cel compressor (R-COMP): zstd, memory to memory.
//
// Why native, and why zstd: a cel blob is compressed once per save on a
// background isolate, and DECOMPRESSED on the main isolate in frame time —
// `BrushFrameStore` promotes a cold cel synchronously the first time it is
// looked at, so this is not a file-format cost, it is a scrubbing cost.
//
// Measured on a real 22.8MB project (104 cels):
//   median cel   deflate -9 3.35ms → zstd -9 0.11ms   (and 7.5% smaller)
//   largest cel  deflate -9 70ms   → zstd -9 55ms
//
// ⛔Not a replacement for deflate: `dart:io` has zlib and always works,
// including in tests and on a host run with no engine. The blob's codec
// byte says which one wrote it, both are read, and the writer picks zstd
// only when the engine answered. A file this app writes must never depend
// on a library that might not be there.
//
// The contract with Dart mirrors the rest of the engine: the caller owns
// both buffers, sizes are exact, and a failure is a zero/negative return
// rather than a partial write.

#include <stdint.h>
#include <string.h>

#include "third_party/zstd/zstd.h"

#if defined(_WIN32)
#define QA_EXPORT __declspec(dllexport)
#else
#define QA_EXPORT __attribute__((visibility("default")))
#endif

// The most bytes [src_size] can compress to — the caller sizes its
// destination with this before calling [qa_zstd_compress].
QA_EXPORT int64_t qa_zstd_compress_bound(int64_t src_size) {
  if (src_size <= 0) {
    return 0;
  }
  return (int64_t)ZSTD_compressBound((size_t)src_size);
}

// Compresses into [dst], answering the byte count, or 0 on failure.
//
// [level] is zstd's own scale. The app uses 9 for its normal save and a
// higher one for "smallest file"; the number is the caller's policy, not
// this file's.
QA_EXPORT int64_t qa_zstd_compress(uint8_t* dst,
                                   int64_t dst_capacity,
                                   const uint8_t* src,
                                   int64_t src_size,
                                   int32_t level) {
  if (dst == NULL || src == NULL || dst_capacity <= 0 || src_size <= 0) {
    return 0;
  }
  size_t written = ZSTD_compress(dst, (size_t)dst_capacity, src,
                                 (size_t)src_size, (int)level);
  if (ZSTD_isError(written)) {
    return 0;
  }
  return (int64_t)written;
}

// The exact decompressed size a frame states, or -1 when the frame does
// not carry one (zstd allows that; every frame this app writes does).
//
// Dart needs it BEFORE allocating, and asking the frame is cheaper and
// safer than storing the number a second time in our own header.
QA_EXPORT int64_t qa_zstd_decompressed_size(const uint8_t* src,
                                            int64_t src_size) {
  if (src == NULL || src_size <= 0) {
    return -1;
  }
  unsigned long long size = ZSTD_getFrameContentSize(src, (size_t)src_size);
  if (size == ZSTD_CONTENTSIZE_UNKNOWN || size == ZSTD_CONTENTSIZE_ERROR) {
    return -1;
  }
  return (int64_t)size;
}

// Decompresses into [dst], answering the byte count, or 0 on failure.
QA_EXPORT int64_t qa_zstd_decompress(uint8_t* dst,
                                     int64_t dst_capacity,
                                     const uint8_t* src,
                                     int64_t src_size) {
  if (dst == NULL || src == NULL || dst_capacity <= 0 || src_size <= 0) {
    return 0;
  }
  size_t written =
      ZSTD_decompress(dst, (size_t)dst_capacity, src, (size_t)src_size);
  if (ZSTD_isError(written)) {
    return 0;
  }
  return (int64_t)written;
}
