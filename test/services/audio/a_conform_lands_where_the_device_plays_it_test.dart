import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/core/on_a_worker.dart';
import 'package:anicel/src/native/qa_audio_device.dart';
import 'package:anicel/src/native/qa_engine_abi.dart';
import 'package:anicel/src/services/audio/audio_conform_runner.dart';
import 'package:anicel/src/services/audio/wav16_header.dart';

import '../../helpers/native_engine_path.dart';
import '../../helpers/temp_dir.dart';

/// 🚨A CONFORM LANDS WHERE THE DEVICE PLAYS IT, PLACED BY THE WORKER THAT
/// MADE IT (conform-landing-copies-on-the-ui-thread).
///
/// The PCM a sound is played from lives in a buffer of the device's own
/// (play-press-first-frame-stall); the store copied each conform, and each
/// rate it was converted to, into one as it landed — on the thread that
/// draws. The worker fills the buffer now, and the runner hands the list
/// over it to whoever asked.
void main() {
  final libraryPath = nativeEngineLibraryPathOrNull();
  final skip = libraryPath == null ? nativeEngineMissingSkipReason : false;
  late Directory directory;

  setUp(() async {
    QaAudioDevice.debugResetForTests();
    debugQaEngineLibraryPathOverride = libraryPath;
    directory = await Directory.systemTemp.createTemp('qa-conform-placed');
  });

  tearDown(() {
    try {
      QaAudioDevice.instance?.close();
    } on Object {
      // A device that never opened is fine to "close".
    }
    QaAudioDevice.debugResetForTests();
    debugQaEngineLibraryPathOverride = null;
    debugWorkersRunHere = true;
    deleteTempQuietly(directory);
  });

  QaAudioDevice openNull() {
    final device = QaAudioDevice.instance!;
    expect(
      device.open(sampleRate: 48000, useNullBackend: true),
      greaterThan(0),
    );
    return device;
  }

  /// A short stereo sound on disk, at the project's rate.
  ConformRequest aSound() {
    final pcm = Int16List(2 * 480);
    for (var index = 0; index < pcm.length; index += 1) {
      pcm[index] = (index % 200 - 100) * 90;
    }
    final path = '${directory.path}/a.wav';
    File(path).writeAsBytesSync(
      wav16Bytes(pcm, sampleRate: 48000, channels: 2),
    );
    return ConformRequest(
      sourcePath: path,
      conformPath: null,
      libraryPathOverride: libraryPath,
    );
  }

  test('🎯a conform\'s samples are a buffer of the device\'s own, held by '
      'the list alone — the conform\'s samples, sample for sample', () async {
    final device = openNull();
    final request = aSound();
    final here = runConformHere(request).samples!;
    // The road production takes: a real isolate.
    debugWorkersRunHere = false;

    final landed = await conformingInto(() => device)(request);

    expect(landed.isUsable, isTrue);
    expect(landed.samples, here);
    expect(
      device.debugHoldsOf(landed.samples!),
      1,
      reason: 'the worker\'s buffer, its maker\'s hold handed to the list',
    );
  }, skip: skip);

  test('🎯each rate it is converted to is one too', () async {
    final device = openNull();
    final from = runConformHere(aSound()).samples!;
    final request = ResampleRequest(
      samples: from,
      channels: 2,
      inputRate: 48000,
      outputRate: 44100,
      libraryPathOverride: libraryPath,
    );
    final here = runResampleHere(request);
    debugWorkersRunHere = false;

    final converted = await resamplingInto(() => device)(request);

    expect(converted, here);
    expect(device.debugHoldsOf(converted), 1);
  }, skip: skip);

  test('with no device, the PCM stays where it was made', () async {
    final request = aSound();

    final landed = await conformingInto(() => null)(request);

    expect(landed.samples, runConformHere(request).samples);
  }, skip: skip);

  test('a buffer that cannot be made places nothing, and leaves the samples '
      'where they are — as a device with no room did', () {
    final samples = Float32List.fromList([0.25, -0.5]);
    final made = <int>[];
    final hands = (
      make: (int floats) {
        made.add(floats);
        throw StateError('no memory for $floats floats');
      },
      release: (Pointer<Float> buffer) => calloc.free(buffer),
    );

    expect(placedWhereTheDevicePlays(samples, hands), (address: 0, floats: 0));
    expect(made, [2]);
    expect(samples, [0.25, -0.5]);
  });

  test('no samples, no buffer — one for nothing is one nothing frees', () {
    final made = <int>[];
    final hands = (
      make: (int floats) {
        made.add(floats);
        return calloc<Float>(floats);
      },
      release: (Pointer<Float> buffer) => calloc.free(buffer),
    );

    expect(placedWhereTheDevicePlays(null, hands), (address: 0, floats: 0));
    expect(
      placedWhereTheDevicePlays(Float32List(0), hands),
      (address: 0, floats: 0),
    );
    expect(made, isEmpty);
  });
}
