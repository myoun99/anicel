import '../models/cut.dart';
import '../models/cut_camera.dart';
import '../models/cut_id.dart';
import '../models/frame.dart';
import '../models/frame_id.dart';
import '../models/layer.dart';
import '../models/layer_id.dart';
import '../models/layer_kind.dart';
import '../models/stroke.dart';
import '../models/timeline_exposure.dart';

Cut duplicateCutAsIndependentCopy({
  required Cut source,
  required CutId newCutId,
  required String newName,
  required Map<LayerId, LayerId> layerIdMap,
  required Map<FrameId, FrameId> frameIdMap,
}) {
  return Cut(
    id: newCutId,
    name: newName,
    layers: source.layers
        .map(
          (layer) => _duplicateLayer(
            layer: layer,
            layerIdMap: layerIdMap,
            frameIdMap: frameIdMap,
          ),
        )
        .toList(),
    duration: source.duration,
    canvasSize: source.canvasSize,
    metadata: source.metadata,
    // Share the immutable track directly: a pose-view round-trip would
    // resynchronize (and thus lose) independently keyed properties.
    camera: CutCamera.fromTrack(source.camera.track),
  );
}

Layer _duplicateLayer({
  required Layer layer,
  required Map<LayerId, LayerId> layerIdMap,
  required Map<FrameId, FrameId> frameIdMap,
}) {
  final newLayerId = layerIdMap[layer.id];
  if (newLayerId == null) {
    throw ArgumentError.value(
      layerIdMap,
      'layerIdMap',
      'Missing mapped LayerId for source layer ${layer.id}.',
    );
  }

  return duplicateLayerAsIndependentCopy(
    source: layer,
    newLayerId: newLayerId,
    newName: layer.name,
    frameIdMap: frameIdMap,
    // The whole cut duplicates together: attach linkage remaps onto the
    // copied base (both the layer pointer and the per-cel links).
    layerIdMap: layerIdMap,
  );
}

Layer duplicateLayerAsIndependentCopy({
  required Layer source,
  required LayerId newLayerId,
  required String newName,
  required Map<FrameId, FrameId> frameIdMap,
  LayerKind? kind,
  Map<LayerId, LayerId> layerIdMap = const {},
}) {
  final attachedTo = source.attachedToLayerId;
  return Layer(
    id: newLayerId,
    name: newName,
    frames: source.frames
        .map((frame) => _duplicateFrame(frame: frame, frameIdMap: frameIdMap))
        .toList(),
    timeline: source.timeline.map(
      (index, exposure) => MapEntry(
        index,
        _duplicateTimelineExposure(exposure: exposure, frameIdMap: frameIdMap),
      ),
    ),
    isVisible: source.isVisible,
    muted: source.muted,
    opacity: source.opacity,
    kind: kind ?? source.kind,
    onTimesheet: source.onTimesheet,
    mark: source.mark,
    // The duplicated layer shows the same library asset (§6-z23).
    mediaReference: source.mediaReference,
    transformTrack: source.transformTrack,
    instructions: source.instructions,
    audioClips: [
      for (final clip in source.audioClips)
        clip.copyWith(frameId: frameIdMap[clip.frameId] ?? clip.frameId),
    ],
    // Attach linkage: the base pointer remaps when its copy is known (a
    // whole-cut duplicate); a lone-layer copy keeps pointing at the
    // original base in the same cut. Cel links remap on BOTH sides where
    // mapped.
    attachedToLayerId: attachedTo == null
        ? null
        : (layerIdMap[attachedTo] ?? attachedTo),
    attachedPlacement: source.attachedPlacement,
    baseFrameLinks: {
      for (final entry in source.baseFrameLinks.entries)
        (frameIdMap[entry.key] ?? entry.key):
            frameIdMap[entry.value] ?? entry.value,
    },
  );
}

Frame _duplicateFrame({
  required Frame frame,
  required Map<FrameId, FrameId> frameIdMap,
}) {
  final newFrameId = frameIdMap[frame.id];
  if (newFrameId == null) {
    throw ArgumentError.value(
      frameIdMap,
      'frameIdMap',
      'Missing mapped FrameId for source frame ${frame.id}.',
    );
  }

  return Frame(
    id: newFrameId,
    duration: frame.duration,
    strokes: frame.strokes.map(_duplicateStroke).toList(),
    name: frame.name,
    // Field-by-field reconstruction is this helper's trap: it silently
    // dropped seName until the text round walked past — every new Frame
    // field must be carried here by hand.
    seName: frame.seName,
    textContent: frame.textContent,
  );
}

TimelineExposure _duplicateTimelineExposure({
  required TimelineExposure exposure,
  required Map<FrameId, FrameId> frameIdMap,
}) {
  final sourceFrameId = exposure.frameId;
  final newFrameId = sourceFrameId == null ? null : frameIdMap[sourceFrameId];
  if (sourceFrameId == null || newFrameId == null) {
    throw ArgumentError.value(
      frameIdMap,
      'frameIdMap',
      'Missing mapped FrameId for timeline exposure ${exposure.frameId}.',
    );
  }
  return exposure.copyWith(frameId: newFrameId);
}

Stroke _duplicateStroke(Stroke stroke) {
  return stroke.copyWith(
    points: stroke.points.map((point) => point.copyWith()).toList(),
    brushSettings: stroke.brushSettings.copyWith(),
  );
}
