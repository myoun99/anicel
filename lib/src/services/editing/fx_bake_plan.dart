import 'dart:collection' show SplayTreeMap;

import '../../core/collection_equality.dart' show setEquals;
import '../../models/attached_layer_resolve.dart'
    show attachedMirrorCelId, fxCarrierOf, isSyncedAttachedLayer;
import '../../models/audio_clip.dart';
import '../../models/canvas_point.dart';
import '../../models/cut.dart';
import '../../models/cut_id.dart';
import '../../models/frame.dart';
import '../../models/frame_id.dart';
import '../../models/fx_basis.dart';
import '../../models/layer.dart';
import '../../models/layer_effect.dart';
import '../../models/layer_id.dart';
import '../../models/pasteboard_bounds.dart';
import '../../models/project.dart';
import '../../models/property_track.dart'
    show KeyValueSpace, PropertyTrack;
import '../../models/property_track_cut.dart' show trackClearedOver;
import '../../models/timeline_coverage.dart' show exposedFrameIdAt;
import '../../models/timeline_exposure.dart';
import '../../models/timeline_repeat.dart'
    show ghostFreeTimeline, rederiveRunBehaviors;
import '../../models/timeline_splice.dart' show splitTimelineAt;
import '../../models/track_conte_laying.dart' show conteBaseOf;
import '../../models/track_transitions.dart' show cutDrawnFrameCount;
import '../../models/transform_track.dart';
import '../commands/link_mirror.dart'
    show existenceMirrorTargets, headMirrorTargets;
import '../cut_frame_composite_plan.dart' show exposedCelIdAt;
import '../playback/cut_frame_composite_signature.dart'
    show BrushFrameRevisionResolver, CutFrameCompositeSignature;
import '../playback/cut_frame_composite_spans.dart';
import '../project_lookup.dart' show requireCut;
import 'layer_merge_plan.dart'
    show
        CelReads,
        LayerMergePicture,
        drawnBare,
        kindHoldingPictures,
        picturesCutAtTheWall,
        rowsKeyedAcrossCuts,
        runsByPicture,
        tailClearOf;

/// Why a bake may show otherwise than the row did — what the press warns of
/// first, as a merge's does (I-78-Q1 「포토샵 · 클튜처럼 (+경고)」).
enum FxBakeChange {
  /// An fx the row runs before the one baked is on: baked into the cels,
  /// the baked one runs before it after (🗣️I-120-Q2, 유저 2026-11-04 「누른
  /// fx 만 굽는다 — 순서가 바뀌면 먼저 경고」). The transform runs after
  /// every fx, so any fx on parts it.
  order,

  /// A picture lies past the wall, which the bake cuts off as a merge does
  /// (I-78-Q15 · Q19).
  wall,
}

/// The frames a press of RASTERIZE bakes, from [start] to [end]
/// (exclusive).
typedef BakedFrames = ({int start, int end});

/// One use of the row a press bakes — the row as one cut holds it: the
/// [cut], the [row] there, the frames [drawn] there and the [frames] it
/// bakes of them — none for a use it leaves showing what it shows — and
/// [keys], each row of the cut a link group holds named as every cut names
/// it ([rowsKeyedAcrossCuts]), so the uses' pictures are one where they
/// show one, and the uses whose row is one key share one bank of cels.
typedef _Use = ({
  Cut cut,
  Layer row,
  int drawn,
  BakedFrames? frames,
  Map<LayerId, LayerId> keys,
});

/// A row riding the row a press bakes, as the use at [use] — its place
/// among the uses — holds it.
typedef _Riding = ({int use, Layer rider});

/// What ONE press of RASTERIZE in a row's fx group header takes: the row in
/// every cut it is used in, the fx — the transform, where [_effectId] is
/// null — and the rows riding the row that wear it.
final class FxBakeTaking {
  const FxBakeTaking._(this._effectId, this._uses, this._riders);

  /// The fx it bakes; null for the transform.
  final EffectId? _effectId;

  /// The row's uses, the pressed cut's first: every member of its link
  /// group, whose cels are one bank — baked together (🗣️I-120-Q6 「같은 셀을
  /// 보는 다른 컷도 같이 굽는다」, as a reference rasterize lets every use
  /// go, F-374-Q10) — and, for a row of a track's conte, its row in every
  /// cut of the track that has the conte, each with a bank of its own but
  /// for the cuts a link group joins (🗣️I-120-Q7 「트랙의 콘티가 있는 컷
  /// 전부에서 같이 굽는다」: the fx's head is the track's).
  final List<_Use> _uses;

  /// The rows riding the row that wear its fx and its transform
  /// ([fxCarrierOf]), baked with it (I-120 ②b — 「어태치 레이어는 주인과
  /// 같이 굽는다」, 07-21) — in every use of it, as each cut holds them
  /// (④b): a rider in one is its link group's in every other.
  final List<_Riding> _riders;

  /// The use the press was pressed in.
  _Use get _pressed => _uses.first;

  /// Whether it bakes an fx that draws at its defaults — the cel number's,
  /// a plugin's — and leaves a frame a use draws, where it would go on
  /// drawing: its switch has no key, and is every use's, so it cannot be
  /// off for the frames baked alone. 🗣️I-120-Q14, its recommendation while
  /// it is asked 「막고 경고」 (Q6's law for what one picture cannot hold):
  /// it bakes nothing, and says why ([FxBakeWait.rest]).
  bool get _cannotKeepTheRest =>
      _uses.any(_keepsAFrame) &&
      _pressed.row.effects.any(
        (fx) => fx.id == _effectId && !fx.kind.changesNothingAtItsDefaults,
      );

  /// It scoped to the frames of the pressed cut its own [band] holds — the
  /// band scoping the press (Q3), which is that cut's: it bakes nothing of
  /// the row's other uses, the cels they show kept where they show them —
  /// as it is where none does, and null where the band holds none of them.
  FxBakeTaking? over(BakedFrames? band) {
    if (band == null) {
      return this;
    }
    final (:cut, :row, :drawn, :frames, :keys) = _pressed;
    // The pressed use bakes: it is what the press bakes of.
    final start = band.start < frames!.start ? frames.start : band.start;
    final end = band.end > frames.end ? frames.end : band.end;
    if (start >= end) {
      return null;
    }
    return FxBakeTaking._(_effectId, [
      (
        cut: cut,
        row: row,
        drawn: drawn,
        frames: (start: start, end: end),
        keys: keys,
      ),
      for (final use in _uses.skip(1))
        (
          cut: use.cut,
          row: use.row,
          drawn: use.drawn,
          frames: null,
          keys: use.keys,
        ),
    ], _riders);
  }
}

