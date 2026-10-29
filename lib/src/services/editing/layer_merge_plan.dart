import 'dart:ui' show Offset, Rect, Size;

import '../../models/attached_layer_resolve.dart'
    show
        attachedGroupEndIndex,
        attachedGroupSlice,
        attachedGroupStartIndex,
        attachedLayersOf,
        attachedMirrorCelId,
        attachedRowAsShown,
        isSyncedAttachedLayer;
import '../../models/attached_mode.dart';
import '../../models/cut.dart';
import '../../models/cut_id.dart';
import '../../models/dirty_region.dart';
import '../../models/frame.dart';
import '../../models/frame_id.dart';
import '../../models/layer.dart';
import '../../models/layer_blend_mode.dart';
import '../../models/layer_folder.dart';
import '../../models/layer_id.dart';
import '../../models/layer_effect.dart' show effectsWithRowsRenamed;
import '../../models/layer_kind.dart';
import '../../models/layer_link_registry.dart';
import '../../models/layer_section_defaults.dart' show firstUnusedName;
import '../../models/pasteboard_bounds.dart';
import '../../models/project.dart';
import '../../models/timeline_coverage.dart';
import '../../models/timeline_exposure.dart';
import '../../models/timeline_repeat.dart' show ghostFreeTimeline;
import '../../models/timeline_run_behavior.dart';
import '../../models/track_conte_laying.dart' show conteBaseOf;
import '../../models/transform_track.dart';
import '../commands/link_mirror.dart' show existenceMirrorTargets;
import '../cut_frame_composite_plan.dart'
    show clipBaseOf, clipsToLayerBelow, exposedCelIdAt, layerPlacementAt;
import '../layer_pose_matrix.dart'
    show LayerPlacement, picturePlacement, placedRectBounds;
import '../playback/cut_frame_composite_signature.dart';
import '../playback/cut_frame_composite_spans.dart';
import '../project_lookup.dart' show requireCut, requireCutPosition;

/// Why a merge's row may show otherwise than the rows it was made of did —
/// what the press warns of (I-78-Q1 「포토샵 · 클튜처럼 (+경고)」).
enum LayerMergeChange {
  /// A row it took met what is under it in a blend of its own: the result
  /// is a NORMAL row, so against the rows under it the look can part.
  blend,

  /// A row it took clipped to a row it did not, or a row it did not take
  /// clipped to one it did: the clip is laid against another row now.
  clip,

  /// A row it took came from outside the folder the result stands in, and
  /// that folder lays a look of its own over what it holds.
  folder,

  /// An attach row riding above a row it took is led over the result, and
  /// covers a picture that stood above it (I-78-Q13 「위쪽 어태치 그대로 결과
  /// 행 위에 붙는다 (+경고)」).
  riderOver,

  /// An attach row riding below a row it took is led under the result, and
  /// goes under a picture that stood below it — Q13's other side, warned
  /// of as Q1 warns of every change in how the rows look.
  riderUnder,

  /// A row it drew shows a picture past the wall, and the merge draws the
  /// screen inside it (I-78-Q15 「참조도 그대로 병합한다」 — 「벽 밖 부분이
  /// 잘리면 … 경고 창에 한 줄로 알린다」).
  ///
  /// 🗣️I-78-Q19 (유저 2026-10-28): 「보통 그림도 같은 경고」 — a drawing
  /// its keys or its folders move past the wall is cut there just the same,
  /// and the one line says so of both. ↩️It was a reference row's alone.
  wall,
}

/// The box round the ink of what [row]'s cel [cel] shows — its drawing and
/// its texts — in the row's own artwork; null where it shows none.
typedef CelInkResolver =
    ({int left, int top, int rightExclusive, int bottomExclusive})? Function(
      LayerId row,
      FrameId cel,
    );

/// What a cut's cels are read by in a merge: what each holds as the
/// composite signature reads it, and where its picture's ink lies.
typedef CelReads = ({
  BrushFrameRevisionResolver revisionOf,
  CelInkResolver inkOf,
});

/// One picture a merge bakes: the cel of the row it lands on, in the cut
/// [into] — the row keeping the cels of the rows the result is one layer
/// with — and the cut and frame it is drawn from.
typedef LayerMergePicture = ({
  Cut into,
  LayerId rowId,
  FrameId frameId,
  Cut from,
  int frameIndex,
});

/// What ONE press of the shared pill's MERGE makes of the rows it takes, in
/// one cut (I-78, rounds ① · ②).
///
/// 🗣️I-78 (유저 2026-10-06): 「여러 레이어 선택시 그림들을 한 레이어로 합침」,
/// and the answers it was opened with (10-07, 10-28):
/// - Q2 「맨 위 레이어의 이름 · 자리」 — [result] wears the topmost taken
///   row's name and stands where it stood.
/// - Q3 「그림이 바뀌는 지점마다 한 장」 and Q6 「전부 보이던 그대로 굽는다」 —
///   a picture per run of frames whose PICTURE is one: the composite
///   signature's runs ([computeCutFrameCompositeSpans]), which find the
///   runs in what the frame shows and never in the keys. A transform, an
///   effect, an opacity that moves inside a hold parts the run there; the
///   same picture shown again is the same cel.
/// - Q5 「안을 전부 한 장으로, 폴더는 그 레이어가 된다」 — a folder taken is
///   everything under it, and the folder becomes the row.
/// - Q7 「숨긴 행도 보이게 해서 합친다」 — every row taken is baked shown.
/// - Q8 「결과 행의 어태치로 남는다」 — an attach row riding a row it takes,
///   and not taken itself, rides [result] after ([layers]): its cels are
///   baked anew as it showed, wearing what it wore of its base — the base's
///   pose, keys and fx short of the cel number (「어태치 레이어는 주인과 같이
///   굽는다」, 07-21) — and of the folders it leaves. A SYNCED row's
///   pictures part wherever the result's do (the answer's 「결과 행의 장이
///   나뉜 곳마다 어태치 그림도 같이 나뉨」), a FREE row's wherever its own
///   picture changes. What is its own stays on its row: its eye, its
///   strength, its blend, its clip. 🗣️I-78-Q13 (유저 10-28 「위쪽 어태치
///   그대로 결과 행 위에 붙는다 (+경고)」): the base's group is led around
///   the result — its rows riding below under it, those riding above over
///   it — wherever the base stood among the rows taken.
/// - 🗣️I-78-Q14 (유저 10-28 「보이던 그대로 같이 굽는다」): an attach row
///   taken without its base is baked wearing it, and its row goes; taken
///   topmost, the result stands just outside the base's group, on the side
///   the row rode (the option's 「위쪽 어태치였으면 묶음 위, 아래쪽이었으면
///   묶음 아래」).
/// - 🗣️I-78-Q15 (유저 10-28 「참조도 그대로 병합한다」): a reference row is
///   baked as it shows, as every row is.
/// - Q10 「맨 위 레이어의 셀 이름 + 갈라진 곳은 꼬리 번호」 and Q11 「그 구간에
///   보이는 것 중 맨 위 행의 셀 이름」 — each picture takes the name of the
///   cel the topmost taken row shows there; a name another picture holds
///   already takes the tail an attach row takes (`firstUnusedName`). A
///   rider's pictures are named so by the cels it showed.
///
/// ⚠️My calls (I-78 card, 10-28): the result stands in the folder its
/// topmost row stood in, whose look — and its parents' — lands on the result
/// after the merge as it did before, so it is not baked; the folders under
/// it are. The result's blocks are new: the marks and memos of the rows'
/// blocks do not come along, and a cel the timeline does not show is no
/// part of what the rows showed.
class LayerMergePlan {
  const LayerMergePlan._({
    required this.cut,
    required this.result,
    required this.pictures,
    required this.changes,
    required this.layers,
    required this.others,
    required this.links,
  });

  /// The cut it was planned of, as it was.
  final Cut cut;

  /// The row the merge leaves — its cels named, their pictures still to be
  /// baked ([pictures]).
  final Layer result;

  /// Every picture the merge's new cels are baked from: [result]'s — every
  /// cut's results' cels are its, one bank — then each rider's.
  final List<LayerMergePicture> pictures;

  final Set<LayerMergeChange> changes;

  /// The cut's rows after the merge ([_layersAfter]): every row it took but
  /// the one [result] is gone, and the attach rows riding [result] stand
  /// led around it with their new cels — their pictures, too, still to be
  /// baked.
  final List<Layer> layers;

  /// Every other cut the merge reaches (Q9), as it was, with its rows
  /// after — its result one with [result] across the cuts.
  final List<({Cut cut, List<Layer> layers})> others;

  /// The project's link table after the merge ([_linksAfter]).
  final LayerLinkRegistry links;
}

