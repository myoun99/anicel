import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/core/on_a_worker.dart';
import 'package:anicel/src/native/qa_audio_device.dart';
import 'package:anicel/src/native/qa_engine_abi.dart';

import '../../helpers/native_engine_path.dart';

/// play-press-first-frame-stall-Q1 (유저 10-15: 「프로젝트를 열면 미리 연다(UI
/// 스레드 밖에서)」): the output opened ahead of a run, on a worker — a first
/// play's open held the UI thread for 63–272 ms. The device is one per
/// process, so what a worker opens is open here.
///
/// miniaudio's null backend throughout — a real callback on a real thread,
/// no speaker: each device is opened on it once and closed again, and every
/// open after that stands on it ([QaAudioDevice.open]).
void main() {
  final libraryPath = nativeEngineLibraryPathOrNull();
  final skip = libraryPath != null ? false : nativeEngineMissingSkipReason;

  setUp(() {
    QaAudioDevice.debugResetForTests();
    debugQaEngineLibraryPathOverride = libraryPath;
  });

  tearDown(() {
    debugWorkersRunHere = true;
    try {
      QaAudioDevice.instance?.close();
    } on Object {
      // A device that never opened is fine to "close".
    }
    QaAudioDevice.debugResetForTests();
    debugQaEngineLibraryPathOverride = null;
  });

  /// The device, closed, on the null backend from here on.
  QaAudioDevice aBenchDevice() {
    final device = QaAudioDevice.instance!;
    expect(device.open(useNullBackend: true), greaterThan(0));
    device.close();
    return device;
  }

  Future<void> ahead(QaAudioDevice device, String? name) =>
      openAudioOutputAhead(device, sampleRate: 48000, preferredName: name);

  test('🚨a worker opens the output and it is open HERE, for the setting it '
      'was opened for — under way until it is', () async {
    // The road production takes: a worker of its own, carrying the binary
    // this isolate loads (`onAWorkerWithThisEngine`).
    debugWorkersRunHere = false;
    final device = aBenchDevice();

    final opening = ahead(device, 'a speaker');
    expect(device.isOpening, isTrue);
    await opening;

    expect(device.isOpening, isFalse);
    expect(device.isOpen, isTrue);
    expect(device.openedFor, 'a speaker',
        reason: 'an unattached name opens the default, and is still what '
            'the device was opened for');
  }, skip: skip);

  test('🚨open for another output it is opened again — and left as it is for '
      'the one it is open for', () async {
    final device = aBenchDevice();
    await ahead(device, null);
    expect(device.play(startSample: 0), isNonZero, reason: 'fixture');

    await ahead(device, null);
    expect(device.isPlaying, isTrue, reason: 'the same output: not opened again');

    await ahead(device, 'another');
    expect(device.isOpen, isTrue);
    expect(device.openedFor, 'another');
    expect(device.isPlaying, isFalse,
        reason: 'opened again: a new device, playing nothing');
  }, skip: skip);

  test('🚨one at a time: an open asked for while one is under way follows '
      'it, and the last asked is what it is open for', () async {
    // Real workers: an open that did not wait its turn would ask whether
    // the output is open for its setting before the one under way had
    // changed it. (A worker that runs here opens before the next is asked.)
    debugWorkersRunHere = false;
    final device = aBenchDevice();
    await ahead(device, 'first');

    final second = ahead(device, 'second');
    final first = ahead(device, 'first');
    await Future.wait([second, first]);

    expect(device.isOpening, isFalse);
    expect(device.openedFor, 'first',
        reason: 'not waiting, it would have found the output still open for '
            'the first and left it — then the open for the second landed');
  }, skip: skip);

  // playback-waits-for-its-sound: a run plays its sound at the rate it was
  // conformed at, and the output is opened again at it ahead of the run —
  // ↩️such a run played every source through a rate conversion, or stood
  // down while one was made.
  test('🚨an open says the rate it was asked for — and one of a device '
      'already open says nothing, as it opens nothing', () {
    final device = QaAudioDevice.instance!;
    expect(
      device.open(sampleRate: 44100, useNullBackend: true),
      greaterThan(0),
    );
    expect(device.openedAtRate, 44100);

    device.open(sampleRate: 48000, useNullBackend: true);
    expect(device.openedAtRate, 44100, reason: 'it opened nothing');
  }, skip: skip);

  test('🚨open at another rate, an open ahead of a run leaves it — and one '
      'asked AT a rate (an arm\'s) opens it again there', () async {
    debugWorkersRunHere = false;
    final device = aBenchDevice();
    await openAudioOutputAhead(device, sampleRate: 44100, preferredName: null);
    expect(device.openedAtRate, 44100, reason: 'fixture');
    expect(device.play(startSample: 0), isNonZero, reason: 'fixture');

    await ahead(device, null);
    expect(device.isPlaying, isTrue, reason: 'any rate, ahead of a run');

    await openAudioOutputAhead(
      device,
      sampleRate: 48000,
      preferredName: null,
      atThatRate: true,
    );
    expect(device.openedAtRate, 48000);
    expect(device.isPlaying, isFalse, reason: 'opened again');
  }, skip: skip);

  group('kept open', () {
    test('🚨the output closes when the last who keeps it lets go — ↩️each '
        'transport closed it as it went, under every other project', () {
      final device = QaAudioDevice.instance!;
      expect(device.open(useNullBackend: true), greaterThan(0));
      final one = Object();
      final other = Object();
      device
        ..keep(one)
        ..keep(other)
        ..letGo(one);
      expect(device.isOpen, isTrue, reason: 'the other keeps it');

      device.letGo(Object());
      expect(device.isOpen, isTrue, reason: 'one who never kept it');

      device.letGo(other);
      expect(device.isOpen, isFalse);
    }, skip: skip);

    test('let go while it is opened ahead, it closes once that open is done',
        () async {
      final device = aBenchDevice();
      final keeper = Object();
      device.keep(keeper);

      final opening = ahead(device, null);
      device.letGo(keeper);
      expect(device.isOpening, isTrue, reason: 'fixture: let go mid-open');
      await opening;
      await pumpEventQueue();

      expect(device.isOpen, isFalse, reason: 'nobody keeps what it opened');
    }, skip: skip);
  });
}