/// Whether a frame [use]'s cut draws is one it does not bake.
bool _keepsAFrame(_Use use) => switch (use.frames) {
  final frames? => !_coversEvery(frames, use.drawn),
  null => use.drawn > 0,
};

/// What a press of RASTERIZE in [rowId]'s group header for [effectId] — the
/// transform's, where null — takes of [cutId] in [project]: null where it
/// bakes nothing.
///
/// 🗣️I-120-Q8 (유저 2026-11-04 「폴더 · 조정 레이어 둘 다 버튼이 꺼진다」): a
/// row with no picture of its own bakes nothing — a folder, an adjustment
/// row, the camera. Nor does a row that wears another's fx: a row riding
/// another wears its base's and authors none (R9 — the panels draw it none).
///
/// ⚠️A reference row stands down wherever the press reaches one — a use of
/// its row or a row riding it — until the round that takes it (⑤, Q5): the
/// card's order, not a law of the verb. And so does a row riding it with a
/// self the press does not reach — linked to a row riding a row that is no
/// use of it: its cels are that self's too, and would show baked over a
/// base that is not (as a merge leaves such a row to stay).
///
/// It bakes every frame each use's cut draws; a band scoping the press
/// narrows it ([FxBakeTaking.over]).
FxBakeTaking? takeFxToBake({
  required Project project,
  required CutId cutId,
  required LayerId rowId,
  required EffectId? effectId,
}) {
  final cut = requireCut(project, cutId);
  final row = cut.layers.byId(rowId);
  if (row == null ||
      !row.kind.isDrawingCel ||
      fxCarrierOf(row, cut.layers)?.id != row.id) {
    return null;
  }
  if (effectId != null && !row.effects.any((fx) => fx.id == effectId)) {
    return null;
  }
  final pressed = (cutId: cut.id, layerId: row.id);
  final uses = [
    for (final (:cutId, :layerId) in [
      pressed,
      for (final use in headMirrorTargets(
        project,
        cutId: cut.id,
        layerId: row.id,
      ))
        if (use != pressed) use,
    ])
      _useOf(project, cutId, layerId),
  ];
  final riders = [
    for (final (index, use) in uses.indexed)
      for (final rider in _ridersOf(use.cut, use.row))
        (use: index, rider: rider),
  ];
  if (_standsDown(project, uses, riders)) {
    return null;
  }
  return FxBakeTaking._(effectId, uses, riders);
}

/// [rowId]'s use in [cutId] ([_Use]), every frame the cut draws baked.
_Use _useOf(Project project, CutId cutId, LayerId rowId) {
  final cut = requireCut(project, cutId);
  final drawn = cutDrawnFrameCount(project, cutId) ?? cut.duration;
  return (
    cut: cut,
    row: cut.layers.byId(rowId)!,
    drawn: drawn,
    frames: (start: 0, end: drawn),
    keys: rowsKeyedAcrossCuts(project.linkRegistry, cut),
  );
}

/// The rows of [cut] riding [row] that wear its fx ([fxCarrierOf]).
List<Layer> _ridersOf(Cut cut, Layer row) => [
  for (final other in cut.layers)
    if (other.id != row.id &&
        other.kind.isDrawingCel &&
        fxCarrierOf(other, cut.layers)?.id == row.id)
      other,
];

/// Whether a press taking [uses] and [riders] stands down ([takeFxToBake]).
bool _standsDown(Project project, List<_Use> uses, List<_Riding> riders) {
  final taken = {
    for (final (:use, :rider) in riders)
      (cutId: uses[use].cut.id, layerId: rider.id),
  };
  return uses.any((use) => use.row.mediaReference != null) ||
      riders.any(
        (riding) =>
            riding.rider.mediaReference != null ||
            existenceMirrorTargets(
              project,
              cutId: uses[riding.use].cut.id,
              layerId: riding.rider.id,
            ).any((self) => !taken.contains(self)),
      );
}

/// What a press of RASTERIZE makes of what it takes ([planFxBake]): a bake
/// ([FxBakePlan]), or nothing, and why ([FxBakeWaits]).
sealed class FxBakeOutcome {
  const FxBakeOutcome();
}

/// It bakes nothing, and [why] is what the press says.
final class FxBakeWaits extends FxBakeOutcome {
  const FxBakeWaits(this.why);

  final FxBakeWait why;
}

/// Why a press of RASTERIZE bakes nothing ([FxBakeWaits]): what the row's
/// pictures cannot hold, which it does not bake and warns of (「막고 경고」 —
/// 🗣️I-120-Q6, as F-374-Q11 for a reference).
enum FxBakeWait {
  /// The fx draws at its defaults, and a frame a use draws is left unbaked:
  /// its switch, every frame's of every use, cannot be off there alone
  /// (Q14, its recommendation while it is asked).
  rest,

  /// A cel the uses share shows as other pictures in one than in another,
  /// and one cel holds one (Q6).
  usesApart,

  /// A panel of a cut's conte would show more than one picture of the row:
  /// the conte's own block parted — a cell more on the conte sheet — or a
  /// synced row's cel of it, which is one for each of the conte's. Both
  /// are asked (🗣️I-120-Q17 · Q18); until they are answered it bakes
  /// nothing and says why.
  panelParts,
}

/// What a press of RASTERIZE makes of a row: its pictures with the fx baked
/// in, and the row after — in every cut it is used in.
final class FxBakePlan extends FxBakeOutcome {
  const FxBakePlan._({
    required this.cut,
    required this.row,
    required this.riders,
    required this.pictures,
    required this.changes,
    required this.layers,
    required this.others,
  });

  /// The cut it was planned of, as it was.
  final Cut cut;

  /// The row after: its cels the baked pictures, the fx at its defaults.
  final Layer row;

  /// The rows riding [row] after, their cels the pictures they showed
  /// wearing the fx ([_riderBaked]).
  final List<Layer> riders;

  /// Every new cel's picture, still to be laid: each drawn of a use of the
  /// row wearing the baked fx alone ([_wearingOnly]), or of a rider riding
  /// it so ([_ridingOnly]).
  final List<LayerMergePicture> pictures;

  final Set<FxBakeChange> changes;

  /// [cut]'s rows after: [row] and [riders] where they stood, and any other
  /// use of the row it holds.
  final List<Layer> layers;

