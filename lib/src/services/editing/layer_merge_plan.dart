import '../../models/attached_layer_resolve.dart'
    show attachedLayersOf, attachedMirrorCelId, isSyncedAttachedLayer;
import '../../models/cut.dart';
import '../../models/frame.dart';
import '../../models/frame_id.dart';
import '../../models/layer.dart';
import '../../models/layer_blend_mode.dart';
import '../../models/layer_folder.dart';
import '../../models/layer_id.dart';
import '../../models/layer_kind.dart';
import '../../models/layer_section_defaults.dart' show firstUnusedName;
import '../../models/timeline_coverage.dart';
import '../../models/timeline_exposure.dart';
import '../../models/timeline_repeat.dart' show ghostFreeTimeline;
import '../../models/timeline_run_behavior.dart';
import '../cut_frame_composite_plan.dart'
    show clipBaseOf, clipsToLayerBelow, exposedCelIdAt;
import '../playback/cut_frame_composite_signature.dart';
import '../playback/cut_frame_composite_spans.dart';

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
}

/// One picture a merge bakes: the cel of the row it lands on, and the cut
/// and frame it is drawn from.
typedef LayerMergePicture = ({
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
///   and not taken itself, rides [result] after ([riders]): its cels are
///   baked anew as it showed, wearing what it wore of its base — the base's
///   pose, keys and fx short of the cel number (「어태치 레이어는 주인과 같이
///   굽는다」, 07-21) — and of the folders it leaves. A SYNCED row's
///   pictures part wherever the result's do (the answer's 「결과 행의 장이
///   나뉜 곳마다 어태치 그림도 같이 나뉨」), a FREE row's wherever its own
///   picture changes. What is its own stays on its row: its eye, its
///   strength, its blend, its clip.
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
    required this.riders,
    required this.pictures,
    required this.removed,
    required this.changes,
  });

  /// The cut it was planned of, as it was.
  final Cut cut;

  /// The row the merge leaves — its cels named, their pictures still to be
  /// baked ([pictures]).
  final Layer result;

  /// The attach rows the merge leaves riding [result], each with its new
  /// cels — their pictures, too, still to be baked.
  final List<Layer> riders;

  /// Every picture the merge's new cels are baked from: [result]'s, then
  /// each rider's.
  final List<LayerMergePicture> pictures;

  /// The rows the merge takes away, bottom → top — every row it took but
  /// the one [result] replaces.
  final List<LayerId> removed;

  final Set<LayerMergeChange> changes;

  /// The cut's rows after the merge: [removed] gone, and [result] and
  /// [riders] where the rows they replace stood.
  List<Layer> get layers {
    final gone = removed.toSet();
    final replaced = {
      result.id: result,
      for (final rider in riders) rider.id: rider,
    };
    return [
      for (final row in cut.layers)
        if (!gone.contains(row.id)) replaced[row.id] ?? row,
    ];
  }
}

