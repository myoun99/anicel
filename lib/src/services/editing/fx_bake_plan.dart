import 'dart:collection' show SplayTreeMap;

import '../../models/attached_layer_mount.dart' show detachedLayer;
import '../../models/attached_layer_resolve.dart'
    show attachedMirrorCelId, fxCarrierOf, isSyncedAttachedLayer;
import '../../models/attached_mode.dart';
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
import '../../models/project.dart';
import '../../models/property_track.dart'
    show KeyValueSpace, PropertyTrack;
import '../../models/property_track_cut.dart' show trackClearedOver;
import '../../models/timeline_coverage.dart' show exposedFrameIdAt;
import '../../models/timeline_exposure.dart';
import '../../models/timeline_repeat.dart'
    show ghostFreeTimeline, rederiveRunBehaviors;
import '../../models/timeline_splice.dart' show splitTimelineAt;
import '../../models/track_transitions.dart' show cutDrawnFrameCount;
import '../../models/transform_track.dart';
import '../commands/link_mirror.dart'
    show existenceMirrorTargets, headMirrorTargets;
import '../cut_frame_composite_plan.dart' show exposedCelIdAt;
import '../playback/cut_frame_composite_signature.dart'
    show BrushFrameRevisionResolver, CutFrameCompositeSignature;
import '../playback/cut_frame_composite_spans.dart';
import '../project_lookup.dart' show requireCut;
import 'cut_duplicate_helpers.dart' show MirrorCopies, mirrorCopiesFor;
import 'layer_merge_plan.dart'
    show
        CelReads,
        LayerMergePicture,
        drawnBare,
        kindHoldingPictures,
        rowsKeyedAcrossCuts,
        runsByPicture,
        tailClearOf;

/// The frames a press of RASTERIZE bakes, from [start] to [end]
/// (exclusive).
typedef BakedFrames = ({int start, int end});

/// What a press of RASTERIZE bakes of a row: the fx by id, and the
/// [transform] where it does ([FxBakeTaking._baking]).
typedef _Baking = ({Set<EffectId> fx, bool transform});

/// What a use a press leaves showing what it shows is drawn wearing.
const _Baking _bakingNothing = (fx: {}, transform: false);

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
/// every cut it is used in, the fx pressed — the transform, where
/// [_effectId] is null — with what it bakes of the chain ([_baking]), and
/// the rows riding the row that wear it.
final class FxBakeTaking {
  const FxBakeTaking._(
    this._effectId,
    this._uses,
    this._riders,
    this._selves,
  );

  /// The fx pressed; null for the transform's header.
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

  /// The rows the riders exist as one with ([existenceMirrorTargets]) that
  /// ride no use of the row — which the press does not reach — each a use
  /// it leaves showing what it shows. One a rider's link group holds has
  /// its cels, and keeps those it shows, the rider's new ones beside them in
  /// the one bank ([_ridersBaked]; 🗣️I-120-Q19, 유저
  /// 2026-11-05 「가능하게 하도록. 행 구조를 바꾸든 뭐하든」 — its link kept, Q20
  /// 「링크유지는 그 최소한」).
  final List<_Use> _selves;

  /// The use the press was pressed in.
  _Use get _pressed => _uses.first;

  /// What it bakes: the fx pressed, and every fx on that runs before it —
  /// the transform pressed, which runs after every fx, each fx on and
  /// itself — so nothing it leaves runs before what it bakes, at its line
  /// (🗣️I-120-Q21, 유저 2026-11-05 「순서는 안바뀌게. 최대한 자기선에서
  /// 래스터라이즈 … 그게 싫으면 유저가 래스터라이즈 순서를 잘 해서 결과 같이
  /// 만들면됨」). ↩️It baked the fx alone, and warned first that an fx on
  /// above it would run after it (Q2 「순서가 바뀌면 먼저 경고」).
  _Baking get _baking {
    final effects = _pressed.row.effects;
    final line = _effectId == null
        ? effects.length
        : effects.indexWhere((fx) => fx.id == _effectId);
    return (
      fx: {
        for (final (index, fx) in effects.indexed)
          if (index == line || (index < line && fx.enabled)) fx.id,
      },
      transform: _effectId == null,
    );
  }

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
    ], _riders, _selves);
  }
}

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
/// card's order, not a law of the verb. ↩️So did a row riding it linked to
/// a row riding one that is no use of it, until Q19 ([FxBakeTaking._selves]).
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
  if (_standsDown(uses, riders)) {
    return null;
  }
  return FxBakeTaking._(
    effectId,
    uses,
    riders,
    _selvesOf(project, uses, riders),
  );
}