  /// Every other cut the row is used in (Q6), as it was, with its rows
  /// after.
  final List<({Cut cut, List<Layer> layers})> others;
}

/// What RASTERIZE makes of [taking] (I-120 round ②).
///
/// 🗣️I-120 (유저 2026-10-21): 「래스터라이즈하면 fx는 그대로 있지만 키만 다
/// 초기화 … 여러장에 적용되야한다면 애니메이션레이어로 전환해서 프레임만들어서
/// 적용」, and its answers (11-04):
/// - Q1 「스위치를 따른다 — 늘 보이던 그대로」 — a picture for each run of
///   frames the row shows ONE picture over, wearing the fx as it is read
///   there, by frame or by block: the composite signature's runs
///   ([runsByPicture]), as a merge finds its pictures (I-78-Q3 · Q6).
/// - Q2 — the fx alone is baked ([FxBakeChange.order]).
/// - Q4 「구운 뒤 그 fx 의 스위치를 끈다」 — every value and key of the fx
///   back at its default, its line kept; one that changes the picture at
///   its defaults (the cel number, a plugin's) switched off besides.
/// - Q6 「같은 셀을 보는 다른 컷도 같이 굽는다 — 한 장에 못 담으면 막고
///   경고」 — every use of the row by its own values and timing, into the
///   one bank its cels are: a picture two uses show is one cel; a cel one
///   use shows as other pictures than another does bakes nothing
///   ([FxBakeWait.usesApart]).
/// - Q7 「트랙의 콘티가 있는 컷 전부에서 같이 굽는다」 — a row of a track's
///   conte in every cut of the track that has it, each by its own values
///   and timing into a bank of its own, as a merge takes them (I-78-Q20).
///   A panel that would show more than one picture of the row bakes
///   nothing while Q17 · Q18 are asked ([FxBakeWait.panelParts]).
///
/// A cel that shows one picture is that picture — its name, its place in
/// the bank. A cel shown as several takes a new cel for each after the
/// first, named with the tail a merge names a parted picture with (I-78-Q10
/// 「갈라진 곳은 꼬리 번호」), its blocks split where the picture changes
/// ([splitTimelineAt]: the head keeps the memo and the marks). A hold or a
/// repeat that would show a cel where another picture belongs is made of
/// blocks of its own. An image row holding more than one picture becomes a
/// drawing row (I-120: 「애니메이션레이어로 전환」). The rows riding the row
/// wear its fx, so they are baked with it ([_riderBaked]) — but the rows
/// riding a conte, which wear their own (I-99): those synced on it keep
/// their pictures, linked to its new cels ([_followersOf]). A synced row
/// of the conte keeps its pictures one for each of the conte's cels, its
/// links where its timing is.
///
/// [readsOf] says how each cut's cels are read; [mintFrameId] names each
/// new cel; [reach] is how far past the canvas the wall stands.
FxBakeOutcome planFxBake(
  FxBakeTaking taking, {
  required CelReads Function(Cut cut) readsOf,
  required FrameId Function(LayerId row) mintFrameId,
  required PasteboardReach reach,
}) {
  if (taking._cannotKeepTheRest) {
    return const FxBakeWaits(FxBakeWait.rest);
  }
  final FxBakeTaking(_effectId: effectId, _uses: uses, _pressed: pressed) =
      taking;
  final shown = [
    for (final use in uses) _shownOf(use, effectId, readsOf(use.cut)),
  ];
  final banked = _banksOf(uses, shown, mintFrameId);
  if (banked == null) {
    return const FxBakeWaits(FxBakeWait.usesApart);
  }
  final held = banked.held;
  final rows = [
    for (final (index, use) in uses.indexed)
      _rowBaked(use, effectId, held[index]),
  ];
  for (final (index, use) in uses.indexed) {
    if (_partsAPanel(use, rows[index], held[index])) {
      return const FxBakeWaits(FxBakeWait.panelParts);
    }
  }
  final riders = _ridersBaked(taking, [
    for (final (index, each) in shown.indexed)
      (runs: each.runs, held: held[index]),
  ], (revisionOf: (cut) => readsOf(cut).revisionOf, mintFrameId: mintFrameId));
  if (riders == null) {
    return const FxBakeWaits(FxBakeWait.usesApart);
  }
  final pictures = [...banked.pictures, ...riders.pictures];
  final cuts = _cutsAfter([
    for (final (index, use) in uses.indexed) ...[
      (cut: use.cut, row: rows[index]),
      for (final follower in _followersAfter(use, held[index]))
        (cut: use.cut, row: follower),
    ],
    ...riders.rows,
  ]);
  return FxBakePlan._(
    cut: pressed.cut,
    row: rows.first,
    riders: [
      for (final (:cut, :row) in riders.rows)
        if (cut.id == pressed.cut.id) row,
    ],
    pictures: pictures,
    changes: {
      if (_runsAfterAnFxOn(pressed.row, effectId)) FxBakeChange.order,
      if (_cutAtTheWall(pictures, readsOf, reach)) FxBakeChange.wall,
    },
    layers: cuts.first.layers,
    others: cuts.sublist(1),
  );
}

/// [use] as the bake draws it ([_Shown]): wearing the fx [effectId] alone
/// ([_wearingOnly]), its cels read by [reads].
_Shown _shownOf(_Use use, EffectId? effectId, CelReads reads) {
  final cut = _wearingOnly(use.cut, use.row, effectId);
  return (
    into: use.cut,
    row: use.row,
    cut: cut,
    runs: runsByPicture(
      cut,
      [cut.layers.byId(use.row.id)!],
      reads.revisionOf,
      keys: use.keys,
    ),
    baked: use.frames,
  );
}

/// Whether a row a picture of [pictures] is drawn of shows a picture past
/// its cut's wall, [reach] past the canvas ([picturesCutAtTheWall]) — each
/// cut's cels read by [readsOf].
bool _cutAtTheWall(
  List<LayerMergePicture> pictures,
  CelReads Function(Cut cut) readsOf,
  PasteboardReach reach,
) => pictures.any(
  (picture) => picturesCutAtTheWall([picture], (
    wall: picture.into.canvasSize.pasteboardAt(reach),
    inkOf: readsOf(picture.into).inkOf,
  )),
);

