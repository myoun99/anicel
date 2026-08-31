// The range byte stream, driven for real.
//
// 🚨★★★**THIS IS WHERE THE BYTE ARITHMETIC IS.** Everything else about
// opening a movie inside the project file is one API call per platform; the
// Windows half is a hand-written COM object whose whole job is「file offset
// = base + position」and「never read past the range」. Get either wrong and
// the reader is handed the archive's own header, or half a movie, and both
// look like a corrupt file rather than a bug in here.
//
// ⛔Windows only, and unlike `qa_video_decode_law_test` this one WANTS the
// platform under it: the object being tested IS Media Foundation's
// interface, and there is nothing portable to check.

#if defined(_WIN32)

#define COBJMACROS
#include <windows.h>
#include <mfapi.h>
#include <mfidl.h>
#include <mfobjects.h>

#include <stdint.h>
#include <stdio.h>
#include <string.h>

extern IMFByteStream* qa_win_range_stream_create(const wchar_t* path,
                                                 int64_t offset,
                                                 int64_t length);

static int g_failures;

static void expect_int(const char* what, long long got, long long want) {
  if (got == want) {
    return;
  }
  printf("FAIL %s: got %lld, want %lld\n", what, got, want);
  g_failures += 1;
}

/// The fixture's byte at [at] — a pattern with a long period, so an
/// off-by-a-few in the base offset cannot land on the same value by luck.
static uint8_t pattern_byte(int64_t at) {
  return (uint8_t)((at * 7 + (at >> 8) * 31) & 0xFF);
}

#define FIXTURE_BYTES 8192
#define RANGE_BASE 1000
#define RANGE_LEN 500

// ---------------------------------------------------------------------------
// The smallest IMFAsyncCallback that can be invoked, so BeginRead/EndRead —
// the pair a source reader may well use, and the one an E_NOTIMPL would have
// quietly broken — can be exercised rather than assumed.

typedef struct {
  const IMFAsyncCallbackVtbl* lpVtbl;
  LONG ref;
  LONG invoked;
} qa_test_callback;

static HRESULT STDMETHODCALLTYPE cb_query(IMFAsyncCallback* self,
                                          REFIID riid,
                                          void** out) {
  if (out == NULL) {
    return E_POINTER;
  }
  if (IsEqualGUID(riid, &IID_IUnknown) ||
      IsEqualGUID(riid, &IID_IMFAsyncCallback)) {
    *out = self;
    return S_OK;
  }
  *out = NULL;
  return E_NOINTERFACE;
}

static ULONG STDMETHODCALLTYPE cb_add_ref(IMFAsyncCallback* self) {
  return (ULONG)InterlockedIncrement(&((qa_test_callback*)self)->ref);
}

static ULONG STDMETHODCALLTYPE cb_release(IMFAsyncCallback* self) {
  return (ULONG)InterlockedDecrement(&((qa_test_callback*)self)->ref);
}

static HRESULT STDMETHODCALLTYPE cb_parameters(IMFAsyncCallback* self,
                                               DWORD* flags,
                                               DWORD* queue) {
  (void)self;
  (void)flags;
  (void)queue;
  return E_NOTIMPL;  // "use the defaults" — the documented answer.
}

static HRESULT STDMETHODCALLTYPE cb_invoke(IMFAsyncCallback* self,
                                           IMFAsyncResult* result) {
  (void)result;
  InterlockedIncrement(&((qa_test_callback*)self)->invoked);
  return S_OK;
}

static const IMFAsyncCallbackVtbl qa_test_callback_vtbl = {
    cb_query, cb_add_ref, cb_release, cb_parameters, cb_invoke,
};

