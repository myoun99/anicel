import 'package:flutter/widgets.dart';

import '../../models/cut_id.dart';
import '../../models/layer.dart';
import '../../models/layer_id.dart';
import '../../models/timeline_row_address.dart';
import '../../services/audio/audio_peaks_extractor.dart';
import '../audio/sound_cannot_play.dart';
import 'memo_token.dart';

/// THE LAYER A KEPT ROW STANDS FOR NOW — handed down past the row's memo.
///
/// 🚨I-57 ㉣ (10-13): a cut switch builds the new cut's rows in the old
/// rows' elements ([RowBerths]), and a row whose FACE is the face the old
/// row showed — its name, kind, label, opacity, switches — is the same row
/// on screen, so its memo hands it back whole ([KeptLayerControlsRows]).
/// Only WHICH layer it stands for changed, and that is asked here, at the
/// moment it matters: a press acts on the layer the row stands for now
/// ([layerIdNow]), and an eye shows that layer's switch ([of]).
///
/// 🚨I-57 (10-13): a CELLS row is kept by its SHAPE — the pieces its
/// layer's kind mounts — and what it draws is asked here too ([shows]):
/// the layer it shows now, the drag preview's when a drag stands on it,
/// and the cells a held file would add. A cut switch then hands every row
/// of the same shape back whole and repaints its pictures; it used to
/// build every row again, and the rows' gesture layers re-described
/// themselves to the semantics tree on every crossing a scrub or a play
/// made — the largest share of a crossing frame left.
///
/// ⛔A kept row's own [Layer] is the one it was BUILT for: equal to this
/// one in its face, another layer by its id. Nothing in a kept row asks
/// that id for what it acts on. Its NAMES are spelled with it — a finder
/// reads them as the row stands.
class BerthRow extends InheritedModel<BerthAspect> {
  const BerthRow({
    super.key,
    required this.layer,
    Layer? shown,
    this.silhouette,
    this.world,
    required super.child,
  }) : shown = shown ?? layer;

  /// The layer the row stands for — the repository's, what its verbs act
  /// on.
  final Layer layer;

  /// What the row draws of it now: [layer], or the drag preview's layer
  /// while a drag stands on the row ([TimelineDragPreviewRowGate.shows]).
  final Layer shown;

  /// The cells a file held over the row would author — null when none is.
  ///
  /// 「끄는 동안 보이는 것은 놓았을 때 생길 것이다」 (미디어 배치 라운드
  /// 2d-2). ⚠️The cells themselves come from [shown], which is already the
  /// drag preview's row: the blocks in the way have moved, and these are
  /// the ones that are not there yet. This span only says WHICH — it does
  /// not author anything, and nothing here asks where the drop would go.
  final ({int startIndex, int endIndexExclusive})? silhouette;

  /// What else a cut switch changes for the row's pictures ([BerthWorld]);
  /// null on a row that draws none (the rail's).
  final BerthWorld? world;

  /// The layer the row at [context] stands for now — [context] rebuilt
  /// when the row stands for ANOTHER layer; null where no kept row stands
  /// above. What the row shows of the layer is its face, which the memo
  /// answers for: a reader takes the layer's identity from here.
  static Layer? of(BuildContext context) => InheritedModel.inheritFrom<
    BerthRow
  >(context, aspect: BerthAspect.standsFor)?.layer;

  /// [of] at an event — a press, a drag's start — without depending on it.
  static Layer? at(BuildContext context) =>
      context.getInheritedWidgetOfExactType<BerthRow>()?.layer;

  /// What the row at [context] draws now — [context] rebuilt whenever that
  /// changes: another layer, the same layer edited, a drag's preview, a
  /// held file's cells. Null where no kept row stands above.
  static BerthRow? shows(BuildContext context) =>
      InheritedModel.inheritFrom<BerthRow>(
        context,
        aspect: BerthAspect.shows,
      );

  bool _showsOtherThan(BerthRow old) =>
      !identical(old.shown, shown) ||
      !identical(old.layer, layer) ||
      old.silhouette != silhouette ||
      old.world != world;

  @override
  bool updateShouldNotify(BerthRow oldWidget) =>
      oldWidget.layer.id != layer.id || _showsOtherThan(oldWidget);

  @override
  bool updateShouldNotifyDependent(
    BerthRow oldWidget,
    Set<BerthAspect> dependencies,
  ) =>
      (dependencies.contains(BerthAspect.standsFor) &&
          oldWidget.layer.id != layer.id) ||
      (dependencies.contains(BerthAspect.shows) &&
          _showsOtherThan(oldWidget));
}

/// What a cut switch changes for a cells row's pictures besides its layer —
/// handed down past the row's memo with the layer ([BerthRow.world]), so a
/// row kept by its shape draws the cut it stands in.
///
/// 🚨I-57 (10-13): every one of these keyed the row's MEMO, so a cut switch
/// built every row again however alike the two cuts' rows were — the world
/// ([substrateGeneration], #29) and the cut's length change at every
/// switch by definition. The memo keys what the row MOUNTS; these are what
/// its mounted pieces draw.
typedef BerthWorld = ({
  /// #29: the (project, cut) world the row's tiles are baked for.
  String substrateGeneration,

  /// How many frames the cut is DRAWN for — its 尺 plus the のりしろ — where
  /// an SE row's end `~` stands (F-358: 「총합적인 엔드라인」).
  int drawnFrameCount,

  /// How far into its block the cut's frame 0 already is (UI-R7 #6) — null
  /// when nothing spills in.
  int? spillInLeadFrames,

  /// The cut the row is seen in, where an SE block reads its delivery
  /// (F-386 · F-496) — null for a row in no cut.
  CutId? cutId,

  /// ㉘: what the row's coverage follows when it is not the layer.
  ByIdentity<Object?> coverageIdentity,

  /// The waveforms an SE row's strips paint — each by identity, null while
  /// extracting.
  ByList<AudioPeaks?> seAudioPeaks,

  /// Why each sound an SE row draws cannot be played — null where it can
  /// (playback-says-the-sound-it-cannot-play).
  ByList<SoundCannotPlay?> seSoundsCannotPlay,
});

/// What a reader of [BerthRow] is rebuilt for.
enum BerthAspect {
  /// Which layer the row stands for ([BerthRow.of]).
  standsFor,

  /// What the row draws ([BerthRow.shows]).
  shows,
}

/// The id of the layer the row at [context] stands for now — [builtFor],
/// where no kept row stands above, the row then being built for the layer
/// it shows. What every verb of a row hands its host.
LayerId layerIdNow(BuildContext context, LayerId builtFor) =>
    BerthRow.at(context)?.id ?? builtFor;

/// [builtFor] as the row at [context] stands now — the address a gesture
/// layer hands its host. A row of a layer names the layer it stands for
/// ([layerIdNow]); a track's row names its track, which no berth changes.
TimelineRowAddress rowAddressNow(
  BuildContext context,
  TimelineRowAddress builtFor,
) => switch (builtFor) {
  LayerRowAddress(:final layerId) => LayerRowAddress(
    layerIdNow(context, layerId),
  ),
  LaneRowAddress(:final layerId, :final laneId) => LaneRowAddress(
    layerIdNow(context, layerId),
    laneId,
  ),
  TrackRowAddress() => builtFor,
};
