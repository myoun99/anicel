import 'dart:typed_data';

import 'package:flutter/foundation.dart' show ValueListenable, ValueNotifier;
import 'package:flutter/painting.dart' show Axis;
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/audio_clip.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/project_frame_rate.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/services/audio/audio_peaks_extractor.dart';
import 'package:anicel/src/ui/timeline/property_lane_model.dart';
import 'package:anicel/src/ui/timeline/timeline_cell_exposure_state.dart';
import 'package:anicel/src/ui/timeline/timeline_cells_row_facts.dart';
import 'package:anicel/src/ui/timeline/timeline_drag_preview.dart';
import 'package:anicel/src/ui/timeline/timeline_exposure_comma_drag_policy.dart';
import 'package:anicel/src/ui/timeline/timeline_frame_geometry.dart';
import 'package:anicel/src/ui/timeline/timeline_frame_range_gesture.dart';
import 'package:anicel/src/ui/timeline/timeline_grid_hooks.dart';
import 'package:anicel/src/ui/timeline/timeline_grid_metrics.dart';

/// 🚨F-244: A KEPT CELLS ROW SEES EVERY FACT IT SHOWS.
///
/// The timeline's rows and the x-sheet's columns keep a cells row while
/// [timelineCellsRowFacts] answers the same, so a fact left out of it is a
/// row kept across a change of it — THE RESIZE LAW's viewport was the one a
/// device found (the newly exposed cells stayed outside every request set).
/// This changes one fact at a time; what a zoom step keeps is
/// `zoom_does_not_rebuild_rows_test`'s.
void main() {
  Layer layer(String id, {LayerKind kind = LayerKind.animation}) => Layer(
    id: LayerId(id),
    name: id,
    kind: kind,
    frames: const [],
    timeline: const {},
  );
  final drawing = layer('drawing');
  final camera = layer('camera', kind: LayerKind.camera);
  final se = Layer(
    id: const LayerId('se'),
    name: 'se',
    kind: LayerKind.se,
    frames: const [],
    timeline: const {0: TimelineExposure.drawing(FrameId('f0'), length: 3)},
    audioClips: [AudioClip(filePath: 'take.wav', frameId: const FrameId('f0'))],
  );
  final trackA = Object();
  final trackB = Object();
  final peaksA = AudioPeaks(bucketsPerSecond: 80, peaks: Float32List(160));
  final peaksB = AudioPeaks(bucketsPerSecond: 80, peaks: Float32List(160));
  final previewA = ValueNotifier<TimelineDragPreview?>(null);
  final previewB = ValueNotifier<TimelineDragPreview?>(null);
  final geometry = ValueNotifier(
    const TimelineFrameGeometry(
      frameCellExtent: 24,
      frameStartIndex: 0,
      frameEndIndexExclusive: 24,
    ),
  );
  // ONE function per answer, as the session's tear-offs are in the app: a
  // fresh closure is a new key.
  TimelineCellExposureState uncovered(Layer layer, int frame) =>
      TimelineCellExposureState.uncovered;
  TimelineCellExposureState covered(Layer layer, int frame) =>
      TimelineCellExposureState.drawingStart;
  String? named(Layer layer, int frame) => '$frame';
  final commaDrag = TimelineCommaDragCallbacks(
    onBegin: (_, _, _) => true,
    onUpdate: (_) {},
    onEnd: () {},
    onCancel: () {},
  );
  final rangeGesture = TimelineRangeGestureCallbacks(
    isInSelection: (_, _) => false,
    onSelectUpdate: (_, _, _, _) {},
    onTapClear: (_) {},
    onMoveBegin: (_, _) => true,
    onMoveUpdate: (_, _) {},
    onMoveEnd: () {},
    onMoveCancel: () {},
  );
  void activate(LayerId layerId, int frame) {}

  TimelineCellsRowFacts facts({
    Layer? row,
    int playbackFrameCount = 24,
    TimelineGridMetrics metrics = TimelineGridMetrics.defaults,
    ProjectFrameRate projectFrameRate = ProjectFrameRate.fps24,
    String substrateGeneration = 'world-0',
    double viewportMainExtent = 400,
    TimelineCellExposureState Function(Layer, int)? exposure,
    String? Function(Layer, int)? frameNames,
    TimelineCommaDragCallbacks? comma,
    TimelineRangeGestureCallbacks? range,
    void Function(LayerId, int)? onActivateCell,
    ValueListenable<TimelineDragPreview?>? dragPreview,
    Object? cameraTrack,
    Map<LayerId, int> spillInLeadFrames = const {},
    String? seClipMarkerTooltip,
    AudioPeaks? peaks,
    bool showSeconds = false,
    void Function(LayerId)? onSelectLayer,
  }) => timelineCellsRowFacts(
    TimelineDisplayRow.layer(row ?? drawing, layerIndex: 0),
    (
      hooks: TimelineGridHooks(
        activeLayerId: null,
        frameCursor: ValueNotifier<int>(0),
        playbackFrameCount: playbackFrameCount,
        exposureStateForLayer: exposure ?? uncovered,
        frameNameForLayer: frameNames,
        onSelectLayer: onSelectLayer ?? (_) {},
        onSelectFrame: (_) {},
        onToggleLayerVisibility: (_) {},
        onLayerOpacityChanged: (_, _) {},
        onToggleLayerTimesheet: (_) {},
        onLayerMarkSelected: (_, _) {},
        projectFrameRate: projectFrameRate,
        substrateGeneration: substrateGeneration,
        commaDrag: comma,
        onActivateCell: onActivateCell,
        dragPreview: dragPreview ?? previewA,
        memoAux: TimelineRowMemoAux(cameraTrack: cameraTrack ?? trackA),
        spillInLeadFrames: spillInLeadFrames,
        seClipMarkerTooltip: seClipMarkerTooltip,
        audioPeaksFor: (_) => peaks ?? peaksA,
        showSeconds: showSeconds,
      ),
      metrics: metrics,
      geometry: geometry,
      windowBucket: null,
      viewportMainExtent: viewportMainExtent,
      rangeGesture: range,
      axis: Axis.horizontal,
      keyPrefix: 'timeline',
    ),
  );

  test('the same facts, asked again, are the same facts — and a verb is '
      'not one', () {
    expect(facts(onSelectLayer: (_) {}), facts(onSelectLayer: (_) {}));
    expect(facts(row: se), facts(row: se), reason: 'the SE peaks, by value');
  });

  final changes = <String, (TimelineCellsRowFacts, TimelineCellsRowFacts)>{
    'layer': (facts(), facts(row: layer('drawing'))),
    'playbackFrameCount': (facts(), facts(playbackFrameCount: 25)),
    'crossAxisExtent': (
      facts(),
      facts(metrics: TimelineGridMetrics.defaults.copyWith(layerRowHeight: 40)),
    ),
    'projectFrameRate': (
      facts(),
      facts(projectFrameRate: const ProjectFrameRate.integer(30)),
    ),
    'substrateGeneration': (facts(), facts(substrateGeneration: 'world-1')),
    // THE RESIZE LAW: a viewport that widens must rebuild the row.
    'viewportMainExtent': (facts(), facts(viewportMainExtent: 800)),
    'exposureStateForLayer': (facts(), facts(exposure: covered)),
    'frameNameForLayer': (facts(), facts(frameNames: named)),
    'hasCommaDrag': (facts(), facts(comma: commaDrag)),
    'hasRangeGesture': (facts(), facts(range: rangeGesture)),
    'hasActivateCell': (facts(), facts(onActivateCell: activate)),
    'dragPreview': (facts(), facts(dragPreview: previewB)),
    // ㉘: a camera key is a new camera track — the camera row's only tell.
    'auxiliaryIdentity': (
      facts(row: camera, cameraTrack: trackA),
      facts(row: camera, cameraTrack: trackB),
    ),
    'spillInLeadFrames': (
      facts(),
      facts(spillInLeadFrames: {const LayerId('drawing'): 3}),
    ),
    'seClipMarkerTooltip': (facts(), facts(seClipMarkerTooltip: 'clipped')),
    'seAudioPeaks': (
      facts(row: se, peaks: peaksA),
      facts(row: se, peaks: peaksB),
    ),
    'showSeconds': (facts(), facts(showSeconds: true)),
  };
  for (final change in changes.entries) {
    test('${change.key} is a fact the row shows — it must change the facts',
        () {
      final (before, after) = change.value;
      expect(
        before == after,
        isFalse,
        reason: 'the row is given ${change.key}; a kept row that survives '
            'its change shows it stale',
      );
    });
  }
}
