import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show visibleForTesting;

import '../../native/qa_engine_abi.dart';
import '../../native/qa_video_decoder.dart';

/// Where a movie is decoded, and — the whole point — WHICH THREAD pays.
///
/// 🚨★★★**A 1080p FRAME COSTS 15 MILLISECONDS AND THE UI ISOLATE WAS PAYING
/// IT.** Measured 2026-09-01 on a desktop, with the app's own encoder making
/// the clip: 14.97 ms per frame decoding sequentially, 110.66 ms for a
/// random access. A frame budget at 24fps is 41.7 ms, so playing a reference
/// movie spent **more than a third of every frame** inside a blocking FFI
/// call — on the isolate that also has to PAINT that frame, which is why the
/// viewer stuttered on its own. On the tablets this app is written for
/// ([[old-device-support-policy]]) it is several times that.
///
/// 🪦This used to end 「on the same thread as the brush」, and the motive it
/// implied — a reference movie running while you draw — is not one the app
/// has: 유저 2026-09-07 said so plainly, and playback is EXCLUSIVE
/// (`PlaybackTransports`), so a viewer run and a canvas run never overlap.
/// The measurement above is unchanged; only the reason it hurts is.
///
/// A `dart:ffi` call blocks the isolate that makes it. There is no async
/// form and no smaller fix: the decode has to happen somewhere else.
///
/// ⛔**Not `Isolate.run` per frame**, which is this repo's existing idiom
/// everywhere else (the conform, the PSD read, the cel encode). Those are
/// one-shot jobs; a decoder is a POSITION in a movie, and starting fresh per
/// frame means re-opening it — the 110 ms number above, every frame. So this
/// is the first long-lived isolate here, and it is long-lived for exactly
/// that reason.
///
/// ⚠️**Everything that decodes goes through here, not just the viewer.** The
/// native side holds ONE document in a process-global, so a worker and the
/// UI isolate both touching `QaVideoDecoder` would be two owners of one
/// global — and the handle bookkeeping that keeps two consumers from
/// blinding each other (#1458) is per-isolate state that would then be
/// tracking half the truth. The import preview rides this too.
abstract interface class VideoDecodeBackend {
  /// Whether this build can read a movie at all.
  ///
  /// 🚨★★★**THE CAPABILITY BELONGS TO THE THING THAT HAS IT.** The viewer
  /// document used to ask `QaVideoDecoder.instance?.isSupported` directly
  /// while doing its actual reading through this backend — one object for
  /// the work and another for「may I」, which can disagree the moment a
  /// backend is anything but the default one.
  ///
  /// ⛔And it made the whole video arm untestable: a fake backend could be
  /// injected ([debugVideoDecodeBackend]) and then never consulted, because
  /// the gate in front of it answered false on any machine without the
  /// native library. `video-viewer-arm-is-unmeasured` is that gap.
  ///
  /// Synchronous on purpose: it is a property of the BUILD, not of a
  /// document or a worker, so nothing has to be started to answer it.
  bool get supported;

  /// Whether this device's decoder can be fed a movie kept FRAMED
  /// ([QaVideoDecoder.readsFramed]) — asked of the backend for the reason
  /// [supported] is.
  bool get readsFramed;

  /// Opens [path] (or the span inside it) and answers what it is, or null.
  Future<({int token, QaVideoInfo info})?> open(
    String path, {
    ({int offset, int length, bool framed})? span,
  });

  /// The frame at [index] of the document [token] named, or null.
  ///
  /// ⚠️A FRESH buffer each time, unlike the direct path's reused one: what
  /// comes back over a port is owned by the receiver, and the alternative is
  /// handing every caller a view that the next frame overwrites.
  Future<Uint8List?> frame(int token, int index);

  /// Why the last open or frame failed, for the sentence a window shows.
  Future<String> lastError();

  /// Closes the document [token] named — and only if it is the loaded one.
  Future<void> close(int token);
}