/// The rows ONE press of MERGE takes of a cut — what lights its button and
/// what the press plans from ([planLayerMerge]): one taking for both, so
/// the button cannot light where the press would merge nothing.
final class LayerMergeTaking {
  LayerMergeTaking._(this.cut, this._index, this._taken, this._anchor)
    : _pictureRows = [
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
}

/// What a press of MERGE takes of [cut]'s [selected] rows — null for
/// nothing it can merge: one picture row alone, and no folder.
///
/// A row that paints no drawing of its own is no part of a picture, and is
/// passed over (Q4's memo: 「불가능한것들은 자연스럽게 무시」). So is a row
/// this round does not merge yet ([_standsDown], [_goesWith]) — and a
/// folder that holds one, whose rows cannot be taken apart from it.
///
/// A folder taken takes everything it holds: every row a folder can hold
/// is laid into its picture — the camera row moves nowhere
/// ([LayerKind.reordersInCut]), and a transition row is its track's.
/// ↩️It took only those that composite, and re-placed the rest in the
/// folder above, for rows no folder can hold.
LayerMergeTaking? takeRowsToMerge({
  required Cut cut,
  required Set<LayerId> selected,
  required bool Function(Layer row) isLinked,
}) {
  final index = LayerFolderIndex(cut.layers);
  bool standsDown(Layer row) => _standsDown(row, cut.layers, isLinked);
  // What a chosen row takes, whole or not at all: itself — or a folder,
  // everything it holds. Null for a row it cannot take.
  List<Layer>? reachOf(Layer row) {
    if (!row.kind.groupsLayers) {
      return _isPicture(row) && !standsDown(row) ? [row] : null;
    }
    final under = index.subtreeMembersOf(row.id);
    return under.any(_isPicture) && !under.any(standsDown)
        ? [row, ...under]
        : null;
  }

  final reaches = {
    for (final row in cut.layers)
      if (selected.contains(row.id)) row.id: ?reachOf(row),
  };
  // Bottom → top: the last is the topmost.
  var heads = [
    for (final row in cut.layers)
      if (reaches.containsKey(row.id)) row,
  ];
  // A row that goes only with others ([_goesWith]) lets go of what took it,
  // which can let go of what it went with: until nothing more lets go.
  while (heads.isNotEmpty) {
    final taken = {
      for (final head in heads)
        for (final row in reaches[head.id]!) row.id,
    };
    final anchor = heads.last;
    final kept = [
      for (final head in heads)
        if (reaches[head.id]!.every(
          (row) => _goesWith(row, cut.layers, taken: taken, anchor: anchor),
        ))
          head,
    ];
    if (kept.length == heads.length) {
      break;
    }
    heads = kept;
  }
  if (heads.isEmpty) {
    return null;
  }
  final taking = LayerMergeTaking._(cut, index, {
    for (final head in heads)
      for (final row in reaches[head.id]!) row.id,
  }, heads.last);
  return heads.any((head) => head.kind.groupsLayers) ||
          taking._pictureRows.length > 1
      ? taking
      : null;
}

/// What a press makes of [taking].
///
/// [revisionOf] says what each cel holds as the composite signature reads
/// it; [mintFrameId] names each new cel of a row.
LayerMergePlan planLayerMerge(
  LayerMergeTaking taking, {
  required BrushFrameRevisionResolver revisionOf,
  required FrameId Function(LayerId row) mintFrameId,
}) {
  final LayerMergeTaking(
    :cut,
    _taken: taken,
    _anchor: anchor,
    _pictureRows: pictureRows,
    _riders: riders,
  ) = taking;
  final over = {
    for (final folder in taking._index.ancestryOf(anchor.folderId)) folder.id,
  };
  final takenRows = [
    for (final row in cut.layers)
      if (taken.contains(row.id)) _shown(row),
  ];
  final folders = _foldersLeft(taking, over, takenRows);
  final baked = _cutWith(taking, folders, takenRows);
  // The result parts wherever a synced rider's picture does too: each
  // rides the result's cels one for one.
  final runs = _runsByPicture(
    _cutWith(taking, folders, [
      ...takenRows,
      for (final rider in riders)
        if (isSyncedAttachedLayer(rider)) _riding(rider),
    ]),
    pictureRows,
    revisionOf,
  );
  final cels = _celsOf(runs, baked, pictureRows, (_) => mintFrameId(anchor.id));
  final result = (row: _resultRow(anchor, cels), runs: runs, cels: cels);
  final minting = (revisionOf: revisionOf, mintFrameId: mintFrameId);
  final ridden = [
    for (final rider in riders)
      _riderBaked(
        rider,
        _aloneWithItsBase(taking, over, rider),
        result,
        minting,
      ),
  ];
  return LayerMergePlan._(
    cut: cut,
    result: result.row,
    riders: [for (final rider in ridden) rider.row],
    pictures: [
      ..._picturesOf(result.row, cels, baked),
      for (final rider in ridden) ...rider.pictures,
    ],
    removed: [
      for (final row in cut.layers)
        if (taken.contains(row.id) && row.id != anchor.id) row.id,
    ],
    changes: _changesOf(taking, over),
  );
}

/// A row whose cels hold artwork — "a real drawing row"
/// ([LayerKind.isDrawingCel]).
bool _isPicture(Layer row) => row.kind.isDrawingCel;

/// The rows this round passes over until the round that merges them comes —
/// the card's order (I-78, 10-28), not a law of the verb:
/// - a 겸용 row and a conte row, whose cels or structure another cut shares
///   (round ④, Q9 · Q12),
/// - a reference row, whose picture is its file's, laid whole past the
///   wall (F-374-Q8) where no picture of the screen reaches — rasterized,
///   it merges as every drawing does (my call, put to the user as
///   I-78-Q15),
/// - a direction block, whose direction is no picture to bake (my call,
///   put to the user as I-78-Q16),
/// - and a row an attach row that stands down rides: the rider would ride
///   the result, its cels baked anew.
///
/// ↩️Round ① passed over every attach row and every row one rides; round ②
/// takes them (Q8), short of what [_goesWith] still holds back.
bool _standsDown(
  Layer row,
  List<Layer> layers,
  bool Function(Layer row) isLinked,
) =>
    isLinked(row) ||
    row.conteKey != null ||
    row.mediaReference != null ||
    row.timeline.values.any((exposure) => exposure.instruction != null) ||
    attachedLayersOf(
      row.id,
      layers,
    ).any((rider) => _standsDown(rider, layers, isLinked));

/// Whether [row] goes with the rows [taken] holds, [anchor] the topmost of
/// those chosen — what round ② still holds back until the card's open
/// questions are answered:
/// - an attach row goes only with its base (I-78-Q14: one taken without it
///   would be baked wearing a base the result does not hold, and stand
///   where the result cannot when it is the topmost),
/// - and a row an attach row rides that is not taken goes only as the
///   topmost row chosen, its riders where they stand (I-78-Q13: under a
///   row taken above its base, a rider on the upper side stands where no
///   rider of the result can).
bool _goesWith(
  Layer row,
  List<Layer> layers, {
  required Set<LayerId> taken,
  required Layer anchor,
}) {
  if (row.attachedToLayerId case final baseId?) {
    return taken.contains(baseId);
  }
  return row.id == anchor.id ||
      attachedLayersOf(
        row.id,
        layers,
      ).every((rider) => taken.contains(rider.id));
}

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

/// The runs of [shown] over every frame a block of [rows] covers, gathered
/// by the picture they show — one list per picture, in the order they
/// first show. A run that shows nothing is none: the row is empty there.
List<List<CutFrameCompositeSpan>> _runsByPicture(
  Cut shown,
  List<Layer> rows,
  BrushFrameRevisionResolver revisionOf,
) {
  final blocks = [for (final row in rows) ...drawingBlocks(row.timeline)];
  if (blocks.isEmpty) {
    return const [];
  }
  final spans = computeCutFrameCompositeSpans(
    cut: shown,
    frames: (
      startIndex: blocks.map((block) => block.startIndex).reduce(_min),
      endIndexExclusive: blocks
          .map((block) => block.endIndexExclusive)
          .reduce(_max),
    ),
    revisionOf: revisionOf,
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
  final cels = <_Cel>[];
  for (final (picture, spans) in runs.indexed) {
    final name = switch (_nameShownAt(shown, rows, spans.first.start)) {
      final shown? => firstUnusedName(
        heldNames,
        (index) => index == 1 ? shown : '$shown-$index',
      ),
      null => null,
    };
    if (name != null) {
      heldNames.add(name);
    }
    cels.add((frameId: mintFrameId(picture), name: name, spans: spans));
  }
  return cels;
}

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

/// The pictures [cels] of [row] are baked from: each drawn of [from] at the
/// first frame it shows.
List<LayerMergePicture> _picturesOf(Layer row, List<_Cel> cels, Cut from) => [
  for (final cel in cels)
    (
      rowId: row.id,
      frameId: cel.frameId,
      from: from,
      frameIndex: cel.spans.first.start,
    ),
];

/// The merged row: [anchor]'s name, place and label over [cels], and
/// nothing of the look it was baked with (Q6).
Layer _resultRow(Layer anchor, List<_Cel> cels) => Layer(
  id: anchor.id,
  name: anchor.name,
  kind: _kindHolding(anchor.kind, cels),
  mark: anchor.mark,
  onTimesheet: anchor.onTimesheet,
  folderId: anchor.folderId,
  frames: _framesOf(cels),
  timeline: _timelineOf(cels),
);

/// The kind a row of [kind] is once it holds [cels]: a picture row's own —
/// a folder or an image that now holds more than one picture becoming a
/// drawing row.
LayerKind _kindHolding(LayerKind kind, List<_Cel> cels) =>
    kind.isDrawingCel && !(kind.holdsSingleCel && cels.length > 1)
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
        for (final picture in _picturesOf(rider, cels, alone))
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
      kind: _kindHolding(rider.kind, cels),
      frames: _framesOf(cels),
      timeline: _timelineOf(cels),
    ),
    pictures: _picturesOf(rider, cels, alone),
  );
}

