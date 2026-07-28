import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/audio_clip.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/project_frame_rate.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/services/audio/audio_peaks_extractor.dart';
import 'package:anicel/src/ui/timeline/se_audio_lane.dart';
import 'package:anicel/src/ui/timeline/timeline_grid_metrics.dart';

// 2.0 s of peaks → 48 frames at fps 24.
final _peaks = AudioPeaks(bucketsPerSecond: 80, peaks: Float32List(160));

Layer _seLayer({int offsetFrames = 0}) => Layer(
  id: const LayerId('se'),
  name: 'S1',
  kind: LayerKind.se,
  frames: [Frame(id: const FrameId('se-f'), duration: 1, strokes: const [])],
  timeline: const {2: TimelineExposure.drawing(FrameId('se-f'), length: 8)},
  audioClips: [
    AudioClip(
      filePath: 'steps.wav',
      frameId: const FrameId('se-f'),
      offsetFrames: offsetFrames,
    ),
  ],
);

void main() {
  test('seAudioLanesFor exposes the audio lane only for SE layers with '
      'sounds, without key semantics', () {
    final lanes = seAudioLanesFor(_seLayer());
    expect(lanes, hasLength(1));
    expect(lanes.single.laneId, seAudioLaneId);
    expect(lanes.single.showsKeyNavigator, isFalse);
    expect(laneIsSeAudio(lanes.single), isTrue);

    expect(seAudioLanesFor(_seLayer().copyWith(audioClips: const [])), isEmpty);
    expect(
      seAudioLanesFor(
        Layer(
          id: const LayerId('cel'),
          name: 'A',
          frames: const [],
          timeline: const {},
        ),
      ),
      isEmpty,
    );
  });

  test('the audio lane value field reads the playhead span offset and '
      'scrubs at 4px per frame', () {
    final lane = seAudioLanesFor(_seLayer(offsetFrames: 3)).single;

    // Frame 4 sits inside the 2..10 block; outside frames fall back to the
    // first span so the field stays usable anywhere.
    expect(lane.valueLabel!(4), '3f');
    expect(lane.valueLabel!(11), '3f');

    expect(lane.scrubValue!('3f', const Offset(8, 0)), '5f');
    expect(lane.scrubValue!('3f', const Offset(-40, 0)), '0f');
    expect(lane.scrubValue!('bogus', const Offset(8, 0)), isNull);
  });

  test('a clip without a carrying block hides the value field', () {
    final lane = seAudioLanesFor(
      _seLayer().copyWith(timeline: const {}, frames: const []),
    ).single;
    expect(lane.valueLabel, isNull);
    expect(lane.scrubValue, isNull);
  });

  test('parseAudioOffsetInput accepts counts with optional sign and f', () {
    expect(parseAudioOffsetInput('12'), 12);
    expect(parseAudioOffsetInput('12f'), 12);
    expect(parseAudioOffsetInput('-12f'), 12);
    expect(parseAudioOffsetInput(' 7 '), 7);
    expect(parseAudioOffsetInput(''), isNull);
    expect(parseAudioOffsetInput('abc'), isNull);
  });

  Future<void> pumpLane(
    WidgetTester tester, {
    required Layer layer,
    required void Function(int clipIndex, int offsetFrames) onSetClipOffset,
    void Function(int clipIndex, int fadeInFrames, int fadeOutFrames)?
    onSetClipFades,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SeAudioLaneFrameRow(
              layer: layer,
              frameStartIndex: 0,
              frameEndIndexExclusive: 16,
              leadingFrameSpacerWidth: 0,
              trailingFrameSpacerWidth: 0,
              metrics: TimelineGridMetrics.defaults,
              frameRate: const ProjectFrameRate.integer(24),
              audioPeaksFor: (_) => _peaks,
              onSetClipOffset: onSetClipOffset,
              onSetClipFades: onSetClipFades,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('dragging the span toward the block start slides the sound '
      'deeper into the file (one commit on release)', (tester) async {
    final commits = <(int, int)>[];
    await pumpLane(
      tester,
      layer: _seLayer(),
      onSetClipOffset: (clipIndex, offsetFrames) =>
          commits.add((clipIndex, offsetFrames)),
    );

    final span = find.byKey(
      const ValueKey<String>('timeline-audio-lane-span-se-0-b2'),
    );
    expect(span, findsOneWidget);

    final cell = TimelineGridMetrics.defaults.frameCellWidth;
    await tester.drag(span, Offset(-2 * cell, 0));
    await tester.pumpAndSettle();

    expect(commits, [(0, 2)]);
  });

  testWidgets('the slide clamps at the file start (no negative offset, no '
      'phantom commit)', (tester) async {
    final commits = <(int, int)>[];
    await pumpLane(
      tester,
      layer: _seLayer(),
      onSetClipOffset: (clipIndex, offsetFrames) =>
          commits.add((clipIndex, offsetFrames)),
    );

    final cell = TimelineGridMetrics.defaults.frameCellWidth;
    await tester.drag(
      find.byKey(const ValueKey<String>('timeline-audio-lane-span-se-0-b2')),
      Offset(3 * cell, 0),
    );
    await tester.pumpAndSettle();

    expect(commits, isEmpty, reason: 'clamped back to the unchanged 0');
  });

  testWidgets('an existing trim slides back out toward the file start', (
    tester,
  ) async {
    final commits = <(int, int)>[];
    await pumpLane(
      tester,
      layer: _seLayer(offsetFrames: 5),
      onSetClipOffset: (clipIndex, offsetFrames) =>
          commits.add((clipIndex, offsetFrames)),
    );

    final cell = TimelineGridMetrics.defaults.frameCellWidth;
    await tester.drag(
      find.byKey(const ValueKey<String>('timeline-audio-lane-span-se-0-b2')),
      Offset(3 * cell, 0),
    );
    await tester.pumpAndSettle();

    expect(commits, [(0, 2)]);
  });

  testWidgets('edge-zone drags set the fade lengths; the middle keeps '
      'sliding', (tester) async {
    final offsets = <(int, int)>[];
    final fades = <(int, int, int)>[];
    await pumpLane(
      tester,
      layer: _seLayer(),
      onSetClipOffset: (clipIndex, offsetFrames) =>
          offsets.add((clipIndex, offsetFrames)),
      onSetClipFades: (clipIndex, fadeIn, fadeOut) =>
          fades.add((clipIndex, fadeIn, fadeOut)),
    );

    final span = find.byKey(
      const ValueKey<String>('timeline-audio-lane-span-se-0-b2'),
    );
    final rect = tester.getRect(span);
    final cell = TimelineGridMetrics.defaults.frameCellWidth;

    // The leading edge zone drags the fade-in length rightward.
    final fadeInGesture = await tester.startGesture(
      rect.centerLeft + const Offset(6, 0),
    );
    await fadeInGesture.moveBy(Offset(3 * cell, 0));
    await fadeInGesture.up();
    await tester.pumpAndSettle();
    expect(fades, [(0, 3, 0)]);
    expect(offsets, isEmpty);

    // The trailing edge zone drags the fade-out length leftward.
    final fadeOutGesture = await tester.startGesture(
      rect.centerRight - const Offset(6, 0),
    );
    await fadeOutGesture.moveBy(Offset(-2 * cell, 0));
    await fadeOutGesture.up();
    await tester.pumpAndSettle();
    expect(fades, [(0, 3, 0), (0, 0, 2)]);
    expect(offsets, isEmpty);

    // The middle still slides the sound.
    await tester.drag(span, Offset(-2 * cell, 0));
    await tester.pumpAndSettle();
    expect(offsets, [(0, 2)]);
    expect(fades, hasLength(2));
  });

  testWidgets('fade lengths clamp to the span and never go negative', (
    tester,
  ) async {
    final fades = <(int, int, int)>[];
    await pumpLane(
      tester,
      layer: _seLayer(),
      onSetClipOffset: (_, _) {},
      onSetClipFades: (clipIndex, fadeIn, fadeOut) =>
          fades.add((clipIndex, fadeIn, fadeOut)),
    );

    final span = find.byKey(
      const ValueKey<String>('timeline-audio-lane-span-se-0-b2'),
    );
    final rect = tester.getRect(span);
    final cell = TimelineGridMetrics.defaults.frameCellWidth;

    // Way past the span end: the fade-in clamps to the block's 8 frames.
    final overGesture = await tester.startGesture(
      rect.centerLeft + const Offset(6, 0),
    );
    await overGesture.moveBy(Offset(20 * cell, 0));
    await overGesture.up();
    await tester.pumpAndSettle();
    expect(fades, [(0, 8, 0)]);

    // Dragging the fade-in backward from zero clamps to zero: no commit
    // (the layer in this harness never carries the earlier commit).
    fades.clear();
    final underGesture = await tester.startGesture(
      rect.centerLeft + const Offset(6, 0),
    );
    await underGesture.moveBy(Offset(-3 * cell, 0));
    await underGesture.up();
    await tester.pumpAndSettle();
    expect(fades, isEmpty);
  });
}
