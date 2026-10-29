import 'dart:typed_data';

import 'package:flutter/foundation.dart' show ValueListenable, ValueNotifier;
import 'package:flutter/painting.dart' show Axis;
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/audio_clip.dart';
import 'package:anicel/src/models/camera_instruction.dart'
    show CameraInstructionDef;
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/project_frame_rate.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/services/audio/audio_peaks_extractor.dart';
import 'package:anicel/src/ui/audio/sound_cannot_play.dart';
import 'package:anicel/src/ui/timeline/berth_row.dart';
import 'package:anicel/src/ui/timeline/property_lane_model.dart';
import 'package:anicel/src/ui/timeline/timeline_cell_exposure_state.dart';
import 'package:anicel/src/ui/timeline/timeline_cells_row_facts.dart';
import 'package:anicel/src/ui/timeline/timeline_cut_end_handle.dart'
    show TimelineNoriShiro;
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
///
/// ↩️The viewport was pinned here as a fact, which built every row again on
/// every pixel the view moved. It rides the live geometry now, which a kept
/// row follows ([TimelineFrameGeometry.viewExtentPx]) — the law itself is
/// `timeline_viewport_resize_test`'s, and a splitter step that builds no
/// row is `a_rail_step_builds_no_row_test`'s.
///
/// 🚨I-57 (10-13): the facts are the row's SHAPE, and what a cut switch
/// changes reaches the kept row past them, as its world
/// ([timelineCellsRowWorld]) — so a fact the row shows changes one of the
/// two, and a cut switch changes the world alone.
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
  AudioPeaks? landedA(String path) => peaksA;
  AudioPeaks? landedB(String path) => peaksB;
  SoundCannotPlay? plays(String path) => null;
  SoundCannotPlay? gone(String path) => SoundCannotPlay.missing;
  CameraInstructionDef? noTerm(String id) => null;
  PropertyLaneRow? noUnion(Layer layer) => null;
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

  /// [row] as a grid tells it — what both its facts and its world are read
  /// from.
  (TimelineDisplayRow, TimelineCellsRowGrid) told({
    Layer? row,
    int playbackFrameCount = 24,
    TimelineNoriShiro Function()? noriShiro,
    TimelineGridMetrics metrics = TimelineGridMetrics.defaults,
    ProjectFrameRate projectFrameRate = ProjectFrameRate.fps24,
    String substrateGeneration = 'world-0',
    TimelineCellExposureState Function(Layer, int)? exposure,
    String? Function(Layer, int)? frameNames,
    TimelineCommaDragCallbacks? comma,
    TimelineRangeGestureCallbacks? range,
    void Function(LayerId, int)? onActivateCell,
    ValueListenable<TimelineDragPreview?>? dragPreview,
    Object? cameraTrack,
    Map<LayerId, int> spillInLeadFrames = const {},
    CutId? cutId,
    String? seClipMarkerTooltip,
    AudioPeaks? Function(String)? peaksFor,
    SoundCannotPlay? Function(String)? cannotPlay,
    CameraInstructionDef? Function(String)? defById,
    PropertyLaneRow? Function(Layer)? unionLaneFor,
    bool showSeconds = false,
    void Function(LayerId)? onSelectLayer,
  }) => (
    TimelineDisplayRow.layer(row ?? drawing, layerIndex: 0),
    (
      hooks: TimelineGridHooks(
        activeLayerId: null,
        frameCursor: ValueNotifier<int>(0),
        playbackFrameCount: playbackFrameCount,
        noriShiro: noriShiro,
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
        cutId: cutId,
        seClipMarkerTooltip: seClipMarkerTooltip,
        audioPeaksFor: peaksFor ?? landedA,
        soundCannotPlay: cannotPlay,
        instructionDefById: defById,
        unionLaneForLayer: unionLaneFor,
        showSeconds: showSeconds,
      ),
      metrics: metrics,
      geometry: geometry,
      windowBucket: null,
      frameAxisController: null,
      nextPage: null,
      rangeGesture: range,
      axis: Axis.horizontal,
      keyPrefix: 'timeline',
    ),
  );
  TimelineCellsRowFacts facts((TimelineDisplayRow, TimelineCellsRowGrid) of) =>
      timelineCellsRowFacts(of.$1, of.$2);
  BerthWorld world((TimelineDisplayRow, TimelineCellsRowGrid) of) =>
      timelineCellsRowWorld(of.$1, of.$2);

  test('the same facts, asked again, are the same facts — and a verb is '
      'not one', () {
    expect(
      facts(told(onSelectLayer: (_) {})),
      facts(told(onSelectLayer: (_) {})),
    );
    expect(
      world(told(row: se)),
      world(told(row: se)),
      reason: 'the SE peaks, by value',
    );
  });

  test('🚨I-57: a cut switch is no fact — another layer of the same shape, '
      'in another world, keeps the row', () {
    final here = told();
    final there = told(
      row: layer('other'),
      playbackFrameCount: 48,
      substrateGeneration: 'world-1',
      spillInLeadFrames: {const LayerId('other'): 3},
      cutId: const CutId('cut-2'),
    );
    expect(facts(there), facts(here), reason: 'the shape is the same');
    expect(
      world(there) == world(here),
      isFalse,
      reason: 'premise: the cut switched under the row',
    );
  });

  final shapes = <String, (Layer, Layer)>{
    'kind': (drawing, layer('drawing', kind: LayerKind.storyboard)),
    'syncedAttached': (
      drawing,
      drawing.copyWith(attachedToLayerId: const LayerId('base')),
    ),
  };
  for (final shape in shapes.entries) {
    test('${shape.key} is the row\'s shape — it must change the facts', () {
      final (before, after) = shape.value;
      expect(
        facts(told(row: before)) == facts(told(row: after)),
        isFalse,
        reason: 'a kept row mounts what its shape mounts; one kept across '
            'a change of ${shape.key} mounts the wrong pieces',
      );
    });
  }

  final changes = <String, ((TimelineDisplayRow, TimelineCellsRowGrid),
      (TimelineDisplayRow, TimelineCellsRowGrid))>{
    'crossAxisExtent': (
      told(),
      told(metrics: TimelineGridMetrics.defaults.copyWith(layerRowHeight: 40)),
    ),
    'projectFrameRate': (
      told(),
      told(projectFrameRate: const ProjectFrameRate.integer(30)),
    ),
    'exposureStateForLayer': (told(), told(exposure: covered)),
    'frameNameForLayer': (told(), told(frameNames: named)),
    'hasCommaDrag': (told(), told(comma: commaDrag)),
    'hasRangeGesture': (told(), told(range: rangeGesture)),
    'hasActivateCell': (told(), told(onActivateCell: activate)),
    'dragPreview': (told(), told(dragPreview: previewB)),
    'seClipMarkerTooltip': (told(), told(seClipMarkerTooltip: 'clipped')),
    'showSeconds': (told(), told(showSeconds: true)),
    // What a kept row's pictures ask again when the world moves (I-57).
    'audioPeaksFor': (told(), told(peaksFor: landedB)),
    'soundCannotPlay': (told(), told(cannotPlay: plays)),
    'instructionDefById': (told(), told(defById: noTerm)),
    'unionLaneFor': (told(), told(unionLaneFor: noUnion)),
  };
  for (final change in changes.entries) {
    test('${change.key} is a fact the row shows — it must change the facts',
        () {
      final (before, after) = change.value;
      expect(
        facts(before) == facts(after),
        isFalse,
        reason: 'the row is given ${change.key}; a kept row that survives '
            'its change shows it stale',
      );
    });
  }

  final worlds = <String, ((TimelineDisplayRow, TimelineCellsRowGrid),
      (TimelineDisplayRow, TimelineCellsRowGrid))>{
    'playbackFrameCount': (told(), told(playbackFrameCount: 25)),
    // F-358: the line the cut is DRAWN to — where an SE row's end `~`
    // stands — moves with the のりしろ as well as the 尺.
    'noriShiro': (
      told(),
      told(noriShiro: () => (drawnFrameCount: 36, label: 'O.L')),
    ),
    'substrateGeneration': (told(), told(substrateGeneration: 'world-1')),
    // ㉘: a camera key is a new camera track — the camera row's only tell.
    'coverageIdentity': (
      told(row: camera, cameraTrack: trackA),
      told(row: camera, cameraTrack: trackB),
    ),
    'spillInLeadFrames': (
      told(),
      told(spillInLeadFrames: {const LayerId('drawing'): 3}),
    ),
    // F-496: an SE block writes the delivery it has in the cut it is seen
    // in.
    'cutId': (
      told(row: se, cutId: const CutId('cut-1')),
      told(row: se, cutId: const CutId('cut-2')),
    ),
    'seAudioPeaks': (
      told(row: se, peaksFor: landedA),
      told(row: se, peaksFor: landedB),
    ),
    // playback-says-the-sound-it-cannot-play: a sound that went missing is
    // a red cell on a row kept as it was.
    'seSoundsCannotPlay': (
      told(row: se, cannotPlay: plays),
      told(row: se, cannotPlay: gone),
    ),
  };
  for (final change in worlds.entries) {
    test('${change.key} is what the row draws of its cut — it must change '
        'its world', () {
      final (before, after) = change.value;
      expect(
        world(before) == world(after),
        isFalse,
        reason: 'a kept row draws ${change.key} from its world; a world '
            'that hides its change leaves the row drawing it stale',
      );
    });
  }
}