/// Each cut [after] names a row of, as it was, with its rows after: each
/// row [after] gives it where it stood — the cuts in the order [after]
/// first names them.
List<({Cut cut, List<Layer> layers})> _cutsAfter(
  List<({Cut cut, Layer row})> after,
) {
  final byCut = <CutId, ({Cut cut, Map<LayerId, Layer> rows})>{};
  for (final (:cut, :row) in after) {
    (byCut[cut.id] ??= (cut: cut, rows: {})).rows[row.id] = row;
  }
  return [
    for (final (:cut, :rows) in byCut.values)
      (
        cut: cut,
        layers: [for (final layer in cut.layers) rows[layer.id] ?? layer],
      ),
  ];
}

/// [use]'s row after its bake: its cels those [held], showing the one
/// [held] names at each frame — its blocks parted where its pictures are,
/// or, synced on a base, linked to each of the base's cels where it shows
/// one — and each of its FX bundles kept showing what it showed
/// ([_Keeping]) — the one baked at rest over the frames baked.
Layer _rowBaked(_Use use, EffectId? effectId, _Held held) {
  final (:cut, :row, :drawn, :frames, keys: _) = use;
  final parted = _holding(
    row,
    held,
    base: switch (_syncedBaseOf(cut, row)) {
      final base? => _heldAsShown(cut, base, held.celAt.keys),
      null => null,
    },
    drawn: drawn,
  );
  _Keeping keeping(FxBasis basis, {required bool baked}) => _Keeping(
    drawn,
    baked: baked ? frames : null,
    reads: (
      was: (frame) => fxReadFrame(basis, row.fxBlocks, frame),
      now: (frame) => fxReadFrame(basis, parted.fxBlocks, frame),
    ),
    paper: layerIdentityPose(cut.canvasSize),
  );
  return parted.copyWith(
    effects: [
      for (final fx in row.effects)
        _effectKept(fx, keeping(fx.basis, baked: fx.id == effectId)),
    ],
    transformTrack: _transformKept(
      row.transformTrack,
      keeping(row.transformBasis, baked: effectId == null),
    ),
  );
}

/// The cels a bake leaves a bank: [cels] the bank, [celAt] the cel each
/// frame of each use shows (by the use's place), [pictures] each new cel's
/// picture still to be laid, and [firstOf] the first picture each cel
/// baked became.
typedef _Bank = ({
  List<Frame> cels,
  List<Map<int, FrameId>> celAt,
  List<LayerMergePicture> pictures,
  Map<FrameId, FrameId> firstOf,
});

/// One row's cels after a bake: the [cels] of its bank, the cel it shows
/// at each frame ([celAt]) and the first picture each cel baked became
/// ([firstOf]).
typedef _Held = ({
  List<Frame> cels,
  Map<int, FrameId> celAt,
  Map<FrameId, FrameId> firstOf,
});

/// [bank] as the use at [place] holds it.
_Held _heldBy(_Bank bank, int place) =>
    (cels: bank.cels, celAt: bank.celAt[place], firstOf: bank.firstOf);

/// [row]'s cels as [cut] shows them at [frames], none of them baked.
_Held _heldAsShown(Cut cut, Layer row, Iterable<int> frames) => (
  cels: row.frames,
  celAt: {
    for (final frame in frames)
      frame: ?exposedCelIdAt(cut: cut, layerId: row.id, frameIndex: frame),
  },
  firstOf: const {},
);

/// Each of [uses]' cels after the bake ([held], by its place) and every
/// new cel's picture still to be laid: the uses whose row is one key
/// ([_Use.keys]) — a link group's — share one bank ([_bankOf]), each new
/// cel of it named under the first of them; any other has one of its
/// own. Null where uses sharing one cannot ([FxBakeWait.usesApart]).
({List<_Held> held, List<LayerMergePicture> pictures})? _banksOf(
  List<_Use> uses,
  List<_Shown> shown,
  FrameId Function(LayerId row) mintFrameId,
) {
  final sharing = <LayerId, List<int>>{};
  for (final (index, use) in uses.indexed) {
    (sharing[use.keys[use.row.id] ?? use.row.id] ??= []).add(index);
  }
  final held = <int, _Held>{};
  final pictures = <LayerMergePicture>[];
  for (final places in sharing.values) {
    final bank = _bankOf(
      [for (final index in places) shown[index]],
      (_, _) => mintFrameId(uses[places.first].row.id),
    );
    if (bank == null) {
      return null;
    }
    for (final (place, index) in places.indexed) {
      held[index] = _heldBy(bank, place);
    }
    pictures.addAll(bank.pictures);
  }
  return (
    held: [for (var index = 0; index < uses.length; index += 1) held[index]!],
    pictures: pictures,
  );
}

/// The base [row]'s cels ride in [cut], where it is synced on one — its
/// cels one for each of the base's ([isSyncedAttachedLayer]).
Layer? _syncedBaseOf(Cut cut, Layer row) => isSyncedAttachedLayer(row)
    ? cut.layers.byId(row.attachedToLayerId!)
    : null;

/// The rows of [cut] synced on [row] that wear fx of their own — the rows
/// riding a conte (I-99): its bake leaves their pictures as they are, its
/// new cels linked to the ones they showed over them ([_linksAfter]).
List<Layer> _followersOf(Cut cut, Layer row) => [
  for (final other in cut.layers)
    if (other.attachedToLayerId == row.id &&
        isSyncedAttachedLayer(other) &&
        fxCarrierOf(other, cut.layers)?.id == other.id)
      other,
];

/// [use]'s rows synced on its row ([_followersOf]) after its bake [held]:
/// each showing the cels it showed, over the row's cels after.
List<Layer> _followersAfter(_Use use, _Held held) => [
  for (final follower in _followersOf(use.cut, use.row))
    follower.copyWith(
      baseFrameLinks: _linksAfter(
        follower,
        held,
        _heldAsShown(use.cut, follower, held.celAt.keys),
      ),
    ),
];

/// Whether [use]'s row [after] its bake ([held]) shows more than one
/// picture over a panel of its cut's conte ([FxBakeWait.panelParts]): the
/// conte itself, its blocks no longer the ones they were — or a row synced
/// on it, a cel of the conte showing more than one of its.
bool _partsAPanel(_Use use, Layer after, _Held held) {
  final (:cut, :row, drawn: _, frames: _, keys: _) = use;
  if (conteBaseOf(cut)?.id == row.id) {
    return !_sameBlocks(row.timeline, after.timeline);
  }
  return switch (_syncedBaseOf(cut, row)) {
    final base? => !_oneEach(
      _heldAsShown(cut, base, held.celAt.keys).celAt,
      held.celAt,
    ),
    null => false,
  };
}

