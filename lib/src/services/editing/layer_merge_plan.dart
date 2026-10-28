import '../../models/attached_layer_resolve.dart' show attachedLayersOf;
import '../../models/cut.dart';
import '../../models/frame.dart';
import '../../models/frame_id.dart';
import '../../models/layer.dart';
import '../../models/layer_blend_mode.dart';
import '../../models/layer_folder.dart';
import '../../models/layer_id.dart';
import '../../models/layer_kind.dart';
import '../../models/layer_section_defaults.dart' show firstUnusedName;
import '../../models/movie_cel.dart' show isMovieReference;
import '../../models/timeline_coverage.dart';
import '../../models/timeline_exposure.dart';
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

/// One picture of the merged row: the cel it is, its name, and the first
/// frame it shows at — where it is baked.
typedef LayerMergePicture = ({FrameId frameId, String? name, int frameIndex});

/// What ONE press of the shared pill's MERGE makes of the rows it takes, in
/// one cut (I-78, round ①).
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
/// - Q10 「맨 위 레이어의 셀 이름 + 갈라진 곳은 꼬리 번호」 and Q11 「그 구간에
///   보이는 것 중 맨 위 행의 셀 이름」 — each picture takes the name of the
///   cel the topmost taken row shows there; a name another picture holds
///   already takes the tail an attach row takes (`firstUnusedName`).
///
/// ⚠️My calls (I-78 card, 10-28): the result stands in the folder its
/// topmost row stood in, whose look — and its parents' — lands on the result
/// after the merge as it did before, so it is not baked; the folders under
/// it are. The result's blocks are new: the marks and memos of the rows'
/// blocks do not come along, and a cel the timeline does not show is no
/// part of what the rows showed.
class LayerMergePlan {
  const LayerMergePlan._({
    required this.result,
    required this.baked,
    required this.pictures,
    required this.layersAfter,
    required this.changes,
  });

  /// The row the merge leaves — its cels named, their pictures still to be
  /// baked from [baked] at each picture's frame.
  final Layer result;

  /// The cut each picture is baked from: the taken rows alone, every one
  /// shown, under the folders whose look the result leaves behind.
  final Cut baked;

  final List<LayerMergePicture> pictures;

  /// The cut's rows once the merge is done.
  final List<Layer> layersAfter;

  final Set<LayerMergeChange> changes;
}

/// [cut]'s rows a press of MERGE takes from [selected], as the plan of
/// what it makes of them — or null when it takes nothing it can merge: one
/// picture row alone, and no folder.
///
/// A row that paints no drawing of its own is no part of a picture, and is
/// passed over (Q4's memo: 「불가능한것들은 자연스럽게 무시」). So is a row
/// this round does not merge yet ([_standsDown]) — and a folder that holds
/// one, whose rows cannot be taken apart from it.
///
/// [revisionOf] says what each cel holds as the composite signature reads
/// it; [mintFrameId] names each new cel of the result.
LayerMergePlan? planLayerMerge({
  required Cut cut,
  required Set<LayerId> selected,
  required BrushFrameRevisionResolver revisionOf,
  required FrameId Function() mintFrameId,
  required bool Function(Layer row) isLinked,
}) {
  final index = LayerFolderIndex(cut.layers);
  bool standsDown(Layer row) => _standsDown(row, cut.layers, isLinked);
  final taken = <LayerId>{};
  final foldersTaken = <LayerId>{};
  Layer? anchor;
  for (final row in cut.layers) {
    if (!selected.contains(row.id) || taken.contains(row.id)) {
      continue;
    }
    if (row.kind.groupsLayers) {
      final under = index.subtreeMembersOf(row.id);
      if (!under.any(_isPicture) || under.any(standsDown)) {
        continue;
      }
      foldersTaken.add(row.id);
      taken
        ..add(row.id)
        ..addAll([
          for (final member in under)
            if (member.kind.composites) member.id,
        ]);
    } else if (_isPicture(row) && !standsDown(row)) {
      taken.add(row.id);
    } else {
      continue;
    }
    // The stack runs bottom → top: the last row taken is the topmost.
    anchor = row;
  }
  final pictureRows = [
    for (final row in cut.layers)
      if (taken.contains(row.id) && _isPicture(row)) row,
  ];
  if (anchor == null || (foldersTaken.isEmpty && pictureRows.length < 2)) {
    return null;
  }
  final over = {
    for (final folder in index.ancestryOf(anchor.folderId)) folder.id,
  };
  final baked = _bakedCut(cut, index, taken, over);
  final pictures = _picturesOf(
    cut,
    baked,
    pictureRows,
    revisionOf: revisionOf,
    mintFrameId: mintFrameId,
  );
  final result = _resultRow(anchor, pictures);
  return LayerMergePlan._(
    result: result,
    baked: baked,
    pictures: [
      for (final picture in pictures)
        (
          frameId: picture.frameId,
          name: picture.name,
          frameIndex: picture.spans.first.start,
        ),
    ],
    layersAfter: _layersAfter(cut, index, taken, foldersTaken, result),
    changes: _changesOf(cut, index, taken, pictureRows, anchor, over),
  );
}