/// The rows ONE press of MERGE takes of a cut — what lights its button and
/// what the press plans from ([planLayerMerge]): one taking for both, so
/// the button cannot light where the press would merge nothing.
final class LayerMergeTaking {
  LayerMergeTaking._(
    this.cut,
    this._index,
    this._taken,
    this._anchor,
    this._conte,
  ) : _pictureRows = [
        for (final row in cut.layers)
          if (_taken.contains(row.id) && _isPicture(row)) row,
      ],
      _riders = [
        for (final row in cut.layers)
          if (!_taken.contains(row.id) &&
              _taken.contains(row.attachedToLayerId))
            row,
      ];

  /// The cut it was taken of.
  final Cut cut;
  final LayerFolderIndex _index;

  /// Every row it takes — a folder with everything it holds.
  final Set<LayerId> _taken;

  /// The topmost row it takes: the row the result is (Q2).
  final Layer _anchor;

  /// The rows it takes that hold pictures, bottom → top.
  final List<Layer> _pictureRows;

  /// The attach rows riding a row it takes that it does not take — the
  /// rows that ride the result (Q8).
  final List<Layer> _riders;

  /// The cut's conte, when the rows it takes are the conte's rows — rows
  /// of the track's structure, merged in every cut of it (I-78-Q20).
  final Layer? _conte;

  /// The row whose place in the track's structure the result keeps, for
  /// the conte's rows: the topmost picture row taken — a 공정 folder taken
  /// files no picture, and the structure forgets a folder filing nothing.
  /// The topmost row taken, for any other rows.
  Layer get _keeper => _conte == null ? _anchor : _pictureRows.last;
}

/// The rows ONE press of MERGE takes of every cut they exist in: the
/// pressed cut's ([pressed]) — what lights its button — and, in each cut a
/// row of them exists in too ([existenceMirrorTargets]), the rows there
/// that exist as they do, taken by that cut's own order (🗣️I-78-Q12,
/// 유저 10-28: 「컷마다 그 컷의 순서 · 타이밍대로 합친다」).
///
/// 🗣️I-78-Q9 (유저 10-28): 「이어진 컷에서도 같이 병합한다」 — a 겸용 row is
/// ONE layer seen from several cuts, which a delete takes from every cut
/// (`DeleteLayerCommand`), and a merge takes rows away.
final class LayerMergeTakings {
  LayerMergeTakings._(this.pressed, this._others, this._project);

  /// The pressed cut's taking.
  final LayerMergeTaking pressed;

  /// Every other cut's, in track order.
  final List<LayerMergeTaking> _others;

  /// The project they were taken of: its link table and its tracks.
  final Project _project;

  List<LayerMergeTaking> get _all => [pressed, ..._others];
}

/// What a press of MERGE takes of [cutId]'s [selected] rows in [project]
/// and of every cut they exist in ([LayerMergeTakings]) — null where it
/// merges nothing in [cutId] ([takeRowsToMerge]).
///
/// A row stays, in every cut, where its other selves cannot go with it
/// ([_toStay]). The press's rows are taken again until none of them has
/// to. And an attach row with a self in another cut stays — and with it
/// the base it rides ([_standsDown]) — until the round that takes it
/// (④b): its cels are its group's, which the merge would bake anew in one
/// cut. A row of a track's conte is none of them: its selves are the
/// track's structure's, and each is baked in its own cut (I-78-Q20).
LayerMergeTakings? takeRowsToMergeAcross({
  required Project project,
  required CutId cutId,
  required Set<LayerId> selected,
}) {
  bool linkedRider(Layer row) =>
      row.attachedToLayerId != null &&
      row.conteKey == null &&
      existenceMirrorTargets(project, cutId: cutId, layerId: row.id).length >
          1;
  final staying = <LayerId>{};
  while (true) {
    final pressed = takeRowsToMerge(
      cut: requireCut(project, cutId),
      selected: selected,
      staysFor: (row) => staying.contains(row.id) || linkedRider(row),
    );
    if (pressed == null) {
      return null;
    }
    final selves = _selvesOf(project, pressed);
    final others = [
      for (final MapEntry(key: other, value: rows) in selves.elsewhere.entries)
        ?takeRowsToMerge(
          cut: requireCut(project, other),
          selected: {for (final row in rows.values) ...row},
          staysFor: (_) => false,
          alone: true,
        ),
    ];
    final stays = _toStay(project, pressed, selves, others);
    if (stays.isEmpty) {
      return LayerMergeTakings._(pressed, others, project);
    }
    // Every row kept is one the next taking passes over, so the kept grow
    // until nothing more has to stay — and a row kept that came back would
    // be kept again for ever: none comes back, but the press must end.
    final kept = staying.length;
    staying.addAll(stays);
    if (staying.length == kept) {
      return null;
    }
  }
}

/// The rows [pressed] takes as they exist in other cuts
/// ([existenceMirrorTargets]): by cut in track order, each row's selves
/// there by the row — and the rows with a self in [pressed]'s cut too.
({Map<CutId, Map<LayerId, List<LayerId>>> elsewhere, Set<LayerId> twice})
_selvesOf(Project project, LayerMergeTaking pressed) {
  final byCut = <CutId, Map<LayerId, List<LayerId>>>{};
  final twice = <LayerId>{};
  for (final rowId in pressed._taken) {
    for (final (:cutId, :layerId) in existenceMirrorTargets(
      project,
      cutId: pressed.cut.id,
      layerId: rowId,
    )) {
      if (layerId == rowId) {
        continue;
      }
      if (cutId == pressed.cut.id) {
        twice.add(rowId);
      }
      ((byCut[cutId] ??= {})[rowId] ??= []).add(layerId);
    }
  }
  return (
    elsewhere: {
      for (final track in project.tracks)
        for (final cut in track.cuts)
          if (cut.id != pressed.cut.id && byCut[cut.id] != null)
            cut.id: byCut[cut.id]!,
    },
    twice: twice,
  );
}

/// The rows of [pressed] that have to stay for the selves [selves] of them
/// the cuts [others] take:
/// - one a cut does not take a self of — that self stands down there
///   ([_standsDown]), or a folder of its holds a row that does;
/// - one a cut takes something more with — a row held by a folder self
///   that is itself a self of a row no press took;
/// - and, until the round that takes them (④b — the card's order, not a
///   law of the verb), one with two selves in one cut, and every row an
///   attach row rides or that rides one where the merge reaches across
///   cuts: the results there are one layer, and a rider's mirrors would be
///   its group's. A row riding its cut's conte by a row of the track's
///   structure is none (I-78-Q20): the result rides the conte as it did.
Set<LayerId> _toStay(
  Project project,
  LayerMergeTaking pressed,
  ({Map<CutId, Map<LayerId, List<LayerId>>> elsewhere, Set<LayerId> twice})
  selves,
  List<LayerMergeTaking> others,
) {
  final takingOf = {for (final taking in others) taking.cut.id: taking};
  final stays = {...selves.twice};
  for (final MapEntry(key: cutId, value: rows) in selves.elsewhere.entries) {
    final taking = takingOf[cutId];
    for (final MapEntry(key: row, value: there) in rows.entries) {
      if (there.length > 1 ||
          taking == null ||
          !there.every(taking._taken.contains)) {
        stays.add(row);
      }
    }
    if (taking == null) {
      continue;
    }
    final asked = {for (final there in rows.values) ...there};
    for (final extra in taking._taken.difference(asked)) {
      if (existenceMirrorTargets(project, cutId: cutId, layerId: extra)
          .any((self) => self.layerId != extra)) {
        final held = taking.cut.layers.byId(extra)!;
        for (final folder in taking._index.ancestryOf(held.folderId)) {
          for (final MapEntry(key: row, value: there) in rows.entries) {
            if (there.contains(folder.id)) {
              stays.add(row);
            }
          }
        }
      }
    }
  }
  if (others.isEmpty) {
    return stays;
  }
  bool attached(LayerMergeTaking taking, LayerId id) {
    final row = taking.cut.layers.byId(id)!;
    return (row.attachedToLayerId != null && row.conteKey == null) ||
        attachedLayersOf(id, taking.cut.layers).isNotEmpty;
  }

  for (final id in pressed._taken) {
    if (attached(pressed, id)) {
      stays.add(id);
    }
  }
  for (final MapEntry(key: cutId, value: rows) in selves.elsewhere.entries) {
    final taking = takingOf[cutId];
    for (final MapEntry(key: row, value: there) in rows.entries) {
      if (taking != null && there.any((id) => attached(taking, id))) {
        stays.add(row);
      }
    }
  }
  return stays;
}

