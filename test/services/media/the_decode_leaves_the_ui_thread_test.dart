import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/native/qa_engine_abi.dart';
import 'package:anicel/src/native/qa_video_decoder.dart';
import 'package:anicel/src/services/media/video_decode_worker.dart';

import '../../helpers/native_engine_path.dart';

/// 🚨★★★**THE WHOLE ROUND IS ONE QUESTION: WHOSE THREAD DECODES?**
///
/// A 1080p frame measured 14.97 ms — more than a third of a 24fps budget —
/// and a `dart:ffi` call blocks the isolate that makes it. Played beside a
/// drawing, that is a third of every frame taken from the brush.
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
    expect(rgba, isNotNull, reason: 'the frame must actually decode');
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
    addTearDown(() => directory.deleteSync(recursive: true));
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
}