/// A row whose cels hold artwork — "a real drawing row"
/// ([LayerKind.isDrawingCel]).
bool _isPicture(Layer row) => row.kind.isDrawingCel;

/// The rows round ① passes over until the round that merges them comes —
/// the card's order (I-78, 10-28), not a law of the verb:
/// - an attach row and a row others ride (round ②, Q8),
/// - a 겸용 row and a conte row, whose cels or structure another cut shares
///   (round ④, Q9 · Q12),
/// - a movie, decoded frame by frame where it shows,
/// - a direction block, whose direction is no picture to bake.
bool _standsDown(
  Layer row,
  List<Layer> layers,
  bool Function(Layer row) isLinked,
) =>
    isAttachedLayer(row) ||
    attachedLayersOf(row.id, layers).isNotEmpty ||
    isLinked(row) ||
    row.conteKey != null ||
    isMovieReference(row) ||
    row.timeline.values.any((exposure) => exposure.instruction != null);

/// [cut] as each picture is baked from it: the [taken] rows and the
/// folders above them that the result does not stand in ([over] are the
/// ones it does), every one of them shown (Q7), each pointing at the
/// nearest folder kept above it.
Cut _bakedCut(
  Cut cut,
  LayerFolderIndex index,
  Set<LayerId> taken,
  Set<LayerId> over,
) {
  final above = <LayerId>{
    for (final row in cut.layers)
      if (taken.contains(row.id))
        for (final folder in index.ancestryOf(row.folderId))
          if (!over.contains(folder.id)) folder.id,
  };
  final kept = {...taken, ...above};
  LayerId? keptParent(LayerId? folderId) {
    for (final folder in index.ancestryOf(folderId)) {
      if (kept.contains(folder.id)) {
        return folder.id;
      }
    }
    return null;
  }

  return cut.copyWith(
    layers: [
      for (final row in cut.layers)
        if (kept.contains(row.id))
          row.copyWith(isVisible: true, folderId: keptParent(row.folderId)),
    ],
  );
}

/// One picture of the result while it is planned: its cel, its name and
/// every run of frames that shows it.
typedef _Picture = ({
  FrameId frameId,
  String? name,
  List<CutFrameCompositeSpan> spans,
});