/// Whether [after] is made of the blocks [before] is — each where it was,
/// as long.
bool _sameBlocks(
  Map<int, TimelineExposure> before,
  Map<int, TimelineExposure> after,
) =>
    before.length == after.length &&
    before.entries.every(
      (block) =>
          after.containsKey(block.key) &&
          after[block.key]!.length == block.value.length,
    );

/// Whether each cel [by] names at a frame is shown with one cel [cels]
/// names there.
bool _oneEach(Map<int, FrameId> by, Map<int, FrameId> cels) {
  final shownWith = <FrameId, FrameId>{};
  return cels.entries.every(
    (at) => (shownWith[by[at.key]!] ??= at.value) == at.value,
  );
}

/// A use of a bank as a bake draws it: the [row] as the cut [into] holds
/// it, the [cut] it is drawn of, the [runs] of frames it shows one picture
/// over there ([runsByPicture]), and the frames [baked] of them — none for
/// a use it leaves.
typedef _Shown = ({
  Cut into,
  Layer row,
  Cut cut,
  List<List<CutFrameCompositeSpan>> runs,
  BakedFrames? baked,
});

/// One picture as a use shows it: the [use], by its place, and the [spans]
/// it shows it over.
typedef _Seen = ({int use, List<CutFrameCompositeSpan> spans});

/// The bank [uses] share after the bake, as each shows it — each new cel
/// named [idOf] the use that shows it first, by its place, and its run
/// there, its picture drawn of that use:
/// each cel no use shows over the frames it bakes kept as it is, each one
/// shown there parted into its pictures — and kept besides where a use
/// still shows it outside them, its pictures all new (🗣️I-120-Q3 「범위
/// 밖은 보이던 그대로」). Null where a use shows a cel as other pictures
/// than another does ([_picturesOfCels]).
_Bank? _bankOf(
  List<_Shown> uses,
  FrameId Function(int use, List<CutFrameCompositeSpan> run) idOf,
) {
  final ran = [for (final use in uses) _bakedRuns(use)];
  final pictured = _picturesOfCels([for (final each in ran) each.baked]);
  if (pictured == null) {
    return null;
  }
  final outside = {
    for (final (index, use) in uses.indexed)
      for (final MapEntry(key: frame, value: cel)
          in ran[index].celAt.entries)
        if (!_holds(use.baked, frame)) cel,
  };
  final celAt = [for (final each in ran) each.celAt];
  // The uses hold one bank.
  final row = uses.first.row;
  final held = {for (final cel in row.frames) ?celNumberOf(cel.name)};
  final bank = <Frame>[];
  final pictures = <LayerMergePicture>[];
  final firstOf = <FrameId, FrameId>{};
  for (final cel in row.frames) {
    final parts = pictured[cel.id] ?? const [];
    // The first picture keeps the place of a cel shown nowhere else.
    final kept = parts.isEmpty || outside.contains(cel.id);
    if (kept) {
      bank.add(cel);
    }
    for (final (index, seen) in parts.indexed) {
      final first = index == 0 && !kept;
      final (:use, :spans) = seen.first;
      final made = Frame(
        id: idOf(use, spans),
        duration: spans.first.length,
        name: first ? cel.name : _tailed(held, cel.name),
        strokes: const [],
      );
      bank.add(made);
      if (first) {
        firstOf[cel.id] = made.id;
      }
      _showing(celAt, seen, made.id);
      pictures.add((
        into: uses[use].into,
        rowId: uses[use].row.id,
        frameId: made.id,
        from: uses[use].cut,
        frameIndex: spans.first.start,
      ));
    }
  }
  return (cels: bank, celAt: celAt, pictures: pictures, firstOf: firstOf);
}

/// [celAt] — each use's, by its place — showing [cel] wherever [seen]
/// shows its picture.
void _showing(
  List<Map<int, FrameId>> celAt,
  List<_Seen> seen,
  FrameId cel,
) {
  for (final (:use, :spans) in seen) {
    for (final span in spans) {
      for (var frame = span.start; frame < span.endExclusive; frame += 1) {
        celAt[use][frame] = cel;
      }
    }
  }
}

/// Each cel the uses show over the frames they bake — [baked], each use's
/// by its place ([_bakedRuns]) — as its pictures, each seen by every use
/// that shows it: null where a use shows a cel as other pictures than
/// another does, which one cel cannot hold (🗣️I-120-Q6 「한 장에 못 담으면
/// 막고 경고」).
Map<FrameId, List<List<_Seen>>>? _picturesOfCels(
  List<Map<FrameId, List<List<CutFrameCompositeSpan>>>> baked,
) {
  final byCel = <FrameId, Map<CutFrameCompositeSignature, List<_Seen>>>{};
  for (final (use, cels) in baked.indexed) {
    for (final MapEntry(key: cel, value: runs) in cels.entries) {
      final signatures = {for (final run in runs) run.first.signature};
      final known = byCel[cel];
      if (known != null && !setEquals(signatures, known.keys.toSet())) {
        return null;
      }
      final pictures = byCel[cel] ??= {};
      for (final run in runs) {
        (pictures[run.first.signature] ??= []).add((use: use, spans: run));
      }
    }
  }
  return {
    for (final MapEntry(key: cel, value: pictures) in byCel.entries)
      cel: [...pictures.values],
  };
}

/// [shown]'s runs: each of its cels' runs over the frames baked ([baked]),
/// and the cel it shows at every frame it shows one ([celAt]). A run its
/// row shows nothing over is none of its.
({
  Map<FrameId, List<List<CutFrameCompositeSpan>>> baked,
  Map<int, FrameId> celAt,
})
_bakedRuns(_Shown shown) {
  final baked = <FrameId, List<List<CutFrameCompositeSpan>>>{};
  final celAt = <int, FrameId>{};
  for (final spans in shown.runs) {
    final cel = exposedCelIdAt(
      cut: shown.cut,
      layerId: shown.row.id,
      frameIndex: spans.first.start,
    );
    if (cel == null) {
      continue;
    }
    final inside = [
      if (shown.baked case final frames?)
        for (final span in spans) ?_within(span, frames),
    ];
    if (inside.isNotEmpty) {
      (baked[cel] ??= []).add(inside);
    }
    for (final span in spans) {
      for (var frame = span.start; frame < span.endExclusive; frame += 1) {
        celAt[frame] = cel;
      }
    }
  }
  return (baked: baked, celAt: celAt);
}

