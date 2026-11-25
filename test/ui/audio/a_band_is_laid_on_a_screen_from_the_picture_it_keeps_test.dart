import 'dart:typed_data';

import 'package:anicel/src/models/project_frame_rate.dart';
import 'package:anicel/src/native/app_gpu_engine.dart';
import 'package:anicel/src/services/audio/audio_peaks_extractor.dart';
import 'package:anicel/src/ui/audio/engine_wave_band.dart';
import 'package:anicel/src/ui/audio/engine_wave_views.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/the_apps_engine_let_go.dart';
import '../../helpers/tiles_laid.dart';

/// A band no row's tile holds — the viewer's face, the offset strip — is
/// baked on the engine into a picture of its own and laid on the grid's
/// screen its slot lays on ([EngineWaveBand]): kept while what it was baked
/// of stays, baked again when that moves, let go of with the engine.
void main() {
  const rate = ProjectFrameRate.fps24;
  final peaks = AudioPeaks.ofChannels(
    bucketsPerSecond: 80,
    lanes: [
      Float32List.fromList([for (var i = 0; i < 160; i += 1) 0.8]),
    ],
  );

  /// The two seconds of [peaks] from frame [from], [perFrame] pixels a
  /// frame, across a band 40 tall.
  List<EngineWaveDrawing> drawn({int from = 0, double perFrame = 4}) => [
    (
      peaks: peaks,
      views: engineWaveViewsOf(
        (
          peaks: peaks,
          startFrame: 0,
          audibleFrames: peaks.durationFrames(rate),
          leadingFrames: 0,
          gain: 1,
        ),
        on: (
          along: (frame) => frame * perFrame,
          origin: from * perFrame,
          from: from,
          to: from + 50,
          axis: Axis.horizontal,
          across: 40,
          devicePixelRatio: 1,
          frameRate: rate,
        ),
        ink: const Color(0xFF204060),
      ),
    ),
  ];

  const onto = Rect.fromLTWH(10, 20, 200, 40);

  setUp(() async {
    await openAppGpuEngine();
    await appGpuGridKernels.ready;
  });

  test('a band is baked into one picture and laid onto its rect, its pixels '
      'one to one', () {
    final band = EngineWaveBand();
    addTearDown(band.letGo);
    late bool laid;
    final tiles = rowSlot().paintThrough(
      () => laid = band.layOn(onto, drawn(), 1),
    );

    expect(laid, isTrue);
    final (:picture, :from, onto: on) = tiles.single;
    expect(on, onto);
    expect(from, const Rect.fromLTWH(0, 0, 200, 40));
    final bytes = picture.picture.read();
    int alphaAt(int x, int y) => bytes[(y * 200 + x) * 4 + 3];
    expect(alphaAt(0, 20), isPositive, reason: 'the band, at its middle');
    expect(alphaAt(0, 0), 0, reason: 'past its peak, nothing');
  });

  test('a band painted again over what it was baked of lays the picture it '
      'keeps; one whose view moved is baked again, and the old let go', () {
    final band = EngineWaveBand();
    addTearDown(band.letGo);
    final slot = rowSlot();
    final first = slot.paintThrough(() => band.layOn(onto, drawn(), 1)).single;
    final again = slot.paintThrough(() => band.layOn(onto, drawn(), 1)).single;
    expect(identical(again.picture, first.picture), isTrue);

    final moved = slot
        .paintThrough(() => band.layOn(onto, drawn(from: 3), 1))
        .single;
    expect(identical(moved.picture, first.picture), isFalse);
    expect(first.picture.debugHolds, 0, reason: 'freed: none holds it');
  });

  test('🚨a band laid on a screen whose frame up does not show it yet says '
      'so, and its painter draws it as well (card a-fast-vertical-timeline-'
      'scroll-paints-row-pictures-a-notch-behind-their-labels)', () {
    final band = EngineWaveBand();
    addTearDown(band.letGo);
    late bool laid;
    final tiles = rowSlot(shownUp: false).paintThrough(
      () => laid = band.layOn(onto, drawn(), 1),
    );
    expect(tiles, hasLength(1), reason: '⛔premise: it laid the band');
    expect(laid, isFalse, reason: 'its painter draws it till a frame shows it');
  });

  test('where no screen lays, it lays nothing and says so', () {
    final band = EngineWaveBand();
    addTearDown(band.letGo);
    expect(band.layOn(onto, drawn(), 1), isFalse);
  });

  test('the picture it keeps goes with the engine it was baked on', () async {
    final band = EngineWaveBand();
    addTearDown(band.letGo);
    final slot = rowSlot();
    final first = slot.paintThrough(() => band.layOn(onto, drawn(), 1)).single;
    expect(first.picture.debugHolds, 2, reason: '⛔전제: the band and the row');

    theAppsEngineLostAndLetGo();
    expect(first.picture.debugHolds, 1, reason: 'the row\'s alone');

    await openAppGpuEngine();
    await appGpuGridKernels.ready;
    final next = slot.paintThrough(() => band.layOn(onto, drawn(), 1)).single;
    expect(identical(next.picture, first.picture), isFalse);
  });
}