/// What a press of MERGE takes of [cut]'s [selected] rows — null for
/// nothing it can merge: one picture row alone, and no folder — unless
/// [alone], for the rows another cut's press takes there (Q12 「그 컷에 없는
/// 행은 그냥 없는 대로 합칩니다」).
///
/// A row that paints no drawing of its own is no part of a picture, and is
/// passed over (Q4's memo: 「불가능한것들은 자연스럽게 무시」). So is a row
/// this round does not merge yet ([_standsDown]) — and a folder that holds
/// one, whose rows cannot be taken apart from it.
///
/// ↩️Until I-78-Q13 · Q14 were answered (10-28) an attach row went only
/// with its base, and a base whose rider stayed only as the topmost row
/// chosen — each letting go of what it went with, until nothing more let
/// go.
///
/// A folder taken takes everything it holds: every row a folder can hold
/// is laid into its picture — the camera row moves nowhere
/// ([LayerKind.reordersInCut]), and a transition row is its track's.
/// ↩️It took only those that composite, and re-placed the rest in the
/// folder above, for rows no folder can hold.
///
/// 🗣️I-78-Q20 (유저 10-30 「트랙의 모든 컷에서 같이 병합」): the rows of the
/// cut's conte merge among themselves — chosen with rows of the cut's own,
/// they are passed over (the option's 「콘티 행과 보통 행이 섞이면 콘티 행은
/// 건너뜁니다」), so the conte's rows are taken only where none of the
/// cut's own is.
LayerMergeTaking? takeRowsToMerge({
  required Cut cut,
  required Set<LayerId> selected,
  required bool Function(Layer row) staysFor,
  bool alone = false,
}) {
  final index = LayerFolderIndex(cut.layers);
  // What a chosen row takes, whole or not at all: itself — or a folder,
  // everything it holds. Nothing of a row it cannot take, nor of the rows
  // of the side it is not taking of ([_standsDown]).
  Map<LayerId, List<Layer>> reachesOf({required bool ofTheConte}) {
    bool standsDown(Layer row) =>
        _standsDown(row, cut.layers, staysFor, ofTheConte: ofTheConte);
    List<Layer>? reachOf(Layer row) {
      if (!row.kind.groupsLayers) {
        return _isPicture(row) && !standsDown(row) ? [row] : null;
      }
      final under = index.subtreeMembersOf(row.id);
      return under.any(_isPicture) &&
              !standsDown(row) &&
              !under.any(standsDown)
          ? [row, ...under]
          : null;
    }

    return {
      for (final row in cut.layers)
        if (selected.contains(row.id)) row.id: ?reachOf(row),
    };
  }

  final own = reachesOf(ofTheConte: false);
  final ofTheConte = own.isEmpty;
  final reaches = ofTheConte ? reachesOf(ofTheConte: true) : own;
  // Bottom → top: the last is the topmost.
  final heads = [
    for (final row in cut.layers)
      if (reaches.containsKey(row.id)) row,
  ];
  if (heads.isEmpty) {
    return null;
  }
  final taking = LayerMergeTaking._(
    cut,
    index,
    {
      for (final head in heads)
        for (final row in reaches[head.id]!) row.id,
    },
    heads.last,
    ofTheConte ? conteBaseOf(cut) : null,
  );
  return alone ||
          heads.any((head) => head.kind.groupsLayers) ||
          taking._pictureRows.length > 1
      ? taking
      : null;
}

/// What a press makes of [takings] — of every cut it reaches, each by its
/// own order and timing (Q12), the results ONE layer across them: one bank
/// of cels ([_bankOf]), one name, one row of the link table.
///
/// [readsOf] says how each cut's cels are read; [mintFrameId] names each
/// new cel of a row; [reach] is how far past the canvas the project's wall
/// stands — the wall the pictures are drawn over.
LayerMergePlan planLayerMerge(
  LayerMergeTakings takings, {
  required CelReads Function(Cut cut) readsOf,
  required FrameId Function(LayerId row) mintFrameId,
  required PasteboardReach reach,
}) {
  final pressed = takings.pressed;
  final all = takings._all;
  final canonical = _canonicalIdsOf(takings);
  final parts = [
    for (final taking in all)
      _partOf(taking, readsOf(taking.cut), canonical[taking.cut.id]!),
  ];
  final wall = pressed.cut.canvasSize.pasteboardAt(reach);
  final layers = _oneLayerOf(takings);
  final made = <int, _Made>{};
  final banked = <LayerMergePicture>[];
  for (final layer in layers) {
    final first = all[layer.first];
    final keptUnder = _resultIdIn(takings, first, first);
    final bank = _bankOf(
      [for (final index in layer) parts[index]],
      (part, spans) => switch (part.follows) {
        final conte? => attachedMirrorCelId(
          keptUnder,
          exposedFrameIdAt(conte.timeline, spans.first.start)!,
        ),
        null => mintFrameId(keptUnder),
      },
    );
    final held = [for (final (:cel, part: _) in bank.cels) cel];
    for (final (at, index) in layer.indexed) {
      final part = parts[index];
      made[index] = _madeOf(
        part,
        (
          id: _resultIdIn(takings, first, part.taking),
          head: pressed._anchor,
          bank: held,
          cels: bank.byPart[at],
        ),
        mintFrameId,
        (wall: wall, inkOf: part.reads.inkOf),
      );
    }
    banked.addAll([
      for (final (:cel, :part) in bank.cels)
        (
          into: first.cut,
          rowId: keptUnder,
          frameId: cel.frameId,
          from: parts[layer[part]].baked,
          frameIndex: cel.spans.first.start,
        ),
    ]);
  }
  final results = [for (final (index, _) in parts.indexed) made[index]!];
  return LayerMergePlan._(
    cut: pressed.cut,
    result: results.first.result,
    pictures: [
      ...banked,
      for (final part in results) ...part.riderPictures,
    ],
    changes: {for (final part in results) ...part.changes},
    layers: results.first.layers,
    others: [
      for (final (index, part) in results.indexed.skip(1))
        (cut: parts[index].taking.cut, layers: part.layers),
    ],
    links: _linksAfter(takings, layers, [
      for (final part in results) part.result,
    ]),
  );
}

/// The takings whose results are ONE layer — each set by its index in
/// [takings], the pressed cut's first: those a link group joins, a row one
/// takes linked to a row another takes (Q12 「컷끼리 계속 겸용입니다」).
///
/// ⛔A track's conte rows are no link across its cuts (`conteHeadTargets`
/// — 「two cuts' conte rows in one group would turn every pair of
/// same-named panels into one picture」): where the press reaches the
/// cuts by the track's structure (I-78-Q20), each cut's result is a layer
/// of its own — but for the cuts a 겸용 pair links.
List<List<int>> _oneLayerOf(LayerMergeTakings takings) {
  final links = takings._project.linkRegistry;
  final all = takings._all;
  final joinedTo = [for (var index = 0; index < all.length; index += 1) index];
  int rootOf(int index) => joinedTo[index] == index
      ? index
      : joinedTo[index] = rootOf(joinedTo[index]);
  final byGroup = <String, int>{};
  for (final (index, taking) in all.indexed) {
    for (final id in taking._taken) {
      final group = links.groupOf(cutId: taking.cut.id, layerId: id);
      if (group != null) {
        joinedTo[rootOf(index)] = rootOf(
          byGroup.putIfAbsent(group.id, () => index),
        );
      }
    }
  }
  final layers = <int, List<int>>{};
  for (var index = 0; index < all.length; index += 1) {
    (layers[rootOf(index)] ??= []).add(index);
  }
  return [...layers.values];
}

/// ONE cut's share of a merge: what it is baked of and drawn from, and the
/// runs of its frames by the picture they show — a picture keyed as every
/// cut keys it ([_runsByPicture]'s `keys`).
typedef _Part = ({
  LayerMergeTaking taking,
  CelReads reads,
  LayerId? standing,
  Set<LayerId> over,
  Cut baked,
  List<List<CutFrameCompositeSpan>> runs,
  Layer? follows,
});

/// [taking]'s share ([_Part]), its cels read by [reads] and its rows
/// keyed as [canonical] names them.
_Part _partOf(
  LayerMergeTaking taking,
  CelReads reads,
  Map<LayerId, LayerId> canonical,
) {
  final standing = _standingFolderOf(taking);
  final over = {
    for (final folder in taking._index.ancestryOf(standing)) folder.id,
  };
  final rows = _bakedRows(taking);
  final folders = _foldersLeft(taking, over, rows);
  // The result parts wherever a synced rider's picture does too: each
  // rides the result's cels one for one.
  final runs = _runsByPicture(
    _cutWith(taking, folders, [
      ...rows,
      for (final rider in taking._riders)
        if (isSyncedAttachedLayer(rider)) _riding(rider),
    ]),
    taking._pictureRows,
    reads.revisionOf,
    keys: canonical,
  );
  return (
    taking: taking,
    reads: reads,
    standing: standing,
    over: over,
    baked: _cutWith(taking, folders, rows),
    runs: runs,
    follows: _conteFollowed(taking, runs),
  );
}

