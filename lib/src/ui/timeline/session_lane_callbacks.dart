import 'package:flutter/foundation.dart' show ValueListenable;

import '../brush/transform_tool_options.dart';
import '../editor_session_manager.dart';
import 'property_lane_model.dart' show PropertyLaneEditCallbacks;
import 'se_audio_lane.dart' show TimelineAudioLaneCallbacks;

/// A rail's lane edits wired to [session] — the one wiring behind the
/// timeline's lanes and the storyboard's S rows (F-101). [frameIsGlobal] is
/// the rail's axis: a cut's rail hands cut frames, a track's rail global
/// ones, and the verbs put either on the row the project holds (F-102).
///
/// [transformOptions] is the transform tool's: a layer's Scale lane links
/// by its 「배율 연동」, read at the moment a value lands — the ONE switch
/// (`transform-fx-scale-x-y-Q1`, 유저 2026-10-07: 「Scale 행에 사슬 버튼 — 변형
/// 도구의 「배율 연동」과 한 스위치」). A rail with no tool beside it reads the
/// tool's own defaults.
PropertyLaneEditCallbacks sessionLaneEditCallbacks(
  EditorSessionManager session, {
  required bool frameIsGlobal,
  required ValueListenable<TransformToolOptions>? transformOptions,
}) {
  bool scaleLinked() =>
      (transformOptions?.value ?? TransformToolOptions.defaults).scaleLinked;
  return PropertyLaneEditCallbacks(
    // The navigator toggles at the playhead, freezing the property's
    // CURRENT resolved value there (AE behavior).
    onToggleKeyAt: (layer, lane, frameIndex) =>
        session.laneVerbs.toggleLaneKeyAt(
          layer.id,
          lane.laneId,
          frameIndex,
          frameIsGlobal: frameIsGlobal,
          description: '${lane.label} keyframe at frame ${frameIndex + 1}',
        ),
    // The SE audio lane has no value field any more — a block's offset is
    // edited in its own edit window (유저 2026-09-27) — so every value that
    // arrives here is a property's.
    onSetValue: (layer, lane, frameIndex, input) =>
        session.laneVerbs.setLaneValueAt(
          layer.id,
          lane.laneId,
          frameIndex,
          input,
          frameIsGlobal: frameIsGlobal,
          description: 'Set ${lane.label} at frame ${frameIndex + 1}',
          scaleLinked: scaleLinked(),
        ),
    // F-195: the same edit, shown while a scrub lasts.
    onPreviewValue: (layer, lane, frameIndex, input) =>
        session.laneVerbs.previewLaneValueAt(
          layer.id,
          lane.laneId,
          frameIndex,
          input,
          frameIsGlobal: frameIsGlobal,
          scaleLinked: scaleLinked(),
        ),
    onEndPreview: session.laneVerbs.endLaneEditPreview,
  );
}

/// The sound edits an SE row's audio band takes, wired to [session] — the
/// one object the timeline's rows and the storyboard's S rows hand over
/// (F-101: the storyboard's Audio lane took the offset alone, so a take's
/// fades could not be dragged there).
TimelineAudioLaneCallbacks sessionAudioLaneCallbacks(
  EditorSessionManager session,
) => TimelineAudioLaneCallbacks(
  // Media-browser drops: link the dragged sound to the block.
  onDropMediaAsset: (layerId, blockStartFrame, path) =>
      session.mediaPool.linkMediaAssetToSeBlock(
        layerId: layerId,
        blockStartFrame: blockStartFrame,
        path: path,
      ),
  onSetClipOffset: session.audioClips.setAudioClipOffset,
  onSetClipFades: (layerId, clipIndex, fadeIn, fadeOut) =>
      session.audioClips.setAudioClipFades(
        layerId,
        clipIndex,
        fadeInFrames: fadeIn,
        fadeOutFrames: fadeOut,
      ),
);
