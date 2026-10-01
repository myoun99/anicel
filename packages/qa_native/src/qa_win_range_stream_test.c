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

#include "qa_framed_fixture.h"
#include "qa_win_range_stream.h"

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
  /// What a real caller does in its callback: finishes the read it began,
  /// on the stream it began it on, with the result it was handed.
  IMFByteStream* stream;
  ULONG ended;
  /// Held shut until the test lets the callback go on — null: at once.
  HANDLE go;
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
  qa_test_callback* callback = (qa_test_callback*)self;
  if (callback->go != NULL) {
    // Bounded: a test that forgot to open the gate fails, it does not hang.
    WaitForSingleObject(callback->go, 5000);
  }
  ULONG ended = 0;
  IMFByteStream_EndRead(callback->stream, result, &ended);
  callback->ended = ended;
  InterlockedIncrement(&callback->invoked);
  return S_OK;
}

static const IMFAsyncCallbackVtbl qa_test_callback_vtbl = {
    cb_query, cb_add_ref, cb_release, cb_parameters, cb_invoke,
};

static qa_test_callback callback_on(IMFByteStream* stream, HANDLE go) {
  qa_test_callback callback;
  callback.lpVtbl = &qa_test_callback_vtbl;
  callback.ref = 1;
  callback.invoked = 0;
  callback.stream = stream;
  callback.ended = 0;
  callback.go = go;
  return callback;
}

/// ⚠️`MFInvokeCallback` QUEUES the callback; it does not call it — so what
/// is waited for is the notification, bounded, never assumed.
static void wait_invoked(qa_test_callback* callback) {
  for (int spin = 0; spin < 2000 && callback->invoked == 0; spin += 1) {
    Sleep(1);
  }
}

// ---------------------------------------------------------------------------
// Close racing a read, as Media Foundation does it: its own work-queue
// threads read while the thread that owns the reader tears it down.

typedef struct {
  IMFByteStream* stream;
  /// The span's block size: every read takes a whole block.
  ULONG block;
  volatile LONG stop;
  LONG reads;
} qa_test_reader;

static DWORD WINAPI read_until_stopped(void* argument) {
  qa_test_reader* reader = (qa_test_reader*)argument;
  uint8_t* sink = (uint8_t*)malloc(reader->block);
  QWORD at = 0;
  while (sink != NULL && reader->stop == 0) {
    // Two blocks in turn, so every read DECODES one: a read that only
    // copies the block the span kept is over before a Close can meet it.
    at = at == 0 ? (QWORD)reader->block * 5 : 0;
    ULONG got = 0;
    IMFByteStream_SetCurrentPosition(reader->stream, at);
    IMFByteStream_Read(reader->stream, sink, reader->block, &got);
    InterlockedIncrement(&reader->reads);
  }
  free(sink);
  return 0;
}

