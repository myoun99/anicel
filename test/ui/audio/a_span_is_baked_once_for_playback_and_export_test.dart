import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/project_frame_rate.dart';
import 'package:anicel/src/native/qa_audio_equalizer.dart';
import 'package:anicel/src/services/audio/audio_conform_pipeline.dart';
import 'package:anicel/src/services/audio/audio_conform_runner.dart';
import 'package:anicel/src/services/audio/audio_equalizer.dart';
import 'package:anicel/src/ui/audio/audio_conform_store.dart';
import 'package:anicel/src/ui/audio/sound_cannot_play.dart';
import 'package:anicel/src/ui/export/export_audio_mix.dart';
import 'package:anicel/src/ui/playback/audio_playback_schedule.dart';

/// 🚨A SPAN OF A SOUND IS BAKED THROUGH ITS ROW'S EQUALIZER ONCE, FROM ITS
/// OWN FIRST SAMPLE, AND PLAYBACK AND AN EXPORT READ THAT ONE BAKE (board
/// audio-fx-grows-like-the-pros ③ — 「라이브 = 익스포트」).
///
/// A filter remembers what it heard: begun where a run or an export
/// starts, it would play other samples there than one begun at the span's
/// start. So the bake is of the whole span, keyed by it, kept beside the
/// conform it was cut from and let go of with it.
void main() {
  const rate = ProjectFrameRate.fps24;
  const sampleRate = 48000;
  // 2,000 samples a frame at 24 fps and 48 kHz.
  int sampleOf(int frame) => rate.frameToSample(frame, sampleRate);

  const every = AudioEqualizer(
    lowCut: 80,
    highCut: 12000,
    lowShelf: 250,
    lowDb: -2,
    highShelf: 4000,
    highDb: 3,
  );
  const darker = AudioEqualizer(
    lowCut: 120,
    highCut: 3000,
    lowShelf: 250,
    lowDb: 6,
    highShelf: 4000,
    highDb: -9,
  );

  /// A row's equalizer over a span trimmed [spanOffsetFrames] into the
  /// file, ten frames long, turning darker four frames in.
  ScheduledEqualizer overTheSpan(int spanOffsetFrames) => ScheduledEqualizer(
    spanOffsetFrames: spanOffsetFrames,
    spanFrames: 10,
    settings: const [
      (frame: 0, equalizer: every),
      (frame: 4, equalizer: darker),
    ],
  );

  /// Thirty frames of a well-mixed stereo sound.
  final sound = Float32List(2 * sampleOf(30));
  for (var index = 0; index < sound.length; index += 1) {
    sound[index] = ((index * 7919) % 2001) / 1000.0 - 1.0;
  }

  ConformResult conformed() => ConformResult(
    outcome: ConformOutcome.built,
    samples: sound,
    channels: 2,
    sampleRate: sampleRate,
    frames: sound.length ~/ 2,
  );

  late List<EqualizeRequest> bakes;
  late AudioConformStore store;

  setUp(() {
    bakes = [];
    store = AudioConformStore(
      resolveConformPath: (_) => null,
      runner: (request) async => conformed(),
      equalizeRunner: (request) async {
        bakes.add(request);
        return runEqualizeHere(request);
      },
      log: (_) {},
    );
  });

  tearDown(() => store.dispose());

  /// The upload a run of [schedule] plans once every bake it asks for has
  /// landed.
  Future<WindowedUploadPlan> uploadOf(List<ScheduledAudioClip> schedule) async {
    final mix = audioMixScheduleFrom(
      schedule: schedule,
      rate: rate,
      sampleRate: sampleRate,
    );
    for (var tries = 0; tries < 10; tries += 1) {
      final plan = planWindowedMixUpload(
        mix: mix,
        conformStore: store,
        deviceRate: sampleRate,
        centerSample: 0,
        backSeconds: 1,
        aheadSeconds: 4,
      );
      if (plan != null) {
        return plan;
      }
      await pumpEventQueue();
    }
    fail('the upload never landed');
  }

  test('the span\'s frames become its samples, each setting on the sample '
      'its frame begins at', () {
    final mix = audioMixScheduleFrom(
      schedule: [
        ScheduledAudioClip(
          filePath: 'a.wav',
          startFrame: 0,
          endFrameExclusive: 10,
          offsetFrames: 2,
          equalizer: overTheSpan(2),
        ),
      ],
      rate: rate,
      sampleRate: sampleRate,
    );
    expect(mix.sources, [
      (
        path: 'a.wav',
        equalized: EqualizedSpan(
          start: sampleOf(2),
          length: sampleOf(10),
          settings: [
            (start: 0, equalizer: every),
            (start: sampleOf(4), equalizer: darker),
          ],
        ),
      ),
    ]);
  });

  test('🎯the bake is the span from its own first sample, wherever a run '
      'begins in it', () async {
    final expected = equalizeAudio(
      samples: Float32List.sublistView(
        sound,
        2 * sampleOf(2),
        2 * sampleOf(12),
      ),
      channels: 2,
      rate: sampleRate,
      settings: [
        (start: 0, equalizer: every),
        (start: sampleOf(4), equalizer: darker),
      ],
    );
    // A run from the span's start, and one begun three frames into it —
    // the clip's trim bumped by the lead it clipped, as a window does.
    final fromItsStart = await uploadOf([
      ScheduledAudioClip(
        filePath: 'a.wav',
        startFrame: 0,
        endFrameExclusive: 10,
        offsetFrames: 2,
        equalizer: overTheSpan(2),
      ),
    ]);
    final fromInside = await uploadOf([
      ScheduledAudioClip(
        filePath: 'a.wav',
        startFrame: 0,
        endFrameExclusive: 7,
        offsetFrames: 5,
        equalizer: overTheSpan(2),
      ),
    ]);

    final atStart = fromItsStart.resident.single;
    final inside = fromInside.resident.single;
    expect(atStart.samples, expected);
    expect(atStart.sourceStart, sampleOf(2));
    expect(identical(inside.samples, atStart.samples), isTrue,
        reason: 'one bake');
    expect(inside.sourceStart, sampleOf(2));
    expect(fromInside.clips.single.sourceOffset, sampleOf(5),
        reason: 'the run reads the bake three frames in');
    expect(bakes, hasLength(1));
  });

  test('🎯an export mixes the bake the run plays', () async {
    final clip = ScheduledAudioClip(
      filePath: 'a.wav',
      startFrame: 0,
      endFrameExclusive: 10,
      offsetFrames: 2,
      equalizer: overTheSpan(2),
    );
    final played = (await uploadOf([clip])).resident.single;
    final source = audioMixScheduleFrom(
      schedule: [clip],
      rate: rate,
      sampleRate: sampleRate,
    ).sources.single;

    final exported = await exportSourcesOf(store)(source);

    expect(identical(exported!.samples, played.samples), isTrue);
    expect(exported.sourceStart, played.sourceStart);
    expect(exported.channels, played.channels);
    expect(bakes, hasLength(1));
  });

  test('an export waits for a bake still under way', () async {
    final source = (
      path: 'a.wav',
      equalized: EqualizedSpan(
        start: sampleOf(2),
        length: sampleOf(10),
        settings: const [(start: 0, equalizer: every)],
      ),
    );
    final exported = await exportSourcesOf(store)(source);
    expect(exported!.samples, hasLength(2 * sampleOf(10)));
    expect(bakes, hasLength(1));
  });

  test('a span with no equalizer plays the conform itself, from its first '
      'sample', () async {
    final upload = await uploadOf([
      const ScheduledAudioClip(
        filePath: 'a.wav',
        startFrame: 0,
        endFrameExclusive: 10,
        offsetFrames: 2,
      ),
    ]);
    expect(identical(upload.resident.single.samples, sound), isTrue);
    expect(upload.resident.single.sourceStart, 0);
    expect(bakes, isEmpty);
  });

  test('a bake under way is landing; it lands with a notify and is kept',
      () async {
    final span = EqualizedSpan(
      start: 0,
      length: sampleOf(4),
      settings: const [(start: 0, equalizer: every)],
    );
    store.resultFor('a.wav');
    await pumpEventQueue();
    var notified = 0;
    store.addListener(() => notified += 1);

    expect(store.equalizedAt('a.wav', sampleRate, span), isNull);
    expect(store.equalizedAt('a.wav', sampleRate, span), isNull);
    expect(store.isLanding('a.wav', sampleRate), isTrue);
    expect(store.isLanding('a.wav', 44100), isFalse, reason: 'another rate');
    await pumpEventQueue();

    expect(notified, 1);
    expect(store.isLanding('a.wav', sampleRate), isFalse);
    expect(store.equalizedAt('a.wav', sampleRate, span), isNotNull);
    expect(bakes, hasLength(1), reason: 'one bake for the span');
    expect(bakes.single.span, span);
    expect(identical(bakes.single.samples, sound), isTrue);
    expect((bakes.single.channels, bakes.single.rate), (2, sampleRate));
  });

  test('another span of the same sound is another bake', () async {
    store.resultFor('a.wav');
    await pumpEventQueue();
    final spans = [
      for (final start in [0, sampleOf(3)])
        EqualizedSpan(
          start: start,
          length: sampleOf(4),
          settings: const [(start: 0, equalizer: every)],
        ),
    ];
    for (final span in spans) {
      store.equalizedAt('a.wav', sampleRate, span);
    }
    await pumpEventQueue();
    expect([for (final bake in bakes) bake.span], spans);
    expect(
      identical(
        store.equalizedAt('a.wav', sampleRate, spans.first),
        store.equalizedAt('a.wav', sampleRate, spans.last),
      ),
      isFalse,
    );
  });

  test('forgetting the sound forgets its bakes', () async {
    final span = EqualizedSpan(
      start: 0,
      length: sampleOf(4),
      settings: const [(start: 0, equalizer: every)],
    );
    store.resultFor('a.wav');
    await pumpEventQueue();
    store.equalizedAt('a.wav', sampleRate, span);
    await pumpEventQueue();
    expect(store.equalizedAt('a.wav', sampleRate, span), isNotNull);

    store.invalidate('a.wav');
    store.resultFor('a.wav');
    await pumpEventQueue();
    expect(store.equalizedAt('a.wav', sampleRate, span), isNull);
    await pumpEventQueue();
    expect(bakes, hasLength(2));
  });

  test('a bake landing after its conform was let go of is dropped', () async {
    final baking = Completer<Float32List>();
    final slow = AudioConformStore(
      resolveConformPath: (_) => null,
      runner: (request) async => conformed(),
      equalizeRunner: (request) => baking.future,
      log: (_) {},
    );
    addTearDown(slow.dispose);
    const span = EqualizedSpan(
      start: 0,
      length: 4,
      settings: [(start: 0, equalizer: every)],
    );
    slow.resultFor('a.wav');
    await pumpEventQueue();
    slow.equalizedAt('a.wav', sampleRate, span);
    slow.invalidate('a.wav');
    slow.resultFor('a.wav');
    await pumpEventQueue();

    baking.complete(Float32List(8));
    await pumpEventQueue();
    expect(
      slow.equalizedAt('a.wav', sampleRate, span),
      isNull,
      reason: 'the bake was of the conform let go of',
    );
  });

  test('a bake the engine would not make is not kicked again, and the run '
      'plays the span without it — saying so', () async {
    var tries = 0;
    final failing = AudioConformStore(
      resolveConformPath: (_) => null,
      runner: (request) async => conformed(),
      equalizeRunner: (request) async {
        tries += 1;
        throw StateError('refused');
      },
      log: (_) {},
    );
    addTearDown(failing.dispose);
    const span = EqualizedSpan(
      start: 0,
      length: 4,
      settings: [(start: 0, equalizer: every)],
    );
    failing.resultFor('a.wav');
    await pumpEventQueue();
    failing.equalizedAt('a.wav', sampleRate, span);
    await pumpEventQueue();

    expect(failing.equalizedAt('a.wav', sampleRate, span), isNull);
    expect(failing.isLanding('a.wav', sampleRate), isFalse);
    await pumpEventQueue();
    expect(tries, 1);
    expect(
      failing.cannotPlayAt('a.wav', sampleRate, equalized: span),
      SoundCannotPlay.conform,
    );
    expect(
      failing.cannotPlayAt('a.wav', sampleRate),
      isNull,
      reason: 'the sound itself plays',
    );
    expect(
      await exportSourcesOf(failing)((path: 'a.wav', equalized: span)),
      isNull,
    );
  });

  test('a bake that failed on a conform let go of does not stop the next '
      'conform\'s', () async {
    final first = Completer<Float32List>();
    var tries = 0;
    final moving = AudioConformStore(
      resolveConformPath: (_) => null,
      runner: (request) async => conformed(),
      equalizeRunner: (request) {
        tries += 1;
        return tries == 1 ? first.future : Future.value(Float32List(8));
      },
      log: (_) {},
    );
    addTearDown(moving.dispose);
    const span = EqualizedSpan(
      start: 0,
      length: 4,
      settings: [(start: 0, equalizer: every)],
    );
    moving.resultFor('a.wav');
    await pumpEventQueue();
    moving.equalizedAt('a.wav', sampleRate, span);
    moving.invalidate('a.wav');
    moving.resultFor('a.wav');
    await pumpEventQueue();

    first.completeError(StateError('its file went away'));
    await pumpEventQueue();
    moving.equalizedAt('a.wav', sampleRate, span);
    await pumpEventQueue();
    expect(tries, 2, reason: 'the failure was of the conform let go of');
    expect(moving.equalizedAt('a.wav', sampleRate, span), isNotNull);
  });

  test('forgetting the sound lets a bake that failed be tried again', () async {
    var tries = 0;
    final once = AudioConformStore(
      resolveConformPath: (_) => null,
      runner: (request) async => conformed(),
      equalizeRunner: (request) async {
        tries += 1;
        return tries == 1 ? throw StateError('refused') : Float32List(8);
      },
      log: (_) {},
    );
    addTearDown(once.dispose);
    const span = EqualizedSpan(
      start: 0,
      length: 4,
      settings: [(start: 0, equalizer: every)],
    );
    once.resultFor('a.wav');
    await pumpEventQueue();
    once.equalizedAt('a.wav', sampleRate, span);
    await pumpEventQueue();
    expect(once.equalizedAt('a.wav', sampleRate, span), isNull);

    once.invalidate('a.wav');
    once.resultFor('a.wav');
    await pumpEventQueue();
    once.equalizedAt('a.wav', sampleRate, span);
    await pumpEventQueue();
    expect(tries, 2);
    expect(once.equalizedAt('a.wav', sampleRate, span), isNotNull);
  });

  group('runEqualizeHere', () {
    test('bakes only the samples of the span the conform holds', () {
      final baked = runEqualizeHere(
        EqualizeRequest(
          samples: Float32List.fromList([1, 2, 3, 4, 5, 6]),
          channels: 2,
          rate: sampleRate,
          span: const EqualizedSpan(
            start: 1,
            length: 9,
            settings: [
              (
                start: 0,
                equalizer: AudioEqualizer.none(lowShelf: 250, highShelf: 4000),
              ),
            ],
          ),
        ),
      );
      expect(baked, [3, 4, 5, 6]);
    });

    test('throws where the engine refuses what it was handed', () {
      expect(
        () => runEqualizeHere(
          EqualizeRequest(
            samples: Float32List(8),
            channels: 2,
            rate: 0,
            span: const EqualizedSpan(start: 0, length: 4, settings: []),
          ),
        ),
        throwsStateError,
      );
    });
  });
}
