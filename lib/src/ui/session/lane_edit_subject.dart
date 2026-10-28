import '../../models/layer_effect.dart';
import '../../models/se_name_tag.dart';
import '../../models/se_sound.dart';
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
    required this.commit,
    required this.preview,
    this.referenceFx,
    this.seNameTag,
    this.seSound,
  });

  /// The transform lanes' keys, the effect chain's, and — on SE rows — the
  /// name tag's and the sound's. Which one an edit reads is the LANE's
  /// question: an effect lane on a camera row edits the layer's chain while
  /// its Position lane edits the cut's camera.
  final TransformTrack transformTrack;
  final List<LayerEffect> effects;

  /// A reference row's REFERENCE FX keys (F-374) — the transform lanes'
  /// other home: a `reference:` lane is the transform lane it holds there.
  /// Null on a row that shows no file.
  final TransformTrack? referenceFx;

  /// The row's name tag (C①). Null on rows that cannot carry one — the
  /// write of a tag throws for any row but an SE row's, so no edit of one
  /// is made there.
  final SeNameTag? seNameTag;

  /// The row's sound (I-140) — null, as [seNameTag] is, on every row but an
  /// SE row's.
  final SeSound? seSound;

  /// [seNameTag] keyed as [keys] — null where [keys] is, or the row
  /// carries no tag.
  SeNameTag? nameTagWith(SeNameTagTrack? keys) =>
      keys == null ? null : seNameTag?.copyWith(track: keys);

  /// [LaneEdit] goes back home by home, in ONE step.
  final void Function(LaneEdit next, String description) commit;

  /// The row as [edit] leaves it — each family it leaves alone as it is:
  /// what an edit made after it reads (I-3: a graph's key moved in its
  /// value, then along the frames).
  LaneEditSubject after(LaneEdit edit) => LaneEditSubject(
    transformTrack: edit.transform.own ?? transformTrack,
    referenceFx: edit.transform.reference ?? referenceFx,
    effects: edit.effects ?? effects,
    seNameTag: edit.nameTag ?? seNameTag,
    seSound: edit.sound ?? seSound,
    commit: commit,
    preview: preview,
  );

  /// What an edit in flight shows as — null where it shows nothing (a V
  /// row's carrier has no transform to show), and where [commit] would
  /// refuse it.
  final TimelineDragPreview? Function(LaneEdit next) preview;
}

/// What an edit leaves a row's TRANSFORM keys at, home by home: its own
/// lanes' track, and a reference row's fx (F-374) — null for a home the
/// edit leaves alone.
typedef TransformHomes = ({TransformTrack? own, TransformTrack? reference});

/// What a lane edit leaves a row's keys at, family by family — each null
/// where the edit leaves that family alone: the transform's two homes, the
/// effect chain and, on an SE row, the name tag and the sound.
///
/// 🚨F-374: ONE edit for every family, so a verb over a span is one step
/// over all the span holds (`RowLaneHomes`). ↩️An edit was ONE family's,
/// which a span over lanes of two could not be.
class LaneEdit {
  const LaneEdit({
    this.transform = (own: null, reference: null),
    this.effects,
    this.nameTag,
    this.sound,
  });

  final TransformHomes transform;
  final List<LayerEffect>? effects;
  final SeNameTag? nameTag;
  final SeSound? sound;

  /// Whether it leaves every family alone.
  bool get isEmpty =>
      transform.own == null &&
      transform.reference == null &&
      effects == null &&
      nameTag == null &&
      sound == null;

  /// This edit and then [later], made on what this one leaves: each family
  /// as the last of the two to touch it leaves it.
  LaneEdit then(LaneEdit later) => LaneEdit(
    transform: (
      own: later.transform.own ?? transform.own,
      reference: later.transform.reference ?? transform.reference,
    ),
    effects: later.effects ?? effects,
    nameTag: later.nameTag ?? nameTag,
    sound: later.sound ?? sound,
  );
}
