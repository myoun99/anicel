// An IMFByteStream over a RANGE of a file — the Windows half of opening a
// movie that lives inside the project file.
//
// 🚨★★★**WHY THIS EXISTS AT ALL.** Media Foundation opens a URL or a byte
// stream, and it ships no stream over a SUB-RANGE: `MFCreateFile` covers the
// whole thing. A carried video's bytes are a stretch of the `.anicel`, so
//「the whole file」 is a ZIP and the reader would fail somewhere far from
// the cause. The other two platforms have their own answers — Android takes
// a descriptor and a range outright, Apple needs a resource loader — and
// this is Windows's.
//
// ⛔Its own translation unit rather than 200 more lines inside
// `qa_video_decode.c`: that file is the DECODE LAW plus three thin backends,
// and hand-written COM is neither.
//
// One object, one reader, one document at a time — the decoder's own
// contract, so nothing here is shared between threads.

#if defined(_WIN32)

#define COBJMACROS
#include <windows.h>
#include <mfapi.h>
#include <mfidl.h>
#include <mfobjects.h>

#include <stdint.h>

typedef struct {
  // ⚠️FIRST, and that is not style: a COM interface pointer IS a pointer to
  // its vtable pointer, so this cast has to be free.
  const IMFByteStreamVtbl* lpVtbl;
  LONG ref;
  HANDLE file;
  /// Where the movie starts inside the file, and how long it is. Every
  /// position below is relative to [base] — the stream is the RANGE, and
  /// nothing above it ever learns the range is not the whole file.
  int64_t base;
  int64_t length;
  int64_t position;
  /// What the last [BeginRead] read, for the [EndRead] that follows it.
  ///
  /// ⚠️One outstanding read at a time. The source reader issues them in
  /// sequence against a stream that answers immediately, and a stream that
  /// reports no async capability is not asked to overlap them.
  ULONG pending;
} qa_range_stream;

static qa_range_stream* qa_range_of(IMFByteStream* self) {
  return (qa_range_stream*)self;
}

static HRESULT STDMETHODCALLTYPE qa_range_query(IMFByteStream* self,
                                                REFIID riid,
                                                void** out) {
  if (out == NULL) {
    return E_POINTER;
  }
  if (IsEqualGUID(riid, &IID_IUnknown) ||
      IsEqualGUID(riid, &IID_IMFByteStream)) {
    *out = self;
    IMFByteStream_AddRef(self);
    return S_OK;
  }
  *out = NULL;
  return E_NOINTERFACE;
}

static ULONG STDMETHODCALLTYPE qa_range_add_ref(IMFByteStream* self) {
  return (ULONG)InterlockedIncrement(&qa_range_of(self)->ref);
}

static ULONG STDMETHODCALLTYPE qa_range_release(IMFByteStream* self) {
  qa_range_stream* stream = qa_range_of(self);
  const LONG left = InterlockedDecrement(&stream->ref);
  if (left == 0) {
    if (stream->file != INVALID_HANDLE_VALUE) {
      CloseHandle(stream->file);
    }
    free(stream);
  }
  return (ULONG)left;
}

static HRESULT STDMETHODCALLTYPE
qa_range_capabilities(IMFByteStream* self, DWORD* capabilities) {
  (void)self;
  if (capabilities == NULL) {
    return E_POINTER;
  }
  // ⛔No MFBYTESTREAM_HAS_SLOW_SEEK and no partial-download flags: this is a
  // local file, and claiming otherwise makes the source reader buffer for a
  // network that is not there.
  *capabilities = MFBYTESTREAM_IS_READABLE | MFBYTESTREAM_IS_SEEKABLE;
  return S_OK;
}

static HRESULT STDMETHODCALLTYPE qa_range_get_length(IMFByteStream* self,
                                                     QWORD* length) {
  if (length == NULL) {
    return E_POINTER;
  }
  *length = (QWORD)qa_range_of(self)->length;
  return S_OK;
}

static HRESULT STDMETHODCALLTYPE qa_range_set_length(IMFByteStream* self,
                                                     QWORD length) {
  (void)self;
  (void)length;
  // A range inside somebody else's file does not grow.
  return E_NOTIMPL;
}