/// The part of [span] within [frames]; null where none is.
CutFrameCompositeSpan? _within(CutFrameCompositeSpan span, BakedFrames frames) {
  final start = span.start > frames.start ? span.start : frames.start;
  final end = span.endExclusive < frames.end ? span.endExclusive : frames.end;
  return start < end
      ? CutFrameCompositeSpan(
          start: start,
          endExclusive: end,
          signature: span.signature,
        )
      : null;
}

/// Whether [frames] holds [frame] — none does, where none are.
bool _holds(BakedFrames? frames, int frame) => switch (frames) {
  (:final start, :final end) => start <= frame && frame < end,
  null => false,
};

/// [row]'s sounds after a bake that made [firstOf]: a cel baked takes its
/// sounds to its first picture.
List<AudioClip> _clipsAfter(Layer row, Map<FrameId, FrameId> firstOf) => [
  for (final clip in row.audioClips)
    switch (firstOf[clip.frameId]) {
      final made? => clip.copyWith(frameId: made),
      null => clip,
    },
];

/// What the rows riding a baked row are baked against: the row's [runs]
/// by picture, and its cels after ([held]).
typedef _Ridden = ({List<List<CutFrameCompositeSpan>> runs, _Held held});

/// What a new cel is made under: what each cut's cels hold as the
/// composite signature reads them, and the minting of a row's new cel.
typedef _Minting = ({
  BrushFrameRevisionResolver Function(Cut cut) revisionOf,
  FrameId Function(LayerId row) mintFrameId,
});

/// [taking]'s riders after its bake, as each cut holds them, and the
/// pictures their new cels are baked from — each drawn of the row it rides
/// in its use, wearing what is baked ([_ridingOnly]), as a merge draws a
/// rider of its base (I-78) — the row baked in each use as [ridden], by
/// the use's place.
///
/// A rider's uses its link group joins share one bank, as the row's do
/// (④b, Q6): null where one shows a cel as other pictures than another
/// ([FxBakeWait.usesApart]). A free rider parts where its own picture does,
/// as the row does. A synced one rides the row's cels one for one: a cel
/// for each of the row's new ones it shows one over, under the id its
/// group's mirror of that cel is minted by ([attachedMirrorCelId]), as a
/// merge's synced rider takes.
({List<({Cut cut, Layer row})> rows, List<LayerMergePicture> pictures})?
_ridersBaked(FxBakeTaking taking, List<_Ridden> ridden, _Minting minting) {
  final uses = taking._uses;
  final sharing = <LayerId, List<_Riding>>{};
  for (final riding in taking._riders) {
    final keys = uses[riding.use].keys;
    (sharing[keys[riding.rider.id] ?? riding.rider.id] ??= []).add(riding);
  }
  final rows = <({Cut cut, Layer row})>[];
  final pictures = <LayerMergePicture>[];
  for (final MapEntry(key: mintedUnder, value: ridings) in sharing.entries) {
    final bank = _bankOf(
      [
        for (final riding in ridings)
          _riderShown(taking, riding, ridden[riding.use], minting),
      ],
      (place, run) => isSyncedAttachedLayer(ridings[place].rider)
          ? attachedMirrorCelId(
              mintedUnder,
              ridden[ridings[place].use].held.celAt[run.first.start]!,
            )
          : minting.mintFrameId(mintedUnder),
    );
    if (bank == null) {
      return null;
    }
    pictures.addAll(bank.pictures);
    for (final (place, (:use, :rider)) in ridings.indexed) {
      final synced = isSyncedAttachedLayer(rider);
      rows.add((
        cut: uses[use].cut,
        row: _holding(
          rider,
          _heldBy(bank, place),
          base: synced ? ridden[use].held : null,
          drawn: uses[use].drawn,
        ),
      ));
    }
  }
  return (rows: rows, pictures: pictures);
}

/// [riding] as the bake draws it in its use ([_Shown]), riding the row
/// baked there ([ridden]).
_Shown _riderShown(
  FxBakeTaking taking,
  _Riding riding,
  _Ridden ridden,
  _Minting minting,
) {
  final use = taking._uses[riding.use];
  final rider = riding.rider;
  final alone = _ridingOnly(use, taking._effectId, rider);
  return (
    into: use.cut,
    row: rider,
    cut: alone,
    runs: isSyncedAttachedLayer(rider)
        ? ridden.runs
        : runsByPicture(
            alone,
            [rider],
            minting.revisionOf(use.cut),
            keys: use.keys,
          ),
    baked: use.frames,
  );
}

/// [row] holding the cels [own] holds after a bake, the [drawn] frames of
/// its cut showing them: synced on a base whose cels after it are [base],
/// linked to them where it shows one ([_linksAfter]) — else its blocks
/// parted where its pictures are ([_timelineShowing]).
Layer _holding(
  Layer row,
  _Held own, {
  required _Held? base,
  required int drawn,
}) {
  final after = row.copyWith(
    kind: kindHoldingPictures(row.kind, own.cels.length),
    frames: own.cels,
    audioClips: _clipsAfter(row, own.firstOf),
  );
  return switch (base) {
    final base? => after.copyWith(
      baseFrameLinks: _linksAfter(row, base, own),
    ),
    null => after.copyWith(timeline: _timelineShowing(row, own.celAt, drawn)),
  };
}

/// A synced [rider]'s links after its base's cels and its own are baked
/// ([base], [own] — either as it was where the bake leaves it): each of
/// the base's cels kept to the cel it showed — its first picture, where
/// that was baked — and each of the base's cels shown at a frame to the
/// rider's cel there.
Map<FrameId, FrameId> _linksAfter(Layer rider, _Held base, _Held own) => {
  for (final MapEntry(key: baseCel, value: cel)
      in rider.baseFrameLinks.entries)
    if (!base.firstOf.containsKey(baseCel)) baseCel: own.firstOf[cel] ?? cel,
  for (final MapEntry(key: frame, value: cel) in own.celAt.entries)
    base.celAt[frame]!: cel,
};

