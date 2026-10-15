import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/core/on_a_worker.dart';
import 'package:anicel/src/models/project_frame_rate.dart';
import 'package:anicel/src/native/qa_audio_device.dart';
import 'package:anicel/src/native/qa_engine_abi.dart';
import 'package:anicel/src/services/audio/audio_conform_pipeline.dart';
import 'package:anicel/src/services/audio/audio_mixer_reference.dart'
    show AudioMixSource;
import 'package:anicel/src/services/audio/conform_pcm_codec.dart';
import 'package:anicel/src/services/audio/conform_pcm_stream.dart';
import 'package:anicel/src/services/media/media_byte_source.dart';
import 'package:anicel/src/ui/audio/audio_conform_store.dart';
import 'package:anicel/src/ui/playback/audio_playback_schedule.dart';
import 'package:anicel/src/ui/playback/audio_windowed_upload.dart';

import '../../helpers/native_engine_path.dart';
import '../../helpers/temp_dir.dart';

/// 🚨★★★**A STREAMING WINDOW MOVES WITHOUT THE THREAD THAT DRAWS**
/// (streaming-advance-reads-on-the-ui-thread, 10-15).
///
/// A sound past two minutes plays out of a window read from disk, and every
/// fifteen seconds of playback the window moves on. That read — and the
/// copies the upload made of it — held the UI thread 47~50ms each time, and
/// the picture skipped a frame. The windows are read on a worker now,
/// straight into buffers of the device's own, and the thread that draws
/// adopts what landed and swaps the schedule. An answer that is no longer
/// wanted when it lands uploads nothing.
void main() {
  final libraryPath = nativeEngineLibraryPathOrNull();
  final skip = libraryPath == null ? nativeEngineMissingSkipReason : false;
  late Directory directory;

  setUp(() async {
    QaAudioDevice.debugResetForTests();
    debugQaEngineLibraryPathOverride = libraryPath;
    directory = await Directory.systemTemp.createTemp('qa-window-worker');
  });

  tearDown(() {
    try {
      QaAudioDevice.instance?.close();
    } on Object {
      // A device that never opened is fine to "close".
    }
    QaAudioDevice.debugResetForTests();
    debugQaEngineLibraryPathOverride = null;
    deleteTempQuietly(directory);
  });

  // Tiny numbers, as the window's own tests use: a 100 Hz project, 10 fps.
  const sampleRate = 100;
  const rate = ProjectFrameRate.integer(10);
  const longFrames = sampleRate * conformStreamingThresholdSeconds + 50;

  /// A store whose 'a' and 'b' both stream from conforms on disk, and the
  /// decode of each — what every window must hold, sample for sample.
  Future<(AudioConformStore, Map<String, Float32List>)> streamingStore() async {
    final decoded = <String, Float32List>{};
    final paths = <String, String>{};
    for (final name in ['a', 'b']) {
      final samples = Float32List(longFrames);
      for (var index = 0; index < longFrames; index += 1) {
        samples[index] = ((index % 1000) - 500) / (name == 'a' ? 1000 : 2000);
      }
      final path = '${directory.path}/$name.conform';
      final bytes = encodeConform(
        samples: samples,
        channels: 1,
        sampleRate: sampleRate,
      );
      File(path).writeAsBytesSync(bytes);
      paths[name] = path;
      decoded[name] = decodeConform(bytes).samples;
    }
    final store = AudioConformStore(
      resolveConformPath: (source) => paths[source],
      projectSampleRate: sampleRate,
      runner: (request) async => ConformResult(
        outcome: ConformOutcome.built,
        conformBytes: mediaAppFileSource(paths[request.sourcePath]!),
        channels: 1,
        sampleRate: sampleRate,
        frames: longFrames,
      ),
      log: (_) {},
    );
    addTearDown(store.dispose);
    store.resultFor('a');
    store.resultFor('b');
    await pumpEventQueue();
    expect(store.isStreaming('a'), isTrue);
    expect(store.isStreaming('b'), isTrue);
    return (store, decoded);
  }

  AudioMixSchedule mixOf(List<String> names) => audioMixScheduleFrom(
    schedule: [
      for (final name in names)
        ScheduledAudioClip(
          filePath: name,
          startFrame: 0,
          endFrameExclusive: 1200,
        ),
    ],
    rate: rate,
    sampleRate: sampleRate,
  );

  WindowedUploadPlan planAround(
    AudioConformStore store,
    AudioMixSchedule mix,
    int centerSample,
  ) => planWindowedMixUpload(
    mix: mix,
    conformStore: store,
    deviceRate: sampleRate,
    centerSample: centerSample,
    backSeconds: AudioStreamingWindow.backSeconds,
    aheadSeconds: AudioStreamingWindow.aheadSeconds,
  )!;

  void expectTheDecode(AudioMixSource window, Float32List decoded) {
    for (var index = 0; index < window.samples.length; index += 1) {
      expect(
        window.samples[index],
        decoded[window.sourceStart + index],
        reason: 'window sample $index is not the decode\'s',
      );
    }
  }

  QaAudioDevice openNull() {
    final device = QaAudioDevice.instance!;
    expect(
      device.open(sampleRate: 48000, useNullBackend: true),
      greaterThan(0),
    );
    return device;
  }

  test('🎯a worker reads each window into a buffer the device adopts — the '
      'decode\'s samples, held by the list alone', () async {
    final device = openNull();
    final (store, decoded) = await streamingStore();
    final plan = planAround(store, mixOf(['a', 'b']), 5000);
    // The road production takes: a real isolate.
    debugWorkersRunHere = false;
    addTearDown(() => debugWorkersRunHere = true);

    final windows = (await readStreamWindowsOnAWorker(plan.reads, device))!;

    expect(windows, hasLength(2));
    for (final (index, name) in ['a', 'b'].indexed) {
      final window = windows[index];
      expect(window.sourceStart, 5000 - 2 * sampleRate);
      expect(window.samples, hasLength(32 * sampleRate));
      expectTheDecode(window, decoded[name]!);
      expect(
        device.debugHoldsOf(window.samples),
        1,
        reason: 'the window is a buffer of the device\'s own, its maker\'s '
            'hold handed to the list that adopted it',
      );
    }
  }, skip: skip);

  test('a buffer that cannot be made lets go of every one made before it, '
      'and hands nothing over', () async {
    final (store, _) = await streamingStore();
    final plan = planAround(store, mixOf(['a', 'b']), 5000);
    final made = <int>[];
    final released = <int>[];
    final hands = (
      make: (int floats) {
        if (made.isNotEmpty) {
          throw StateError('no memory for $floats floats');
        }
        final buffer = calloc<Float>(floats);
        made.add(buffer.address);
        return buffer;
      },
      release: (Pointer<Float> buffer) {
        released.add(buffer.address);
        calloc.free(buffer);
      },
    );

    expect(() => readStreamWindowsInto(plan.reads, hands), throwsStateError);
    expect(released, made, reason: 'the first window\'s buffer leaked');
  });

  test('🚨a read that does not land whole (its file gone from under it) '
      'gives its buffer back, and hands over none', () async {
    final (store, _) = await streamingStore();
    final plan = planAround(store, mixOf(['a', 'b']), 5000);
    for (final file in directory.listSync().whereType<File>()) {
      file.deleteSync();
    }
    final made = <int>[];
    final released = <int>[];
    final hands = (
      make: (int floats) {
        final buffer = calloc<Float>(floats);
        made.add(buffer.address);
        return buffer;
      },
      release: (Pointer<Float> buffer) {
        released.add(buffer.address);
        calloc.free(buffer);
      },
    );

    final landed = readStreamWindowsInto(plan.reads, hands);

    expect(landed, isNull);
    expect(made, hasLength(1), reason: 'it stops at the first broken one');
    expect(released, made, reason: 'a buffer nothing landed in leaked');
  });

  group('an advance that lands', () {
    late QaAudioDevice device;
    late AudioConformStore store;
    late AudioStreamingWindow window;
    late Completer<List<AudioMixSource>?> reading;
    late List<StreamWindowRead> asked;
    late int readsAsked;
    ({QaAudioDevice device, int deviceRate})? carrying;

    setUp(() async {
      if (libraryPath == null) {
        return;
      }
      device = openNull();
      (store, _) = await streamingStore();
      reading = Completer();
      asked = [];
      readsAsked = 0;
      window = AudioStreamingWindow(
        readWindows: (reads, _) {
          readsAsked += 1;
          asked = reads;
          return reading.future;
        },
      )..mix = mixOf(['a']);
      expect(
        window.upload(
          device: device,
          conformStore: store,
          deviceRate: sampleRate,
          centerSample: 0,
        ),
        isTrue,
      );
      carrying = (device: device, deviceRate: sampleRate);
    });

    /// Moves the device to [at] and asks the window to follow it there;
    /// the read is out once this returns.
    Future<void> followTo(int at) async {
      device.seek(at);
      expect(device.positionSamples, at);
      window.followPlayback(
        positionSamples: at,
        deviceRate: sampleRate,
        conformStore: store,
        current: () => carrying,
      );
      await pumpEventQueue();
      expect(asked, isNotEmpty, reason: 'the advance never read');
    }

    Future<void> land() async {
      reading.complete([for (final read in asked) streamWindowReadHere(read)]);
      await pumpEventQueue();
    }

    test('🎯nothing changed meanwhile: it moves the window there', () async {
      await followTo(5000);
      expect(window.centerSample, 0, reason: 'moved before it landed');
      await land();
      expect(window.centerSample, 5000);
    }, skip: skip);

    test('🚨the player stopped meanwhile: it uploads nothing', () async {
      await followTo(5000);
      carrying = null;
      await land();
      expect(window.centerSample, 0);
    }, skip: skip);

    test('🚨another mix was put in meanwhile: its windows are not of it, and '
        'it uploads nothing', () async {
      await followTo(5000);
      window.mix = mixOf(['a', 'b']);
      await land();
      expect(window.centerSample, 0);
    }, skip: skip);

    test('🚨the window was uploaded anew meanwhile (a seek, an edit): the '
        'newer upload stands', () async {
      await followTo(5000);
      expect(
        window.upload(
          device: device,
          conformStore: store,
          deviceRate: sampleRate,
          centerSample: 9000,
        ),
        isTrue,
      );
      await land();
      expect(window.centerSample, 9000);
    }, skip: skip);

    test('🚨windows that did not land whole upload nothing — the old window '
        'still has fifteen seconds to play', () async {
      await followTo(5000);
      reading.complete(null);
      await pumpEventQueue();
      expect(window.centerSample, 0);
    }, skip: skip);

    test('a read the memory was not there for uploads nothing — the old '
        'schedule plays on, and nothing is thrown at the tick', () async {
      await followTo(5000);
      reading.completeError(StateError('no memory for a window'));
      await pumpEventQueue();
      expect(window.centerSample, 0);
    }, skip: skip);

    test('one read at a time: ticks while it is out ask for no second '
        'one', () async {
      await followTo(5000);
      window.followPlayback(
        positionSamples: 6000,
        deviceRate: sampleRate,
        conformStore: store,
        current: () => carrying,
      );
      await pumpEventQueue();
      expect(readsAsked, 1);
      await land();
      expect(window.centerSample, 5000);
    }, skip: skip);
  });
}
