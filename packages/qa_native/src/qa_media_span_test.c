// The span reader, driven for real — on every host CI has, because nothing
// in it is platform code.
//
// 🚨★★★**WHAT THIS PROTECTS: THE WINDOW STAYS A WINDOW.** A framed reader that
// quietly decoded every block would hand back the right bytes to every check
// that only compares bytes, so the checks here also COUNT what was decoded and
// read (`qa_media_span_stats`) — that count is the only thing that tells the
// two apart.
//
// ⚠️Fixtures come from qa_framed_fixture.h, which says why C has a writer of
// its own at all and why it is not the format's writer.

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "qa_media_span.h"
#include "qa_framed_fixture.h"

static int g_failures;

static void expect_int(const char* what, long long got, long long want) {
  if (got == want) {
    return;
  }
  printf("FAIL %s: got %lld, want %lld\n", what, got, want);
  g_failures += 1;
}

static void expect_true(const char* what, int ok) {
  if (!ok) {
    printf("FAIL %s\n", what);
    g_failures += 1;
  }
}

/// Byte i of the medium is derived from i, so any window can be checked
/// without holding the whole medium — and it compresses.
static uint8_t medium_byte(int64_t i) {
  return (uint8_t)((i / 7 + (i % 5)) & 0xFF);
}

#define PREFIX_BYTES 1234
#define SUFFIX_BYTES 777

/// Writes junk, then a framed blob of a [total]-byte medium in blocks of
/// [block_bytes], then more junk, to [path]. Answers the blob's length and
/// each block's compressed length through [lengths].
static int64_t write_framed_fixture(const char* path,
                                    int64_t total,
                                    int64_t block_bytes,
                                    uint32_t* lengths) {
  uint8_t* medium = (uint8_t*)malloc((size_t)total);
  FILE* file = fopen(path, "wb");
  if (medium == NULL || file == NULL) {
    free(medium);
    if (file != NULL) {
      fclose(file);
    }
    return -1;
  }
  for (int64_t i = 0; i < total; i += 1) {
    medium[i] = medium_byte(i);
  }
  for (int i = 0; i < PREFIX_BYTES; i += 1) {
    fputc((i * 13 + 7) & 0xFF, file);
  }
  const int64_t blob =
      qa_fixture_write_framed(file, medium, total, block_bytes, lengths);
  for (int i = 0; i < SUFFIX_BYTES; i += 1) {
    fputc((i * 29 + 3) & 0xFF, file);
  }
  fclose(file);
  free(medium);
  return blob;
}

/// Whether [got] bytes of a window at [position] are the medium's own.
static int window_is_medium(const uint8_t* window, int64_t position,
                            int64_t got) {
  for (int64_t i = 0; i < got; i += 1) {
    if (window[i] != medium_byte(position + i)) {
      return 0;
    }
  }
  return 1;
}

static void test_plain(void) {
  const char* path = "qa_media_span_plain.bin";
  const int64_t total = 5000;
  FILE* file = fopen(path, "wb");
  if (file == NULL) {
    printf("FAIL plain: could not write %s\n", path);
    g_failures += 1;
    return;
  }
  for (int i = 0; i < PREFIX_BYTES; i += 1) {
    fputc(0xEE, file);
  }
  for (int64_t i = 0; i < total; i += 1) {
    fputc(medium_byte(i), file);
  }
  fclose(file);

  qa_media_span* span = qa_media_span_open(path, PREFIX_BYTES, total, 0);
  expect_true("plain: opens", span != NULL);
  if (span != NULL) {
    expect_int("plain: size is the span's", qa_media_span_size(span), total);
    uint8_t window[300];
    expect_int("plain: a window", qa_media_span_read(span, 1000, window, 300),
               300);
    expect_true("plain: base + position, not position",
                window_is_medium(window, 1000, 300));
    expect_int("plain: short at the end",
               qa_media_span_read(span, total - 100, window, 300), 100);
    expect_int("plain: nothing past the end",
               qa_media_span_read(span, total, window, 300), 0);
    qa_media_span_close(span);
  }
  // ⛔A span that runs past the file is refused, not clamped.
  expect_true("plain: a span past the file is refused",
              qa_media_span_open(path, PREFIX_BYTES, total + 1, 0) == NULL);
  remove(path);
}