static HRESULT STDMETHODCALLTYPE qa_range_get_position(IMFByteStream* self,
                                                       QWORD* position) {
  if (position == NULL) {
    return E_POINTER;
  }
  *position = (QWORD)qa_range_of(self)->position;
  return S_OK;
}

static HRESULT STDMETHODCALLTYPE qa_range_set_position(IMFByteStream* self,
                                                       QWORD position) {
  qa_range_stream* stream = qa_range_of(self);
  // ⚠️CLAMPED, not refused. A reader probing past the end is ordinary — it
  // is how it finds the end — and an error there reads as a broken file.
  int64_t wanted = (int64_t)position;
  if (wanted < 0) {
    wanted = 0;
  }
  if (wanted > stream->length) {
    wanted = stream->length;
  }
  stream->position = wanted;
  return S_OK;
}

static HRESULT STDMETHODCALLTYPE qa_range_is_end(IMFByteStream* self,
                                                 BOOL* end) {
  if (end == NULL) {
    return E_POINTER;
  }
  qa_range_stream* stream = qa_range_of(self);
  *end = stream->position >= stream->length ? TRUE : FALSE;
  return S_OK;
}

/// The one place bytes actually move. Everything else is bookkeeping.
static HRESULT qa_range_read_at(qa_range_stream* stream,
                                BYTE* into,
                                ULONG want,
                                ULONG* got) {
  *got = 0;
  const int64_t left = stream->length - stream->position;
  if (left <= 0 || want == 0) {
    return S_OK;
  }
  const ULONG take = (int64_t)want > left ? (ULONG)left : want;
  // 🚨The file offset is base + position. Reading at `position` alone is the
  // bug this whole file exists to make impossible — it would hand back the
  // archive's own header as if it were the movie.
  OVERLAPPED where;
  memset(&where, 0, sizeof(where));
  const int64_t at = stream->base + stream->position;
  where.Offset = (DWORD)(at & 0xFFFFFFFF);
  where.OffsetHigh = (DWORD)((at >> 32) & 0xFFFFFFFF);
  DWORD read = 0;
  if (!ReadFile(stream->file, into, take, &read, &where)) {
    return HRESULT_FROM_WIN32(GetLastError());
  }
  stream->position += (int64_t)read;
  *got = read;
  return S_OK;
}

static HRESULT STDMETHODCALLTYPE qa_range_read(IMFByteStream* self,
                                               BYTE* into,
                                               ULONG want,
                                               ULONG* got) {
  if (into == NULL || got == NULL) {
    return E_POINTER;
  }
  return qa_range_read_at(qa_range_of(self), into, want, got);
}

static HRESULT STDMETHODCALLTYPE qa_range_begin_read(IMFByteStream* self,
                                                     BYTE* into,
                                                     ULONG want,
                                                     IMFAsyncCallback* callback,
                                                     IUnknown* state) {
  // ⛔NOT E_NOTIMPL. The source reader is free to use the async pair, and a
  // stream that refuses it can fail to open a file it can plainly read. The
  // read happens NOW — a local file has nothing to wait for — and the
  // callback is invoked so the caller's shape is honoured.
  if (into == NULL || callback == NULL) {
    return E_POINTER;
  }
  qa_range_stream* stream = qa_range_of(self);
  ULONG got = 0;
  const HRESULT read = qa_range_read_at(stream, into, want, &got);
  if (FAILED(read)) {
    return read;
  }
  stream->pending = got;
  IMFAsyncResult* result = NULL;
  const HRESULT made = MFCreateAsyncResult(NULL, callback, state, &result);
  if (FAILED(made)) {
    return made;
  }
  const HRESULT invoked = MFInvokeCallback(result);
  IMFAsyncResult_Release(result);
  return invoked;
}

static HRESULT STDMETHODCALLTYPE qa_range_end_read(IMFByteStream* self,
                                                   IMFAsyncResult* result,
                                                   ULONG* got) {
  (void)result;
  if (got == NULL) {
    return E_POINTER;
  }
  *got = qa_range_of(self)->pending;
  return S_OK;
}

