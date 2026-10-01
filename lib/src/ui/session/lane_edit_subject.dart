import '../../models/layer_effect.dart';
import '../../models/se_name_tag.dart';
import '../../models/transform_track.dart';
import '../timeline/timeline_drag_preview.dart';

/// WHAT a lane edit edits: where a row's keys live, how an edit goes back,
/// and what one in flight shows as.
///
/// The move path used to name its subjects inline, in three methods that
/// each had to remember the whole list — and two subjects were missing from
/// all three. A CAMERA lane edits `cut.camera.track`, not the camera layer's
/// own (unused) transform track, so opening the band there would have
/// written keys where nothing reads them; that is why camera keys were left
/// with a private marker drag while every other lane moved by selection. A V
/// TRACK's EFFECT chain was simply never looked at, so an fx key range on
/// that row answered "nothing to move" and refused in silence.
///
/// 🚨F-195 (2026-09-27): ONE subject for every lane edit. The range move
/// resolved this answer for itself while the lane verbs — a value scrubbed
/// or typed, a key toggled, a canvas handle dropped — committed through
/// funnels of their own: the same three homes (a row, a V track, the cut's
/// camera), answered twice. `LaneVerbs.laneEditSubjectOf` answers it once,
/// from the funnels the verbs commit and preview through.
class LaneEditSubject {
  const LaneEditSubject({
    required this.transformTrack,
    required this.effects,
    required this.commitTransform,
    required this.commitEffects,
    required this.previewTransform,
    required this.previewEffects,
    this.seNameTag,
    this.commitSeNameTag,
    this.previewSeNameTag,
  });

  /// The transform lanes' keys, the effect chain's, and — on SE rows — the
  /// name tag's. Which one an edit reads is the LANE's question: an effect
  /// lane on a camera row edits the layer's chain while its Position lane
  /// edits the cut's camera.
  final TransformTrack transformTrack;
  final List<LayerEffect> effects;

  /// The row's name tag (C①). Null on rows that cannot carry one — the
  /// name-tag arm is only armed where a tag can exist, because the commit
  /// verb throws for non-SE layers.
  final SeNameTag? seNameTag;

  final void Function(TransformTrack next, String description)
  commitTransform;
  final void Function(List<LayerEffect> next, String description)
  commitEffects;
  final void Function(SeNameTag next, String description)? commitSeNameTag;

  /// What an edit in flight shows as — null where it shows nothing (a V
  /// row's carrier has no transform to show).
  final TimelineDragPreview? Function(TransformTrack next) previewTransform;
  final TimelineDragPreview Function(List<LayerEffect> next) previewEffects;
  final TimelineDragPreview Function(SeNameTag next)? previewSeNameTag;
}
