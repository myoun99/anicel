import '../../models/cut.dart';
import '../../models/cut_camera.dart';
import '../../models/cut_id.dart';
import '../../models/frame.dart';
import '../../models/frame_id.dart';
import '../../models/layer.dart';
import '../../models/layer_id.dart';
import '../../models/layer_kind.dart';
import '../../models/stroke.dart';
import '../../models/timeline_exposure.dart';

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
          (layer) => duplicateLayerAsIndependentCopy(
            source: layer,
            newLayerId: _requireMapped(
              layerIdMap,
              layer.id,
              argument: 'layerIdMap',
              what: 'LayerId for source layer',
            ),
            newName: layer.name,
            frameIdMap: frameIdMap,
            // The whole cut duplicates together: attach linkage remaps
            // onto the copied base (both the layer pointer and the
            // per-cel links).
            layerIdMap: layerIdMap,
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

Layer duplicateLayerAsIndependentCopy({
  required Layer source,
  required LayerId newLayerId,
  required String newName,
  required Map<FrameId, FrameId> frameIdMap,
  LayerKind? kind,
  Map<LayerId, LayerId> layerIdMap = const {},
}) {
  final attachedTo = source.attachedToLayerId;
  final folderId = source.folderId;
  // Field-by-field reconstruction is this helper's trap, the same one
  // [duplicateFrameContent] documents: every field NOT listed here is
  // silently reset to its default. The R6 audit found nine already lost —
  // blendMode, folderId (so a duplicated cut FLATTENED every folder),
  // seNameTag, isFillReference, runBehaviors, collapsed, audioGain,
  // audioPan and attachedMode. Anything added to [Layer] belongs here.
  return Layer(
    id: newLayerId,
    name: newName,
    frames: source.frames
        .map(
          (frame) => duplicateFrameContent(
            frame: frame,
            newFrameId: _requireMapped(
              frameIdMap,
              frame.id,
              argument: 'frameIdMap',
              what: 'FrameId for source frame',
            ),
          ),
        )
        .toList(),
    timeline: source.timeline.map(
      (index, exposure) => MapEntry(
        index,
        remapTimelineExposure(exposure: exposure, frameIdMap: frameIdMap),
      ),
    ),
    isVisible: source.isVisible,
    collapsed: source.collapsed,
    muted: source.muted,
    audioGain: source.audioGain,
    audioPan: source.audioPan,
    opacity: source.opacity,
    blendMode: source.blendMode,
    kind: kind ?? source.kind,
    onTimesheet: source.onTimesheet,
    mark: source.mark,
    isFillReference: source.isFillReference,
    // The duplicated layer shows the same library asset (§6-z23).
    mediaReference: source.mediaReference,
    seNameTag: source.seNameTag,
    transformTrack: source.transformTrack,
    // The effect chain is layer state like the transform track (R6): a
    // duplicated cut keeps its 촬영 work.
    effects: source.effects,
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
    attachedMode: source.attachedMode,
    // Folder membership remaps exactly like the attach pointer: the copied
    // folder row when the whole cut duplicates, the ORIGINAL folder when a
    // lone layer is copied inside the same cut.
    folderId: folderId == null ? null : (layerIdMap[folderId] ?? folderId),
    baseFrameLinks: {
      for (final entry in source.baseFrameLinks.entries)
        (frameIdMap[entry.key] ?? entry.key):
            frameIdMap[entry.value] ?? entry.value,
    },
  );
}

/// One frame's CONTENT under a new id — strokes deep-copied, so the copy
/// owes the source nothing afterwards.
///
/// Public because ㉕'s independent paste wants exactly this and nothing
/// else: a cel that came from another cel and is not linked to it. The cut
/// duplication below is the same question asked about a whole cut, so it
/// asks it here rather than growing a second answer.
///
/// ⚠️Field-by-field reconstruction is this helper's trap: it silently
/// dropped `seName` until the text round walked past — every new [Frame]
/// field must be carried here by hand.
Frame duplicateFrameContent({
  required Frame frame,
  required FrameId newFrameId,
}) {
  return Frame(
    id: newFrameId,
    duration: frame.duration,
    strokes: frame.strokes.map(_duplicateStroke).toList(),
    name: frame.name,
    seName: frame.seName,
    textContent: frame.textContent,
  );
}

/// One timeline cell pointed at the copied cel: the exposure's frame id
/// resolved through [frameIdMap], which must cover it.
///
/// Public because the paste planner rebuilds a layer's whole timeline with
/// exactly this rule and used to spell it out inline.
TimelineExposure remapTimelineExposure({
  required TimelineExposure exposure,
  required Map<FrameId, FrameId> frameIdMap,
}) {
  final sourceFrameId = exposure.frameId;
  if (sourceFrameId == null) {
    throw ArgumentError.value(
      frameIdMap,
      'frameIdMap',
      'Missing mapped FrameId for timeline exposure ${exposure.frameId}.',
    );
  }
  return exposure.copyWith(
    frameId: _requireMapped(
      frameIdMap,
      sourceFrameId,
      argument: 'frameIdMap',
      what: 'FrameId for timeline exposure',
    ),
  );
}

/// The id [key] was minted as, or an [ArgumentError] naming the map that
/// should have carried it. Three walks of this file look a minted id up
/// and refuse the same way when it is missing.
V _requireMapped<K, V>(
  Map<K, V> map,
  K key, {
  required String argument,
  required String what,
}) {
  final mapped = map[key];
  if (mapped == null) {
    throw ArgumentError.value(map, argument, 'Missing mapped $what $key.');
  }
  return mapped;
}

Stroke _duplicateStroke(Stroke stroke) {
  return stroke.copyWith(
    points: stroke.points.map((point) => point.copyWith()).toList(),
    brushSettings: stroke.brushSettings.copyWith(),
  );
}