/// The one the app uses. Overridable so a widget test never spawns an
/// isolate it cannot await — see [videoDecodeBackend].
VideoDecodeBackend? _backend;

/// 🚨A widget test's clock is fake, and a real isolate does not run on it:
/// awaiting one under `testWidgets` hangs until the test times out. The
/// audio device makes the same call the same way, and the seam is here
/// rather than at each call site so there is one answer to 「am I allowed to
/// spawn?」.
VideoDecodeBackend get videoDecodeBackend =>
    _backend ??= Platform.environment['FLUTTER_TEST'] == 'true'
    ? const DirectVideoDecodeBackend()
    : IsolateVideoDecodeBackend();

set debugVideoDecodeBackend(VideoDecodeBackend? backend) => _backend = backend;

/// Decoding on the CALLER's isolate — what everything did before, and what
/// tests and one-frame jobs still want.
///
/// ⚠️Correct, never fast: this is the 15 ms that motivated the isolate.
final class DirectVideoDecodeBackend implements VideoDecodeBackend {
  const DirectVideoDecodeBackend();

  @override
  bool get supported => QaVideoDecoder.instance?.isSupported ?? false;

  @override
  bool get readsFramed => QaVideoDecoder.instance?.readsFramed ?? false;

  @override
  Future<({int token, QaVideoInfo info})?> open(
    String path, {
    ({int offset, int length, bool framed})? span,
  }) async {
    final decoder = QaVideoDecoder.instance;
    if (decoder == null || !decoder.isSupported) {
      return null;
    }
    final document = decoder.openDocument(path, span: span);
    if (document == null) {
      return null;
    }
    final token = _documents.length;
    _documents.add(document);
    return (token: token, info: document.info);
  }

  @override
  Future<Uint8List?> frame(int token, int index) async {
    final document = _documentAt(token);
    if (document == null) {
      return null;
    }
    final rgba = QaVideoDecoder.instance?.frameOf(document, index);
    // ⚠️Copied, because the direct path decodes into scratch the next frame
    // overwrites and the isolate path hands over a buffer of its own. One
    // contract, or callers learn which backend they have.
    return rgba == null ? null : Uint8List.fromList(rgba);
  }

  @override
  Future<String> lastError() async => QaVideoDecoder.instance?.lastError ?? '';

  @override
  Future<void> close(int token) async {
    final document = _documentAt(token);
    if (document != null) {
      QaVideoDecoder.instance?.closeDocument(document);
    }
  }

  /// ⚠️Static because the backend itself is `const`: the tokens have to
  /// outlive any particular instance, and there is one native decoder
  /// anyway.
  static final List<QaVideoDocument> _documents = [];

  static QaVideoDocument? _documentAt(int token) =>
      token < 0 || token >= _documents.length ? null : _documents[token];
}

// ---------------------------------------------------------------------------
// The isolate.

/// What the worker is being asked to do. ⛔Records and primitives only —
/// what crosses a port is copied, and a request that carried anything
/// clever would be a request that cannot cross.
const int _opOpen = 0;
const int _opFrame = 1;
const int _opLastError = 2;
const int _opClose = 3;

final class IsolateVideoDecodeBackend implements VideoDecodeBackend {
  IsolateVideoDecodeBackend();

  /// ⚠️Answered on THIS isolate: whether the library loads is a property of
  /// the build, and asking a worker would mean starting one to find out.
  @override
  bool get supported => QaVideoDecoder.instance?.isSupported ?? false;

  /// ⚠️On THIS isolate too, for the same reason: the device does not change
  /// between isolates.
  @override
  bool get readsFramed => QaVideoDecoder.instance?.readsFramed ?? false;

  SendPort? _worker;
  Future<SendPort>? _starting;

