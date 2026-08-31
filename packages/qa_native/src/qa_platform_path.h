// A path crosses into native code as UTF-8, and becomes wide EXACTLY ONCE.
//
// 🚨★★★THIS IS THE KOREAN-FILENAME ANSWER, and it is a header rather than a
// comment because the bug is a SECOND COPY, not a missing one. Windows has
// two personalities for `const char*` — UTF-8 or the machine's local
// codepage — and `fopen`/`CreateFileA` pick the second. On a Korean or
// Japanese Windows a file whose name is not ASCII then fails to open with an
// error that says nothing about encoding. The audio decoder avoided the
// question for a year by refusing paths altogether; the video decoder had to
// answer it, and this is that answer lifted out so there is one of it.
//
// ⛔Do not widen a path any other way, and do not call the `*A` or narrow
// stdio entry points with one. Everything platform-specific about a path
// lives here.
//
// Header-only and `static`: it is three short functions, and a translation
// unit of its own would buy a link dependency and nothing else.

#ifndef QA_PLATFORM_PATH_H
#define QA_PLATFORM_PATH_H

#include <stdint.h>
#include <stdio.h>
#include <sys/types.h>

#if defined(_WIN32)

#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#include <windows.h>

/// UTF-8 [path] into [wide], or 0 when it is not valid UTF-8 or does not fit.
///
/// [capacity] counts wchar_t, not bytes. ⚠️A path that does not fit FAILS
/// rather than truncating: half a path names a different file, and opening
/// the wrong one is worse than not opening.
static inline int qa_widen_path(const char* path, wchar_t* wide, int capacity) {
  if (path == NULL || wide == NULL || capacity <= 0) {
    return 0;
  }
  return MultiByteToWideChar(CP_UTF8, 0, path, -1, wide, capacity) != 0;
}

/// `fopen` for a UTF-8 path. Read-only binary is the only mode anything here
/// needs, so it is not a parameter nobody varies.
static inline FILE* qa_open_path_read(const char* path) {
  wchar_t wide[1024];
  if (!qa_widen_path(path, wide, (int)(sizeof(wide) / sizeof(wide[0])))) {
    return NULL;
  }
  return _wfopen(wide, L"rb");
}

/// Positions [file] at absolute [offset], or 0 if it will not go.
///
/// 🚨★★★**NOT `fseek`.** Its offset is a `long`, which is 32 bits on Windows
/// however wide the machine is — so a seek past 2GB silently fails or wraps.
/// The files this reaches into are project archives holding movies; two
/// gigabytes is a size a real one has, not a theoretical bound.
static inline int qa_seek_absolute(FILE* file, int64_t offset) {
  return offset >= 0 && _fseeki64(file, offset, SEEK_SET) == 0;
}

/// How many bytes [file] holds, or -1. Leaves the position at the end —
/// callers here seek before they read.
static inline int64_t qa_file_size(FILE* file) {
  if (_fseeki64(file, 0, SEEK_END) != 0) {
    return -1;
  }
  return (int64_t)_ftelli64(file);
}

#else

/// Everywhere else a path is bytes and `fopen` takes those bytes. There is
/// no second personality to choose between.
static inline FILE* qa_open_path_read(const char* path) {
  if (path == NULL) {
    return NULL;
  }
  return fopen(path, "rb");
}

/// Positions [file] at absolute [offset], or 0 if it will not go.
///
/// `fseeko` rather than `fseek` for the reason above: the offset is `off_t`,
/// which is 64 bits on every 64-bit target. ⚠️On a 32-bit build (armeabi-v7a)
/// `off_t` is 32 bits unless the whole TU is compiled with
/// `_FILE_OFFSET_BITS=64`, so the reach there is 2GB — a real limit, stated
/// rather than hidden, and one no phone-sized project has met.
static inline int qa_seek_absolute(FILE* file, int64_t offset) {
  return offset >= 0 && fseeko(file, (off_t)offset, SEEK_SET) == 0;
}

/// How many bytes [file] holds, or -1. Leaves the position at the end —
/// callers here seek before they read.
static inline int64_t qa_file_size(FILE* file) {
  if (fseeko(file, 0, SEEK_END) != 0) {
    return -1;
  }
  return (int64_t)ftello(file);
}

#endif

#endif  // QA_PLATFORM_PATH_H