static void test_framed(void) {
  const char* path = "qa_media_span_framed.bin";
  const int64_t block_bytes = 64 * 1024;
  const int64_t total = block_bytes * 3 + 1000;
  uint32_t lengths[QA_FIXTURE_MAX_BLOCKS];
  const int64_t blob = write_framed_fixture(path, total, block_bytes, lengths);
  expect_true("framed: fixture written", blob > 0);
  if (blob <= 0) {
    return;
  }
  qa_media_span* span = qa_media_span_open(path, PREFIX_BYTES, blob, 1);
  expect_true("framed: opens", span != NULL);
  if (span == NULL) {
    remove(path);
    return;
  }
  expect_int("framed: size is the MEDIUM's", qa_media_span_size(span), total);

  int64_t decoded = 0;
  int64_t read_before = 0;
  qa_media_span_stats(span, &decoded, &read_before);
  expect_int("framed: opening decodes nothing", decoded, 0);

  // A window inside the second block reads that block and nothing else.
  uint8_t window[1000];
  const int64_t at = block_bytes + 12345;
  expect_int("framed: a window", qa_media_span_read(span, at, window, 100),
             100);
  expect_true("framed: the window is the medium's",
              window_is_medium(window, at, 100));
  int64_t read_after = 0;
  qa_media_span_stats(span, &decoded, &read_after);
  expect_int("framed: ONE block decoded", decoded, 1);
  expect_int("framed: and only its stored bytes read",
             read_after - read_before, lengths[1]);

  // Many small windows in that block decode it once.
  for (int64_t p = at; p < at + 6000; p += 400) {
    qa_media_span_read(span, p, window, 300);
  }
  qa_media_span_stats(span, &decoded, NULL);
  expect_int("framed: small windows reuse the block", decoded, 1);

  // A window across a boundary decodes both sides.
  const int64_t across = block_bytes * 2 - 50;
  expect_int("framed: across a boundary",
             qa_media_span_read(span, across, window, 100), 100);
  expect_true("framed: across a boundary is the medium's",
              window_is_medium(window, across, 100));

  // The tail block is short, and a read past the end is short too.
  expect_int("framed: short at the end",
             qa_media_span_read(span, total - 100, window, 1000), 100);
  expect_true("framed: the tail is the medium's",
              window_is_medium(window, total - 100, 100));
  expect_int("framed: nothing past the end",
             qa_media_span_read(span, total, window, 10), 0);
  qa_media_span_close(span);

  // ⛔A blob cut short is refused at the door: its last block would run past
  // the span into whatever follows it in the file.
  expect_true("framed: a torn blob is refused",
              qa_media_span_open(path, PREFIX_BYTES, blob - 10, 1) == NULL);
  // ⛔And the same bytes read as a framed header from the wrong origin are
  // not a medium.
  expect_true("framed: the wrong origin is refused",
              qa_media_span_open(path, 0, blob, 1) == NULL);
  remove(path);
}

static void test_framed_at_another_block_size(void) {
  // ⚠️The reader's authority is the HEADER's block size, never a constant:
  // entries written when the writer used 4MB still live in files.
  const char* path = "qa_media_span_block_size.bin";
  const int64_t block_bytes = 4096;
  const int64_t total = block_bytes * 5 + 17;
  uint32_t lengths[QA_FIXTURE_MAX_BLOCKS];
  const int64_t blob = write_framed_fixture(path, total, block_bytes, lengths);
  qa_media_span* span =
      blob > 0 ? qa_media_span_open(path, PREFIX_BYTES, blob, 1) : NULL;
  expect_true("block size: opens", span != NULL);
  if (span != NULL) {
    uint8_t window[256];
    const int64_t at = block_bytes * 3 + 100;
    expect_int("block size: a window",
               qa_media_span_read(span, at, window, 256), 256);
    expect_true("block size: the window is the medium's",
                window_is_medium(window, at, 256));
    qa_media_span_close(span);
  }
  remove(path);
}

static void test_corrupt_block(void) {
  const char* path = "qa_media_span_corrupt.bin";
  const int64_t block_bytes = 8192;
  const int64_t total = block_bytes * 2;
  uint32_t lengths[QA_FIXTURE_MAX_BLOCKS];
  const int64_t blob = write_framed_fixture(path, total, block_bytes, lengths);
  if (blob <= 0) {
    expect_true("corrupt: fixture written", 0);
    return;
  }
  // Break the second block's frame at its magic number — a flipped byte
  // deeper in could still decode, to the wrong bytes, and prove nothing.
  FILE* file = fopen(path, "r+b");
  if (file != NULL) {
    const long inside = (long)(PREFIX_BYTES + 16 + 4 * 2 + lengths[0]);
    fseek(file, inside, SEEK_SET);
    const int was = fgetc(file);
    fseek(file, inside, SEEK_SET);
    fputc(was ^ 0xFF, file);
    fclose(file);
  }
  qa_media_span* span = qa_media_span_open(path, PREFIX_BYTES, blob, 1);
  expect_true("corrupt: the header still opens", span != NULL);
  if (span != NULL) {
    uint8_t window[64];
    expect_int("corrupt: the good block reads",
               qa_media_span_read(span, 10, window, 64), 64);
    expect_int("corrupt: the broken block says so, it does not guess",
               qa_media_span_read(span, block_bytes + 10, window, 64), -1);
    qa_media_span_close(span);
  }
  remove(path);
}

int main(void) {
  test_plain();
  test_framed();
  test_framed_at_another_block_size();
  test_corrupt_block();
  if (g_failures > 0) {
    printf("%d failure(s)\n", g_failures);
    return 1;
  }
  printf("qa_media_span: all checks passed\n");
  return 0;
}