  /// Fails when the worker stops answering — it exited, or an uncaught
  /// error killed it.
  ///
  /// 🚨★★★**A REQUEST THAT WAS SENT ALWAYS GETS AN ANSWER.** `Isolate.spawn`
  /// defaults to `errorsAreFatal: true`, and the worker's body allocates
  /// three full frames per decode (a native scratch, a `Uint8List`, and the
  /// copy into the transfer — 8.3 MB each at 1080p, 33 MB at 4K on the
  /// tablets this app is written for). Any of those throwing used to KILL
  /// the isolate with nothing on this side listening: `reply.first` never
  /// completed, [_queue] never settled, and every later request — the
  /// viewer's AND the import preview's, since they share one backend —
  /// waited behind it for the life of the process.
  ///
  /// ⛔A timeout would be the wrong shape: a slow decode on a slow device is
  /// the normal case, and cancelling it would throw away a frame that was
  /// going to arrive. What is needed is not a deadline but the FACT that
  /// nobody is going to answer, and the isolate reports that itself.
  Completer<Never>? _died;

  /// The next document handle this backend hands out.
  ///
  /// ⛔Monotonic, and never reset — not even when the worker is replaced.
  /// See [open] for the cross-talk a restarting index caused.
  int _nextToken = 0;

  /// One request at a time, in order.
  ///
  /// 🚨★★★**THE NATIVE DOCUMENT IS A POSITION, SO THE ORDER IS THE ANSWER.**
  /// Two frame requests in flight would interleave a seek with a read and
  /// hand each caller the other's picture. The viewer already asks for one
  /// frame at a time; this is what makes that a property rather than a habit.
  Future<void> _queue = Future.value();

  Future<SendPort> _ensure() {
    final worker = _worker;
    if (worker != null) {
      return Future.value(worker);
    }
    return _starting ??= () async {
      final ready = ReceivePort();
      // Exit and error land on ONE port: an uncaught error is fatal by
      // default, so a worker that errors also exits, and the two are the
      // same fact told twice. Whichever arrives first is the one that
      // counts; the listener is written so the second changes nothing.
      final stopped = ReceivePort();
      final died = Completer<Never>();
      // ⚠️Nothing may be pending when the worker dies. Without this the
      // rejection below is an unhandled async error rather than an answer
      // to a question nobody asked. Later listeners still receive it.
      died.future.ignore();
      stopped.listen((message) {
        // Forget it, so the NEXT request spawns a fresh worker. A device
        // that ran out of memory for one frame can decode the next one.
        _worker = null;
        _starting = null;
        _died = null;
        stopped.close();
        if (!died.isCompleted) {
          died.completeError(
            StateError('the video decode worker stopped: $message'),
          );
        }
      });
      await Isolate.spawn(
        _videoDecodeWorker,
        (
          ready: ready.sendPort,
          // The override has to travel: a fresh isolate resolves the binary
          // from scratch, and a test that built one locally says where.
          libraryPath: debugQaEngineLibraryPathOverride,
        ),
        debugName: 'qa-video-decode',
        onError: stopped.sendPort,
        onExit: stopped.sendPort,
      );
      _died = died;
      // The handshake is a wait like any other: an isolate that dies before
      // it can say hello would otherwise hang here instead of at [_ask].
      final port = await Future.any([ready.first, died.future]) as SendPort;
      ready.close();
      return _worker = port;
    }();
  }

  /// Sends one request and waits for its answer, behind everything already
  /// asked.
  Future<Object?> _ask(int op, Object? args) {
    final result = _queue.then((_) async {
      final worker = await _ensure();
      // ⛔NOT nullable-with-a-fallback. [_ensure] assigns `_died` before it
      // assigns `_worker`, and the death listener is a PORT event rather
      // than a microtask, so it cannot land between this line and the one
      // above. A `died == null ? await reply.first : …` arm read as
      // defensive and was in fact unreachable — and what it held was
      // exactly the unguarded wait this whole field exists to abolish
      // (found by the 2026-09-09 audit).
      final died = _died!;
      final reply = ReceivePort();
      try {
        worker.send((op: op, args: args, reply: reply.sendPort));
        // 🚨The race IS the answer. `reply.first` alone waits forever on a
        // worker that is not there any more — see [_died] for what kills
        // one and what that used to cost.
        return await Future.any([reply.first, died.future]);
      } finally {
        reply.close();
      }
    });
    // ⛔The queue must not inherit the failure — one bad frame would jam
    // every request after it.
    _queue = result.then((_) {}, onError: (_) {});
    return result;
  }

