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
import 'package:anicel/src/ui/audio/waveform_painter.dart';
import 'package:anicel/src/ui/timeline/property_lane_model.dart';
import 'package:anicel/src/ui/timeline/se_audio_lane.dart';
import 'package:anicel/src/ui/timeline/timeline_cell_exposure_state.dart';
import 'package:anicel/src/ui/timeline/timeline_cells_row_facts.dart';
import 'package:anicel/src/ui/timeline/timeline_frame_geometry.dart';
import 'package:anicel/src/ui/timeline/timeline_grid_hooks.dart';
import 'package:anicel/src/ui/timeline/timeline_grid_metrics.dart';

/// lane-rows-built-twice — ONE builder lays a lane row for both grids
/// ([timelineLaneRowFrom]), and each grid's way of laying it rides in: the
/// timeline's along its row, the x-sheet's down its column, under each
/// grid's own keys.
void main() {
  const frames = 16;
  final peaks = AudioPeaks(bucketsPerSecond: 80, peaks: Float32List(160));
  final se = Layer(
    id: const LayerId('se'),
    name: 'S1',
    kind: LayerKind.se,
    frames: [Frame(id: const FrameId('se-f'), duration: 1, strokes: const [])],
    timeline: const {0: TimelineExposure.drawing(FrameId('se-f'), length: 8)},
    audioClips: [
      AudioClip(filePath: 'steps.wav', frameId: const FrameId('se-f')),
    ],
  );
  final drawing = Layer(
    id: const LayerId('a'),
    name: 'A',
    frames: const [],
    timeline: const {},
  );
  const position = PropertyLaneRow(
    laneId: 'position',
    label: 'Position',
    keyedFrames: {5},
  );

  /// The box [key] is laid in when [row] is built at [layer] by a grid that
  /// lays its rows along [axis] under [keyPrefix].
  Future<Rect> laid(
    WidgetTester tester,
    TimelineDisplayRow row,
    Layer layer, {
    required Axis axis,
    required String keyPrefix,
    required String key,
    Map<LayerId, int> spillInLeadFrames = const {},
    TimelineAudioLaneCallbacks? audioLane,
  }) async {
    final cursor = ValueNotifier<int>(0);
    addTearDown(cursor.dispose);
    final geometry = ValueNotifier(
      const TimelineFrameGeometry(
        frameCellExtent: 24,
        frameStartIndex: 0,
        frameEndIndexExclusive: frames,
      ),
    );
    addTearDown(geometry.dispose);
    final grid = (
      hooks: TimelineGridHooks(
        activeLayerId: null,
        frameCursor: cursor,
        playbackFrameCount: frames,
        exposureStateForLayer: (_, _) => TimelineCellExposureState.uncovered,
        onSelectLayer: (_) {},
        onSelectFrame: (_) {},
        onToggleLayerVisibility: (_) {},
        onLayerOpacityChanged: (_, _) {},
        onToggleLayerTimesheet: (_) {},
        onLayerMarkSelected: (_, _) {},
        projectFrameRate: ProjectFrameRate.fps24,
        audioPeaksFor: (_) => peaks,
        spillInLeadFrames: spillInLeadFrames,
        audioLane: audioLane,
      ),
      metrics: TimelineGridMetrics.defaults,
      geometry: geometry,
      windowBucket: null,
      viewportMainExtent: 400.0,
      rangeGesture: null,
      axis: axis,
      keyPrefix: keyPrefix,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: timelineLaneRowFrom(row, layer, grid, (
              startIndex: 0,
              endIndexExclusive: frames,
              leadingSpacer: 0,
              trailingSpacer: 0,
              laneRange: null,
            )),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return tester.getRect(find.byKey(ValueKey<String>('$keyPrefix-$key')));
  }

  testWidgets('a sound\'s lane runs along the timeline\'s row and down the '
      'x-sheet\'s column', (tester) async {
    final row = TimelineDisplayRow.lane(
      se,
      seAudioLanesFor(se).single,
      layerIndex: 0,
    );
    const span = 'audio-lane-span-se-0-b0';
    final along = await laid(
      tester,
      row,
      se,
      axis: Axis.horizontal,
      keyPrefix: 'timeline',
      key: span,
    );
    final down = await laid(
      tester,
      row,
      se,
      axis: Axis.vertical,
      keyPrefix: 'xsheet',
      key: span,
    );
    expect(along.width, greaterThan(along.height), reason: 'fixture');
    expect(along.left, 0, reason: 'its block starts at the first frame given');
    expect(
      down.size,
      Size(along.height, along.width),
      reason: 'turned on its side',
    );
  });

  testWidgets('a property lane runs its frames along the timeline\'s row and '
      'down the x-sheet\'s column', (tester) async {
    final row = TimelineDisplayRow.lane(drawing, position, layerIndex: 0);
    const key = 'lane-key-a-position-5';
    final along = await laid(
      tester,
      row,
      drawing,
      axis: Axis.horizontal,
      keyPrefix: 'timeline',
      key: key,
    );
    final down = await laid(
      tester,
      row,
      drawing,
      axis: Axis.vertical,
      keyPrefix: 'xsheet',
      key: key,
    );
    const cell = TimelineGridMetrics.defaults;
    expect(
      along.center.dx,
      inExclusiveRange(5 * cell.frameCellWidth, 6 * cell.frameCellWidth),
      reason: 'frame 5\'s key stands in the sixth cell of the frames given',
    );
    expect(
      down.center,
      Offset(along.center.dy, along.center.dx),
      reason: 'turned on its side',
    );
  });

  testWidgets('a sound\'s lane edits its own layer through its grid\'s hooks '
      '— the spill the grid knows, the slide and the fades', (tester) async {
    final offsets = <(LayerId, int, int)>[];
    final fades = <(LayerId, int, int, int)>[];
    final row = TimelineDisplayRow.lane(
      se,
      seAudioLanesFor(se).single,
      layerIndex: 0,
    );
    final rect = await laid(
      tester,
      row,
      se,
      axis: Axis.vertical,
      keyPrefix: 'xsheet',
      key: 'audio-lane-span-se-0-b0',
      spillInLeadFrames: {const LayerId('se'): 14},
      audioLane: TimelineAudioLaneCallbacks(
        onSetClipOffset: (layerId, clipIndex, offsetFrames) =>
            offsets.add((layerId, clipIndex, offsetFrames)),
        onSetClipFades: (layerId, clipIndex, fadeIn, fadeOut) =>
            fades.add((layerId, clipIndex, fadeIn, fadeOut)),
      ),
    );
    final span = find.byKey(
      const ValueKey<String>('xsheet-audio-lane-span-se-0-b0'),
    );
    final waveform =
        tester
                .widget<CustomPaint>(
                  find.descendant(
                    of: span,
                    matching: find.byWidgetPredicate(
                      (widget) =>
                          widget is CustomPaint &&
                          widget.painter is WaveformPainter,
                    ),
                  ),
                )
                .painter!
            as WaveformPainter;
    expect(waveform.leadingFrames, 14, reason: 'drawn from where it is');

    final cell = TimelineGridMetrics.defaults.frameCellWidth;
    await tester.drag(span, Offset(0, -2 * cell));
    await tester.pumpAndSettle();
    expect(offsets, [(const LayerId('se'), 0, 2)]);

    final fadeIn = await tester.startGesture(
      rect.topCenter + const Offset(0, 6),
    );
    await fadeIn.moveBy(Offset(0, 3 * cell));
    await fadeIn.up();
    await tester.pumpAndSettle();
    expect(fades, [(const LayerId('se'), 0, 3, 0)]);
  });
}
