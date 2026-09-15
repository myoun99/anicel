import '../editor_session_manager.dart';
import 'property_lane_model.dart' show PropertyLaneEditCallbacks;
import 'se_audio_lane.dart'
    show
        TimelineAudioLaneCallbacks,
        laneIsSeAudio,
        parseAudioOffsetInput,
        seAudioSpanForLaneValue;

/// A rail's lane edits wired to [session] — the one wiring behind the
/// timeline's lanes and the storyboard's S rows (F-101). [frameIsGlobal] is
/// the rail's axis: a cut's rail hands cut frames, a track's rail global
/// ones, and the verbs put either on the row the project holds (F-102).
PropertyLaneEditCallbacks sessionLaneEditCallbacks(
  EditorSessionManager session, {
  required bool frameIsGlobal,
}) => PropertyLaneEditCallbacks(
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
  onSetValue: (layer, lane, frameIndex, input) {
    // The SE audio lane's value field edits the playhead span's offset
    // trim instead of a transform property (one undo via the session).
    if (laneIsSeAudio(lane)) {
      final offset = parseAudioOffsetInput(input);
      final span = seAudioSpanForLaneValue(layer, frameIndex);
      if (offset == null || span == null) {
        return;
      }
      session.audioClips.setAudioClipOffset(layer.id, span.clipIndex, offset);
      return;
    }
    session.laneVerbs.setLaneValueAt(
      layer.id,
      lane.laneId,
      frameIndex,
      input,
      frameIsGlobal: frameIsGlobal,
      description: 'Set ${lane.label} at frame ${frameIndex + 1}',
    );
  },
);

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