  @override
  Future<({int token, QaVideoInfo info})?> open(
    String path, {
    ({int offset, int length, bool framed})? span,
  }) async {
    // 🚨★★★**THE TOKEN IS MINTED HERE, BY THE SIDE THAT OUTLIVES THE
    // WORKER.** It used to be the worker's own list index, and the worker's
    // list is created fresh on every spawn — so once [_died] let a dead
    // worker be replaced (2026-09-08), the next document opened on the new
    // worker got index 0 and a document already open somewhere else was
    // still holding token 0. The viewer would then have drawn the import
    // preview's movie, and closing one would have closed the other: exactly
    // the bug both this file and `import_preview.dart` carry tombstones for
    // (#1458, 「a handle says which movie is whose」), made reachable again
    // by the recovery that was supposed to be free.
    //
    // ⛔A monotonic counter and nothing else. It never restarts, so a token
    // from a dead generation is simply absent from the new worker's map —
    // `frame` answers null and the caller says 「could not be read」, which
    // is true. ⚠️It cannot answer 「reopen it for me」; that would need the
    // path kept here, and inventing a silent reopen is not this round's to
    // decide (board: `a-dead-worker-forgets-its-documents`).
    final token = _nextToken++;
    final answer = await _ask(_opOpen, (token: token, path: path, span: span));
    if (answer == null) {
      return null;
    }
    final opened =
        answer
            as ({
              int token,
              int width,
              int height,
              int frameCount,
              int fpsNumerator,
              int fpsDenominator,
            });
    return (
      token: opened.token,
      info: QaVideoInfo(
        width: opened.width,
        height: opened.height,
        frameCount: opened.frameCount,
        fpsNumerator: opened.fpsNumerator,
        fpsDenominator: opened.fpsDenominator,
      ),
    );
  }

  @override
  Future<Uint8List?> frame(int token, int index) async {
    final answer = await _ask(_opFrame, (token: token, index: index));
    if (answer == null) {
      return null;
    }
    // Transferred rather than copied: 1080p RGBA is 8MB, and a copy per
    // frame is the cost this whole file exists to avoid paying twice.
    return (answer as TransferableTypedData).materialize().asUint8List();
  }

  @override
  Future<String> lastError() async =>
      (await _ask(_opLastError, null) as String?) ?? '';

  @override
  Future<void> close(int token) => _ask(_opClose, token);
}

/// The worker's body: it owns the decoder, and nothing else in the process
/// touches one.
void _videoDecodeWorker(({SendPort ready, String? libraryPath}) start) {
  if (start.libraryPath != null) {
    debugQaEngineLibraryPathOverride = start.libraryPath;
  }
  final requests = ReceivePort();
  start.ready.send(requests.sendPort);

  // 🚨★★★KEYED BY THE HANDLE THE ASKER MINTED, not by this list's own
  // index. This map is created fresh on every spawn, so an index would
  // start over at 0 while a document opened on the PREVIOUS worker was
  // still holding 0 — see [IsolateVideoDecodeBackend.open]. A handle that
  // belongs to a generation that died is simply absent here, and absent is
  // an answer.
  final documents = <int, QaVideoDocument>{};
  QaVideoDocument? documentAt(int token) => documents[token];

  requests.listen(
    (message) => serveVideoDecodeRequest(
      message as ({int op, Object? args, SendPort reply}),
      documents,
      documentAt,
    ),
  );
}