/// The conte whose timing the result of [taking] — of its conte's rows —
/// follows, as every row it takes did (I-78-Q20): each of its pictures
/// ([runs]) shown where one cel of the conte is, and each such cel showing
/// one — what a synced row's cels are, one for each of the conte's. Null
/// for a result that keeps a timing of its own.
Layer? _conteFollowed(
  LayerMergeTaking taking,
  List<List<CutFrameCompositeSpan>> runs,
) {
  final conte = taking._conte;
  if (conte == null || !taking._pictureRows.every(isSyncedAttachedLayer)) {
    return null;
  }
  final shown = <FrameId>{};
  for (final spans in runs) {
    final cels = {
      for (final span in spans) ...[
        exposedFrameIdAt(conte.timeline, span.start),
        exposedFrameIdAt(conte.timeline, span.start + span.length - 1),
      ],
    };
    final cel = cels.length == 1 ? cels.single : null;
    if (cel == null || !shown.add(cel)) {
      return null;
    }
  }
  return conte;
}

/// Every cut's rows as ONE key names them across the cuts: a row of a link
/// group by its group's first member — the row its cels are kept under —
/// and every other row by its own id.
Map<CutId, Map<LayerId, LayerId>> _canonicalIdsOf(LayerMergeTakings takings) {
  final links = takings._project.linkRegistry;
  return {
    for (final taking in takings._all)
      taking.cut.id: {
        for (final row in taking.cut.layers)
          if (links.groupOf(cutId: taking.cut.id, layerId: row.id)
              case final group?)
            row.id: group.canonical.layerId,
      },
  };
}

/// One cel of the bank the results share, and the share it first shows in.
typedef _BankCel = ({_Cel cel, int part});

/// The cels the results that are ONE layer hold — one bank for every cut,
/// as a 겸용 layer's cels are its group's (`UpdateLayerTimelineCommand`):
/// a cel for each picture a share shows, the same picture in two cuts one
/// cel (the Q12 question's reading: 「같은 조합이면 같은 이름(은행의 한
/// 그림)을, 다른 조합이면 꼬리 번호」) — minted by [mint], handed the share
/// and the picture's runs, and named after the cel the topmost row taken
/// shows where it first shows (Q10 · Q11), clear of every name the bank
/// holds. With them, each share's own cels by its runs.
({List<_BankCel> cels, List<List<_Cel>> byPart}) _bankOf(
  List<_Part> parts,
  FrameId Function(_Part share, List<CutFrameCompositeSpan> spans) mint,
) {
  final held = <String>{};
  final bySignature = <CutFrameCompositeSignature, _BankCel>{};
  final cels = <_BankCel>[];
  _BankCel celOf(int part, List<CutFrameCompositeSpan> spans) {
    final known = bySignature[spans.first.signature];
    if (known != null) {
      return known;
    }
    final share = parts[part];
    final cel = (
      cel: (
        frameId: mint(share, spans),
        name: _nameTakenAt(
          held,
          share.baked,
          share.taking._pictureRows,
          spans.first.start,
        ),
        spans: spans,
      ),
      part: part,
    );
    cels.add(cel);
    return bySignature[spans.first.signature] = cel;
  }

  final byPart = [
    for (final (part, share) in parts.indexed)
      [
        for (final spans in share.runs)
          switch (celOf(part, spans).cel) {
            final cel => (frameId: cel.frameId, name: cel.name, spans: spans),
          },
      ],
  ];
  return (cels: cels, byPart: byPart);
}

/// Of a share, the row the merge leaves there: [id], wearing [head] — the
/// pressed cut's topmost row, whose name a 겸용 layer wears in every cut —
/// over the [bank] every cut's results hold, showing its own [cels].
typedef _ResultOf = ({
  LayerId id,
  Layer head,
  List<_Cel> bank,
  List<_Cel> cels,
});

/// What a share's cut is made of the merge: its result where its topmost
/// row stood, its rows after, the pictures of the rows riding it baked
/// anew, and why it may show otherwise.
typedef _Made = ({
  Layer result,
  List<Layer> layers,
  List<LayerMergePicture> riderPictures,
  Set<LayerMergeChange> changes,
});

/// What [part]'s cut is made of the merge ([_Made]): its result
/// ([_ResultOf]) — a row of its conte, where it takes the conte's rows
/// ([_onTheConte]) — the rows riding it baked anew, minted by
/// [mintFrameId], its pictures checked at [wall].
_Made _madeOf(
  _Part part,
  _ResultOf of,
  FrameId Function(LayerId row) mintFrameId,
  _WallCheck wall,
) {
  final taking = part.taking;
  final row = _resultRow(of, taking._anchor, part.standing);
  final result = (
    row: switch (taking._conte) {
      final conte? => _onTheConte(
        row,
        taking._keeper,
        conte,
        following: part.follows == null ? null : of.cels,
      ),
      null => row,
    },
    runs: part.runs,
    cels: of.cels,
  );
  final minting = (revisionOf: part.reads.revisionOf, mintFrameId: mintFrameId);
  final ridden = [
    for (final rider in taking._riders)
      _riderBaked(
        rider,
        _aloneWithItsBase(taking, part.over, rider),
        result,
        minting,
      ),
  ];
  return (
    result: result.row,
    layers: _layersAfter(taking, part.over, result.row, {
      for (final rider in ridden) rider.row.id: rider.row,
    }),
    riderPictures: [for (final rider in ridden) ...rider.pictures],
    changes: _changesOf(
      taking,
      part.over,
      _picturesOf(taking.cut, result.row, of.cels, part.baked),
      wall,
    ),
  );
}

/// The id [taking]'s result keeps, of the results ONE layer with [first]'s
/// ([_oneLayerOf]): that of [first]'s keeper's self there ([_keeper]),
/// where it has one — so the results' cels stay where the link table keeps
/// [first]'s now ([_linksAfter]) — else that of its own keeper.
LayerId _resultIdIn(
  LayerMergeTakings takings,
  LayerMergeTaking first,
  LayerMergeTaking taking,
) {
  if (identical(taking, first)) {
    return first._keeper.id;
  }
  return takings._project.linkRegistry.counterpartIn(
        cutId: first.cut.id,
        layerId: first._keeper.id,
        targetCutId: taking.cut.id,
      ) ??
      taking._keeper.id;
}

/// The link table after [takings]' merge leaves [results], one for each
/// cut: every group a row it takes stood in gone — each of its members is
/// taken, in its own cut — and the results of each of [layers] ONE layer
/// across their cuts (Q12 「컷끼리 계속 겸용입니다(이름 · 그림 은행 같이
/// 씀)」), its first member the one the first's cels are kept under now:
/// what the pictures are laid under before the table changes.
LayerLinkRegistry _linksAfter(
  LayerMergeTakings takings,
  List<List<int>> layers,
  List<Layer> results,
) {
  final project = takings._project;
  final links = project.linkRegistry;
  final all = takings._all;
  final gone = {
    for (final taking in all) ...taking._taken,
  };
  final groups = [
    for (final group in links.groups)
      if (!group.members.any((member) => gone.contains(member.layerId)))
        group,
  ];
  for (final layer in layers) {
    if (layer.length < 2) {
      continue;
    }
    final first = all[layer.first];
    final keptUnder = links
        .groupOf(cutId: first.cut.id, layerId: first._keeper.id)
        ?.canonical;
    final members = [
      for (final index in layer)
        LayerLinkMember(
          trackId: requireCutPosition(project, all[index].cut.id).trackId,
          cutId: all[index].cut.id,
          layerId: results[index].id,
        ),
    ];
    groups.add(
      LayerLinkGroup(
        id: firstUnusedName({
          for (final group in groups) group.id,
        }, (index) => 'link-$index'),
        members: [
          ...members.where((member) => member == keptUnder),
          ...members.where((member) => member != keptUnder),
        ],
      ),
    );
  }
  return LayerLinkRegistry(groups: groups);
}

/// What the result is baked of: the rows [taking] takes, each shown (Q7),
/// and the bases they ride without them — hidden, there to be worn (Q14);
/// the conte bare ([_bare]), which the result rides after (I-78-Q20).
List<Layer> _bakedRows(LayerMergeTaking taking) {
  final LayerMergeTaking(:cut, _taken: taken) = taking;
  final takenRows = [
    for (final row in cut.layers)
      if (taken.contains(row.id)) _shown(row),
  ];
  return [
    ...takenRows,
    for (final row in cut.layers)
      if (!taken.contains(row.id) &&
          takenRows.any((rider) => rider.attachedToLayerId == row.id))
        if (row.id == taking._conte?.id)
          _bare(row)
        else
          row.copyWith(isVisible: false),
  ];
}

