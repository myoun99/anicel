// The one resolution of the NDK media API — see qa_ndk_media.h for why
// there is only one.
//
// ⛔Compiles to nothing off Android, like the other platform-only units.

#if defined(__ANDROID__)

#include "qa_ndk_media.h"

#include <dlfcn.h>
#include <pthread.h>
#include <string.h>

static qa_ndk_media_api g_api;
static int g_opened = 0;
static pthread_once_t g_once = PTHREAD_ONCE_INIT;

/// ⚠️EVERY symbol is looked up and NONE is required here. What a caller
/// needs is a set, and the three sets differ — the encoder never asks for
/// an extractor, a decoder never asks for a muxer — so refusing the whole
/// library over one missing function is how a capability was lost that had
/// nothing to do with it (the audio decoder once required the API 28 custom
/// source and so decoded no AAC at all below Android 9). The capability
/// questions below answer for each set.
static void qa_ndk_media_resolve(void) {
  memset(&g_api, 0, sizeof(g_api));
  void* library = dlopen("libmediandk.so", RTLD_NOW);
  if (library == NULL) {
    return;
  }
#define QA_NDK_SYM(field, name) *(void**)(&g_api.field) = dlsym(library, name);
  QA_NDK_SYM(extractor_new, "AMediaExtractor_new")
  QA_NDK_SYM(extractor_delete, "AMediaExtractor_delete")
  QA_NDK_SYM(extractor_set_source, "AMediaExtractor_setDataSource")
  QA_NDK_SYM(extractor_set_source_fd, "AMediaExtractor_setDataSourceFd")
  QA_NDK_SYM(extractor_set_source_custom, "AMediaExtractor_setDataSourceCustom")
  QA_NDK_SYM(extractor_track_count, "AMediaExtractor_getTrackCount")
  QA_NDK_SYM(extractor_track_format, "AMediaExtractor_getTrackFormat")
  QA_NDK_SYM(extractor_select_track, "AMediaExtractor_selectTrack")
  QA_NDK_SYM(extractor_seek_to, "AMediaExtractor_seekTo")
  QA_NDK_SYM(extractor_read_sample, "AMediaExtractor_readSampleData")
  QA_NDK_SYM(extractor_sample_time, "AMediaExtractor_getSampleTime")
  QA_NDK_SYM(extractor_advance, "AMediaExtractor_advance")

  QA_NDK_SYM(codec_create_decoder, "AMediaCodec_createDecoderByType")
  QA_NDK_SYM(codec_create_encoder, "AMediaCodec_createEncoderByType")
  QA_NDK_SYM(codec_delete, "AMediaCodec_delete")
  QA_NDK_SYM(codec_configure, "AMediaCodec_configure")
  QA_NDK_SYM(codec_start, "AMediaCodec_start")
  QA_NDK_SYM(codec_stop, "AMediaCodec_stop")
  QA_NDK_SYM(codec_flush, "AMediaCodec_flush")
  QA_NDK_SYM(codec_dequeue_input, "AMediaCodec_dequeueInputBuffer")
  QA_NDK_SYM(codec_input_buffer, "AMediaCodec_getInputBuffer")
  QA_NDK_SYM(codec_queue_input, "AMediaCodec_queueInputBuffer")
  QA_NDK_SYM(codec_dequeue_output, "AMediaCodec_dequeueOutputBuffer")
  QA_NDK_SYM(codec_output_buffer, "AMediaCodec_getOutputBuffer")
  QA_NDK_SYM(codec_release_output, "AMediaCodec_releaseOutputBuffer")
  QA_NDK_SYM(codec_output_format, "AMediaCodec_getOutputFormat")

  QA_NDK_SYM(format_new, "AMediaFormat_new")
  QA_NDK_SYM(format_delete, "AMediaFormat_delete")
  QA_NDK_SYM(format_get_int32, "AMediaFormat_getInt32")
  QA_NDK_SYM(format_get_int64, "AMediaFormat_getInt64")
  QA_NDK_SYM(format_get_float, "AMediaFormat_getFloat")
  QA_NDK_SYM(format_get_string, "AMediaFormat_getString")
  QA_NDK_SYM(format_set_string, "AMediaFormat_setString")
  QA_NDK_SYM(format_set_int32, "AMediaFormat_setInt32")

  QA_NDK_SYM(muxer_new, "AMediaMuxer_new")
  QA_NDK_SYM(muxer_add_track, "AMediaMuxer_addTrack")
  QA_NDK_SYM(muxer_start, "AMediaMuxer_start")
  QA_NDK_SYM(muxer_stop, "AMediaMuxer_stop")
  QA_NDK_SYM(muxer_delete, "AMediaMuxer_delete")
  QA_NDK_SYM(muxer_write, "AMediaMuxer_writeSampleData")

  QA_NDK_SYM(source_new, "AMediaDataSource_new")
  QA_NDK_SYM(source_delete, "AMediaDataSource_delete")
  QA_NDK_SYM(source_set_userdata, "AMediaDataSource_setUserdata")
  QA_NDK_SYM(source_set_read_at, "AMediaDataSource_setReadAt")
  QA_NDK_SYM(source_set_get_size, "AMediaDataSource_setGetSize")
  QA_NDK_SYM(source_set_close, "AMediaDataSource_setClose")
#undef QA_NDK_SYM
  // ⚠️Never dlclose'd: the table points into it for the life of the process,
  // and every caller holds those pointers without a reference of its own.
  g_opened = 1;
}

