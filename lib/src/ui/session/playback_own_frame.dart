import '../../models/track_frame_axis.dart';
import '../../services/playback/playback_frame_mapping.dart'
    show PlaybackPosition;
import '../playback/canvas_playback_controller.dart'
    show CanvasPlaybackController, PlaybackScope;

/// The frame of its cut's OWN a playing [position] stands on.
///
/// A cut played ALONE counts its playlist from its material's first frame
/// — the cut's own already. The all-cuts playlist is the TRACK's axis,
/// where a cut stands at its conte's place: its own frames begin a のりしろ
/// earlier in a cut an O.L arrives into ([TrackFrameAxis.leadOf]), so the
/// frame the position counts from the cut's place is that much short.
///
/// ↩️Every reader took the position's frame as it came, so through such a
/// cut the timeline's playhead, the sheet's, and the frame a stop landed on
/// ran that margin behind the picture (I-73-ol-index-space, 2026-10-08).
/// The pictures themselves were never wrong: the track stack reads each
/// cut's contribution, which counts from its material.
int playbackOwnFrameOf(
  PlaybackPosition position, {
  required CanvasPlaybackController playback,
  required TrackFrameAxis axis,
}) => playback.scope == PlaybackScope.allCuts
    ? position.localFrameIndex + axis.leadOf(position.cutId)
    : position.localFrameIndex;