/// [rowId]'s use in [cutId] ([_Use]): every frame the cut draws [baked], or
/// none.
_Use _useOf(
  Project project,
  CutId cutId,
  LayerId rowId, {
  bool baked = true,
}) {
  final cut = requireCut(project, cutId);
  final drawn = cutDrawnFrameCount(project, cutId) ?? cut.duration;
  return (
    cut: cut,
    row: cut.layers.byId(rowId)!,
    drawn: drawn,
    frames: baked ? (start: 0, end: drawn) : null,
    keys: rowsKeyedAcrossCuts(project.linkRegistry, cut),
  );
}

/// The rows [riders] exist as one with that are none of them
/// ([FxBakeTaking._selves]) — each a use baking nothing.
List<_Use> _selvesOf(
  Project project,
  List<_Use> uses,
  List<_Riding> riders,
) {
  final taken = {
    for (final (:use, :rider) in riders)
      (cutId: uses[use].cut.id, layerId: rider.id),
  };
  final reached = {
    for (final (:use, :rider) in riders)
      for (final self in existenceMirrorTargets(
        project,
        cutId: uses[use].cut.id,
        layerId: rider.id,
      ))
        if (!taken.contains(self)) self,
  };
  return [
    for (final (:cutId, :layerId) in reached)
      _useOf(project, cutId, layerId, baked: false),
  ];
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
bool _standsDown(List<_Use> uses, List<_Riding> riders) =>
    uses.any((use) => use.row.mediaReference != null) ||
    riders.any((riding) => riding.rider.mediaReference != null);

/// A picture a bake copies as it is besides the ones it draws: [cut]'s
/// cels of the row [row], each copied to the cel [minted] names it to — a
/// row synced on a conte whose panel the bake parts keeps the picture it
/// showed over each part ([mirrorCopiesFor], Q17).
typedef FxBakeCopy = ({Cut cut, LayerId row, Map<FrameId, FrameId> minted});

/// What a press of RASTERIZE makes of a row: its pictures with the fx baked
/// in, and the row after — in every cut it is used in.
final class FxBakePlan {
  const FxBakePlan._({
    required this.cut,
    required this.row,
    required this.riders,
    required this.pictures,
    required this.copies,
    required this.layers,
    required this.others,
    required this.freed,
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

  /// Every new cel's picture copied as it is, still to be copied once it
  /// lands ([FxBakeCopy]).
  final List<FxBakeCopy> copies;

  /// [cut]'s rows after: [row] and [riders] where they stood, and any other
  /// use of the row it holds.
  final List<Layer> layers;

  /// Every other cut the row is used in (Q6), as it was, with its rows
  /// after.
  final List<({Cut cut, List<Layer> layers})> others;

  /// The names of the rows it makes free, on timings of their own
  /// ([_freedOf], Q18) — a change of the rows' make the press says after.
  final List<String> freed;
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
/// - Q4 「구운 뒤 그 fx 의 스위치를 끈다」 — every value and key of the fx
///   back at its default, its line kept; one that changes the picture at
///   its defaults (the cel number, a plugin's) switched off besides — in
///   every use, a band's bake too (Q14, 11-05 「범위 안만 굽고 스위치를
///   끈다」).
/// - Q6 「같은 셀을 보는 다른 컷도 같이 굽는다」 — every use of the row by its
///   own values and timing, into the one bank its cels are: a picture two
///   uses show is one cel, and a cel one use shows as other pictures than
///   another does is parted into a cel for each, each use's timing showing
///   its own (Q20, 11-05 「링크유지한채 … 래스터라이즈. 거기서 같은그림
///   (같은번호)은 같은결과가 되면 좋음」). ↩️It baked nothing and warned
///   (Q6 「한 장에 못 담으면 막고 경고」) until Q20. A row a rider's link
///   group holds riding no use of the row keeps the cels it shows
///   ([FxBakeTaking._selves], Q19).
/// - Q7 「트랙의 콘티가 있는 컷 전부에서 같이 굽는다」 — a row of a track's
///   conte in every cut of the track that has it, each by its own values
///   and timing into a bank of its own, as a merge takes them (I-78-Q20).
///   A panel the conte shows as more than one picture is parted as any
///   row's block is (Q17 「칸을 나눈다(보통 레이어와 같은 법)」) — the rows
///   synced on it keeping a copy of their picture over each part
///   ([_followersAfter]); a row synced on the conte showing more than one
///   picture over one panel is made free on a timing of its own (Q18
///   「그 행을 자유(자기 타이밍)로 바꾼다 — 병합과 같은 법」, [_freedOf]).
///   ↩️Both baked nothing and said why until the 11-05 answers.
/// - Q15 (11-05) 「같은 이름 키 전부에 새 손잡이」 — a named key a band's
///   cut paces anew keeps its name, and every key of the name takes what
///   it moved ([_namesCarried]).
/// - Q21 (11-05) 「경고 창을 없앤다 — 묻지 않고 굽는다 … 순서는
///   안바뀌게」 — what it bakes is the fx up to its line
///   ([FxBakeTaking._baking]), and a picture past the wall is cut off as a
///   merge cuts it, unasked.
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
/// their pictures, linked to its new cels ([_followersAfter]). A synced row
/// of the conte keeps its pictures one for each of the conte's cels, its
/// links where its timing is — or, one cel of the conte's showing more than
/// one of them, its timing its own ([_freedOf]).
///
/// [readsOf] says how each cut's cels are read; [mintFrameId] names each
/// new cel.
FxBakePlan planFxBake(
  FxBakeTaking taking, {
  required CelReads Function(Cut cut) readsOf,
  required FrameId Function(LayerId row) mintFrameId,
}) {
  final FxBakeTaking(_baking: baking, _uses: uses, _pressed: pressed) = taking;
  final shown = [
    for (final use in uses) _shownOf(use, baking, readsOf(use.cut).revisionOf),
  ];
  final banked = _banksOf(uses, shown, mintFrameId);
  final held = banked.held;
  final freed = _freedOf(uses, held);
  final rows = _namesCarried(uses, [
    for (final (index, use) in uses.indexed)
      _rowBaked(use, baking, held[index], free: freed.contains(index)),
  ]);
  final riders = _ridersBaked(taking, [
    for (final (index, each) in shown.indexed)
      (runs: each.runs, held: held[index]),
  ], (revisionOf: (cut) => readsOf(cut).revisionOf, mintFrameId: mintFrameId));
  final followers = [
    for (final (index, use) in uses.indexed) _followersAfter(use, held[index]),
  ];
  final cuts = _cutsAfter([
    for (final (index, use) in uses.indexed) ...[
      (cut: use.cut, row: rows[index]),
      for (final follower in followers[index].rows)
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
    pictures: [...banked.pictures, ...riders.pictures],
    copies: [for (final each in followers) ...each.copies],
    layers: cuts.first.layers,
    others: cuts.sublist(1),
    freed: [
      ...{
        for (final (index, use) in uses.indexed)
          if (freed.contains(index)) use.row.name,
      },
    ],
  );
}

/// [use] as the bake draws it ([_Shown]): wearing what is [baking] alone
/// ([_wearingOnly]), its cels read by [revisionOf].
_Shown _shownOf(
  _Use use,
  _Baking baking,
  BrushFrameRevisionResolver revisionOf,
) {
  final cut = _wearingOnly(use.cut, use.row, baking);
  return (
    into: use.cut,
    row: use.row,
    cut: cut,
    runs: runsByPicture(
      cut,
      [cut.layers.byId(use.row.id)!],
      revisionOf,
      keys: use.keys,
    ),
    baked: use.frames,
  );
}

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
/// one, or made [free] ([_freed]) — and each of its FX bundles kept
/// showing what it showed ([_Keeping]) — those it is [baking] at rest over
/// the frames baked.
Layer _rowBaked(
  _Use use,
  _Baking baking,
  _Held held, {
  required bool free,
}) {
  final (:cut, :row, :drawn, :frames, keys: _) = use;
  final parted = free
      ? _freed(use, held)
      : _holding(row, held, base: _baseHeld(use, held), drawn: drawn);
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
        _switchedAfter(
          _effectKept(
            fx,
            keeping(fx.basis, baked: baking.fx.contains(fx.id)),
          ),
          baked: baking.fx.contains(fx.id),
        ),
    ],
    transformTrack: _transformKept(
      row.transformTrack,
      keeping(row.transformBasis, baked: baking.transform),
    ),
  );
}

/// [fx] switched as a bake leaves it: one [baked] whose defaults change the
/// picture — the cel number's, a plugin's — off, so the cels it was baked
/// into do not wear it twice; in every use, the switch being every frame's
/// of every use (🗣️I-120-Q4 「구운 뒤 그 fx 의 스위치를 끈다」 · Q14 「범위
/// 안만 굽고 스위치를 끈다」).
LayerEffect _switchedAfter(LayerEffect fx, {required bool baked}) =>
    baked && !fx.kind.changesNothingAtItsDefaults
    ? fx.copyWith(enabled: false)
    : fx;

/// [rows], each of [uses] after its bake, with what it moved of a named key
/// carried to every key of the name — on its lane, and on that lane in
/// each use the row's link group holds, one naming space (🗣️I-120-Q15,
/// 유저 2026-11-05 「같은 이름 키 전부에 새 손잡이」): the link a write of
/// a row's fx or transform hands on ([namedEffectKeyChanges] ·
/// [transformNamedKeyChanges]).
List<Layer> _namesCarried(List<_Use> uses, List<Layer> rows) {
  final after = [...rows];
  for (final places in _linkGroupsOf(uses)) {
    final moved = [
      for (final place in places)
        (
          namedEffectKeyChanges(uses[place].row.effects, rows[place].effects),
          transformNamedKeyChanges(
            uses[place].row.transformTrack,
            rows[place].transformTrack,
          ),
        ),
    ];
    for (final place in places) {
      after[place] = moved.fold(
        after[place],
        (row, changes) => row.copyWith(
          effects: effectsWithNamedValues(row.effects, changes.$1),
          transformTrack: transformTrackWithNamedKeys(
            row.transformTrack,
            changes.$2,
          ),
        ),
      );
    }
  }
  return after;
}

/// [row] as every cut a link group of [keys] holds it in names it — the
/// key its uses share one bank of cels and one naming space by
/// ([rowsKeyedAcrossCuts]).
LayerId _linkKey(Map<LayerId, LayerId> keys, LayerId row) => keys[row] ?? row;

/// The places of [uses] each link group holds ([_linkKey]), a group for
/// each — one bank of cels, and one naming space.
Iterable<List<int>> _linkGroupsOf(List<_Use> uses) {
  final groups = <LayerId, List<int>>{};
  for (final (index, use) in uses.indexed) {
    (groups[_linkKey(use.keys, use.row.id)] ??= []).add(index);
  }
  return groups.values;
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

/// The cels of the base [use]'s row is synced on, where it rides one, as
/// its cut shows them where [held] shows a cel — the base not baked.
_Held? _baseHeld(_Use use, _Held held) =>
    switch (_syncedBaseOf(use.cut, use.row)) {
      final base? => _heldAsShown(use.cut, base, held.celAt.keys),
      null => null,
    };

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
/// own.
({List<_Held> held, List<LayerMergePicture> pictures}) _banksOf(
  List<_Use> uses,
  List<_Shown> shown,
  FrameId Function(LayerId row) mintFrameId,
) {
  final held = <int, _Held>{};
  final pictures = <LayerMergePicture>[];
  for (final places in _linkGroupsOf(uses)) {
    final bank = _bankOf(
      [for (final index in places) shown[index]],
      (_, _) => mintFrameId(uses[places.first].row.id),
    );
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

/// [use]'s rows synced on its row ([_followersOf]) after its bake [held],
/// and the pictures they copy: each showing the cels it showed over the
/// row's cels after — and over each part after the first of a cel the
/// bake parted, a copy of the one it showed there (🗣️I-120-Q17, 유저
/// 2026-11-05 「칸을 나눈다(보통 레이어와 같은 법)」: 싱크 행의 셀도 같은
/// 그림으로 같이 나뉜다), as a row synced on a base whose cels are re-cut
/// keeps them ([mirrorCopiesFor]) — minted under its link group's row.
({List<Layer> rows, List<FxBakeCopy> copies}) _followersAfter(
  _Use use,
  _Held held,
) {
  final followers = _followersOf(use.cut, use.row);
  if (followers.isEmpty) {
    return (rows: const [], copies: const []);
  }
  final born = [
    for (final part in _laterParts(use, held))
      ...mirrorCopiesFor(
        attachedRows: followers,
        baseMinted: part,
        mintedUnder: (follower) => _linkKey(use.keys, follower.id),
      ),
  ];
  return (
    rows: [
      for (final follower in followers)
        follower.copyWith(
          frames: _withCopies(follower.frames, [
            for (final each in born)
              if (each.layerId == follower.id) each,
          ]),
          baseFrameLinks: {
            ..._linksAfter(
              follower,
              held,
              _heldAsShown(use.cut, follower, held.celAt.keys),
            ),
            for (final each in born)
              if (each.layerId == follower.id) ...each.baseLinks,
          },
        ),
    ],
    copies: [
      for (final each in born)
        (cut: use.cut, row: each.layerId, minted: each.minted),
    ],
  );
}

/// Each part of a cel of [use]'s row its bake parted ([held]) but the
/// first — every part of one it keeps — with the cel it is part of: one to
/// a map, a cel parted into three being two ([mirrorCopiesFor]'s source →
/// copy).
List<Map<FrameId, FrameId>> _laterParts(_Use use, _Held held) {
  final kept = {for (final cel in use.row.frames) cel.id};
  final firsts = {...held.firstOf.values};
  final of = <FrameId, FrameId>{};
  for (final frame in held.celAt.keys.toList()..sort()) {
    final cel = held.celAt[frame]!;
    if (!kept.contains(cel) && !firsts.contains(cel)) {
      of[cel] ??= exposedCelIdAt(
        cut: use.cut,
        layerId: use.row.id,
        frameIndex: frame,
      )!;
    }
  }
  return [
    for (final MapEntry(key: part, value: cel) in of.entries) {cel: part},
  ];
}

/// [cels] with each copy [born] of one of them after it, in the order they
/// were made, each named with the first tail none of them wears — as a
/// bake names a part of a cel (I-78-Q10 「갈라진 곳은 꼬리 번호」).
List<Frame> _withCopies(List<Frame> cels, List<MirrorCopies> born) {
  final copiesOf = <FrameId, List<Frame>>{};
  for (final each in born) {
    for (final MapEntry(key: source, value: copy) in each.minted.entries) {
      (copiesOf[source] ??= []).add(
        each.born.singleWhere((cel) => cel.id == copy),
      );
    }
  }
  final held = {for (final cel in cels) ?celNumberOf(cel.name)};
  return [
    for (final cel in cels) ...[
      cel,
      for (final copy in copiesOf[cel.id] ?? const <Frame>[])
        copy.copyWith(name: _tailed(held, cel.name)),
    ],
  ];
}

/// The places of [uses] whose row its bake makes free, on a timing of its
/// own: a row synced on a base one of whose cels would show more than one
/// of its after ([held]) — a cel of its to each of the base's — and, the
/// mode being its link group's, every place the group holds (🗣️I-120-Q18,
/// 유저 2026-11-05 「그 행을 자유(자기 타이밍)로 바꾼다 — 병합과 같은 법」:
/// 다른 컷의 같은 행은 그 컷에서 칸 안에 그림이 둘이 될 때만 바뀐다).
Set<int> _freedOf(List<_Use> uses, List<_Held> held) => {
  for (final places in _linkGroupsOf(uses))
    if (places.any((place) => _outgrowsItsBase(uses[place], held[place])))
      ...places,
};

/// Whether [use]'s row, synced on a base, shows more than one of its cels
/// after its bake ([held]) over one of the base's.
bool _outgrowsItsBase(_Use use, _Held held) =>
    switch (_syncedBaseOf(use.cut, use.row)) {
      final base? => !_oneEach(
        _heldAsShown(use.cut, base, held.celAt.keys).celAt,
        held.celAt,
      ),
      null => false,
    };

/// [use]'s row, synced on its base, holding its cels after its bake
/// ([held]) on a timing of its own: the base's as it showed it, laid as
/// its own ([detachedLayer]), parted where its pictures are — riding the
/// base still, free, as a merge leaves a row of the conte whose timing is
/// its own (I-78-Q20).
Layer _freed(_Use use, _Held held) {
  final (:cut, :row, :drawn, frames: _, keys: _) = use;
  final standing = detachedLayer(
    attached: row,
    base: _syncedBaseOf(cut, row),
    drawnFrameCount: drawn,
  );
  return _holding(standing, held, base: null, drawn: drawn).copyWith(
    attachedToLayerId: row.attachedToLayerId,
    attachedMode: AttachedMode.free,
  );
}

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
/// 밖은 보이던 그대로」).
_Bank _bankOf(
  List<_Shown> uses,
  FrameId Function(int use, List<CutFrameCompositeSpan> run) idOf,
) {
  final ran = [for (final use in uses) _bakedRuns(use)];
  final pictured = _picturesOfCels([for (final each in ran) each.baked]);
  final outside = {
    for (final (index, use) in uses.indexed)
      for (final MapEntry(key: frame, value: cel)
          in ran[index].celAt.entries)
        if (!_holds(use.baked, frame)) cel,
  };
  final celAt = [for (final each in ran) each.celAt];
  final bank = <Frame>[];
  final pictures = <LayerMergePicture>[];
  final firstOf = <FrameId, FrameId>{};
  final cels = _bankCels(uses);
  final held = {for (final cel in cels) ?celNumberOf(cel.name)};
  for (final cel in cels) {
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

/// The one bank [uses] hold: every cel any of them holds, the first's in
/// its order and then each one only another holds — a mirror the settle
/// minted in one cut of a link group alone is the group's too, or the use
/// that shows it would be left showing a cel its row lacks.
List<Frame> _bankCels(List<_Shown> uses) {
  final cels = <FrameId, Frame>{};
  for (final use in uses) {
    for (final cel in use.row.frames) {
      cels.putIfAbsent(cel.id, () => cel);
    }
  }
  return [...cels.values];
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
/// that shows it: the same picture in two uses one, as a merge's bank
/// holds it (the I-78-Q12 reading 「같은 조합이면 같은 이름 … 다른 조합이면
/// 꼬리 번호」) — a use showing a cel as a picture no other does a picture
/// of its own (🗣️I-120-Q20 「같은그림(같은번호)은 같은결과가 되면 좋음」).
Map<FrameId, List<List<_Seen>>> _picturesOfCels(
  List<Map<FrameId, List<List<CutFrameCompositeSpan>>>> baked,
) {
  final byCel = <FrameId, Map<CutFrameCompositeSignature, List<_Seen>>>{};
  for (final (use, cels) in baked.indexed) {
    for (final MapEntry(key: cel, value: runs) in cels.entries) {
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
/// (④b, Q6) — and so do the rows of the group riding no use of the row
/// ([FxBakeTaking._selves]), which keep the cels they show (Q19). A free
/// rider parts where its own picture does, as the row does. A synced one
/// rides the row's cels one for one: a cel for each of the row's new ones
/// it shows one over, under the id its group's mirror of that cel is
/// minted by ([attachedMirrorCelId]), as a merge's synced rider takes.
({List<({Cut cut, Layer row})> rows, List<LayerMergePicture> pictures})
_ridersBaked(FxBakeTaking taking, List<_Ridden> ridden, _Minting minting) {
  final uses = taking._uses;
  final sharing = <LayerId, List<_Riding>>{};
  for (final riding in taking._riders) {
    final keys = uses[riding.use].keys;
    (sharing[_linkKey(keys, riding.rider.id)] ??= []).add(riding);
  }
  final rows = <({Cut cut, Layer row})>[];
  final pictures = <LayerMergePicture>[];
  for (final MapEntry(key: mintedUnder, value: ridings) in sharing.entries) {
    final selves = [
      for (final self in taking._selves)
        if (_linkKey(self.keys, self.row.id) == mintedUnder) self,
    ];
    final bank = _bankOf(
      [
        for (final riding in ridings)
          _riderShown(taking, riding, ridden[riding.use], minting),
        for (final self in selves)
          _shownOf(self, _bakingNothing, minting.revisionOf(self.cut)),
      ],
      // A self bakes nothing, so a rider shows every new cel first.
      (place, run) => isSyncedAttachedLayer(ridings[place].rider)
          ? attachedMirrorCelId(
              mintedUnder,
              ridden[ridings[place].use].held.celAt[run.first.start]!,
            )
          : minting.mintFrameId(mintedUnder),
    );
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
    for (final (place, self) in selves.indexed) {
      final held = _heldBy(bank, ridings.length + place);
      rows.add((
        cut: self.cut,
        row: _holding(
          self.row,
          held,
          base: _baseHeld(self, held),
          drawn: self.drawn,
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
  final alone = _ridingOnly(use, taking._baking, rider);
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
/// wearing what it is [baking] alone: its fx, and the transform where it
/// bakes it. The rows the fx reads (a lens blur's map) stand by it hidden,
/// read as they are (🗣️I-132-Q23 「꺼도 맵으로 읽는다」) — and so does the
/// base of a row that rides one and wears fx of its own: the conte (I-99),
/// which lays nothing on it but makes it a row of the conte's — wearing
/// its own — and whose cels a synced one's ride.
Cut _wearingOnly(Cut cut, Layer row, _Baking baking) {
  final fx = [
    for (final effect in row.effects)
      if (baking.fx.contains(effect.id)) effect,
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
            transformTrack: baking.transform
                ? row.transformTrack
                : TransformTrack.empty(),
          ),
    ],
  );
}

/// [use]'s cut holding [rider] as it rides, drawn bare out of any folder
/// over its row hidden wearing what is [baking] alone ([_wearingOnly]) —
/// so what the rider is drawn of the row is what it wore of it. A row's
/// eye is its own (UI-R24 #5), so the row hidden hides nothing of the
/// rider.
Cut _ridingOnly(_Use use, _Baking baking, Layer rider) {
  final (:cut, :row, drawn: _, frames: _, keys: _) = use;
  final worn = _wearingOnly(cut, row, baking);
  return worn.copyWith(
    layers: [
      for (final layer in worn.layers)
        if (layer.id == row.id) layer.copyWith(isVisible: false) else layer,
      drawnBare(rider).copyWith(folderId: null),
    ],
  );
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
/// the frames baked ([_Keeping.lane]). A value with no keys — a row it
/// reads — is at its default only where every frame is.
LayerEffect _effectKept(LayerEffect fx, _Keeping keeping) {
  if (keeping.keepsAll) {
    return fx;
  }
  final every = keeping.bakesEvery;
  return LayerEffect(
    id: fx.id,
    kind: fx.kind,
    plugin: fx.plugin,
    enabled: fx.enabled,
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
