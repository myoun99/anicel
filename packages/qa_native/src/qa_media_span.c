// The one reader of a medium stored in a span of a file — see
// qa_media_span.h for why there is only one, and for the framed layout.

#include "qa_media_span.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "qa_platform_path.h"
#include "third_party/zstd/zstd.h"

/// Bytes before the block lengths: blockBytes, totalLength, blockCount.
#define QA_FRAMED_PREFIX 16

/// A block size no writer of this format has used, and no reader should
/// trust — the header is read from a file, and a number this size would
/// have one allocation take everything.
#define QA_FRAMED_MAX_BLOCK (64 * 1024 * 1024)

struct qa_media_span {
  FILE* file;
  /// Where the STORED bytes start in the file, and how many there are.
  int64_t base;
  int64_t stored_length;
  /// How many bytes the MEDIUM has.
  int64_t size;
  int32_t framed;

  // ---- framed only
  int64_t block_bytes;
  int64_t block_count;
  /// block_count + 1 offsets into the stored bytes: where each block starts,
  /// and where the last one ends.
  int64_t* block_starts;
  /// One compressed block, sized to the largest.
  uint8_t* stored_block;
  /// One decoded block — the one the last window landed in, kept for the
  /// next: a document reads in windows far smaller than a block, and
  /// decoding 512KB for each of them is the cost this exists to not pay.
  uint8_t* block;
  int64_t block_index;
  int64_t block_size;

  int64_t blocks_decoded;
  int64_t stored_bytes_read;
};

static uint32_t qa_read_u32(const uint8_t* at) {
  return (uint32_t)at[0] | ((uint32_t)at[1] << 8) | ((uint32_t)at[2] << 16) |
         ((uint32_t)at[3] << 24);
}

static uint64_t qa_read_u64(const uint8_t* at) {
  return (uint64_t)qa_read_u32(at) | ((uint64_t)qa_read_u32(at + 4) << 32);
}

/// Exactly [want] stored bytes from [at] (relative to the span's base), or 0.
static int qa_span_read_stored(qa_media_span* span,
                               int64_t at,
                               void* out,
                               int64_t want) {
  if (at < 0 || want < 0 || at + want > span->stored_length) {
    return 0;
  }
  if (!qa_seek_absolute(span->file, span->base + at)) {
    return 0;
  }
  int64_t got = 0;
  while (got < want) {
    const size_t read =
        fread((uint8_t*)out + got, 1, (size_t)(want - got), span->file);
    if (read == 0) {
      return 0;
    }
    got += (int64_t)read;
  }
  span->stored_bytes_read += want;
  return 1;
}

/// Reads the framed header and sizes the buffers, or answers 0 when it does
/// not hold together with the span it sits in.
static int qa_span_open_framed(qa_media_span* span) {
  uint8_t prefix[QA_FRAMED_PREFIX];
  if (!qa_span_read_stored(span, 0, prefix, QA_FRAMED_PREFIX)) {
    return 0;
  }
  const int64_t block_bytes = (int64_t)qa_read_u32(prefix);
  const uint64_t total = qa_read_u64(prefix + 4);
  const int64_t block_count = (int64_t)qa_read_u32(prefix + 12);
  if (block_bytes <= 0 || block_bytes > QA_FRAMED_MAX_BLOCK ||
      total > (uint64_t)INT64_MAX) {
    return 0;
  }
  // ⛔The count must be the one the length implies: a header that says
  // otherwise was not written by this format's writer.
  const int64_t implied = ((int64_t)total + block_bytes - 1) / block_bytes;
  if (block_count != implied) {
    return 0;
  }
  const int64_t header_length = QA_FRAMED_PREFIX + 4 * block_count;
  if (header_length > span->stored_length) {
    return 0;
  }
  uint8_t* lengths = NULL;
  if (block_count > 0) {
    lengths = (uint8_t*)malloc((size_t)(4 * block_count));
    if (lengths == NULL ||
        !qa_span_read_stored(span, QA_FRAMED_PREFIX, lengths,
                             4 * block_count)) {
      free(lengths);
      return 0;
    }
  }
  span->block_starts =
      (int64_t*)malloc((size_t)(block_count + 1) * sizeof(int64_t));
  if (span->block_starts == NULL) {
    free(lengths);
    return 0;
  }
  int64_t at = header_length;
  int64_t largest = 0;
  for (int64_t i = 0; i < block_count; i += 1) {
    const int64_t length = (int64_t)qa_read_u32(lengths + 4 * i);
    span->block_starts[i] = at;
    at += length;
    if (length <= 0 || at > span->stored_length) {
      // A block that runs past the span is a torn entry, and reading it
      // would decode whatever follows it in the file.
      free(lengths);
      return 0;
    }
    if (length > largest) {
      largest = length;
    }
  }
  span->block_starts[block_count] = at;
  free(lengths);
  span->block_bytes = block_bytes;
  span->block_count = block_count;
  span->size = (int64_t)total;
  if (block_count > 0) {
    span->stored_block = (uint8_t*)malloc((size_t)largest);
    span->block = (uint8_t*)malloc((size_t)block_bytes);
    if (span->stored_block == NULL || span->block == NULL) {
      return 0;
    }
  }
  span->block_index = -1;
  return 1;
}