/// [conte] as the rows riding it are baked against it: hidden, and laying
/// nothing over them — no pose, no opacity of its keys, no fx — what the
/// result wears of it after, riding it as they did, and would wear twice
/// baked in.
Layer _bare(Layer conte) => conte.copyWith(
  isVisible: false,
  transformTrack: TransformTrack.empty(),
  effects: const [],
);

/// The folder the result stands in: the topmost row's — or, for an attach
/// row taken without its base, its base's, the group's folder, where the
/// result stands just outside the group (Q14).
LayerId? _standingFolderOf(LayerMergeTaking taking) {
  final anchor = taking._anchor;
  return switch (_baseLeftBy(taking)) {
    final base? => base.folderId,
    null => anchor.folderId,
  };
}

/// The base the topmost row taken rides, when it is not taken itself (Q14)
/// — but the conte, which the result of its rows rides as they did
/// ([_onTheConte]).
Layer? _baseLeftBy(LayerMergeTaking taking) =>
    switch (taking._anchor.attachedToLayerId) {
      final baseId?
          when taking._conte == null && !taking._taken.contains(baseId) =>
        taking.cut.layers.byId(baseId),
      _ => null,
    };

/// The rows riding the rows [taking] takes that it does not take — each
/// base's group but the base ([attachedGroupSlice]), organizer folders and
/// all — by the side of the base they stand on: what is led around the
/// result (Q8 · Q13).
///
/// A folder the result stands in ([over]) is none of them: the topmost row
/// taken from inside a group's organizer folder stands in it after (Q2), so
/// the folder holds the result, and is no organizer any more.
({List<Layer> below, List<Layer> above}) _ledAround(
  LayerMergeTaking taking,
  Set<LayerId> over,
) {
  final LayerMergeTaking(:cut, _taken: taken) = taking;
  final below = <Layer>[];
  final above = <Layer>[];
  for (final base in cut.layers) {
    if (!taken.contains(base.id)) {
      continue;
    }
    var side = below;
    for (final member in attachedGroupSlice(base.id, cut.layers)) {
      if (member.id == base.id) {
        side = above;
      } else if (!taken.contains(member.id) && !over.contains(member.id)) {
        side.add(member);
      }
    }
  }
  return (below: below, above: above);
}

/// The cut's rows after [taking]'s merge: the rows it takes gone, and
/// [result] standing where the topmost of them stood — or just outside the
/// group of the base it rode without as the group stood, on the side it
/// rode (Q14) — with the rows [_ledAround] it, [ridden] where it bakes them
/// anew: those of a base's folder in the result's.
List<Layer> _layersAfter(
  LayerMergeTaking taking,
  Set<LayerId> over,
  Layer result,
  Map<LayerId, Layer> ridden,
) {
  final LayerMergeTaking(:cut, _taken: taken, _anchor: anchor) = taking;
  final led = _ledAround(taking, over);
  final ledIds = {
    for (final row in [...led.below, ...led.above]) row.id,
  };
  Layer seated(Layer row) => switch (ridden[row.id] ?? row) {
    final rider when ledIds.contains(rider.folderId) => rider,
    final rider => rider.copyWith(folderId: result.folderId),
  };
  final kept = [
    for (final row in cut.layers)
      if (!taken.contains(row.id) && !ledIds.contains(row.id)) row,
  ];
  final order = {for (final (index, row) in cut.layers.indexed) row.id: index};
  final edge = switch (_baseLeftBy(taking)) {
    final base? when order[anchor.id]! < order[base.id]! =>
      attachedGroupStartIndex(base.id, cut.layers),
    final base? => attachedGroupEndIndex(base.id, cut.layers),
    null => order[anchor.id]!,
  };
  final at = kept.where((row) => order[row.id]! < edge).length;
  return [
    ...kept.take(at),
    for (final row in led.below) seated(row),
    result,
    for (final row in led.above) seated(row),
    ...kept.skip(at),
  ];
}

/// A row whose cels hold artwork — "a real drawing row"
/// ([LayerKind.isDrawingCel]).
bool _isPicture(Layer row) => row.kind.isDrawingCel;

/// The rows a merge passes over:
/// - a row of the side it does not take of — the conte's rows, which merge
///   only among themselves ([takeRowsToMerge], 🗣️I-78-Q20), where it takes
///   the cut's own ([ofTheConte] false), and the cut's own where it takes
///   the conte's,
/// - until the round that merges them comes — the card's order (I-78,
///   10-28), not a law of the verb — a row [staysFor] keeps: a 겸용 row a
///   band's blocks merge, and a row whose other selves cannot go with it
///   ([_toStay]),
/// - a direction block, whose direction is no picture to bake (🗣️I-78-Q16,
///   유저 10-28: 「건너뛴다 (지금 동작 그대로)」),
/// - and a row an attach row that stands down rides: the rider would ride
///   the result, its cels baked anew — which passes over the conte itself
///   wherever a row rides it, the cut's own though it is.
///
/// ↩️Round ① passed over every attach row and every row one rides; round ②
/// takes them (Q8 · Q13 · Q14). ↩️A reference row was passed over too, its
/// file laid whole past the wall (F-374-Q8) where no picture of the screen
/// reaches, until 🗣️I-78-Q15 (유저 10-28 「참조도 그대로 병합한다」): what
/// lies there is warned of instead ([LayerMergeChange.wall]). ↩️And every
/// conte row was passed over until Q20 was answered.
bool _standsDown(
  Layer row,
  List<Layer> layers,
  bool Function(Layer row) staysFor, {
  required bool ofTheConte,
}) =>
    staysFor(row) ||
    (row.conteKey != null) != ofTheConte ||
    row.timeline.values.any((exposure) => exposure.instruction != null) ||
    attachedLayersOf(row.id, layers).any(
      (rider) =>
          _standsDown(rider, layers, staysFor, ofTheConte: ofTheConte),
    );

/// The folders above [rows] that the result does not stand in ([over]):
/// the looks the rows leave, baked into their pictures.
Set<LayerId> _foldersLeft(
  LayerMergeTaking taking,
  Set<LayerId> over,
  Iterable<Layer> rows,
) => {
  for (final row in rows)
    for (final folder in taking._index.ancestryOf(row.folderId))
      if (!over.contains(folder.id)) folder.id,
};

/// [taking]'s cut holding only [rows] — each as it is laid there — and the
/// [folders] over them, shown, in the cut's order, each pointing at the
/// nearest row kept above it.
Cut _cutWith(LayerMergeTaking taking, Set<LayerId> folders, List<Layer> rows) {
  final laid = {for (final row in rows) row.id: row};
  final cut = taking.cut;
  LayerId? keptParent(LayerId? folderId) {
    for (final folder in taking._index.ancestryOf(folderId)) {
      if (laid.containsKey(folder.id) || folders.contains(folder.id)) {
        return folder.id;
      }
    }
    return null;
  }

  return cut.copyWith(
    layers: [
      for (final row in cut.layers)
        if (laid[row.id] ?? (folders.contains(row.id) ? _shown(row) : null)
            case final kept?)
          kept.copyWith(folderId: keptParent(row.folderId)),
    ],
  );
}

/// [taking]'s cut holding [rider] alone with its base, and the folders over
/// the base the result does not stand in ([over]) — the base hidden, so
/// what the rider is drawn of it is what it wore: the base's pose, keys
/// and fx, and the looks of the folders it leaves.
Cut _aloneWithItsBase(
  LayerMergeTaking taking,
  Set<LayerId> over,
  Layer rider,
) {
  final base = taking.cut.layers.byId(rider.attachedToLayerId!)!;
  return _cutWith(taking, _foldersLeft(taking, over, [base]), [
    base.copyWith(isVisible: false),
    _riding(rider),
  ]);
}

/// [row] baked as it would show with its eye on (Q7).
Layer _shown(Layer row) => row.copyWith(isVisible: true);

/// [rider] baked as it rides: shown, with nothing of its own laid — its
/// strength, blend and clip stay on its row, and land on the pictures as
/// they did.
Layer _riding(Layer rider) => rider.copyWith(
  isVisible: true,
  opacity: 1,
  blendMode: LayerBlendMode.normal,
  clipsToBelow: false,
);

/// One cel of a row the merge makes: its id, its name, and every run of
/// frames that shows it.
typedef _Cel = ({
  FrameId frameId,
  String? name,
  List<CutFrameCompositeSpan> spans,
});