/// [cut] holding [row] alone as it is drawn into its cels: shown, laying
/// nothing of its own over them — no strength, blend, clip or folder — and
/// wearing the fx [effectId] alone, or the transform alone where null. The
/// rows the fx reads (a lens blur's map) stand by it hidden, read as they
/// are (🗣️I-132-Q23 「꺼도 맵으로 읽는다」) — and so does the base of a
/// row that rides one and wears fx of its own: the conte (I-99), which
/// lays nothing on it but makes it a row of the conte's — wearing its own
/// — and whose cels a synced one's ride.
Cut _wearingOnly(Cut cut, Layer row, EffectId? effectId) {
  final fx = [
    for (final effect in row.effects)
      if (effect.id == effectId) effect,
  ];
  final read = {
    for (final effect in fx) ...effect.layers.values.nonNulls,
    ?row.attachedToLayerId,
  }..remove(row.id);
  return cut.copyWith(
    layers: [
      for (final layer in cut.layers)
        if (read.contains(layer.id))
          layer.copyWith(isVisible: false, folderId: null)
        else if (layer.id == row.id)
          drawnBare(row).copyWith(
            folderId: null,
            effects: fx,
            transformTrack: effectId == null
                ? row.transformTrack
                : TransformTrack.empty(),
          ),
    ],
  );
}

/// [use]'s cut holding [rider] as it rides, drawn bare out of any folder
/// over its row hidden wearing what is baked — the fx [effectId] alone, or
/// the transform alone where null ([_wearingOnly]) — so what the rider is
/// drawn of the row is what it wore of it. A row's eye is its own (UI-R24
/// #5), so the row hidden hides nothing of the rider.
Cut _ridingOnly(_Use use, EffectId? effectId, Layer rider) {
  final (:cut, :row, drawn: _, frames: _, keys: _) = use;
  final worn = _wearingOnly(cut, row, effectId);
  return worn.copyWith(
    layers: [
      for (final layer in worn.layers)
        if (layer.id == row.id) layer.copyWith(isVisible: false) else layer,
      drawnBare(rider).copyWith(folderId: null),
    ],
  );
}

/// Whether an fx [row] runs before [effectId]'s is on — every fx, for the
/// transform, which runs last ([FxBakeChange.order]).
bool _runsAfterAnFxOn(Layer row, EffectId? effectId) {
  for (final fx in row.effects) {
    if (fx.id == effectId) {
      return false;
    }
    if (fx.enabled) {
      return true;
    }
  }
  return false;
}

/// How a bake keeps one FX bundle of its row showing what it showed (Q1 ·
/// Q3), a lane at a time ([lane]): over the frames it [baked] — none for a
/// bundle it leaves — at rest, and on every other frame the cut draws as it
/// was, read where it [reads] that frame from — by the block, the head of
/// the block showing it ([fxReadFrame]): a block the bake parts goes on
/// showing the value its head showed (I-120: a bundle read by the block
/// steps on the drawings, and the parts are the bake's, not the person's).
final class _Keeping {
  _Keeping(
    this.frames, {
    required this.baked,
    required this.reads,
    required this.paper,
  });

  /// The frames the cut draws.
  final int frames;

  /// The frames baked into the pictures; null for a bundle it leaves.
  final BakedFrames? baked;

  /// The frame the bundle reads each frame at on the row before the bake
  /// ([was]) and after it ([now]).
  final ({int Function(int frame) was, int Function(int frame) now}) reads;

  /// Where a row stands with no key: on the cut's paper
  /// ([layerIdentityPose]).
  final TransformPose paper;

  /// Whether it bakes every frame the cut draws.
  bool get bakesEvery => switch (baked) {
    final frames? => _coversEvery(frames, this.frames),
    null => false,
  };

  /// Whether it leaves the bundle as it is.
  bool get keepsAll => baked == null && _parted.isEmpty;

  /// Each run of the frames it does not bake that read at a frame of their
  /// own after the bake — each from the [head] of the block it parted.
  late final List<({int start, int end, int head})> _parted = () {
    final runs = <({int start, int end, int head})>[];
    for (var frame = 0; frame < frames; frame += 1) {
      final head = reads.was(frame);
      if (reads.now(frame) == head || _holds(baked, frame)) {
        continue;
      }
      final last = runs.lastOrNull;
      if (last != null && last.end == frame) {
        runs.last = (start: last.start, end: frame + 1, head: head);
      } else {
        runs.add((start: frame, end: frame + 1, head: head));
      }
    }
    return runs;
  }();

  /// A value with no key after it: [rest] where it bakes the bundle — the
  /// keys hold whatever a frame it does not bake showed — else as it was.
  T unkeyedAfter<T>(T unkeyed, T rest) => baked == null ? unkeyed : rest;

  /// [track], a lane of [values], kept ([trackClearedOver] at a time):
  /// [rest] over the frames baked, and each run of frames it parted at
  /// what its head showed; [unkeyed] is its value with no key — [rest]
  /// where none is given.
  PropertyTrack<T> lane<T>(
    PropertyTrack<T> track,
    _LaneValues<T> values, {
    required T rest,
    T? unkeyed,
  }) {
    final before = unkeyed ?? rest;
    T shown(PropertyTrack<T> keys, int frame, T orElse) => keys.resolveAt(
      frameIndex: frame,
      orElse: () => orElse,
      space: values.space,
    );
    final drawn = (
      frames: frames,
      space: values.space,
      unkeyed: () => before,
      same: values.same,
    );
    PropertyTrack<T> held(PropertyTrack<T> keys, BakedFrames over, T value) =>
        trackClearedOver(keys, range: over, rest: value, lane: drawn);
    var kept = switch (baked) {
      final over? => held(track, over, rest),
      null => track,
    };
    for (final (:start, :end, :head) in _parted) {
      kept = held(kept, (start: start, end: end), shown(track, head, before));
    }
    assert(
      [
        for (var frame = 0; frame < frames; frame += 1) frame,
      ].every(
        (frame) => values.same(
          shown(kept, reads.now(frame), unkeyedAfter(before, rest)),
          _holds(baked, frame) ? rest : shown(track, reads.was(frame), before),
        ),
      ),
      'each frame shows what it showed — a bake only parts blocks',
    );
    return kept;
  }
}

/// Whether [baked] holds every one of the [drawn] frames.
bool _coversEvery(BakedFrames baked, int drawn) =>
    baked.start <= 0 && baked.end >= drawn;

