import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/project_frame_rate.dart';
import 'package:anicel/src/services/audio/audio_conform_pipeline.dart';
import 'package:anicel/src/services/audio/audio_conform_runner.dart';
import 'package:anicel/src/services/audio/sound_filters.dart';
import 'package:anicel/src/ui/audio/audio_conform_store.dart';

/// 🚨A DRAGGED KNOB'S BAKES ARE BOUNDED BY ITS SLOT (agreed with 저장 on
/// board audio-fx-grows-like-the-pros, 11-17): each value a knob passes is
/// a span of its own, so a store that kept every one kept a whole span a
/// value, and kicked a worker a value. A slot — a row's clip — holds the
/// bake last asked of it and the one last made: two at most, one under
/// way at a time, and once the knob stops, at most two more kicked.
void main() {
  const rate = ProjectFrameRate.fps24;
  const sampleRate = 48000;
  int sampleOf(int frame) => rate.frameToSample(frame, sampleRate);

  const knob = (row: LayerId('s1'), clip: FrameId('f1'));
  const other = (row: LayerId('s2'), clip: FrameId('f1'));

  /// The span [slot]'s knob makes standing at [db] dB of lows.
  FilteredSpan at(double db, {FilterSlot slot = knob}) => FilteredSpan(
    slot: slot,
    start: 0,
    length: sampleOf(4),
    stages: [
      [
        (
          start: 0,
          filter: AudioEqualizer(
            lowCut: 0,
            highCut: 0,
            lowShelf: 250,
            lowDb: db,
            highShelf: 4000,
            highDb: 0,
          ),
        ),
      ],
    ],
  );

  final sound = Float32List(2 * sampleOf(10));
  for (var index = 0; index < sound.length; index += 1) {
    sound[index] = ((index * 7919) % 2001) / 1000.0 - 1.0;
  }

  late List<FilterRequest> kicked;
  late List<Completer<void>> gates;
  late int underWay;
  late int mostUnderWay;
  late AudioConformStore store;

  setUp(() {
    kicked = [];
    gates = [];
    underWay = 0;
    mostUnderWay = 0;
    store = AudioConformStore(
      resolveConformPath: (_) => null,
      runner: (request) async => ConformResult(
        outcome: ConformOutcome.built,
        samples: sound,
        channels: 2,
        sampleRate: sampleRate,
        frames: sound.length ~/ 2,
      ),
      // Each bake waits at a gate of its own till the test opens it.
      filterRunner: (request) async {
        kicked.add(request);
        underWay += 1;
        mostUnderWay = underWay > mostUnderWay ? underWay : mostUnderWay;
        final gate = Completer<void>();
        gates.add(gate);
        await gate.future;
        underWay -= 1;
        return runFilterHere(request);
      },
      log: (_) {},
    );
  });

  tearDown(() {
    for (final gate in gates) {
      if (!gate.isCompleted) {
        gate.complete();
      }
    }
    store.dispose();
  });

  Future<void> conformed() async {
    store.resultFor('a.wav');
    await pumpEventQueue();
  }

  /// Opens every gate there is and lets what passed land.
  Future<void> landAll() async {
    for (final gate in gates) {
      if (!gate.isCompleted) {
        gate.complete();
      }
    }
    await pumpEventQueue();
  }

  test('🎯a knob dragged through twenty values while one bakes kicks one, '
      'then the one it stopped at', () async {
    await conformed();
    for (var db = 1; db <= 20; db += 1) {
      store.filteredAt('a.wav', sampleRate, at(db.toDouble()));
    }
    expect(kicked.map((bake) => bake.span), [at(1)]);
    await landAll();
    // The run asks again as the bake lands, for where the knob stands.
    expect(store.filteredAt('a.wav', sampleRate, at(20)), isNull);
    await landAll();
    expect(kicked.map((bake) => bake.span), [at(1), at(20)]);
    expect(store.filteredAt('a.wav', sampleRate, at(20)), isNotNull);
    expect(mostUnderWay, 1);
  });

  test('🎯a slot holds two bakes at most, however far its knob goes', () async {
    await conformed();
    var most = 0;
    for (var db = 1; db <= 12; db += 1) {
      // A run that asks at every step and lets each bake land: the
      // knob's every value is made in turn.
      store.filteredAt('a.wav', sampleRate, at(db.toDouble()));
      await landAll();
      store.filteredAt('a.wav', sampleRate, at(db.toDouble()));
      final held = store.heldFilteringsOf('a.wav');
      most = held > most ? held : most;
    }
    expect(kicked, hasLength(12));
    expect(most, lessThanOrEqualTo(2));
    expect(store.heldFilteringsOf('a.wav'), 1);
  });

  test('the bake a knob moved back to stays held while the next is made',
      () async {
    await conformed();
    store.filteredAt('a.wav', sampleRate, at(1));
    await landAll();
    expect(store.filteredAt('a.wav', sampleRate, at(1)), isNotNull);
    store.filteredAt('a.wav', sampleRate, at(2));
    // Back where it was before the second lands: the first is still held.
    expect(store.filteredAt('a.wav', sampleRate, at(1)), isNotNull);
    await landAll();
    expect(store.filteredAt('a.wav', sampleRate, at(1)), isNotNull);
    expect(kicked.map((bake) => bake.span), [at(1), at(2)]);
  });

  test('🎯two slots on one sound never let go of each other\'s bakes',
      () async {
    await conformed();
    store
      ..filteredAt('a.wav', sampleRate, at(1))
      ..filteredAt('a.wav', sampleRate, at(5, slot: other));
    await landAll();
    // A run asks for both at every landing: each made once, both held.
    for (var round = 0; round < 3; round += 1) {
      expect(store.filteredAt('a.wav', sampleRate, at(1)), isNotNull);
      expect(
        store.filteredAt('a.wav', sampleRate, at(5, slot: other)),
        isNotNull,
      );
      await landAll();
    }
    expect(kicked, hasLength(2));
    expect(store.heldFilteringsOf('a.wav'), 2);
  });
}