/// The runs of [shown] over every frame a block of [rows] covers — as the
/// cut shows them ([attachedRowAsShown]: a synced attach row's are its
/// base's) — gathered by the picture they show — one list per picture, in
/// the order they first show. A run that shows nothing is none: the row is
/// empty there. Each picture is keyed with the rows [keys] names named so
/// ([_renamed]), its cels read as their own rows' all the same.
List<List<CutFrameCompositeSpan>> _runsByPicture(
  Cut shown,
  List<Layer> rows,
  BrushFrameRevisionResolver revisionOf, {
  Map<LayerId, LayerId> keys = const {},
}) {
  final blocks = [
    for (final row in rows)
      ...drawingBlocks(attachedRowAsShown(row, shown.layers).timeline),
  ];
  if (blocks.isEmpty) {
    return const [];
  }
  final back = {
    for (final MapEntry(:key, :value) in keys.entries) value: key,
  };
  final spans = computeCutFrameCompositeSpans(
    cut: _renamed(shown, keys),
    frames: (
      startIndex: blocks.map((block) => block.startIndex).reduce(_min),
      endIndexExclusive: blocks
          .map((block) => block.endIndexExclusive)
          .reduce(_max),
    ),
    revisionOf: (layerId, frameId) =>
        revisionOf(back[layerId] ?? layerId, frameId),
  );
  final bySignature =
      <CutFrameCompositeSignature, List<CutFrameCompositeSpan>>{};
  for (final span in spans) {
    if (span.signature.nodes.isNotEmpty) {
      bySignature.putIfAbsent(span.signature, () => []).add(span);
    }
  }
  return bySignature.values.toList();
}

/// [cut] with each row [keys] names named so, wherever a row names one:
/// its own id, its folder, the base it rides, the rows its effects read.
Cut _renamed(Cut cut, Map<LayerId, LayerId> keys) {
  if (keys.isEmpty) {
    return cut;
  }
  LayerId? named(LayerId? id) => id == null ? null : keys[id] ?? id;
  return cut.copyWith(
    layers: [
      for (final row in cut.layers)
        row.copyWith(
          id: named(row.id),
          folderId: named(row.folderId),
          attachedToLayerId: named(row.attachedToLayerId),
          effects: effectsWithRowsRenamed(
            row.effects,
            (id) => keys[id] ?? id,
          ),
        ),
    ],
  );
}

/// A cel for each picture of [runs], minted by [mintFrameId] (handed the
/// picture's place) and named after the cel the topmost of [rows] shows in
/// [shown] where it first shows (Q10 · Q11).
List<_Cel> _celsOf(
  List<List<CutFrameCompositeSpan>> runs,
  Cut shown,
  List<Layer> rows,
  FrameId Function(int picture) mintFrameId,
) {
  final heldNames = <String>{};
  return [
    for (final (picture, spans) in runs.indexed)
      (
        frameId: mintFrameId(picture),
        name: _nameTakenAt(heldNames, shown, rows, spans.first.start),
        spans: spans,
      ),
  ];
}

/// The name a new cel takes where the topmost of [rows] that shows a cel
/// in [shown] at [frameIndex] shows one (Q10 · Q11): that cel's number, its
/// tail clear of every name [held] holds — which holds it from then on.
String? _nameTakenAt(
  Set<String> held,
  Cut shown,
  List<Layer> rows,
  int frameIndex,
) {
  final name = switch (_nameShownAt(shown, rows, frameIndex)) {
    final number? => _tailClearOf(held, number),
    null => null,
  };
  if (name != null) {
    held.add(name);
  }
  return name;
}

/// [number], or [number] with the first tail no name of [held] wears
/// (Q10).
String _tailClearOf(Set<String> held, String number) => firstUnusedName(
  held,
  (index) => index == 1 ? number : '$number-$index',
);

/// The name of the cel the topmost of [rows] that shows one at
/// [frameIndex] shows there — null where its cel is unnamed, or none shows.
String? _nameShownAt(Cut cut, List<Layer> rows, int frameIndex) {
  for (final row in rows.reversed) {
    final celId = exposedCelIdAt(
      cut: cut,
      layerId: row.id,
      frameIndex: frameIndex,
    );
    if (celId != null) {
      return celNumberOf(row.frameById(celId)?.name);
    }
  }
  return null;
}

/// The pictures [cels] of [row] in [into] are baked from: each drawn of
/// [from] at the first frame it shows.
List<LayerMergePicture> _picturesOf(
  Cut into,
  Layer row,
  List<_Cel> cels,
  Cut from,
) => [
  for (final cel in cels)
    (
      into: into,
      rowId: row.id,
      frameId: cel.frameId,
      from: from,
      frameIndex: cel.spans.first.start,
    ),
];

/// The merged row [of] makes: its head's name and label over the bank, in
/// the folder it stands in ([_standingFolderOf]), and nothing of the look
/// it was baked with (Q6) — nor a base it rode (Q14) — its [anchor]'s
/// sheet switch, which each cut keeps of its own.
Layer _resultRow(_ResultOf of, Layer anchor, LayerId? folderId) => Layer(
  id: of.id,
  name: of.head.name,
  kind: _kindHolding(of.head.kind, of.bank.length),
  mark: of.head.mark,
  onTimesheet: anchor.onTimesheet,
  folderId: folderId,
  frames: _framesOf(of.bank),
  timeline: _timelineOf(of.cels),
);

/// [row] made a row of [conte] (🗣️I-78-Q20: 「결과는 트랙 구조에서 맨 위 행
/// 자리에 서고 모든 컷이 같은 구조를 유지」): riding it on the side [keeper]
/// rode, as [keeper]'s row of the track's structure, of its kind — and,
/// [following] the conte's timing as every row taken did
/// ([_conteFollowed]), a cel for each cel of the conte it shows, as a
/// synced row's are; a timing of its own where null.
Layer _onTheConte(
  Layer row,
  Layer keeper,
  Layer conte, {
  required List<_Cel>? following,
}) {
  final riding = row.copyWith(
    kind: _kindHolding(keeper.kind, row.frames.length),
    attachedToLayerId: conte.id,
    attachedPlacement: keeper.attachedPlacement,
    conteKey: keeper.conteKey,
  );
  if (following == null) {
    return riding.copyWith(attachedMode: AttachedMode.free);
  }
  return riding.copyWith(
    attachedMode: AttachedMode.synced,
    timeline: const {},
    baseFrameLinks: {
      for (final cel in following)
        exposedFrameIdAt(conte.timeline, cel.spans.first.start)!: cel.frameId,
    },
  );
}

/// The kind a row of [kind] is once it holds [pictures] cels: a picture
/// row's own — a folder or an image that now holds more than one picture
/// becoming a drawing row.
LayerKind _kindHolding(LayerKind kind, int pictures) =>
    kind.isDrawingCel && !(kind.holdsSingleCel && pictures > 1)
    ? kind
    : LayerKind.animation;

List<Frame> _framesOf(List<_Cel> cels) => [
  for (final cel in cels)
    Frame(
      id: cel.frameId,
      duration: cel.spans.first.length,
      name: cel.name,
      strokes: const [],
    ),
];

Map<int, TimelineExposure> _timelineOf(List<_Cel> cels) => {
  for (final cel in cels)
    for (final span in cel.spans)
      span.start: TimelineExposure.drawing(cel.frameId, length: span.length),
};

/// The result as a rider is laid against: the row, its runs by picture
/// and the cels they are.
typedef _Ridden = ({
  Layer row,
  List<List<CutFrameCompositeSpan>> runs,
  List<_Cel> cels,
});

/// What a new cel is made under: what each cel holds as the composite
/// signature reads it, and the minting of a row's new cel.
typedef _Minting = ({
  BrushFrameRevisionResolver revisionOf,
  FrameId Function(LayerId row) mintFrameId,
});

