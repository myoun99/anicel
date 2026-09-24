import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/native/qa_engine_abi.dart';
import 'package:anicel/src/native/qa_video_decoder.dart';
import 'package:anicel/src/services/media/video_decode_worker.dart';

import '../../helpers/native_engine_path.dart';
import '../../helpers/project_scratch_folder.dart';

/// 🚨★★★**THE WHOLE ROUND IS ONE QUESTION: WHOSE THREAD DECODES?**
///
/// A 1080p frame measured 14.97 ms — more than a third of a 24fps budget —
/// and a `dart:ffi` call blocks the isolate that makes it. Spent on the
/// isolate that also PAINTS, that is a viewer stuttering on its own.
///
/// 🪦This used to end 「Played beside a drawing, that is a third of every
/// frame taken from the brush」. That motive is retired: 유저 2026-09-07
/// settled that playback is EXCLUSIVE (`PlaybackTransports`), so a viewer
/// run and a canvas run never overlap. The measurement is unchanged; what it
/// buys is the viewer's own smoothness and scrubbing (110 ms per seek).
///
/// ⚠️「It still works」 cannot see the difference: both backends return the
/// same pixels. What separates them is whether the CALLER can do anything
/// while the decode happens, so that is what is measured here — with a
/// zero-duration timer, which is the smallest piece of 「anything」 there is.
void main() {
  final libraryPath = nativeEngineLibraryPathOrNull();
  final skip = libraryPath != null ? false : nativeEngineMissingSkipReason;

  setUp(() {
    QaVideoDecoder.debugResetForTests();
    debugQaEngineLibraryPathOverride = libraryPath;
  });

  tearDown(() {
    debugVideoDecodeBackend = null;
    QaVideoDecoder.instance?.close();
    QaVideoDecoder.debugResetForTests();
    debugQaEngineLibraryPathOverride = null;
  });

  const movie = 'test/fixtures/tone_with_video.mp4';

  bool readerHere() =>
      QaVideoDecoder.instance != null && QaVideoDecoder.instance!.isSupported;

  /// Whether a zero-duration timer scheduled just before the frame gets to
  /// run BEFORE the frame arrives.
  ///
  /// 🚨This is the property, stated as something a machine can answer. A
  /// blocking decode holds the isolate through the whole call, so nothing
  /// scheduled beforehand can run until it is over; a decode on a worker
  /// leaves the event loop turning, and the timer — which is queued behind
  /// nothing — lands first.
  Future<bool> timerRunsFirst(VideoDecodeBackend backend) async {
    final opened = await backend.open(movie);
    expect(opened, isNotNull, reason: 'the fixture must open');
    // Warm: the first frame of a document also pays for starting the
    // pipeline, and that is not what is being compared.
    await backend.frame(opened!.token, 0);

    var timerFired = false;
    Timer.run(() => timerFired = true);
    final rgba = await backend.frame(opened.token, 1);
    final wonRace = timerFired;
    // WHY a frame did not come is the native reader's own sentence — and on
    // a machine nobody here can sit at (Codemagic's Mac), it is the only
    // account of it there will be.
    final why = rgba == null ? await backend.lastError() : '';
    expect(rgba, isNotNull, reason: 'the frame must actually decode: $why');
    await backend.close(opened.token);
    return wonRace;
  }

  test('the isolate backend leaves the caller free; the direct one does '
      'not', () async {
    if (!readerHere()) {
      return; // no reader in this build — absence is answered elsewhere
    }

    // ⚠️The control FIRST, so a green result cannot come from a timer that
    // would have fired either way. If this stops being false, the
    // measurement has stopped measuring.
    expect(
      await timerRunsFirst(const DirectVideoDecodeBackend()),
      isFalse,
      reason: 'decoding on the calling isolate must hold it — if even the '
          'direct backend lets a timer through, this test cannot tell the '
          'two apart and proves nothing about the other one',
    );

    expect(
      await timerRunsFirst(IsolateVideoDecodeBackend()),
      isTrue,
      reason: 'the decode is supposed to happen somewhere else — the caller '
          'has to be able to run a timer while it does, because that is the '
          'brush, the scroll and the cursor',
    );
  }, skip: skip);

  test('both backends produce the SAME pixels — one law, two places to run '
      'it', () async {
    if (!readerHere()) {
      return;
    }
    const direct = DirectVideoDecodeBackend();
    final onDirect = await direct.open(movie);
    final fromDirect = Uint8List.fromList(
      (await direct.frame(onDirect!.token, 3))!,
    );
    await direct.close(onDirect.token);

    final worker = IsolateVideoDecodeBackend();
    final onWorker = await worker.open(movie);
    expect(onWorker!.info.width, onDirect.info.width);
    expect(onWorker.info.height, onDirect.info.height);
    expect(onWorker.info.frameCount, onDirect.info.frameCount);
    final fromWorker = (await worker.frame(onWorker.token, 3))!;
    await worker.close(onWorker.token);

    expect(
      fromWorker,
      orderedEquals(fromDirect),
      reason: 'a frame is a frame — if moving the decode changed the '
          'picture, the move is not what it claims to be',
    );
  }, skip: skip);

  test('frames asked for at once come back in order, each its own', () async {
    // 🚨★★★**THE NATIVE DOCUMENT IS A POSITION.** Two reads in flight would
    // interleave a seek with a decode and hand each caller the other's
    // picture. The worker serializes, so asking for three at once is
    // allowed to be slow and is NOT allowed to be wrong.
    if (!readerHere()) {
      return;
    }
    final backend = IsolateVideoDecodeBackend();
    final opened = await backend.open(movie);
    final wanted = <int, Uint8List>{};
    for (final index in [2, 5, 9]) {
      wanted[index] = Uint8List.fromList(
        (await backend.frame(opened!.token, index))!,
      );
    }

    final together = await Future.wait([
      for (final index in [2, 5, 9]) backend.frame(opened!.token, index),
    ]);

    expect(together[0], orderedEquals(wanted[2]!));
    expect(together[1], orderedEquals(wanted[5]!));
    expect(together[2], orderedEquals(wanted[9]!));
    await backend.close(opened!.token);
  }, skip: skip);

  test('a movie that cannot be read says so instead of hanging', () async {
    if (!readerHere()) {
      return;
    }
    final backend = IsolateVideoDecodeBackend();
    final directory = Directory.systemTemp.createTempSync('qa_bad');
    deleteAfterSessionEnds(directory);
    final path = '${directory.path}${Platform.pathSeparator}not.mp4';
    File(path).writeAsBytesSync(List.filled(4096, 0x41));

    expect(await backend.open(path), isNull);
    expect(
      await backend.lastError(),
      isNotEmpty,
      reason: 'the reason has to cross the port too — it is the sentence the '
          'window shows',
    );
    // ⛔And the worker is still usable afterwards: one bad open must not
    // jam the queue behind it.
    expect(await backend.open(movie), isNotNull);
  }, skip: skip);

  test('🚨a handle names ONE document for ever — a worker that restarts '
      'cannot hand it to another', () async {
    // 🚨★★★THE REGRESSION THIS CATCHES WAS INTRODUCED BY THE FIX ABOVE IT.
    // Letting a dead worker be replaced (2026-09-08) was free liveness and a
    // correctness hole: the worker's document list is built fresh on every
    // spawn, and the token used to be that list's INDEX. So the first
    // document opened on a new worker got 0 while a document already open
    // elsewhere was still holding 0 — the viewer would have drawn the import
    // preview's movie, and closing one would have closed the other. That is
    // #1458 exactly, which both this backend and `import_preview.dart` carry
    // tombstones for.
    //
    // ⛔The nail is the HANDLE, not the recovery: two documents opened by the
    // same backend must never share one, whatever happened to the worker in
    // between. Monotonic minting on the SPAWNER — the side that outlives a
    // worker — is what makes that unrepresentable.
    if (!readerHere()) {
      return;
    }
    final backend = IsolateVideoDecodeBackend();
    final first = await backend.open(movie);
    final second = await backend.open(movie);
    expect(first, isNotNull, reason: 'fixture: the movie opens');
    expect(second, isNotNull, reason: 'fixture: and opens again');
    expect(
      second!.token,
      isNot(first!.token),
      reason: 'two live documents, two handles — an index that restarts with '
          'the worker would have handed out the same one twice',
    );
    await backend.close(first.token);
    // ⛔AND A CLOSED HANDLE IS NOT RECYCLED EITHER: the next open must not
    // be handed the number the closed document had, or a request still in
    // flight for the old one would land on the new one.
    final third = await backend.open(movie);
    expect(third, isNotNull);
    expect(third!.token, isNot(first.token));
    expect(third.token, isNot(second.token));
    await backend.close(second.token);
    await backend.close(third.token);
  }, skip: skip);

  test('🚨a request whose work THROWS is answered before the worker dies', () {
    // 🚨★★★**THE STRONGER OF THE TWO NEVER-SETTLES.** `Isolate.spawn`
    // defaults to `errorsAreFatal: true`, and the frame arm allocates three
    // whole frames per decode — a native scratch, a `Uint8List`, and the
    // copy into the transfer, each 8.3 MB at 1080p and 33 MB at 4K. Those
    // raise (`ArgumentError('Could not allocate …')`, `OutOfMemoryError`)
    // rather than returning null, so before 2026-09-08 an out-of-memory
    // frame KILLED the worker with nobody listening: `reply.first` never
    // completed, the request queue never settled behind it, and every later
    // ask — the viewer's and the import preview's, which share one backend —
    // waited for the life of the process.
    //
    // ⚠️This does not go through [IsolateVideoDecodeBackend], and that is
    // the point: every op that crosses the port is BUILT by that class, so
    // nothing a test can ask for makes the work throw. The failure is
    // modelled where it actually lives — inside the frame arm, on a lookup
    // that raises the way an allocation does.
    final port = ReceivePort();
    addTearDown(port.close);

    expect(
      () => serveVideoDecodeRequest(
        // 1 is the frame op. ⚠️If those constants are ever renumbered this
        // lands on the default arm, which replies without throwing — and
        // this expectation then fails loudly rather than passing on nothing.
        (op: 1, args: (token: 0, index: 0), reply: port.sendPort),
        <int, QaVideoDocument>{},
        (_) => throw StateError('the decode ran out of memory'),
      ),
      throwsA(isA<StateError>()),
      reason: '⛔the throw is NOT swallowed — an OutOfMemoryError is not '
          'something to carry on from, and the spawner starts a fresh worker '
          'for the next request. What changed is only that the asker is told',
    );

    expect(
      port.first,
      completion(isNull),
      reason: 'the answer went out FIRST. `null` is not new vocabulary — it '
          'is already what every op says for 「could not」, and every caller '
          'on the other side already reads it that way',
    );
  });
}