/// Answers one request — and answers it even when the work throws.
///
/// 🚨★★★**IT ANSWERS BEFORE IT DIES.** Every allocation in the frame arm
/// throws rather than returning null: `malloc` raises
/// `ArgumentError('Could not allocate …')` and `Uint8List` raises
/// `OutOfMemoryError`, three full frames' worth per decode (8.3 MB each at
/// 1080p, 33 MB at 4K on the tablets this app is written for). An uncaught
/// throw here is FATAL to this isolate — `Isolate.spawn` defaults to
/// `errorsAreFatal: true` — and the asker would then be left waiting on a
/// port nobody holds, with [IsolateVideoDecodeBackend._queue] jammed behind
/// it for every later request from every consumer.
///
/// `null` is not a new vocabulary word: it is already what every op says for
/// 「could not」, and each caller on the other side already reads it that way.
///
/// ⛔The reply comes FIRST and the isolate is then allowed to die. An
/// `OutOfMemoryError` is not something to carry on from here — the spawner
/// sees the exit and starts a fresh worker for the next request, which is
/// the only recovery that means anything.
///
/// 🧪Visible because the failure it exists for cannot be reached through
/// [IsolateVideoDecodeBackend]: every op that crosses the port is built by
/// that class, so nothing a test can ASK for makes the work throw.
@visibleForTesting
void serveVideoDecodeRequest(
  ({int op, Object? args, SendPort reply}) request,
  Map<int, QaVideoDocument> documents,
  QaVideoDocument? Function(int token) documentAt,
) {
  try {
    _serve(request, documents, documentAt);
  } on Object {
    request.reply.send(null);
    rethrow;
  }
}

/// One request, answered.
///
/// ⚠️Split out of the listener so the catch there wraps the WHOLE of it.
/// Every arm sends exactly once: an arm that returned without replying
/// would be the same endless wait the catch exists to prevent.
void _serve(
  ({int op, Object? args, SendPort reply}) request,
  Map<int, QaVideoDocument> documents,
  QaVideoDocument? Function(int token) documentAt,
) {
  final decoder = QaVideoDecoder.instance;
  switch (request.op) {
    case _opOpen:
      final args =
          request.args!
              as ({
                int token,
                String path,
                ({int offset, int length, bool framed})? span,
              });
      final document = decoder == null || !decoder.isSupported
          ? null
          : decoder.openDocument(args.path, span: args.span);
      if (document == null) {
        request.reply.send(null);
        return;
      }
      documents[args.token] = document;
      request.reply.send((
        token: args.token,
        width: document.info.width,
        height: document.info.height,
        frameCount: document.info.frameCount,
        fpsNumerator: document.info.fpsNumerator,
        fpsDenominator: document.info.fpsDenominator,
      ));
    case _opFrame:
      final args = request.args! as ({int token, int index});
      final document = documentAt(args.token);
      final rgba = document == null
          ? null
          : decoder?.frameOf(document, args.index);
      request.reply.send(
        rgba == null
            ? null
            // ⚠️A copy INTO the transfer, because the decoder hands back a
            // view of scratch it reuses. The copy stays on this isolate,
            // which is the one with time to spare.
            : TransferableTypedData.fromList([Uint8List.fromList(rgba)]),
      );
    case _opLastError:
      request.reply.send(decoder?.lastError ?? '');
    case _opClose:
      // ⚠️Removed, not just closed. The handle is the ASKER's now and never
      // repeats, so an entry left behind is a closed document a stale
      // request could still be handed. Before 2026-09-09 the list index WAS
      // the handle, so removing an entry would have renumbered every one
      // after it — which is why the old code deliberately left it.
      final document = documents.remove(request.args! as int);
      if (document != null) {
        decoder?.closeDocument(document);
      }
      request.reply.send(null);
    default:
      request.reply.send(null);
  }
}