/// [rider] riding [result] (Q8), and the pictures its new cels are baked
/// from — each drawn of [alone] ([_aloneWithItsBase]).
///
/// A synced rider takes a cel for each of the result's, under the id its
/// mirror of that cel is minted by ([attachedMirrorCelId]) — one it shows
/// nothing in is an empty cel, so nothing is drawn for it. A free one
/// takes a cel wherever its own picture changes.
({Layer row, List<LayerMergePicture> pictures}) _riderBaked(
  Layer rider,
  Cut alone,
  _Ridden result,
  _Minting minting,
) {
  if (isSyncedAttachedLayer(rider)) {
    final cels = _celsOf(
      result.runs,
      alone,
      [rider],
      (picture) =>
          attachedMirrorCelId(rider.id, result.cels[picture].frameId),
    );
    return (
      row: rider.copyWith(
        attachedToLayerId: result.row.id,
        frames: _framesOf(cels),
        baseFrameLinks: {
          for (final (picture, cel) in cels.indexed)
            result.cels[picture].frameId: cel.frameId,
        },
      ),
      pictures: [
        for (final picture in _picturesOf(alone, rider, cels, alone))
          if (exposedCelIdAt(
                cut: alone,
                layerId: rider.id,
                frameIndex: picture.frameIndex,
              ) !=
              null)
            picture,
      ],
    );
  }
  final cels = _celsOf(
    _runsByPicture(alone, [rider], minting.revisionOf),
    alone,
    [rider],
    (_) => minting.mintFrameId(rider.id),
  );
  return (
    row: rider.copyWith(
      attachedToLayerId: result.row.id,
      kind: _kindHolding(rider.kind, cels.length),
      frames: _framesOf(cels),
      timeline: _timelineOf(cels),
    ),
    pictures: _picturesOf(alone, rider, cels, alone),
  );
}

/// Why the result may show otherwise than the rows [taking] takes did
/// ([LayerMergeChange]) — [over] being the folders it stands in, [drawn]
/// its pictures, and [wall] the one they are drawn over with where its
/// cels' ink lies.
Set<LayerMergeChange> _changesOf(
  LayerMergeTaking taking,
  Set<LayerId> over,
  List<LayerMergePicture> drawn,
  _WallCheck wall,
) {
  final LayerMergeTaking(
    :cut,
    _taken: taken,
    _pictureRows: pictureRows,
  ) = taking;
  final takenRows = [
    for (final row in cut.layers)
      if (taken.contains(row.id)) row,
  ];
  bool clipsAcross(Layer row) =>
      clipsToLayerBelow(row) &&
      switch (clipBaseOf(cut, row)) {
        final base? => taken.contains(row.id) != taken.contains(base.id),
        null => false,
      };
  final looksOver = cut.layers.any(
    (folder) => over.contains(folder.id) && _laysALook(folder),
  );
  return {
    if (takenRows.any((row) => _blendsItsOwnWay(row.blendMode)))
      LayerMergeChange.blend,
    if (cut.layers.any(clipsAcross)) LayerMergeChange.clip,
    if (looksOver &&
        pictureRows.any(
          (row) => !over.every(
            (folderId) => cut.layers.isInsideFolder(row.folderId, folderId),
          ),
        ))
      LayerMergeChange.folder,
    ..._ridersLed(taking, over),
    if (_cutAtTheWall(drawn, wall)) LayerMergeChange.wall,
  };
}

/// The changes the rows [_ledAround] the result make: one led over a
/// picture it did not cover ([LayerMergeChange.riderOver]), or under one
/// it did not stand under ([LayerMergeChange.riderUnder]).
Set<LayerMergeChange> _ridersLed(LayerMergeTaking taking, Set<LayerId> over) {
  final order = {
    for (final (index, row) in taking.cut.layers.indexed) row.id: index,
  };
  final pictures = [for (final row in taking._pictureRows) order[row.id]!];
  final led = _ledAround(taking, over);
  return {
    if (led.above.any((row) => pictures.any((at) => at > order[row.id]!)))
      LayerMergeChange.riderOver,
    if (led.below.any((row) => pictures.any((at) => at < order[row.id]!)))
      LayerMergeChange.riderUnder,
  };
}

/// The wall a merge's pictures are drawn over, and where its cels' ink
/// lies ([CelInkResolver]).
typedef _WallCheck = ({PasteboardWall wall, CelInkResolver inkOf});

/// Whether a row a picture of [drawn] is drawn of shows a picture past the
/// wall there — the part the merge, drawing the screen inside the wall,
/// cuts off (I-78-Q15 · Q19). Read where the row SHOWS it at the picture's
/// frame, as its cut paints it ([layerPlacementAt]): its keys, its folders'
/// and a reference's fx move it from where its pixels are laid ([_laidOf]).
bool _cutAtTheWall(List<LayerMergePicture> drawn, _WallCheck check) {
  final (:wall, :inkOf) = check;
  for (final (:from, :frameIndex, into: _, rowId: _, frameId: _) in drawn) {
    for (final row in from.layers) {
      final cel = from.layers.rowVisible(row)
          ? exposedCelIdAt(cut: from, layerId: row.id, frameIndex: frameIndex)
          : null;
      final laid = cel == null ? null : _laidOf(row, cel, inkOf);
      if (laid == null) {
        continue;
      }
      final shown = DirtyRegion.wholePixelsOf(
        placedRectBounds(
          switch (layerPlacementAt(
            cut: from,
            layer: row,
            frameIndex: frameIndex,
          )) {
            final placement? => placement.compose(laid.at),
            null => laid.at,
          },
          laid.box,
        ),
      ).rect;
      if (wall.rect.expandToInclude(shown) != wall.rect) {
        return true;
      }
    }
  }
  return false;
}

/// What [row] lays of its cel [cel] in its own artwork — [box], [at] there:
/// a reference row's file whole where its pixels are laid, past the wall
/// too (F-374-Q8, [MediaReference.laid]); any other row's ink ([inkOf])
/// where it is drawn. Null where it lays nothing.
({LayerPlacement at, Rect box})? _laidOf(
  Layer row,
  FrameId cel,
  CelInkResolver inkOf,
) {
  if (row.mediaReference case final reference?) {
    final picture = reference.pictureSize;
    return (
      at: picturePlacement(reference.laid, picture),
      box:
          Offset.zero &
          Size(picture.width.toDouble(), picture.height.toDouble()),
    );
  }
  return switch (inkOf(row.id, cel)) {
    null => null,
    final ink => (
      at: const LayerPlacement.identity(),
      box: Rect.fromLTRB(
        ink.left.toDouble(),
        ink.top.toDouble(),
        ink.rightExclusive.toDouble(),
        ink.bottomExclusive.toDouble(),
      ),
    ),
  };
}

/// Whether [folder] lays anything over what it holds.
bool _laysALook(Layer folder) =>
    folder.opacity != 1 ||
    _blendsItsOwnWay(folder.blendMode) ||
    folder.effects.isNotEmpty ||
    folder.transformTrack.isNotEmpty;

int _min(int a, int b) => a < b ? a : b;
int _max(int a, int b) => a > b ? a : b;

/// Whether [mode] meets what is under it otherwise than laid over it — a
/// folder's pass-through is no blend of its own (Photoshop · CSP's 「통과」).
bool _blendsItsOwnWay(LayerBlendMode mode) =>
    mode != LayerBlendMode.normal && mode != LayerBlendMode.passThrough;

/// What ONE press of MERGE makes of the blocks a band of frames holds —
/// each row's blocks made one block over one cel (I-78, round ③).
///
/// 🗣️I-78-Q4 (유저 2026-10-07): 「한 행의 여러 블록을 레이어랑 같은 규칙으로
/// 제일 왼쪽 블록에 합침. 이름은 제일 왼쪽 블록 이름따라감 … 여러 행의 여러
/// 프레임에 걸쳐서 병합할때는 그걸 여러행으로 나눌뿐 … 각 행이 판단해서 이건
/// 병합이 가능한 상태서만 작동하도록. 즉 불가능한것들은 자연스럽게 무시」:
/// - each row merges on its own, and a row that cannot is passed over;
/// - the blocks of a row the band holds become ONE block where the leftmost
///   stood, over the run they make — first start to last end, the frames
///   between them too (the option the answer took: 「길이는 고른 범위
///   전체」) — showing a new cel named as the leftmost's is, with Q10's tail
///   where a cel that stays wears that name;
/// - the cel is their cels laid over each other as they are: the row's own
///   look — its keys, its fx — stays on the row, and lands on the one cel
///   as it landed on each.
///
/// 🗣️I-78-Q17 · Q18 (유저 10-28 「제일 왼쪽 블록이 위 (레이어의 맨 위처럼)」 ·
/// 「이대로 진행」), my calls put to the user and taken as they stood: the
/// leftmost cel lies on top, as the topmost row's picture does in a merge
/// of rows; the run's
/// outer edges — a hold, a repeat — stay with it, while its blocks' marks
/// and memos do not come along, as a merge of rows' do not; a cel only the
/// run showed goes, as a delete takes it (F-136); and a synced attach row
/// riding the row merges along, its cels for the run's laid the same way
/// (「어태치 레이어는 주인과 같이」, 07-21), its mirrors of the cels that go
/// going with them.
class BlockMergePlan {
  const BlockMergePlan._({
    required this.cut,
    required this.rows,
    required this.pictures,
  });

  /// The cut it was planned of, as it was.
  final Cut cut;