int main(void) {
  wchar_t directory[MAX_PATH];
  wchar_t fixture[MAX_PATH];
  if (GetTempPathW(MAX_PATH, directory) == 0 ||
      GetTempFileNameW(directory, L"qar", 0, fixture) == 0) {
    printf("FAIL fixture: no temp file\n");
    return 1;
  }
  {
    uint8_t bytes[FIXTURE_BYTES];
    for (int64_t at = 0; at < FIXTURE_BYTES; at += 1) {
      bytes[at] = pattern_byte(at);
    }
    const HANDLE file =
        CreateFileW(fixture, GENERIC_WRITE, 0, NULL, CREATE_ALWAYS,
                    FILE_ATTRIBUTE_NORMAL, NULL);
    DWORD wrote = 0;
    if (file == INVALID_HANDLE_VALUE ||
        !WriteFile(file, bytes, FIXTURE_BYTES, &wrote, NULL) ||
        wrote != FIXTURE_BYTES) {
      printf("FAIL fixture: could not write %d bytes\n", FIXTURE_BYTES);
      return 1;
    }
    CloseHandle(file);
  }

  IMFByteStream* stream =
      qa_win_range_stream_create(fixture, RANGE_BASE, RANGE_LEN);
  if (stream == NULL) {
    printf("FAIL fixture: the stream would not open\n");
    DeleteFileW(fixture);
    return 1;
  }

  // 🚨THE LENGTH IS THE RANGE'S, not the file's. Reporting the file's is how
  // a reader walks off the end of the movie into whatever follows it.
  QWORD length = 0;
  IMFByteStream_GetLength(stream, &length);
  expect_int("the stream is as long as the range", (long long)length,
             RANGE_LEN);

  DWORD capabilities = 0;
  IMFByteStream_GetCapabilities(stream, &capabilities);
  expect_int("readable", (capabilities & MFBYTESTREAM_IS_READABLE) != 0, 1);
  expect_int("seekable", (capabilities & MFBYTESTREAM_IS_SEEKABLE) != 0, 1);

  // A read at the start must land on the RANGE's first byte.
  uint8_t got[64];
  ULONG read = 0;
  IMFByteStream_Read(stream, got, 16, &read);
  expect_int("a first read gets what was asked for", read, 16);
  for (int i = 0; i < 16; i += 1) {
    expect_int("the first bytes are the range's own", got[i],
               pattern_byte(RANGE_BASE + i));
  }

  // ⚠️THE CLAMP. Asking for more than the range holds must hand back only
  // what is inside it — the bytes after are somebody else's file.
  IMFByteStream_SetCurrentPosition(stream, RANGE_LEN - 10);
  read = 0;
  IMFByteStream_Read(stream, got, 40, &read);
  expect_int("a read past the end stops at the end", read, 10);
  for (int i = 0; i < 10; i += 1) {
    expect_int("and the last bytes are still the range's", got[i],
               pattern_byte(RANGE_BASE + RANGE_LEN - 10 + i));
  }
  BOOL ended = FALSE;
  IMFByteStream_IsEndOfStream(stream, &ended);
  expect_int("and the stream says it is at the end", ended ? 1 : 0, 1);

  // Seeking is relative to the RANGE, both ways.
  QWORD landed = 0;
  IMFByteStream_Seek(stream, msoBegin, 100, 0, &landed);
  expect_int("seek from the beginning lands inside the range",
             (long long)landed, 100);
  read = 0;
  IMFByteStream_Read(stream, got, 4, &read);
  expect_int("and reads from there", read, 4);
  expect_int("with the range's bytes", got[0], pattern_byte(RANGE_BASE + 100));
  IMFByteStream_Seek(stream, msoCurrent, -4, 0, &landed);
  expect_int("a backward seek is relative to where we are",
             (long long)landed, 100);

  // 🚨BEGIN/END READ. A source reader is free to use the async pair, and
  // returning E_NOTIMPL there can fail to open a file the stream can plainly
  // read — so the pair is implemented, and therefore has to be checked.
  if (SUCCEEDED(MFStartup(MF_VERSION, MFSTARTUP_LITE))) {
    qa_test_callback callback;
    callback.lpVtbl = &qa_test_callback_vtbl;
    callback.ref = 1;
    callback.invoked = 0;
    IMFByteStream_SetCurrentPosition(stream, 200);
    memset(got, 0, sizeof(got));
    const HRESULT began = IMFByteStream_BeginRead(
        stream, got, 8, (IMFAsyncCallback*)&callback, NULL);
    expect_int("BeginRead succeeds", SUCCEEDED(began) ? 1 : 0, 1);
    // ⚠️`MFInvokeCallback` QUEUES the callback; it does not call it. The
    // first draft of this test asserted the count right here and failed —
    // correctly. The bytes are already in the buffer either way (the read
    // itself is synchronous), so what is being waited for is the
    // notification, and a caller that never gets it would hang forever.
    for (int spin = 0; spin < 2000 && callback.invoked == 0; spin += 1) {
      Sleep(1);
    }
    expect_int("and the callback is invoked", callback.invoked, 1);
    ULONG ended_read = 0;
    IMFByteStream_EndRead(stream, NULL, &ended_read);
    expect_int("EndRead reports what was read", ended_read, 8);
    for (int i = 0; i < 8; i += 1) {
      expect_int("and the async read filled the buffer with range bytes",
                 got[i], pattern_byte(RANGE_BASE + 200 + i));
    }
    MFShutdown();
  } else {
    printf("FAIL BeginRead: Media Foundation would not start\n");
    g_failures += 1;
  }

  IMFByteStream_Release(stream);

  // ⛔A range that runs past the end of the file is refused, not truncated:
  // a stream promising bytes the file cannot supply turns into a movie that
  // looks corrupt instead of a range that was wrong.
  IMFByteStream* past =
      qa_win_range_stream_create(fixture, FIXTURE_BYTES - 10, 100);
  expect_int("a range past the end is refused", past == NULL ? 1 : 0, 1);
  if (past != NULL) {
    IMFByteStream_Release(past);
  }
  IMFByteStream* exact =
      qa_win_range_stream_create(fixture, FIXTURE_BYTES - 100, 100);
  expect_int("a range ending exactly at the end is fine",
             exact == NULL ? 0 : 1, 1);
  if (exact != NULL) {
    IMFByteStream_Release(exact);
  }

  DeleteFileW(fixture);
  if (g_failures == 0) {
    printf("qa_win_range_stream: all checks passed\n");
    return 0;
  }
  printf("qa_win_range_stream: %d check(s) failed\n", g_failures);
  return 1;
}

#else
int main(void) { return 0; }
#endif