/// Why the result may show otherwise than the rows [taking] takes did
/// ([LayerMergeChange]) — [over] being the folders it stands in.
Set<LayerMergeChange> _changesOf(LayerMergeTaking taking, Set<LayerId> over) {
  final LayerMergeTaking(
    :cut,
    _index: index,
    _taken: taken,
    _anchor: anchor,
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
  final looksOver = index.ancestryOf(anchor.folderId).any(_laysALook);
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
/// ⚠️My calls, put to the user (I-78-Q17 · Q18): the leftmost cel lies on
/// top, as the topmost row's picture does in a merge of rows; the run's
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
/// A row passes over as a merge of rows passes it over ([_standsDown]),
/// and so does a row with one block in the band, or none. A synced attach
/// row owns no blocks of its own: it merges as its base does.
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
              !_standsDown(row, cut.layers, isLinked))
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
  final kept = [
    for (final cel in row.frames)
      if (!gone.contains(cel.id)) cel,
  ];
  return (
    row: row.copyWith(
      frames: [
        ...kept,
        Frame(
          id: celId,
          duration: runEnd - starts.first,
          name: _nameKept(row.frameById(cels.first)?.name, kept),
          strokes: const [],
        ),
      ],
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
  final kept = [
    for (final cel in rider.frames)
      if (!unlinked.contains(cel.id)) cel,
  ];
  return (
    row: rider.copyWith(
      frames: [
        ...kept,
        Frame(
          id: celId,
          duration: 1,
          name: _nameKept(switch (rider.baseFrameLinks[merged.cels.first]) {
            final leftmost? => rider.frameById(leftmost)?.name,
            null => null,
          }, kept),
          strokes: const [],
        ),
      ],
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

/// [name] as a new cel takes it among the cels [kept]: its printed number
/// ([celNumberOf]), with the tail an attach row takes where one of them
/// wears that already (Q10).
String? _nameKept(String? name, List<Frame> kept) {
  final shown = celNumberOf(name);
  if (shown == null) {
    return null;
  }
  final held = {for (final cel in kept) ?celNumberOf(cel.name)};
  return firstUnusedName(
    held,
    (index) => index == 1 ? shown : '$shown-$index',
  );
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