qa_media_span* qa_media_span_open(const char* utf8_path,
                                  int64_t offset,
                                  int64_t length,
                                  int32_t framed) {
  if (utf8_path == NULL || offset < 0 || length < 0) {
    return NULL;
  }
  FILE* file = qa_open_path_read(utf8_path);
  if (file == NULL) {
    return NULL;
  }
  // ⛔The span must be INSIDE the file. One that promises bytes the file
  // cannot supply is a truncated medium, which reads as a corrupt one rather
  // than as a span that was wrong.
  const int64_t file_size = qa_file_size(file);
  if (file_size < 0 || offset + length > file_size) {
    fclose(file);
    return NULL;
  }
  qa_media_span* span = (qa_media_span*)calloc(1, sizeof(*span));
  if (span == NULL) {
    fclose(file);
    return NULL;
  }
  span->file = file;
  span->base = offset;
  span->stored_length = length;
  span->size = length;
  span->framed = framed ? 1 : 0;
  span->block_index = -1;
  if (span->framed && !qa_span_open_framed(span)) {
    qa_media_span_close(span);
    return NULL;
  }
  return span;
}

int64_t qa_media_span_size(const qa_media_span* span) {
  return span == NULL ? 0 : span->size;
}

/// The decoded block [index], through the one-block cache, or NULL.
static const uint8_t* qa_span_block(qa_media_span* span, int64_t index) {
  if (span->block_index == index) {
    return span->block;
  }
  const int64_t start = span->block_starts[index];
  const int64_t stored = span->block_starts[index + 1] - start;
  // The last block is short; every other one is exactly block_bytes.
  const int64_t expected = index == span->block_count - 1
                               ? span->size - span->block_bytes * index
                               : span->block_bytes;
  span->block_index = -1;
  if (!qa_span_read_stored(span, start, span->stored_block, stored)) {
    return NULL;
  }
  const size_t decoded =
      ZSTD_decompress(span->block, (size_t)span->block_bytes,
                      span->stored_block, (size_t)stored);
  // ⛔A block that decodes to any other length is a broken file, not a
  // short one: the window it serves would be the wrong bytes.
  if (ZSTD_isError(decoded) || (int64_t)decoded != expected) {
    return NULL;
  }
  span->blocks_decoded += 1;
  span->block_index = index;
  span->block_size = expected;
  return span->block;
}

int64_t qa_media_span_read(qa_media_span* span,
                           int64_t position,
                           void* out,
                           int64_t want) {
  if (span == NULL || out == NULL || position < 0 || want <= 0 ||
      position >= span->size) {
    return 0;
  }
  if (want > span->size - position) {
    want = span->size - position;
  }
  if (!span->framed) {
    // 🚨base + position. Reading at `position` alone hands back whatever
    // precedes the medium in the file as if it were the medium.
    return qa_span_read_stored(span, position, out, want) ? want : -1;
  }
  int64_t wrote = 0;
  while (wrote < want) {
    const int64_t at = position + wrote;
    const int64_t index = at / span->block_bytes;
    const uint8_t* block = qa_span_block(span, index);
    if (block == NULL) {
      return -1;
    }
    const int64_t from = at - index * span->block_bytes;
    int64_t take = span->block_size - from;
    if (take > want - wrote) {
      take = want - wrote;
    }
    memcpy((uint8_t*)out + wrote, block + from, (size_t)take);
    wrote += take;
  }
  return wrote;
}

void qa_media_span_close(qa_media_span* span) {
  if (span == NULL) {
    return;
  }
  if (span->file != NULL) {
    fclose(span->file);
  }
  free(span->block_starts);
  free(span->stored_block);
  free(span->block);
  free(span);
}

void qa_media_span_stats(const qa_media_span* span,
                         int64_t* blocks_decoded,
                         int64_t* stored_bytes_read) {
  if (blocks_decoded != NULL) {
    *blocks_decoded = span == NULL ? 0 : span->blocks_decoded;
  }
  if (stored_bytes_read != NULL) {
    *stored_bytes_read = span == NULL ? 0 : span->stored_bytes_read;
  }
}