const qa_ndk_media_api* qa_ndk_media(void) {
  pthread_once(&g_once, qa_ndk_media_resolve);
  return g_opened ? &g_api : NULL;
}

int qa_ndk_media_decodes(const qa_ndk_media_api* api) {
  return api != NULL && api->extractor_new != NULL &&
         api->extractor_delete != NULL &&
         api->extractor_set_source != NULL &&
         api->extractor_set_source_fd != NULL &&
         api->extractor_track_count != NULL &&
         api->extractor_track_format != NULL &&
         api->extractor_select_track != NULL &&
         api->extractor_seek_to != NULL &&
         api->extractor_read_sample != NULL &&
         api->extractor_sample_time != NULL &&
         api->extractor_advance != NULL &&
         api->codec_create_decoder != NULL && api->codec_delete != NULL &&
         api->codec_configure != NULL && api->codec_start != NULL &&
         api->codec_stop != NULL && api->codec_flush != NULL &&
         api->codec_dequeue_input != NULL &&
         api->codec_input_buffer != NULL &&
         api->codec_queue_input != NULL &&
         api->codec_dequeue_output != NULL &&
         api->codec_output_buffer != NULL &&
         api->codec_release_output != NULL &&
         api->codec_output_format != NULL && api->format_delete != NULL &&
         api->format_get_int32 != NULL && api->format_get_int64 != NULL &&
         api->format_get_string != NULL;
}

int qa_ndk_media_encodes(const qa_ndk_media_api* api) {
  return api != NULL && api->codec_create_encoder != NULL &&
         api->codec_delete != NULL && api->codec_configure != NULL &&
         api->codec_start != NULL && api->codec_stop != NULL &&
         api->codec_dequeue_input != NULL &&
         api->codec_input_buffer != NULL &&
         api->codec_queue_input != NULL &&
         api->codec_dequeue_output != NULL &&
         api->codec_output_buffer != NULL &&
         api->codec_release_output != NULL &&
         api->codec_output_format != NULL && api->format_new != NULL &&
         api->format_delete != NULL && api->format_set_string != NULL &&
         api->format_set_int32 != NULL && api->muxer_new != NULL &&
         api->muxer_add_track != NULL && api->muxer_start != NULL &&
         api->muxer_stop != NULL && api->muxer_delete != NULL &&
         api->muxer_write != NULL;
}

int qa_ndk_media_reads_custom(const qa_ndk_media_api* api) {
  return api != NULL && api->extractor_set_source_custom != NULL &&
         api->source_new != NULL && api->source_delete != NULL &&
         api->source_set_userdata != NULL &&
         api->source_set_read_at != NULL &&
         api->source_set_get_size != NULL;
}

#endif  // __ANDROID__