/// [fx] as [keeping] keeps it: where it bakes the fx, at its defaults over
/// the frames baked ([_Keeping.lane]) — and, where it bakes every frame,
/// switched off where its defaults still change the picture (Q4), so the
/// cels it was baked into do not wear it twice. A value with no keys — its
/// switch, a row it reads — is at its default only where every frame is.
LayerEffect _effectKept(LayerEffect fx, _Keeping keeping) {
  if (keeping.keepsAll) {
    return fx;
  }
  final every = keeping.bakesEvery;
  return LayerEffect(
    id: fx.id,
    kind: fx.kind,
    plugin: fx.plugin,
    enabled: fx.enabled && (!every || fx.kind.changesNothingAtItsDefaults),
    basis: fx.basis,
    parameters: {
      for (final MapEntry(key: id, value: parameter) in fx.parameters.entries)
        id: _parameterKept(parameter, fx.specOf(id)!, keeping),
    },
    colors: {
      for (final MapEntry(key: id, value: keys) in fx.colors.entries)
        id: keeping.lane(
          keys,
          _colours,
          rest: fx.specOf(id)!.defaultValue.toInt(),
        ),
    },
    points: {
      for (final MapEntry(key: id, value: keys) in fx.points.entries)
        id: _transformKept(keys, keeping),
    },
    layers: every ? null : fx.layers,
    stand: _transformKept(fx.stand, keeping),
  );
}

/// [parameter] of [spec] as [keeping] keeps it.
EffectParameter _parameterKept(
  EffectParameter parameter,
  EffectParameterSpec spec,
  _Keeping keeping,
) => EffectParameter(
  value: keeping.unkeyedAfter(parameter.value, spec.defaultValue),
  track: keeping.lane(
    parameter.track,
    (space: spec.keySpace, same: _sameNumber),
    rest: spec.defaultValue,
    unkeyed: parameter.value,
  ),
);

/// [track] as [keeping] keeps it — at rest where a row stands with no key
/// ([_Keeping.paper]).
TransformTrack _transformKept(TransformTrack track, _Keeping keeping) {
  if (keeping.keepsAll) {
    return track;
  }
  final rest = keeping.paper;
  return TransformTrack.properties(
    anchorPoint: keeping.lane(track.anchorPoint, _places, rest: rest.center),
    position: keeping.lane(track.position, _places, rest: rest.center),
    scale: keeping.lane(
      track.scale,
      _scales,
      rest: CanvasPoint(x: rest.scaleX, y: rest.scaleY),
    ),
    rotation: keeping.lane(
      track.rotation,
      _numbers,
      rest: rest.rotationDegrees,
    ),
    opacity: keeping.lane(track.opacity, _numbers, rest: 1.0),
  );
}

/// What a lane's values are to a cut ([trackClearedOver]): how they walk
/// between keys, and whether two of them show as one.
typedef _LaneValues<T> = ({
  KeyValueSpace<T> space,
  bool Function(T a, T b) same,
});

/// A number's: a cut's half paced anew reads its curve within a millionth
/// of the value.
const _LaneValues<double> _numbers = (
  space: doubleKeySpace,
  same: _sameNumber,
);

bool _sameNumber(double a, double b) =>
    (a - b).abs() <= 1e-6 * (a.abs() > 1 ? a.abs() : 1);

/// A scale's: its two numbers, each a number's.
const _LaneValues<CanvasPoint> _scales = (
  space: pointKeySpace,
  same: _sameScale,
);

bool _sameScale(CanvasPoint a, CanvasPoint b) =>
    _sameNumber(a.x, b.x) && _sameNumber(a.y, b.y);

/// A place on a path's: a half of a path cut is measured anew in its own
/// 256 steps ([CubicWalk]), within a hundredth of a pixel of where the
/// whole put it.
const _LaneValues<CanvasPoint> _places = (
  space: pathKeySpace,
  same: _samePlace,
);

bool _samePlace(CanvasPoint a, CanvasPoint b) =>
    (a.x - b.x).abs() <= 1e-2 && (a.y - b.y).abs() <= 1e-2;

/// A colour's: its channels are rounded on its way, so only the very
/// colour is the same.
const _LaneValues<int> _colours = (space: argbKeySpace, same: _sameColour);

bool _sameColour(int a, int b) => a == b;

/// [name]'s printed number with the first tail none of [held] wears — which
/// holds it from then on; null for a cel with no number.
String? _tailed(Set<String> held, String? name) {
  final number = celNumberOf(name);
  if (number == null) {
    return null;
  }
  final tailed = tailClearOf(held, number);
  held.add(tailed);
  return tailed;
}

/// [row]'s timeline showing [celAt]'s cel at each frame it names: each
/// block split where its picture changes and showing its pictures' cels,
/// its holds and repeats derived again ([rederiveRunBehaviors]) — and,
/// where one would show a cel another picture belongs on, made of blocks
/// of its own.
Map<int, TimelineExposure> _timelineShowing(
  Layer row,
  Map<int, FrameId> celAt,
  int drawnFrames,
) {
  Layer laid(Map<int, TimelineExposure> authored) => rederiveRunBehaviors(
    row.copyWith(timeline: _splitBy(authored, celAt)),
    drawnFrameCount: drawnFrames,
  );
  final derived = laid(ghostFreeTimeline(row));
  if (_shows(derived, celAt)) {
    return derived.timeline;
  }
  final authored = laid({
    for (final MapEntry(key: start, value: entry) in row.timeline.entries)
      start: entry.ghost
          ? TimelineExposure.drawing(
              entry.frameId!,
              length: entry.length!,
              breakdownMarks: entry.breakdownMarks,
            )
          : entry,
  });
  assert(_shows(authored, celAt), 'every frame is a block of its own');
  return authored.timeline;
}

/// [authored] with each block split where [celAt] changes, each part
/// showing the cel [celAt] names at its head — or its own, where none.
SplayTreeMap<int, TimelineExposure> _splitBy(
  Map<int, TimelineExposure> authored,
  Map<int, FrameId> celAt,
) {
  var next = SplayTreeMap<int, TimelineExposure>.from(authored);
  for (final MapEntry(key: start, value: entry) in authored.entries) {
    for (var frame = start + 1; frame < start + entry.length!; frame += 1) {
      if (celAt[frame] != celAt[frame - 1]) {
        next = splitTimelineAt(next, frame);
      }
    }
  }
  return SplayTreeMap.from({
    for (final MapEntry(key: start, value: entry) in next.entries)
      start: switch (celAt[start]) {
        final cel? => entry.copyWith(frameId: cel),
        null => entry,
      },
  });
}

/// Whether [row] shows [celAt]'s cel at every frame it names.
bool _shows(Layer row, Map<int, FrameId> celAt) => celAt.entries.every(
  (at) => exposedFrameIdAt(row.timeline, at.key) == at.value,
);
