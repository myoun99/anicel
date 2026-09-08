import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

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

  /// Opens [path] (or the range inside it) and answers what it is, or null.
  Future<({int token, QaVideoInfo info})?> open(
    String path, {
    ({int offset, int length})? range,
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
  Future<({int token, QaVideoInfo info})?> open(
    String path, {
    ({int offset, int length})? range,
  }) async {
    final decoder = QaVideoDecoder.instance;
    if (decoder == null || !decoder.isSupported) {
      return null;
    }
    final document = decoder.openDocument(path, range: range);
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

  SendPort? _worker;
  Future<SendPort>? _starting;

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
      await Isolate.spawn(
        _videoDecodeWorker,
        (
          ready: ready.sendPort,
          // The override has to travel: a fresh isolate resolves the binary
          // from scratch, and a test that built one locally says where.
          libraryPath: debugQaEngineLibraryPathOverride,
        ),
        debugName: 'qa-video-decode',
      );
      final port = await ready.first as SendPort;
      ready.close();
      return _worker = port;
    }();
  }

  /// Sends one request and waits for its answer, behind everything already
  /// asked.
  Future<Object?> _ask(int op, Object? args) {
    final result = _queue.then((_) async {
      final worker = await _ensure();
      final reply = ReceivePort();
      worker.send((op: op, args: args, reply: reply.sendPort));
      final answer = await reply.first;
      reply.close();
      return answer;
    });
    // ⛔The queue must not inherit the failure — one bad frame would jam
    // every request after it.
    _queue = result.then((_) {}, onError: (_) {});
    return result;
  }

  @override
  Future<({int token, QaVideoInfo info})?> open(
    String path, {
    ({int offset, int length})? range,
  }) async {
    final answer = await _ask(_opOpen, (
      path: path,
      offset: range?.offset ?? 0,
      length: range?.length ?? 0,
    ));
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

  final documents = <QaVideoDocument>[];
  QaVideoDocument? documentAt(int token) =>
      token < 0 || token >= documents.length ? null : documents[token];

  requests.listen((message) {
    final request = message as ({int op, Object? args, SendPort reply});
    final decoder = QaVideoDecoder.instance;
    switch (request.op) {
      case _opOpen:
        final args =
            request.args! as ({String path, int offset, int length});
        final document = decoder == null || !decoder.isSupported
            ? null
            : decoder.openDocument(
                args.path,
                range: args.length > 0
                    ? (offset: args.offset, length: args.length)
                    : null,
              );
        if (document == null) {
          request.reply.send(null);
          return;
        }
        documents.add(document);
        request.reply.send((
          token: documents.length - 1,
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
        final document = documentAt(request.args! as int);
        if (document != null) {
          decoder?.closeDocument(document);
        }
        request.reply.send(null);
      default:
        request.reply.send(null);
    }
  });
}