static HRESULT STDMETHODCALLTYPE qa_range_write(IMFByteStream* self,
                                                const BYTE* from,
                                                ULONG want,
                                                ULONG* wrote) {
  (void)self;
  (void)from;
  (void)want;
  (void)wrote;
  return E_NOTIMPL;
}

static HRESULT STDMETHODCALLTYPE
qa_range_begin_write(IMFByteStream* self,
                     const BYTE* from,
                     ULONG want,
                     IMFAsyncCallback* callback,
                     IUnknown* state) {
  (void)self;
  (void)from;
  (void)want;
  (void)callback;
  (void)state;
  return E_NOTIMPL;
}

static HRESULT STDMETHODCALLTYPE qa_range_end_write(IMFByteStream* self,
                                                    IMFAsyncResult* result,
                                                    ULONG* wrote) {
  (void)self;
  (void)result;
  (void)wrote;
  return E_NOTIMPL;
}

static HRESULT STDMETHODCALLTYPE qa_range_seek(IMFByteStream* self,
                                               MFBYTESTREAM_SEEK_ORIGIN origin,
                                               LONGLONG move,
                                               DWORD flags,
                                               QWORD* landed) {
  (void)flags;
  qa_range_stream* stream = qa_range_of(self);
  const int64_t from =
      origin == msoCurrent ? stream->position : 0;
  HRESULT set = qa_range_set_position(self, (QWORD)(from + move));
  if (landed != NULL) {
    *landed = (QWORD)stream->position;
  }
  return set;
}

static HRESULT STDMETHODCALLTYPE qa_range_flush(IMFByteStream* self) {
  (void)self;
  return S_OK;
}

static HRESULT STDMETHODCALLTYPE qa_range_close(IMFByteStream* self) {
  qa_range_stream* stream = qa_range_of(self);
  if (stream->file != INVALID_HANDLE_VALUE) {
    CloseHandle(stream->file);
    stream->file = INVALID_HANDLE_VALUE;
  }
  return S_OK;
}

// ⚠️ORDER IS THE INTERFACE. A vtable is positional: one entry out of place
// and the reader calls Write where it meant Read, with no compiler to say
// so. This list is `IMFByteStream`'s declaration order, IUnknown first.
static const IMFByteStreamVtbl qa_range_vtbl = {
    qa_range_query,        qa_range_add_ref,      qa_range_release,
    qa_range_capabilities, qa_range_get_length,   qa_range_set_length,
    qa_range_get_position, qa_range_set_position, qa_range_is_end,
    qa_range_read,         qa_range_begin_read,   qa_range_end_read,
    qa_range_write,        qa_range_begin_write,  qa_range_end_write,
    qa_range_seek,         qa_range_flush,        qa_range_close,
};

/// A readable, seekable stream over `[offset, offset + length)` of [path],
/// or NULL. The caller owns one reference.
///
/// ⚠️`FILE_SHARE_READ | FILE_SHARE_WRITE`: the file being read from is the
/// project the app is still using, and refusing to share it would make
/// opening a carried movie lock the save out.
IMFByteStream* qa_win_range_stream_create(const wchar_t* path,
                                          int64_t offset,
                                          int64_t length) {
  if (path == NULL || offset < 0 || length <= 0) {
    return NULL;
  }
  const HANDLE file =
      CreateFileW(path, GENERIC_READ, FILE_SHARE_READ | FILE_SHARE_WRITE, NULL,
                  OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, NULL);
  if (file == INVALID_HANDLE_VALUE) {
    return NULL;
  }
  LARGE_INTEGER size;
  if (!GetFileSizeEx(file, &size) || offset + length > size.QuadPart) {
    // ⛔The range must be INSIDE the file. A stream that reports a length
    // the file cannot supply turns into a truncated movie rather than a
    // refusal, and a truncated movie looks like a corrupt one.
    CloseHandle(file);
    return NULL;
  }
  qa_range_stream* stream = (qa_range_stream*)calloc(1, sizeof(*stream));
  if (stream == NULL) {
    CloseHandle(file);
    return NULL;
  }
  stream->lpVtbl = &qa_range_vtbl;
  stream->ref = 1;
  stream->file = file;
  stream->base = offset;
  stream->length = length;
  stream->position = 0;
  return (IMFByteStream*)stream;
}

#endif  // _WIN32