  /// Every row the merge changes, as it leaves it: each row whose blocks
  /// it makes one, and the synced attach rows riding it.
  final List<Layer> rows;

  /// The new cels' pictures, still to be laid.
  final List<BlockMergePicture> pictures;

  /// The cut's rows after the merge: [rows] where they stood.
  List<Layer> get layers {
    final replaced = {for (final row in rows) row.id: row};
    return [for (final row in cut.layers) replaced[row.id] ?? row];
  }
}

/// One new cel of a block merge: of [rowId], laid of [layers] — each the
/// cut holding one of the cels it is made of, alone and as it is, drawn at
/// its first frame — bottom → top.
typedef BlockMergePicture = ({
  LayerId rowId,
  FrameId frameId,
  List<Cut> layers,
});

/// The blocks ONE press of MERGE takes of a band — what lights its button
/// and what the press plans from ([planBlockMerge]), as [LayerMergeTaking]
/// is for rows.
final class BlockMergeTaking {
  BlockMergeTaking._(this.cut, this._starts);

  /// The cut it was taken of.
  final Cut cut;

  /// Each row it merges, in the cut's order, and its blocks' starts.
  final Map<Layer, List<int>> _starts;
}

/// What a press of MERGE takes of [cut]'s blocks starting at
/// [blockStarts], by row — null where no row merges any.
///
/// A row passes over as a merge of the cut's own rows passes it over
/// ([_standsDown]) — a conte row among them, as every one was before
/// I-78-Q20, which answered the merge of rows — and so does a row with one
/// block in the band, or none. A synced attach row owns no blocks of its
/// own: it merges as its base does.
BlockMergeTaking? takeBlocksToMerge({
  required Cut cut,
  required Map<LayerId, List<int>> blockStarts,
  required bool Function(Layer row) isLinked,
}) {
  final starts = {
    for (final row in cut.layers)
      if ([...?blockStarts[row.id]]..sort() case final starts
          when starts.length > 1 &&
              _isPicture(row) &&
              !isSyncedAttachedLayer(row) &&
              !_standsDown(row, cut.layers, isLinked, ofTheConte: false))
        row: starts,
  };
  return starts.isEmpty ? null : BlockMergeTaking._(cut, starts);
}

/// What a press makes of [taking]; [mintFrameId] names each new cel.
BlockMergePlan planBlockMerge(
  BlockMergeTaking taking, {
  required FrameId Function(LayerId row) mintFrameId,
}) {
  final cut = taking.cut;
  final rows = <Layer>[];
  final pictures = <BlockMergePicture>[];
  for (final MapEntry(key: row, value: starts) in taking._starts.entries) {
    final merged = _blocksMerged(cut, row, starts, mintFrameId(row.id));
    rows.add(merged.row);
    pictures.add(merged.picture);
    for (final rider in attachedLayersOf(row.id, cut.layers)) {
      if (isSyncedAttachedLayer(rider)) {
        final ridden = _riderMerged(cut, rider, merged);
        rows.add(ridden.row);
        pictures.addAll(ridden.pictures);
      }
    }
  }
  return BlockMergePlan._(cut: cut, rows: rows, pictures: pictures);
}

/// One row's blocks made one: the row after, the cels the run showed —
/// leftmost first, each once — those of them the row lets go, and the new
/// cel's picture.
typedef _BlocksMerged = ({
  Layer row,
  List<FrameId> cels,
  Set<FrameId> gone,
  BlockMergePicture picture,
});

/// [row]'s blocks at [starts] made one block over the new cel [celId].
_BlocksMerged _blocksMerged(
  Cut cut,
  Layer row,
  List<int> starts,
  FrameId celId,
) {
  final blocks = [for (final start in starts) row.timeline[start]!];
  final runEnd = starts.last + blocks.last.length!;
  final cels = [
    ...{for (final block in blocks) block.frameId!},
  ];
  final timeline = ghostFreeTimeline(row)
    ..removeWhere((index, _) => index >= starts.first && index < runEnd)
    ..[starts.first] = TimelineExposure.drawing(
      celId,
      length: runEnd - starts.first,
      startEdge: _markKept(blocks, TimelineRunEdgeSide.start),
      endEdge: _markKept(blocks, TimelineRunEdgeSide.end),
    );
  final shown = {
    for (final exposure in timeline.values)
      if (exposure.isDrawing) exposure.frameId,
  };
  final gone = {
    for (final cel in cels)
      if (!shown.contains(cel)) cel,
  };
  return (
    row: row.copyWith(
      frames: _celsAfter(row, gone, (
        id: celId,
        length: runEnd - starts.first,
        name: row.frameById(cels.first)?.name,
      )),
      timeline: timeline,
      // A cel that goes takes its sounds with it (REC1-A).
      audioClips: [
        for (final clip in row.audioClips)
          if (!gone.contains(clip.frameId)) clip,
      ],
    ),
    cels: cels,
    gone: gone,
    picture: (
      rowId: row.id,
      frameId: celId,
      layers: [for (final cel in cels.reversed) _celAlone(cut, row, cel)],
    ),
  );
}

/// [rider] as its base's blocks [merged] leaves it: a mirror of the new
/// cel laid of its own for the run's, and its mirrors of the cels the base
/// lets go gone with them.
({Layer row, List<BlockMergePicture> pictures}) _riderMerged(
  Cut cut,
  Layer rider,
  _BlocksMerged merged,
) {
  final baseCel = merged.picture.frameId;
  final celId = attachedMirrorCelId(rider.id, baseCel);
  final laid = [
    for (final cel in {
      for (final cel in merged.cels) ?rider.baseFrameLinks[cel],
    })
      if (rider.frameById(cel) != null) cel,
  ];
  final links = {
    for (final link in rider.baseFrameLinks.entries)
      if (!merged.gone.contains(link.key)) link.key: link.value,
  };
  final unlinked = {
    for (final cel in merged.gone) ?rider.baseFrameLinks[cel],
  }.difference({...links.values});
  return (
    row: rider.copyWith(
      frames: _celsAfter(rider, unlinked, (
        id: celId,
        length: 1,
        name: switch (rider.baseFrameLinks[merged.cels.first]) {
          final leftmost? => rider.frameById(leftmost)?.name,
          null => null,
        },
      )),
      baseFrameLinks: {...links, baseCel: celId},
    ),
    pictures: [
      if (laid.isNotEmpty)
        (
          rowId: rider.id,
          frameId: celId,
          layers: [
            for (final cel in laid.reversed) _celAlone(cut, rider, cel),
          ],
        ),
    ],
  );
}

/// The [side] mark the one block [blocks] become carries: the mode of the
/// carrier nearest that edge — the one a run glued of runs keeps
/// ([TimelineRunEdgeMark]) — and the bound one of them claimed, so a hold
/// set before frames were glued on past it holds on.
TimelineRunEdgeMark _markKept(
  List<TimelineExposure> blocks,
  TimelineRunEdgeSide side,
) {
  final marks = [for (final block in blocks) block.edgeMark(side)];
  final inward = side == TimelineRunEdgeSide.end ? marks.reversed : marks;
  return TimelineRunEdgeMark(
    mode: inward.map((mark) => mark.mode).nonNulls.firstOrNull,
    bound: marks.any((mark) => mark.bound),
  );
}

/// [row]'s cels less those [going], and after them [made] — the one a
/// block merge makes, [made]'s length long — named as [made]'s name is
/// among the ones kept.
List<Frame> _celsAfter(
  Layer row,
  Set<FrameId> going,
  ({FrameId id, int length, String? name}) made,
) {
  final kept = [
    for (final cel in row.frames)
      if (!going.contains(cel.id)) cel,
  ];
  return [
    ...kept,
    Frame(
      id: made.id,
      duration: made.length,
      name: _nameKept(made.name, kept),
      strokes: const [],
    ),
  ];
}

/// [name] as a new cel takes it among the cels [kept]: its printed number
/// ([celNumberOf]), with the tail an attach row takes where one of them
/// wears that already (Q10).
String? _nameKept(String? name, List<Frame> kept) {
  final shown = celNumberOf(name);
  if (shown == null) {
    return null;
  }
  return _tailClearOf({for (final cel in kept) ?celNumberOf(cel.name)}, shown);
}

/// [cut] holding [cel] of [row] alone and as it is — no look of the row's,
/// no folder over it — shown at its first frame.
Cut _celAlone(Cut cut, Layer row, FrameId cel) => cut.copyWith(
  layers: [
    Layer(
      id: row.id,
      name: row.name,
      kind: row.kind,
      frames: [row.frameById(cel)!],
      timeline: {0: TimelineExposure.drawing(cel, length: 1)},
    ),
  ],
);
