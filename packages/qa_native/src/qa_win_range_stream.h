// The Windows byte stream over a medium stored in a span of a file — see
// qa_win_range_stream.c. ⚠️One declaration for every caller: the video
// decoder, the audio decoder and the stream's own test each spelled it as an
// `extern` of their own, and a signature change would have had to find all
// three.

#ifndef QA_WIN_RANGE_STREAM_H
#define QA_WIN_RANGE_STREAM_H

#if defined(_WIN32)

#include <stdint.h>

#include <mfobjects.h>

/// A readable, seekable stream over the medium stored in
/// `[offset, offset + length)` of [utf8_path] — its own bytes, or a framed
/// blob of them when [framed] — or NULL. The caller owns one reference.
IMFByteStream* qa_win_range_stream_create(const char* utf8_path,
                                          int64_t offset,
                                          int64_t length,
                                          int32_t framed);

#endif  // _WIN32

#endif  // QA_WIN_RANGE_STREAM_H
