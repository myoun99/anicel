import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/core/on_a_worker.dart';
import 'package:anicel/src/models/project_frame_rate.dart';
import 'package:anicel/src/native/gpu_engine_asset.dart';
import 'package:anicel/src/native/qa_audio_device.dart';
import 'package:anicel/src/services/audio/audio_conform_pipeline.dart';
import 'package:anicel/src/services/audio/audio_mixer_reference.dart'
    show AudioMixSource;
import 'package:anicel/src/services/audio/conform_pcm_codec.dart';
import 'package:anicel/src/services/audio/conform_pcm_stream.dart';
import 'package:anicel/src/services/audio/equalized_stream.dart'
    show StreamWindowRead;
import 'package:anicel/src/services/media/media_byte_source.dart';
import 'package:anicel/src/ui/audio/audio_conform_store.dart';
import 'package:anicel/src/ui/playback/audio_playback_schedule.dart';
import 'package:anicel/src/ui/playback/audio_windowed_upload.dart';

import '../../helpers/stream_windows_read_here.dart';
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
  late Directory directory;

  setUp(() async {
    QaAudioDevice.debugResetForTests();
    directory = await Directory.systemTemp.createTemp('qa-window-worker');
  });

  tearDown(() {
    try {
      QaAudioDevice.instance?.close();
    } on Object {
      // A device that never opened is fine to "close".
    }
    QaAudioDevice.debugResetForTests();
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
    backSeconds: AudioStreamingWindow.playing.backSeconds,
    aheadSeconds: AudioStreamingWindow.playing.aheadSeconds,
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
  });

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

  test('a window that holds nothing (asked past its file\'s end) makes no '
      'buffer, and lands as an empty window', () async {
    final device = openNull();
    final (store, _) = await streamingStore();
    final reader = planAround(store, mixOf(['a']), 5000).reads.single.reader;
    final past = (
      reader: reader,
      start: reader.length + 10,
      count: 100,
      equalized: null,
    );
    final made = <int>[];
    final hands = (
      make: (int floats) {
        made.add(floats);
        return calloc<Float>(floats);
      },
      release: (Pointer<Float> buffer) => calloc.free(buffer),
    );

    expect(readStreamWindowsInto([past], hands), [
      (startSample: reader.length, address: 0, floats: 0),
    ]);
    expect(made, isEmpty, reason: 'a buffer for nothing, which nothing frees');
    final windows = (await readStreamWindowsOnAWorker([past], device))!;
    expect(windows.single.samples, isEmpty);
    expect(windows.single.sourceStart, reader.length);
  });

  test('🚨and on the worker\'s road, windows that did not land whole are '
      'none at all', () async {
    final device = openNull();
    final (store, _) = await streamingStore();
    final plan = planAround(store, mixOf(['a', 'b']), 5000);
    for (final file in directory.listSync().whereType<File>()) {
      file.deleteSync();
    }

    expect(await readStreamWindowsOnAWorker(plan.reads, device), isNull);
  });

  group('the hands a worker fills buffers with', () {
    test('make the device\'s own buffers, and let go of them as its lists '
        'do', () {
      final device = openNull();
      final hands = audioBuffersHere();
      final buffer = hands.make(8);
      final samples = device.adoptSamples(buffer.address, 8);
      expect(device.debugHoldsOf(samples), 1, reason: 'its maker\'s');
      // A hold of the test's own, for the hands to let go of.
      _retain(buffer);
      expect(device.debugHoldsOf(samples), 2);

      hands.release(buffer);

      expect(device.debugHoldsOf(samples), 1, reason: 'the list\'s alone');
    });

    test('throw where the memory is not there, rather than hand back a '
        'buffer that is none', () {
      expect(() => audioBuffersHere().make(-1), throwsStateError);
    });
  });

  test('🎯a window reads on a worker unless a test holds the read', () {
    expect(
      AudioStreamingWindow().readWindows,
      same(readStreamWindowsOnAWorker),
      reason: 'a move read on the thread that draws again',
    );
  });

  /// 🚨EVERY MOVE takes the advance's road
  /// (long-sound-windows-are-read-on-the-ui-isolate, 11-15): planned here,
  /// read on a worker, put here. ↩️An arm, a seek, an edit, a scrub and the
  /// viewer's sound read their windows on the thread that draws.
  group('a move whose windows are read on a worker', () {
    late QaAudioDevice device;
    late AudioConformStore store;
    late AudioStreamingWindow window;
    late List<Completer<List<AudioMixSource>?>> readings;
    late List<List<StreamWindowRead>> asked;
    late int landings;
    late int ticksThatPut;
    ({QaAudioDevice device, int deviceRate})? carrying;

    setUp(() async {
      device = openNull();
      (store, _) = await streamingStore();
      readings = [];
      asked = [];
      landings = 0;
      ticksThatPut = 0;
      window = AudioStreamingWindow(
        readWindows: (reads, _) {
          asked.add(reads);
          return (readings..add(Completer())).last.future;
        },
        onLanded: () => landings += 1,
      )..mix = mixOf(['a']);
      carrying = (device: device, deviceRate: sampleRate);
    });

    OutputArm uploadAt(int centerSample) => window.upload(
      device: device,
      conformStore: store,
      deviceRate: sampleRate,
      centerSample: centerSample,
    );

    /// The [index]th read asked lands, whole: each window read as a worker
    /// reads it.
    Future<void> land(int index) async {
      readings[index].complete([
        for (final read in asked[index]) streamWindowReadHere(read),
      ]);
      await pumpEventQueue();
    }

    /// The device at [at], and the tick that follows it there — counted
    /// where it goes on to upload: a tick asks who carries the window only
    /// then.
    void tickAt(int at) {
      device.seek(at);
      window.followPlayback(
        positionSamples: at,
        deviceRate: sampleRate,
        conformStore: store,
        current: () {
          ticksThatPut += 1;
          return carrying;
        },
      );
    }

    /// The window armed around 0, its windows landed.
    Future<void> armedAtZero() async {
      expect(uploadAt(0), isA<OutputComing>());
      await land(0);
      expect(uploadAt(0), isA<OutputArmed>());
      expect(window.centerSample, 0);
    }

    test('🎯an upload says its windows are coming, tells its owner once they '
        'land, and asked again puts them — reading nothing', () async {
      expect(uploadAt(5000), isA<OutputComing>());
      expect(asked, hasLength(1));
      expect(window.centerSample, 0, reason: 'nothing moved before it lands');
      expect(landings, 0);

      await land(0);
      expect(landings, 1);

      expect(uploadAt(5000), isA<OutputArmed>());
      expect(window.centerSample, 5000);
      expect(window.hasStreaming, isTrue);
      expect(asked, hasLength(1), reason: 'the windows that landed, put');
    });

    test('asked again while they are on their way, for where they hold, it '
        'reads no second time', () async {
      expect(uploadAt(5000), isA<OutputComing>());
      expect(uploadAt(5100), isA<OutputComing>());
      expect(asked, hasLength(1));

      await land(0);
      expect(uploadAt(5100), isA<OutputArmed>());
      expect(window.centerSample, 5000, reason: 'where they were read');
    });

    test('🚨asked somewhere they do not hold meanwhile, the later ask '
        'stands: what lands for the earlier is not kept', () async {
      expect(uploadAt(5000), isA<OutputComing>());
      expect(uploadAt(9000), isA<OutputComing>());
      expect(asked, hasLength(2));

      await land(0);
      expect(landings, 0, reason: 'nobody waits for those');
      expect(uploadAt(9000), isA<OutputComing>());
      expect(asked, hasLength(2), reason: 'the later read is still out');

      await land(1);
      expect(uploadAt(9000), isA<OutputArmed>());
      expect(window.centerSample, 9000);
    });

    test('🎯an advance: the tick after its windows land moves the window '
        'there', () async {
      await armedAtZero();
      tickAt(5000);
      expect(asked, hasLength(2));
      expect(window.centerSample, 0, reason: 'moved before it landed');

      await land(1);
      expect(window.centerSample, 0, reason: 'put by a tick, not the landing');
      tickAt(5010);
      expect(window.centerSample, 5000);
    });

    test('🚨the player stopped meanwhile: it moves nothing', () async {
      await armedAtZero();
      tickAt(5000);
      carrying = null;
      await land(1);
      tickAt(5010);
      expect(window.centerSample, 0);
    });

    test('🚨another mix was put in meanwhile: its windows are not of it, and '
        'it reads that mix\'s', () async {
      await armedAtZero();
      tickAt(5000);
      window.mix = mixOf(['a', 'b']);
      await land(1);
      tickAt(5010);
      expect(window.centerSample, 0);
      expect(asked, hasLength(3));
      expect(asked.last, hasLength(2), reason: 'the new mix\'s two windows');
    });

    test('🚨an edit mid-run — another mix put where the stream stands: the '
        'tick after its windows land puts them, though the stream wants no '
        'window moved (AudioDeviceTransport.refreshSchedule)', () async {
      await armedAtZero();
      window.mix = mixOf(['a', 'b']);
      expect(uploadAt(10), isA<OutputComing>(), reason: 'the new mix\'s');
      expect(asked, hasLength(2));
      expect(asked.last, hasLength(2), reason: 'its two windows');

      await land(1);
      expect(window.centerSample, 0, reason: 'put by a tick, not the landing');
      tickAt(20);
      expect(
        window.centerSample,
        10,
        reason: 'the edit is heard at the next look — ↩️a tick put only a '
            'window it wanted moved, and the old mix played on till the '
            'stream got past half of it, up to fifteen seconds',
      );
      expect(asked, hasLength(2), reason: 'out of what landed');
    });

    test('🚨windows a tick put are on the device: the ticks after it put '
        'nothing again', () async {
      await armedAtZero();
      tickAt(5000);
      await land(1);
      tickAt(5010);
      expect(window.centerSample, 5000, reason: 'fixture: put');
      final put = ticksThatPut;

      tickAt(5020);
      tickAt(5030);
      expect(
        ticksThatPut,
        put,
        reason: '↩️kept as landed and not yet put, they were put again at '
            'every look of the run',
      );
    });

    test('🚨a mix with no stream put in lets go of the windows read for the '
        'one before: no tick puts for them', () async {
      await armedAtZero();
      tickAt(5000);
      await land(1); // landed, and not put yet
      window.mix = mixOf([]);
      expect(uploadAt(5000), isA<OutputArmed>(), reason: 'nothing to read');
      expect(window.hasStreaming, isFalse);
      final put = ticksThatPut;

      tickAt(5010);
      expect(
        ticksThatPut,
        put,
        reason: '↩️what had landed for the stream stood as not yet put, and '
            'every tick put the mix again',
      );
      expect(window.centerSample, 5000, reason: 'where the upload put it');
    });

    test('🚨and of those still on their way: nobody is told they landed, '
        'and nothing is kept of them', () async {
      await armedAtZero();
      tickAt(5000);
      window.mix = mixOf([]);
      expect(uploadAt(5000), isA<OutputArmed>());
      final told = landings;
      final put = ticksThatPut;

      await land(1);
      expect(landings, told, reason: 'no one waits for a stream that is gone');
      tickAt(5010);
      expect(ticksThatPut, put, reason: 'nor is there anything to put');
    });

    test('🚨windows that did not land whole are not put by a tick — the old '
        'window still has fifteen seconds to play — and the next reads '
        'again', () async {
      await armedAtZero();
      tickAt(5000);
      readings[1].complete(null);
      await pumpEventQueue();
      tickAt(5010);
      expect(window.centerSample, 0);
      expect(asked, hasLength(3));
    });

    test('a read the memory was not there for is the same: nothing is put, '
        'and nothing is thrown at the tick', () async {
      await armedAtZero();
      tickAt(5000);
      readings[1].completeError(StateError('no memory for a window'));
      await pumpEventQueue();
      tickAt(5010);
      expect(window.centerSample, 0);
    });

    test('but an arm has no window where it starts to keep: it puts what '
        'came back', () async {
      expect(uploadAt(5000), isA<OutputComing>());
      readings[0].complete(null);
      await pumpEventQueue();
      expect(landings, 1, reason: 'its owner waits for it');

      expect(uploadAt(5000), isA<OutputArmed>());
      expect(window.centerSample, 5000);
    });

    test('one read at a time: ticks while it is out ask for no second '
        'one', () async {
      await armedAtZero();
      tickAt(5000);
      tickAt(5100);
      expect(asked, hasLength(2));
      await land(1);
      tickAt(5200);
      expect(window.centerSample, 5000);
    });

    test('🚨a start the window as it stands plays is played now — its move '
        'read meanwhile; one outside its edges waits for the move', () async {
      expect(uploadAt(5000), isA<OutputComing>());
      await land(0);
      expect(uploadAt(5000), isA<OutputArmed>());

      bool covers(int at) => window.cover(
        at,
        device: device,
        conformStore: store,
        deviceRate: sampleRate,
      );
      // At 100 Hz the window trails 200 samples, and moves 100 behind.
      expect(covers(4850), isTrue, reason: 'inside its trailing edge');
      expect(asked, hasLength(2), reason: 'moved there all the same');
      expect(covers(4700), isFalse, reason: 'past it: silence till it lands');
      // And leads 3000, moving 1500 ahead.
      expect(covers(7000), isTrue, reason: 'inside its leading edge');
      expect(covers(8100), isFalse, reason: 'past that one too');
    });
  });
}

/// A hold of the test's own on a device buffer, taken in the engine that
/// made it.
@Native<Pointer<Float> Function(Pointer<Float>)>(
  symbol: 'qa_audio_buffer_retain',
  assetId: gpuEngineAsset,
)
external Pointer<Float> _retain(Pointer<Float> samples);
