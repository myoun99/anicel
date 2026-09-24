// TEST FIXTURES ONLY: a FRAMED blob written from C, for the C tests that
// read one back (qa_media_span_test.c, qa_audio_range_test.c).
//
// ⚠️This is NOT the format's writer — that is `writeMediaBlob` in Dart, and
// the Dart suite reads what THAT writes through the native reader. C has no
// other way to make a fixture, so this one only has to agree with the layout
// in qa_media_span.h; ONE copy of it serves every C test.

#ifndef QA_FRAMED_FIXTURE_H
#define QA_FRAMED_FIXTURE_H

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

#include "third_party/zstd/zstd.h"

/// How many blocks a fixture may have — [qa_fixture_write_framed]'s
/// [lengths] needs room for this many.
#define QA_FIXTURE_MAX_BLOCKS 64

static void qa_fixture_put_u32(uint8_t* at, uint32_t value) {
  at[0] = (uint8_t)(value & 0xFF);
  at[1] = (uint8_t)((value >> 8) & 0xFF);
  at[2] = (uint8_t)((value >> 16) & 0xFF);
  at[3] = (uint8_t)((value >> 24) & 0xFF);
}

/// Writes [medium] — [total] bytes — framed in blocks of [block_bytes] at
/// [file]'s current position, and answers the blob's length, or -1. Each
/// block's compressed length lands in [lengths].
static int64_t qa_fixture_write_framed(FILE* file,
                                       const uint8_t* medium,
                                       int64_t total,
                                       int64_t block_bytes,
                                       uint32_t* lengths) {
  const int64_t count = (total + block_bytes - 1) / block_bytes;
  if (count > QA_FIXTURE_MAX_BLOCKS || total <= 0) {
    return -1;
  }
  const size_t bound = ZSTD_compressBound((size_t)block_bytes);
  uint8_t* packed = (uint8_t*)malloc(bound * (size_t)count);
  if (packed == NULL) {
    return -1;
  }
  int64_t packed_bytes = 0;
  for (int64_t b = 0; b < count; b += 1) {
    const int64_t start = b * block_bytes;
    const int64_t size =
        total - start < block_bytes ? total - start : block_bytes;
    const size_t wrote = ZSTD_compress(packed + packed_bytes, bound,
                                       medium + start, (size_t)size, 9);
    if (ZSTD_isError(wrote)) {
      free(packed);
      return -1;
    }
    lengths[b] = (uint32_t)wrote;
    packed_bytes += (int64_t)wrote;
  }
  uint8_t header[16 + 4 * QA_FIXTURE_MAX_BLOCKS];
  qa_fixture_put_u32(header, (uint32_t)block_bytes);
  qa_fixture_put_u32(header + 4, (uint32_t)((uint64_t)total & 0xFFFFFFFFu));
  qa_fixture_put_u32(header + 8, (uint32_t)((uint64_t)total >> 32));
  qa_fixture_put_u32(header + 12, (uint32_t)count);
  for (int64_t b = 0; b < count; b += 1) {
    qa_fixture_put_u32(header + 16 + 4 * b, lengths[b]);
  }
  const int64_t header_bytes = 16 + 4 * count;
  fwrite(header, 1, (size_t)header_bytes, file);
  fwrite(packed, 1, (size_t)packed_bytes, file);
  free(packed);
  return header_bytes + packed_bytes;
}

#endif  // QA_FRAMED_FIXTURE_H
