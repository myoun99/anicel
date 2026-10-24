// The one serving of a span to MediaExtractor — see qa_ndk_media.h for why
// there is only one.
//
// ↩️Until 2026-10-24 this file also resolved the whole NDK media API by
// dlsym, every symbol looked up and none required here: what a caller
// needed was a set, and the sets differed — refusing the whole library over
// one missing function is how the audio decoder once decoded no AAC at all
// below Android 9 (qa_audio_decode.c). Linked, on an API 29 floor, there
// are no sets left to differ.
//
// ⛔Compiles to nothing off Android, like the other platform-only units.

#if defined(__ANDROID__)

#include "qa_ndk_media.h"

#include <pthread.h>
#include <stdlib.h>

#include "qa_media_span.h"

/// ⚠️LOCKED: the extractor may ask from a thread of its own, and the span
/// reader is ONE reader — its file position and its cached block are shared
/// by every read.
struct qa_ndk_served_span {
  AMediaDataSource* source;
  qa_media_span* span;
  pthread_mutex_t lock;
};

/// `AMediaDataSourceReadAt`: -1 is BOTH the end and a failure, and 0 is only
/// for a zero-byte ask.
static ssize_t qa_ndk_served_read_at(void* user,
                                     off64_t offset,
                                     void* buffer,
                                     size_t size) {
  qa_ndk_served_span* served = (qa_ndk_served_span*)user;
  if (size == 0) {
    return 0;
  }
  pthread_mutex_lock(&served->lock);
  const int64_t read =
      qa_media_span_read(served->span, (int64_t)offset, buffer, (int64_t)size);
  pthread_mutex_unlock(&served->lock);
  return read > 0 ? (ssize_t)read : -1;
}

static ssize_t qa_ndk_served_size(void* user) {
  return (ssize_t)qa_media_span_size(((qa_ndk_served_span*)user)->span);
}

void qa_ndk_served_span_free(qa_ndk_served_span* served) {
  if (served == NULL) {
    return;
  }
  if (served->source != NULL) {
    AMediaDataSource_delete(served->source);
  }
  qa_media_span_close(served->span);
  pthread_mutex_destroy(&served->lock);
  free(served);
}

qa_ndk_served_span* qa_ndk_served_span_open(const char* utf8_path,
                                            int64_t offset,
                                            int64_t length,
                                            int32_t framed) {
  qa_ndk_served_span* served =
      (qa_ndk_served_span*)calloc(1, sizeof(*served));
  if (served == NULL) {
    return NULL;
  }
  served->span = qa_media_span_open(utf8_path, offset, length, framed);
  if (served->span == NULL) {
    free(served);
    return NULL;
  }
  pthread_mutex_init(&served->lock, NULL);
  served->source = AMediaDataSource_new();
  if (served->source == NULL) {
    qa_ndk_served_span_free(served);
    return NULL;
  }
  AMediaDataSource_setUserdata(served->source, served);
  AMediaDataSource_setReadAt(served->source, qa_ndk_served_read_at);
  AMediaDataSource_setGetSize(served->source, qa_ndk_served_size);
  return served;
}

AMediaDataSource* qa_ndk_served_span_source(const qa_ndk_served_span* served) {
  return served == NULL ? NULL : served->source;
}

#endif  // __ANDROID__
