import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/project_frame_rate.dart';
import 'package:anicel/src/native/qa_audio_equalizer.dart';
import 'package:anicel/src/services/audio/audio_conform_pipeline.dart';
import 'package:anicel/src/services/audio/audio_equalizer.dart';
import 'package:anicel/src/services/audio/audio_mixer_reference.dart';
import 'package:anicel/src/services/audio/conform_pcm_codec.dart';
import 'package:anicel/src/services/audio/conform_pcm_stream.dart';
import 'package:anicel/src/services/audio/equalized_stream.dart';
import 'package:anicel/src/services/media/media_byte_source.dart';
import 'package:anicel/src/ui/audio/audio_conform_store.dart';
import 'package:anicel/src/ui/export/export_audio_mix.dart';
import 'package:anicel/src/ui/playback/audio_playback_schedule.dart';

import '../../helpers/stream_windows_read_here.dart';
import '../../helpers/temp_dir.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer_id.dart';

/// The one row's clip these spans are baked for.
const aSlot = (row: LayerId('s1'), clip: FrameId('f1'));

/// 🚨A SPAN TOO LONG TO HOLD IS BAKED THROUGH ITS EQUALIZER A WINDOW AT A
/// TIME, ON FROM THE CHECKPOINT BEFORE EACH — AND EVERY WINDOW HOLDS WHAT
/// THE WHOLE SPAN BAKED AT ONCE HOLDS THERE (board
/// audio-fx-grows-like-the-pros ③).
///
/// A streamed conform is never held, so its span cannot be baked whole in
/// memory; baked to disk, its int16 would have clipped what an equalizer
/// raises past full scale. The filters' memory every quarter second is all
/// that is kept, and playback's windows and an export's blocks both read
/// through it ([readStreamedWindow]).
void main() {
  const sampleRate = 48000;
  const rate = ProjectFrameRate.fps24;
  // Two seconds of stereo; 2,000 samples a frame.
  const frames = 2 * sampleRate;

  // Raised past full scale on purpose: a bake keeps what goes over 1.
  const bright = AudioEqualizer(
    lowCut: 80,
    highCut: 0,
    lowShelf: 250,
    lowDb: 0,
    highShelf: 4000,
    highDb: 12,
  );
  const darker = AudioEqualizer(
    lowCut: 120,
    highCut: 3000,
    lowShelf: 250,
    lowDb: 6,
    highShelf: 4000,
    highDb: -9,
  );

  /// The span three frames into the file, forty long, darker fifteen in.
  const span = ScheduledEqualizer(
    slot: aSlot,
    spanOffsetFrames: 3,
    spanFrames: 40,
    stages: [[
      (frame: 0, equalizer: bright),
      (frame: 15, equalizer: darker),
    ]],
  );
  const spanStart = 6000;
  const spanEnd = 86000;
  const equalized = EqualizedSpan(
    slot: aSlot,
    start: spanStart,
    length: spanEnd - spanStart,
    stages: [[
      (start: 0, equalizer: bright),
      (start: 30000, equalizer: darker),
    ]],
  );

  late Directory directory;
  late String conformPath;
  late Float32List decoded;
  late Float32List whole;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('qa-eq-checkpoints');
    final sound = Float32List(2 * frames);
    for (var index = 0; index < sound.length; index += 1) {
      sound[index] = ((index * 7919) % 2001) / 1100.0 - 0.9;
    }
    final bytes = encodeConform(
      samples: sound,
      channels: 2,
      sampleRate: sampleRate,
    );
    conformPath = '${directory.path}/long.conform';
    File(conformPath).writeAsBytesSync(bytes);
    decoded = decodeConform(bytes).samples;
    whole = equalizeAudio(
      samples: Float32List.sublistView(decoded, 2 * spanStart, 2 * spanEnd),
      channels: 2,
      rate: sampleRate,
      stages: equalized.stages,
    );
  });

  tearDown(() => deleteTempQuietly(directory));

  /// What the whole span baked at once holds for the source samples from
  /// [start] to [end].
  Float32List wholeFrom(int start, int end) => Float32List.sublistView(
    whole,
    2 * (start - spanStart),
    2 * (end - spanStart),
  );

  AudioConformStore streamingStore() {
    final store = AudioConformStore(
      resolveConformPath: (_) => conformPath,
      projectSampleRate: sampleRate,
      runner: (request) async => ConformResult(
        outcome: ConformOutcome.built,
        conformBytes: mediaAppFileSource(conformPath),
        channels: 2,
        sampleRate: sampleRate,
        frames: frames,
      ),
      log: (_) {},
    );
    addTearDown(store.dispose);
    return store;
  }

  test('the bake keeps what its equalizer raises past full scale', () {
    expect(whole.any((sample) => sample.abs() > 1), isTrue);
  });

  test('🎯every window, baked on from the checkpoint before it, is the '
      'whole span\'s bake there', () {
    final reader = ConformPcmStreamReader.open(conformPath)!;
    final checkpoints = equalizerCheckpointsOf(reader, equalized)!;
    expect(checkpoints.spacing, sampleRate ~/ 4);
    expect(checkpoints.memories, hasLength(7), reason: '80,000 / 12,000');
    expect(checkpoints.memories.first, everyElement(0));

    // The one read a window takes, through this span's checkpoints.
    ({int startSample, Float32List samples}) windowOf(int start, int count) =>
        readStreamedWindow((
          reader: reader,
          start: start,
          count: count,
          equalized: (span: equalized, checkpoints: checkpoints),
        ));

    for (final (start, end) in [
      (spanStart, spanStart + 1),
      (17999, 18001), // across a checkpoint
      (18000, 30000), // from one, to the next
      (35999, 36001), // across a setting's start
      (spanEnd - 1, spanEnd),
      (70000, spanEnd),
    ]) {
      final window = windowOf(start, end - start);
      expect(window.startSample, start, reason: '$start..$end');
      expect(window.samples, wholeFrom(start, end), reason: '$start..$end');
    }
    // Clamped into the span at either end.
    final before = windowOf(0, 10000);
    expect(before.startSample, spanStart);
    expect(before.samples, wholeFrom(spanStart, 10000));
    expect(windowOf(80000, 10000).samples, wholeFrom(80000, spanEnd));
  });

  test('🎯playback streams the whole span\'s bake, wherever the run begins '
      'in it', () async {
    final store = streamingStore();
    store.resultFor('long');
    await pumpEventQueue();
    expect(store.isStreaming('long'), isTrue);

    for (final (lead, center) in [(0, 0), (0, 40000), (10, 30000)]) {
      final mix = audioMixScheduleFrom(
        schedule: [
          ScheduledAudioClip(
            filePath: 'long',
            startFrame: 0,
            endFrameExclusive: 40 - lead,
            offsetFrames: 3 + lead,
            equalizer: span,
          ),
        ],
        rate: rate,
        sampleRate: sampleRate,
      );
      WindowedUploadPlan? plan() => planWindowedMixUpload(
        mix: mix,
        conformStore: store,
        deviceRate: sampleRate,
        centerSample: center,
        backSeconds: 0,
        aheadSeconds: 1,
      );
      var planned = plan();
      if (planned == null) {
        await pumpEventQueue();
        planned = plan();
      }
      final window = readHere(planned!).sources.single;
      final first = window.sourceStart;
      expect(
        window.samples,
        wholeFrom(first, first + window.length),
        reason: 'begun $lead frames in, around $center',
      );
      expect(window.length, greaterThan(0));
    }
  });

  test('🎯an export streamed through the checkpoints writes what one mixed '
      'from the whole bake writes', () async {
    final store = streamingStore();
    const clip = ScheduledAudioClip(
      filePath: 'long',
      startFrame: 0,
      endFrameExclusive: 40,
      offsetFrames: 3,
      equalizer: span,
    );
    // As the export does before it mixes (`_writeAudioMix`).
    await store.ensureFor('long');
    final streamedPath = '${directory.path}/streamed.wav';
    final residentPath = '${directory.path}/resident.wav';

    expect(
      await writeExportAudioMixWav(
        schedule: [clip],
        rate: rate,
        totalFrames: 40,
        sampleRate: sampleRate,
        resolveSource: exportSourcesOf(store),
        resolveStreamReader: exportStreamsOf(store),
        outputPath: streamedPath,
        device: () => null,
      ),
      isTrue,
    );
    expect(
      await writeExportAudioMixWav(
        schedule: [clip],
        rate: rate,
        totalFrames: 40,
        sampleRate: sampleRate,
        resolveSource: (_) async => AudioMixSource(
          samples: whole,
          channels: 2,
          sourceStart: spanStart,
        ),
        outputPath: residentPath,
        device: () => null,
      ),
      isTrue,
    );
    final streamed = File(streamedPath).readAsBytesSync();
    expect(streamed, File(residentPath).readAsBytesSync());
    expect(streamed.skip(44).any((byte) => byte != 0), isTrue);
  });

  test('a streamed span\'s checkpoints are made once, landing until they '
      'land, and let go of with the sound', () async {
    final store = streamingStore();
    store.resultFor('long');
    await pumpEventQueue();

    expect(store.equalizerCheckpointsFor('long', equalized), isNull);
    expect(store.isLanding('long', sampleRate), isTrue);
    expect(store.cannotPlayAt('long', sampleRate, equalized: equalized), isNull);
    await pumpEventQueue();
    final made = store.equalizerCheckpointsFor('long', equalized);
    expect(made, isNotNull);
    expect(store.isLanding('long', sampleRate), isFalse);
    expect(identical(store.equalizerCheckpointsFor('long', equalized), made),
        isTrue);

    store.invalidate('long');
    store.resultFor('long');
    await pumpEventQueue();
    expect(store.equalizerCheckpointsFor('long', equalized), isNull,
        reason: 'made again for the conform as it is now');
  });

  // 저장 (11-17): 「isLanding 이 셋을 다 세는지(대기 집합 셋)만 시험으로」.
  test('🚨a run waits on every kind of sound under way: a conform, a '
      'conversion, a bake, a long span\'s checkpoints', () async {
    final conforming = Completer<ConformResult>();
    final converting = Completer<Float32List>();
    final baking = Completer<Float32List>();
    final resident = AudioConformStore(
      resolveConformPath: (_) => null,
      runner: (request) => conforming.future,
      resampleRunner: (request) => converting.future,
      equalizeRunner: (request) => baking.future,
      log: (_) {},
    );
    addTearDown(resident.dispose);

    resident.resultFor('a');
    expect(resident.isLanding('a', sampleRate), isTrue, reason: 'conform');
    conforming.complete(
      ConformResult(
        outcome: ConformOutcome.built,
        samples: Float32List.sublistView(decoded, 0, 2 * 4000),
        channels: 2,
        sampleRate: sampleRate,
        frames: 4000,
      ),
    );
    await pumpEventQueue();
    expect(resident.isLanding('a', sampleRate), isFalse);

    resident.samplesAtRate('a', 44100);
    expect(resident.isLanding('a', 44100), isTrue, reason: 'conversion');
    converting.complete(Float32List(8));
    await pumpEventQueue();
    expect(resident.isLanding('a', 44100), isFalse);

    resident.equalizedAt(
      'a',
      sampleRate,
      const EqualizedSpan(slot: aSlot, start: 0, length: 100, stages: []),
    );
    expect(resident.isLanding('a', sampleRate), isTrue, reason: 'bake');
    baking.complete(Float32List(200));
    await pumpEventQueue();
    expect(resident.isLanding('a', sampleRate), isFalse);

    final streamed = streamingStore();
    streamed.resultFor('long');
    await pumpEventQueue();
    streamed.equalizerCheckpointsFor('long', equalized);
    expect(streamed.isLanding('long', sampleRate), isTrue,
        reason: 'checkpoints');
    await pumpEventQueue();
    expect(streamed.isLanding('long', sampleRate), isFalse);
  });
}