int main(void) {
  // Unbuffered: a check that kills the process must not take the lines
  // printed before it with it.
  setvbuf(stdout, NULL, _IONBF, 0);
  wchar_t directory[MAX_PATH];
  wchar_t fixture[MAX_PATH];
  if (GetTempPathW(MAX_PATH, directory) == 0 ||
      GetTempFileNameW(directory, L"qar", 0, fixture) == 0) {
    printf("FAIL fixture: no temp file\n");
    return 1;
  }
  // The stream takes the path as UTF-8, like every path that crosses into
  // this library (qa_platform_path.h widens it once, inside).
  char fixture_utf8[MAX_PATH * 4];
  if (WideCharToMultiByte(CP_UTF8, 0, fixture, -1, fixture_utf8,
                          (int)sizeof(fixture_utf8), NULL, NULL) == 0) {
    printf("FAIL fixture: the temp path is not UTF-8-able\n");
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
      qa_win_range_stream_create(fixture_utf8, RANGE_BASE, RANGE_LEN, 0);
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
    qa_test_callback callback = callback_on(stream, NULL);
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
    wait_invoked(&callback);
    expect_int("and the callback is invoked", callback.invoked, 1);
    expect_int("EndRead reports what was read", callback.ended, 8);
    for (int i = 0; i < 8; i += 1) {
      expect_int("and the async read filled the buffer with range bytes",
                 got[i], pattern_byte(RANGE_BASE + 200 + i));
    }

    // 🚨TWO READS IN FLIGHT: each EndRead answers for ITS read. The count
    // lived in one field of the stream, so a read that finished after the
    // next one began reported the next one's bytes — a short read is the
    // end of the file to a parser.
    {
      HANDLE go = CreateEventW(NULL, TRUE, FALSE, NULL);
      qa_test_callback first = callback_on(stream, go);
      qa_test_callback second = callback_on(stream, NULL);
      uint8_t eight[8];
      uint8_t three[3];
      IMFByteStream_SetCurrentPosition(stream, 0);
      IMFByteStream_BeginRead(stream, eight, 8, (IMFAsyncCallback*)&first,
                              NULL);
      IMFByteStream_BeginRead(stream, three, 3, (IMFAsyncCallback*)&second,
                              NULL);
      wait_invoked(&second);
      SetEvent(go);
      wait_invoked(&first);
      expect_int("the first read's EndRead reports the first read",
                 first.ended, 8);
      expect_int("the second read's EndRead reports the second read",
                 second.ended, 3);
      CloseHandle(go);
    }

    // 🚨A READ IN FLIGHT HOLDS ITS STREAM. Its callback finishes it on the
    // stream it began on, so the stream must outlive the owner's last
    // reference — a reader torn down while the work queue is behind lets
    // go of a stream whose read has not been finished.
    {
      IMFByteStream* held =
          qa_win_range_stream_create(fixture_utf8, RANGE_BASE, RANGE_LEN, 0);
      HANDLE go = CreateEventW(NULL, TRUE, FALSE, NULL);
      qa_test_callback late = callback_on(held, go);
      IMFByteStream_BeginRead(held, got, 8, (IMFAsyncCallback*)&late, NULL);
      const ULONG left = IMFByteStream_Release(held);
      expect_int("a read in flight keeps its stream alive", (long long)left,
                 1);
      SetEvent(go);
      wait_invoked(&late);
      expect_int("and finishes on it", late.ended, 8);
      CloseHandle(go);
    }
    MFShutdown();
  } else {
    printf("FAIL BeginRead: Media Foundation would not start\n");
    g_failures += 1;
  }

  IMFByteStream_Release(stream);

  // A read after Close is refused — the stream has nothing left to read.
  {
    IMFByteStream* closed =
        qa_win_range_stream_create(fixture_utf8, RANGE_BASE, RANGE_LEN, 0);
    IMFByteStream_Close(closed);
    read = 0;
    const HRESULT after = IMFByteStream_Read(closed, got, 8, &read);
    expect_int("a read after Close is refused", FAILED(after) ? 1 : 0, 1);
    expect_int("and reads nothing", read, 0);
    IMFByteStream_Release(closed);
  }

  // ⛔A range that runs past the end of the file is refused, not truncated:
  // a stream promising bytes the file cannot supply turns into a movie that
  // looks corrupt instead of a range that was wrong.
  IMFByteStream* past =
      qa_win_range_stream_create(fixture_utf8, FIXTURE_BYTES - 10, 100, 0);
  expect_int("a range past the end is refused", past == NULL ? 1 : 0, 1);
  if (past != NULL) {
    IMFByteStream_Release(past);
  }
  IMFByteStream* exact =
      qa_win_range_stream_create(fixture_utf8, FIXTURE_BYTES - 100, 100, 0);
  expect_int("a range ending exactly at the end is fine",
             exact == NULL ? 0 : 1, 1);
  if (exact != NULL) {
    IMFByteStream_Release(exact);
  }

  // 🚨A FRAMED SPAN: the stream serves the MEDIUM's bytes, decompressed —
  // its length is the medium's and a position is a position in the medium.
  // This is what lets Media Foundation play a movie the save compressed.
  {
    enum { kMedium = 20000, kBlock = 4096 };
    static uint8_t medium[kMedium];
    for (int64_t at = 0; at < kMedium; at += 1) {
      medium[at] = pattern_byte(at);
    }
    uint32_t lengths[QA_FIXTURE_MAX_BLOCKS];
    FILE* out = _wfopen(fixture, L"wb");
    int64_t blob = -1;
    if (out != NULL) {
      for (int i = 0; i < RANGE_BASE; i += 1) {
        fputc(0xEE, out);
      }
      blob = qa_fixture_write_framed(out, medium, kMedium, kBlock, lengths);
      fclose(out);
    }
    IMFByteStream* framed =
        blob > 0 ? qa_win_range_stream_create(fixture_utf8, RANGE_BASE, blob, 1)
                 : NULL;
    expect_int("a framed span opens", framed == NULL ? 0 : 1, 1);
    if (framed != NULL) {
      QWORD medium_length = 0;
      IMFByteStream_GetLength(framed, &medium_length);
      expect_int("its length is the MEDIUM's", (long long)medium_length,
                 kMedium);
      // Across a block boundary, where a wrong block index shows.
      IMFByteStream_SetCurrentPosition(framed, kBlock * 2 - 8);
      read = 0;
      IMFByteStream_Read(framed, got, 16, &read);
      expect_int("a read across a block boundary", read, 16);
      for (int i = 0; i < 16; i += 1) {
        expect_int("and the bytes are the medium's, decompressed", got[i],
                   pattern_byte(kBlock * 2 - 8 + i));
      }
      IMFByteStream_Release(framed);
    }

  }

  // 🚨CLOSE RACING A READ (framed-movie-parity-hangs-under-load): Media
  // Foundation reads on its own work-queue threads while the thread that
  // owns the reader tears it down, and Close freed the file and the block
  // buffers under a read still using them. A read after Close is refused;
  // a read Close meets finishes first.
  {
    // Big blocks, so a read spends its time decoding one — the window a
    // Close has to land in.
    enum { kRaceMedium = 1 << 20, kRaceBlock = 1 << 16 };
    static uint8_t race_medium[kRaceMedium];
    for (int64_t at = 0; at < kRaceMedium; at += 1) {
      race_medium[at] = pattern_byte(at);
    }
    uint32_t race_lengths[QA_FIXTURE_MAX_BLOCKS];
    FILE* out = _wfopen(fixture, L"wb");
    int64_t race_blob = -1;
    if (out != NULL) {
      race_blob = qa_fixture_write_framed(out, race_medium, kRaceMedium,
                                          kRaceBlock, race_lengths);
      fclose(out);
    }
    expect_int("the race's framed span is written", race_blob > 0 ? 1 : 0,
               1);
    if (race_blob > 0) {
      LONG reads = 0;
      for (int cycle = 0; cycle < 300; cycle += 1) {
        IMFByteStream* racing =
            qa_win_range_stream_create(fixture_utf8, 0, race_blob, 1);
        if (racing == NULL) {
          expect_int("a framed span opens for the race", 0, 1);
          break;
        }
        qa_test_reader reader;
        reader.stream = racing;
        reader.block = kRaceBlock;
        reader.stop = 0;
        reader.reads = 0;
        const HANDLE thread =
            CreateThread(NULL, 0, read_until_stopped, &reader, 0, NULL);
        // Let the reader get going, then close under it.
        for (int spin = 0; spin < 200 && reader.reads < 2; spin += 1) {
          Sleep(0);
        }
        IMFByteStream_Close(racing);
        InterlockedExchange(&reader.stop, 1);
        WaitForSingleObject(thread, 5000);
        CloseHandle(thread);
        reads += reader.reads;
        IMFByteStream_Release(racing);
      }
      expect_int("LIVENESS: the race read", reads > 0 ? 1 : 0, 1);
    }
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