/// The pictures [baked] shows over every frame a [pictureRows] block covers
/// — one per signature, in the order they first show — each named after
/// the cel the topmost row shows where it first shows (Q10 · Q11).
List<_Picture> _picturesOf(
  Cut cut,
  Cut baked,
  List<Layer> pictureRows, {
  required BrushFrameRevisionResolver revisionOf,
  required FrameId Function() mintFrameId,
}) {
  final blocks = [
    for (final row in pictureRows) ...drawingBlocks(row.timeline),
  ];
  if (blocks.isEmpty) {
    return const [];
  }
  final spans = computeCutFrameCompositeSpans(
    cut: baked,
    frames: (
      startIndex: blocks.map((block) => block.startIndex).reduce(_min),
      endIndexExclusive: blocks
          .map((block) => block.endIndexExclusive)
          .reduce(_max),
    ),
    revisionOf: revisionOf,
  );
  final bySignature = <CutFrameCompositeSignature, _Picture>{};
  final heldNames = <String>{};
  for (final span in spans) {
    if (span.signature.nodes.isEmpty) {
      continue; // Nothing shows: the result is empty here too.
    }
    final known = bySignature[span.signature];
    if (known != null) {
      known.spans.add(span);
      continue;
    }
    final name = switch (_nameShownAt(cut, pictureRows, span.start)) {
      final shown? => firstUnusedName(
        heldNames,
        (index) => index == 1 ? shown : '$shown-$index',
      ),
      null => null,
    };
    if (name != null) {
      heldNames.add(name);
    }
    bySignature[span.signature] = (
      frameId: mintFrameId(),
      name: name,
      spans: [span],
    );
  }
  return bySignature.values.toList();
}

/// The name of the cel the topmost of [pictureRows] that shows one at
/// [frameIndex] shows there — null where its cel is unnamed, or none shows.
String? _nameShownAt(Cut cut, List<Layer> pictureRows, int frameIndex) {
  for (final row in pictureRows.reversed) {
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

/// The merged row: [anchor]'s name, place and label over [pictures], and
/// nothing of the look it was baked with (Q6) — a picture row, a folder or
/// an image that now holds more than one picture becoming a drawing row.
Layer _resultRow(Layer anchor, List<_Picture> pictures) {
  final kind =
      anchor.kind.isDrawingCel &&
          !(anchor.kind.holdsSingleCel && pictures.length > 1)
      ? anchor.kind
      : LayerKind.animation;
  return Layer(
    id: anchor.id,
    name: anchor.name,
    kind: kind,
    mark: anchor.mark,
    onTimesheet: anchor.onTimesheet,
    folderId: anchor.folderId,
    frames: [
      for (final picture in pictures)
        Frame(
          id: picture.frameId,
          duration: picture.spans.first.length,
          name: picture.name,
          strokes: const [],
        ),
    ],
    timeline: {
      for (final picture in pictures)
        for (final span in picture.spans)
          span.start: TimelineExposure.drawing(
            picture.frameId,
            length: span.length,
          ),
    },
  );
}

/// [cut]'s rows once [result] stands where its row stood and the rest of
/// what was [taken] is gone — a row a taken folder held that was not taken
/// stands in the folder above it now.
List<Layer> _layersAfter(
  Cut cut,
  LayerFolderIndex index,
  Set<LayerId> taken,
  Set<LayerId> foldersTaken,
  Layer result,
) {
  LayerId? standingParent(LayerId? folderId) {
    for (final folder in index.ancestryOf(folderId)) {
      if (!foldersTaken.contains(folder.id)) {
        return folder.id;
      }
    }
    return null;
  }

  // The very row where its folder stays: the stack's rows are compared by
  // instance downstream, and a copy of one is a change to it.
  Layer standing(Layer row) => foldersTaken.contains(row.folderId)
      ? row.copyWith(folderId: standingParent(row.folderId))
      : row;

  return [
    for (final row in cut.layers)
      if (row.id == result.id)
        result
      else if (!taken.contains(row.id))
        standing(row),
  ];
}

/// Why the result may show otherwise than the [taken] rows did
/// ([LayerMergeChange]).
Set<LayerMergeChange> _changesOf(
  Cut cut,
  LayerFolderIndex index,
  Set<LayerId> taken,
  List<Layer> pictureRows,
  Layer anchor,
  Set<LayerId> over,
) {
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
