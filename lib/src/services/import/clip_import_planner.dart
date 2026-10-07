/// PURE construction of the project a CLIP STUDIO PAINT file opens as. The
/// door reads the bytes and bakes the pictures; this decides SHAPE, so every
/// rule below is testable on a document a test builds — the split
/// `planTvpImport` and `planPsdExpansion` use.
///
/// The shape is the user's (보드 `csp-clip-import-analysis`, 10-07 「상담
/// 끝」, and 「클튜랑 같게하자」 — structure and look as the file opens in
/// CLIP STUDIO):
///
/// * **Every timeline a cut, all of them 겸용 cuts** (Q4: 「전부 겸용컷으로
///   들여옴 … 클튜는 레이어랑 타임라인이랑 나뉘어있어서 … 겸용컷이랑 완벽히
///   동일한 상태」): one bank per row shared by every cut, the timing each
///   cut's own — the state `CreateLinkedCutCommand` leaves.
/// * **Folders outside the cels are folder rows, structure as it is** (Q6):
///   nesting, name, eye, opacity, blend, and the fold (Q3: 「접힌 폴더는
///   접힌상태로 들여오도록. 이건 tvp든 뭐든 임포트할때의 기본」).
/// * **An animation folder is always a folder row** (Q7) holding a BASE row
///   — the top visible layer of every cel (Q2), one cel per CLIP STUDIO cel,
///   named as there — and BELOW it the attach rows the cels' other layers
///   make, by their place from the top, synced to the base. Hidden layers
///   come too (Q3: 「모든 레이어를 가져오는게 목표」), as attach rows in a
///   folder whose eye is off.
/// * **The look is kept by baking** (Q5, answered twice: 「최대한 보기
///   같은걸 원한다」): a row's opacity is its strongest cel's, and a weaker
///   cel's picture is baked fainter by the difference. A blend cannot be
///   baked, so a line of cels that blends two ways is two rows — the same
///   law for hidden layers (「법 통일」).
/// * A layer outside the cels is an image row (「단일그림은 … 그에 대응하는
///   이미지레이어로」). A cel placed on no timeline is not imported
///   (「임포트 안해도 상관없고」), and what there is no place for is said,
///   never dropped quietly.
library;

import 'dart:collection';
import 'dart:math' as math;

import '../../models/attached_layer_resolve.dart' show attachedMirrorCelId;
import '../../models/attached_mode.dart';
import '../../models/attached_placement.dart';
import '../../models/canvas_size.dart';
import '../../models/covering_image_normalize.dart';
import '../../models/cut.dart';
import '../../models/cut_id.dart';
import '../../models/frame.dart';
import '../../models/frame_id.dart';
import '../../models/import/import_warning.dart';
import '../../models/layer.dart';
import '../../models/layer_blend_mode.dart';
import '../../models/layer_folder.dart' show createFolderLayer;
import '../../models/layer_id.dart';
import '../../models/layer_kind.dart';
import '../../models/layer_link_registry.dart';
import '../../models/timeline_exposure.dart';
import '../../models/timeline_repeat.dart' show rederiveRunBehaviors;
import '../../models/track_id.dart';
import '../editing/default_cut_helpers.dart';
import 'clip_document.dart';
import 'media_import_planner.dart' show ImportIdMint;

/// What a CLIP STUDIO composite number blends as here — the program's own
/// menu order (memory `csp-clip-format-notes` §4; 0 · 2 · 30 measured on
/// the samples, the rest from the table MoArt reads by). A number with no
/// formula here is absent, and arrives as normal and said — the .tvpp and
/// PSD law.
const Map<int, LayerBlendMode> clipBlendModes = {
  0: LayerBlendMode.normal,
  1: LayerBlendMode.darken,
  2: LayerBlendMode.multiply,
  3: LayerBlendMode.colorBurn,
  7: LayerBlendMode.lighten,
  8: LayerBlendMode.screen,
  9: LayerBlendMode.colorDodge,
  11: LayerBlendMode.add,
  14: LayerBlendMode.overlay,
  15: LayerBlendMode.softLight,
  16: LayerBlendMode.hardLight,
  21: LayerBlendMode.difference,
  22: LayerBlendMode.exclusion,
  30: LayerBlendMode.passThrough,
};

/// The composite a CLIP STUDIO folder passes its layers through with.
const int _passThrough = 30;

/// `LayerOpacity` at 100%.
const double _fullOpacity = 256;

/// One picture of the file to bake into a cel.
final class ClipCelBake {
  const ClipCelBake({
    required this.cutId,
    required this.layerId,
    required this.frameId,
    required this.source,
    required this.alpha,
  });

  /// The cel's address — the CANONICAL member's, the first cut's row, which
  /// keys the one bank every 겸용 cut shares.
  final CutId cutId;
  final LayerId layerId;
  final FrameId frameId;

  /// The layer whose picture this is — its render, or the original of a
  /// dropped picture, standing where it stands.
  final ClipLayer source;

  /// What the picture's alpha is multiplied by: below 1 where the cel was
  /// fainter than its row's opacity (Q5 — 「낮은채로 구워버려서」).
  final double alpha;
}

/// The project a file opens as, before a pixel is read.
final class ClipImportPlan {
  const ClipImportPlan({
    required this.cuts,
    required this.links,
    required this.bakes,
    required this.fps,
    required this.warnings,
  });

  /// One per timeline, in the file's order; one for a file with none.
  final List<Cut> cuts;

  /// One link group per row, across the cuts — none for a single cut.
  final LayerLinkRegistry links;
  final List<ClipCelBake> bakes;

  /// The first timeline's rate; null for a file with no timeline.
  final int? fps;
  final List<ImportWarning> warnings;
}

/// Plans the project [document] opens as.
///
/// [name] names the one cut of a file with no timeline. [hiddenFolderName]
/// is the program language's word for the folder hidden layers stand in.
/// Link members carry [trackId], the track the cuts land on.
ClipImportPlan planClipImport({
  required ClipDocument document,
  required String name,
  required String hiddenFolderName,
  required TrackId trackId,
  required ImportIdMint mint,
}) {
  final warnings = <ImportWarning>[
    for (final detail in document.warnings)
      ImportWarning(
        'clipRead',
        'Part of the file could not be followed: {detail}',
        {'detail': detail},
      ),
  ];
  final views = document.timelines.isEmpty
      ? [_CutView.still(name)]
      : [
          for (var i = 0; i < document.timelines.length; i += 1)
            _CutView.of(document.timelines[i], i),
        ];
  final cutIds = [for (final _ in views) mint.nextCutId()];
  final planner = _Planner(
    views: views,
    mint: mint,
    hiddenFolderName: hiddenFolderName,
    warnings: warnings,
  )..walk(document.root, null, const []);
  final canvas = CanvasSize(width: document.width, height: document.height);
  final cuts = [
    for (var i = 0; i < views.length; i += 1)
      cutWithCoveringImageRows(
        importedCut(
          defaultCut: createDefaultCut(
            cutId: cutIds[i],
            name: views[i].name,
            layerId: mint.nextLayerId(),
            canvasSize: canvas,
          ),
          layers: [for (final row in planner.rows) row.layerIn(i, views[i])],
          duration: views[i].duration,
        ),
        drawnFrameCount: views[i].duration,
      ),
  ];
  return ClipImportPlan(
    cuts: cuts,
    links: _linksOf(planner.rows, cutIds, trackId),
    bakes: [
      for (final bake in planner.bakes)
        ClipCelBake(
          cutId: cutIds.first,
          layerId: bake.row.ids.first,
          frameId: bake.frameId,
          source: bake.source,
          alpha: bake.alpha,
        ),
    ],
    fps: _fpsOf(document, warnings),
    warnings: warnings,
  );
}

/// The project's rate: the first timeline's. CLIP STUDIO counts whole
/// frames per second (유저 10-06: 「클튜는 소수점 fps가 불가능해」); a
/// project has one rate, so timelines that differ are said.
int? _fpsOf(ClipDocument document, List<ImportWarning> warnings) {
  final timelines = document.timelines;
  if (timelines.isEmpty) {
    return null;
  }
  final fps = timelines.first.fps.round();
  if (timelines.any((timeline) => timeline.fps.round() != fps)) {
    warnings.add(
      ImportWarning(
        'clipFps',
        'The timelines run at different frame rates — the project takes '
        'the first one\'s, {fps} fps.',
        {'fps': '$fps'},
      ),
    );
  }
  return fps;
}

/// One link group per row across the cuts — and per camera row, as a 겸용
/// cut's camera is linked (F-84). Nothing to link in a single cut.
LayerLinkRegistry _linksOf(
  List<_Row> rows,
  List<CutId> cutIds,
  TrackId trackId,
) {
  if (cutIds.length < 2) {
    return LayerLinkRegistry.empty;
  }
  final memberships = <List<LayerId>>[
    for (final row in rows) row.ids,
    [for (final cutId in cutIds) cameraLayerIdForCut(cutId)],
  ];
  return LayerLinkRegistry(
    groups: [
      for (var g = 0; g < memberships.length; g += 1)
        LayerLinkGroup(
          id: 'link-${g + 1}',
          members: [
            for (var i = 0; i < cutIds.length; i += 1)
              LayerLinkMember(
                trackId: trackId,
                cutId: cutIds[i],
                layerId: memberships[g][i],
              ),
          ],
        ),
    ],
  );
}

/// How the file's tracks show in one cut: a timeline, or — for a file with
/// none — everything, throughout.
final class _CutView {
  _CutView.of(ClipTimeline this.timeline, int index)
    : name = timeline.name.isEmpty ? '${index + 1}' : timeline.name,
      duration = math.max(1, timeline.end - timeline.start);

  _CutView.still(this.name) : timeline = null, duration = defaultCutDuration;

  final ClipTimeline? timeline;
  final String name;
  final int duration;

  /// Where the timeline's frame 0 of this cut stands.
  int get start => timeline?.start ?? 0;

  ClipTrack? trackOf(ClipLayer layer) => timeline?.tracks[layer.uuid];

  /// Where every one of [layers] shows, as cut frames. A track's clips are
  /// where its layer shows; a layer the timeline holds no track for is not
  /// timed by it and shows throughout (measured: the samples' text layers
  /// have none).
  List<ClipSpan> within(List<ClipLayer> layers) {
    var spans = [(start: 0, end: duration)];
    for (final layer in layers) {
      if (trackOf(layer) case final track?) {
        spans = _overlap(spans, [
          for (final piece in track.pieces) ?inCut(piece.span),
        ]);
      }
    }
    return spans;
  }

  /// [span] in cut frames, inside the cut — null when nothing is left.
  ClipSpan? inCut(ClipSpan span) {
    final from = math.max(0, span.start - start);
    final to = math.min(duration, span.end - start);
    return to > from ? (start: from, end: to) : null;
  }
}

/// Where both [a] and [b] are.
List<ClipSpan> _overlap(List<ClipSpan> a, List<ClipSpan> b) => [
  for (final x in a)
    for (final y in b)
      if (math.min(x.end, y.end) > math.max(x.start, y.start))
        (start: math.max(x.start, y.start), end: math.min(x.end, y.end)),
];

/// A row as planned, before a cut gives it its place: [ids] holds its id in
/// every cut, the first one canonical.
sealed class _Row {
  _Row(this.parent, this.ids);

  final _FolderRow? parent;
  final List<LayerId> ids;

  Layer layerIn(int cut, _CutView view);
}

final class _FolderRow extends _Row {
  _FolderRow(
    super.parent,
    super.ids, {
    required this.name,
    required this.visible,
    required this.opacity,
    required this.blend,
    required this.collapsed,
  });

  final String name;
  final bool visible;
  final double opacity;
  final LayerBlendMode blend;
  final bool collapsed;

  @override
  Layer layerIn(int cut, _CutView view) =>
      createFolderLayer(
        id: ids[cut],
        name: name,
        parentId: parent?.ids[cut],
      ).copyWith(
        isVisible: visible,
        opacity: opacity,
        blendMode: blend,
        collapsed: collapsed,
      );
}

/// A layer outside every cel: one picture, held wherever its timeline shows
/// it.
final class _PictureRow extends _Row {
  _PictureRow(
    super.parent,
    super.ids, {
    required this.source,
    required this.folders,
    required this.frame,
    required this.blend,
  });

  final ClipLayer source;

  /// The folders above [source] — whose clips are its clips too.
  final List<ClipLayer> folders;
  final Frame frame;
  final LayerBlendMode blend;

  @override
  Layer layerIn(int cut, _CutView view) => Layer(
    id: ids[cut],
    name: source.name,
    kind: LayerKind.image,
    frames: [frame],
    // Held from the head; the covering law shapes it into the image row's
    // one cel and its hold (`cutWithCoveringImageRows`).
    timeline: view.within([...folders, source]).isEmpty
        ? const {}
        : {0: TimelineExposure.drawing(frame.id, length: view.duration)},
    isVisible: source.isShown,
    opacity: source.opacity / _fullOpacity,
    blendMode: blend,
    folderId: parent?.ids[cut],
  );
}

/// An animation folder's base: one cel per CLIP STUDIO cel, timed by each
/// cut's own timeline.
final class _BaseRow extends _Row {
  _BaseRow(
    super.parent,
    super.ids, {
    required this.folder,
    required this.folders,
    required this.bank,
    required this.opacity,
    required this.blend,
  });

  final ClipLayer folder;

  /// The folders above [folder] — whose clips cut its cels down.
  final List<ClipLayer> folders;

  /// One cel per CLIP STUDIO cel, named as there.
  final List<Frame> bank;
  final double opacity;
  final LayerBlendMode blend;

  @override
  Layer layerIn(int cut, _CutView view) => rederiveRunBehaviors(
    Layer(
      id: ids[cut],
      name: folder.name,
      frames: bank,
      timeline: _exposures(view),
      opacity: opacity,
      blendMode: blend,
      kind: LayerKind.animation,
      folderId: parent?.ids[cut],
    ),
    // A cut that has not landed owes no のりしろ (the tvp planner's word).
    drawnFrameCount: view.duration,
  );

  /// The blocks [view]'s timeline keys: each cel from its key to the next
  /// one or the end of its clip — never into the next clip — and only where
  /// the folders above show at all. A breakdown label inside a block is its
  /// dot; one on the block's own head says nothing more.
  SplayTreeMap<int, TimelineExposure> _exposures(_CutView view) {
    final out = SplayTreeMap<int, TimelineExposure>();
    final track = view.trackOf(folder);
    if (track == null) {
      return out;
    }
    final byName = {for (final cel in bank) cel.name: cel.id};
    final above = view.within(folders);
    for (final piece in track.pieces) {
      final keys = piece.cels;
      for (var k = 0; k < keys.length; k += 1) {
        final frameId = byName[keys[k].cel];
        final until = k + 1 < keys.length ? keys[k + 1].frame : piece.span.end;
        final held = view.inCut((
          start: math.max(keys[k].frame, piece.span.start),
          end: math.min(until, piece.span.end),
        ));
        if (frameId == null || held == null) {
          continue;
        }
        for (final block in _overlap([held], above)) {
          final head = block.start + view.start;
          final end = block.end + view.start;
          out[block.start] = TimelineExposure.drawing(
            frameId,
            length: block.end - block.start,
            breakdownOffsets: {
              for (final label in track.labels)
                if (label > head && label < end) label - head,
            }.toList(),
          );
        }
      }
    }
    return out;
  }
}

/// A line of the cels' other layers — below the base, synced to it: one
/// mirror cel per base cel, the always-mirror shape
/// (`cutWithReconciledAttachedMirrors`) made here rather than by the first
/// write.
final class _AttachRow extends _Row {
  _AttachRow(
    super.parent,
    super.ids, {
    required this.base,
    required this.name,
    required this.opacity,
    required this.blend,
  });

  final _BaseRow base;
  final String name;
  final double opacity;
  final LayerBlendMode blend;

  /// [frameId]'s mirror cel — under the canonical member's id, so every 겸용
  /// cut names the same one (F-278).
  FrameId mirrorOf(FrameId frameId) => attachedMirrorCelId(ids.first, frameId);

  @override
  Layer layerIn(int cut, _CutView view) => Layer(
    id: ids[cut],
    name: name,
    frames: [
      for (final cel in base.bank)
        Frame(id: mirrorOf(cel.id), duration: 1, strokes: const []),
    ],
    timeline: const {},
    opacity: opacity,
    blendMode: blend,
    kind: LayerKind.animation,
    // An attach row is born off the sheet (`addAttachedLayer`).
    onTimesheet: false,
    attachedToLayerId: base.ids[cut],
    attachedPlacement: AttachedPlacement.below,
    attachedMode: AttachedMode.synced,
    baseFrameLinks: {for (final cel in base.bank) cel.id: mirrorOf(cel.id)},
    folderId: parent?.ids[cut],
  );
}

/// One layer of one cel, as the row it lands on sees it.
final class _Leaf {
  const _Leaf({
    required this.layer,
    required this.visible,
    required this.opacity,
    required this.blend,
    required this.spread,
  });

  final ClipLayer layer;

  /// Its own eye and every folder's between it and the cel's top.
  final bool visible;

  /// Its own opacity times every folder's in the cel, 0 … 1.
  final double opacity;
  final LayerBlendMode blend;

  /// Whether a folder's opacity or blend inside the cel was handed down to
  /// it — exact for a layer alone, and only where layers overlap can it
  /// look different.
  final bool spread;
}

/// The cels of one line — a place from the top, and a blend — on their way
/// to one row.
final class _Line {
  _Line(this.rank, this.blend, this.firstCel);

  final int rank;
  final LayerBlendMode blend;

  /// Where in the bank its first cel stands — the tie-break.
  final int firstCel;

  /// Each with the cel it is in, by the cel's place in the bank.
  final leaves = <(int, _Leaf)>[];

  /// The row's opacity: its strongest picture's (Q5 — a bake can only make
  /// fainter). With no picture at all, its strongest layer's.
  double get opacity {
    final drawn = [
      for (final (_, leaf) in leaves)
        if (leaf.layer.hasPicture) leaf.opacity,
    ];
    return (drawn.isEmpty
            ? [for (final (_, leaf) in leaves) leaf.opacity]
            : drawn)
        .reduce(math.max);
  }
}

/// What the planner bakes, before the cuts are made.
typedef _Bake = ({_Row row, FrameId frameId, ClipLayer source, double alpha});

final class _Planner {
  _Planner({
    required this.views,
    required this.mint,
    required this.hiddenFolderName,
    required this.warnings,
  });

  final List<_CutView> views;
  final ImportIdMint mint;
  final String hiddenFolderName;
  final List<ImportWarning> warnings;

  /// Bottom first, the order a cut stores.
  final rows = <_Row>[];
  final bakes = <_Bake>[];

  /// Layers whose blend was already said to have no equivalent.
  final _blendsSaid = <int>{};

  List<LayerId> _ids() => [for (final _ in views) mint.nextLayerId()];

  /// Plans [folder]'s children, bottom to top, into [parent]; [folders] are
  /// the file's folders above them.
  void walk(ClipLayer folder, _FolderRow? parent, List<ClipLayer> folders) {
    for (final child in folder.children) {
      if (child.isAnimationFolder) {
        _animationFolder(child, parent, folders);
      } else if (child.isFolder) {
        final row = _folderRowOf(child, parent);
        walk(child, row, [...folders, child]);
        // A folder row sits directly above its members.
        rows.add(row);
      } else {
        _outsideLayer(child, parent, folders);
      }
    }
  }

  _FolderRow _folderRowOf(ClipLayer folder, _FolderRow? parent) => _FolderRow(
    parent,
    _ids(),
    name: folder.name,
    visible: folder.isShown,
    opacity: folder.opacity / _fullOpacity,
    blend: _blendOf(folder, folder.name),
    collapsed: folder.isCollapsed,
  );

  void _outsideLayer(
    ClipLayer layer,
    _FolderRow? parent,
    List<ClipLayer> folders,
  ) {
    _sayWhatIsNotDrawn(layer, layer.name);
    // A sound belongs on the SE rows — said above, no picture row.
    if (layer.kind == ClipLayerKind.sound) {
      return;
    }
    final ids = _ids();
    final frame = Frame(
      id: mint.nextFrameId(ids.first),
      duration: 1,
      strokes: const [],
      // Named, as a 겸용 cut's image row links by its picture's name
      // (F-98 · F-278: 「이름이 같아야만 링크」).
      name: layer.name.isEmpty ? null : layer.name,
    );
    final row = _PictureRow(
      parent,
      ids,
      source: layer,
      folders: folders,
      frame: frame,
      blend: _blendOf(layer, layer.name),
    );
    rows.add(row);
    if (layer.hasPicture) {
      bakes.add((row: row, frameId: frame.id, source: layer, alpha: 1));
    }
    _sayWhereShownInPart(layer, folders);
  }

  /// An image row holds its picture through the whole cut; a layer whose
  /// clips cover only part of a timeline is said, by name and cut
  /// (`csp-clip-import-analysis-Q8` asks what it should become).
  void _sayWhereShownInPart(ClipLayer layer, List<ClipLayer> folders) {
    for (final view in views) {
      final shown = view.within([...folders, layer]).fold(
        0,
        (frames, span) => frames + span.end - span.start,
      );
      if (shown > 0 && shown < view.duration) {
        warnings.add(
          ImportWarning(
            'clipShownInPart',
            '{name}: shown on part of {cut} only — here it is shown '
            'throughout.',
            {'name': layer.name, 'cut': view.name},
          ),
        );
      }
    }
  }

  void _animationFolder(
    ClipLayer folder,
    _FolderRow? parent,
    List<ClipLayer> folders,
  ) {
    final folderRow = _folderRowOf(folder, parent);
    final cels = _placedCels(folder);
    final leaves = [for (final cel in cels) _leavesOf(cel, folder)];
    final (:visible, :hidden) = _linesOf(leaves);
    // The base is the line most top layers stand in. A folder with no
    // visible layer still has its base, empty.
    final baseLine = visible.firstOrNull?.rank == 0
        ? visible.removeAt(0)
        : null;
    final baseIds = _ids();
    final base = _BaseRow(
      folderRow,
      baseIds,
      folder: folder,
      folders: folders,
      bank: [
        for (final cel in cels)
          Frame(
            id: mint.nextFrameId(baseIds.first),
            duration: 1,
            strokes: const [],
            name: cel.name,
          ),
      ],
      opacity: baseLine?.opacity ?? 1,
      blend: baseLine?.blend ?? LayerBlendMode.normal,
    );
    if (baseLine != null) {
      _bake(base, baseLine, (cel) => base.bank[cel].id);
    }
    final organizer = hidden.isEmpty
        ? null
        : _FolderRow(
            folderRow,
            _ids(),
            name: hiddenFolderName,
            visible: false,
            opacity: 1,
            blend: LayerBlendMode.passThrough,
            collapsed: true,
          );
    final attaches = _attachRowsOf(base, [
      for (final line in visible) (line, folderRow),
      for (final line in hidden) (line, organizer!),
    ]);
    // Bottom first: the hidden rows and their folder, the attach rows from
    // the lowest line up, the base, and the folder row over them all.
    rows.addAll([
      ...attaches.skip(visible.length).toList().reversed,
      ?organizer,
      ...attaches.take(visible.length).toList().reversed,
      base,
      folderRow,
    ]);
    _sayAboutCels(folder, cels, leaves);
  }

  /// [lines]' rows, each in its folder, named from the top after [base] —
  /// `A-2`, `A-3` … (MoArt's form) — and its pictures baked in.
  List<_AttachRow> _attachRowsOf(
    _BaseRow base,
    List<(_Line, _FolderRow)> lines,
  ) => [
    for (final (i, (line, parent)) in lines.indexed)
      _attachRowOf(base, line, parent, '${base.folder.name}-${i + 2}'),
  ];

  _AttachRow _attachRowOf(
    _BaseRow base,
    _Line line,
    _FolderRow parent,
    String name,
  ) {
    final row = _AttachRow(
      parent,
      _ids(),
      base: base,
      name: name,
      opacity: line.opacity,
      blend: line.blend,
    );
    _bake(row, line, (cel) => row.mirrorOf(base.bank[cel].id));
    return row;
  }

  /// The cels' layers in lines: the visible ones counted from the top, the
  /// hidden ones apart, and a line for every blend a place holds. Each list
  /// runs from the top: by place, then the line more cels stand in, then
  /// the one whose first cel comes first.
  ({List<_Line> visible, List<_Line> hidden}) _linesOf(
    List<List<_Leaf>> leaves,
  ) {
    final visible = <(int, LayerBlendMode), _Line>{};
    final hidden = <(int, LayerBlendMode), _Line>{};
    for (var cel = 0; cel < leaves.length; cel += 1) {
      var shown = 0;
      var unseen = 0;
      for (final leaf in leaves[cel]) {
        final rank = leaf.visible ? shown++ : unseen++;
        (leaf.visible ? visible : hidden)
            .putIfAbsent((rank, leaf.blend), () => _Line(rank, leaf.blend, cel))
            .leaves
            .add((cel, leaf));
      }
    }
    List<_Line> ordered(Iterable<_Line> lines) => lines.toList()
      ..sort((a, b) {
        final byRank = a.rank.compareTo(b.rank);
        final byCount = b.leaves.length.compareTo(a.leaves.length);
        return byRank != 0
            ? byRank
            : byCount != 0
            ? byCount
            : a.firstCel.compareTo(b.firstCel);
      });
    return (visible: ordered(visible.values), hidden: ordered(hidden.values));
  }

  /// Bakes [line]'s pictures into [row] — each fainter by what it lacked of
  /// the row's opacity.
  void _bake(_Row row, _Line line, FrameId Function(int cel) frameOf) {
    final strongest = line.opacity;
    for (final (cel, leaf) in line.leaves) {
      if (leaf.layer.hasPicture) {
        bakes.add((
          row: row,
          frameId: frameOf(cel),
          source: leaf.layer,
          alpha: strongest > 0 ? leaf.opacity / strongest : 1,
        ));
      }
    }
  }

  /// [folder]'s cels some timeline places, in the order they first come —
  /// the cuts' order, then each one's frames.
  List<ClipLayer> _placedCels(ClipLayer folder) {
    final byName = <String, ClipLayer>{};
    for (final cel in folder.children) {
      byName.putIfAbsent(cel.name, () => cel);
    }
    final placed = <String>{};
    var missing = 0;
    for (final view in views) {
      for (final piece in view.trackOf(folder)?.pieces ?? const <ClipPiece>[]) {
        for (final key in piece.cels) {
          if (byName.containsKey(key.cel)) {
            placed.add(key.cel);
          } else {
            missing += 1;
          }
        }
      }
    }
    _sayCount(
      'clipUnplaced',
      '{name}: {count} cels are on no timeline — not imported.',
      folder.name,
      folder.children.length - placed.length,
    );
    _sayCount(
      'clipNoSuchCel',
      '{name}: {count} keys name a cel the folder does not hold.',
      folder.name,
      missing,
    );
    return [for (final name in placed) byName[name]!];
  }

  /// [cel]'s layers, top to bottom — a folder inside it opened up, since
  /// only the place from the top lines layers up across cels (their names
  /// differ cel to cel).
  List<_Leaf> _leavesOf(ClipLayer cel, ClipLayer folder) {
    final where = '${folder.name} / ${cel.name}';
    final out = <_Leaf>[];
    void visit(ClipLayer layer, List<ClipLayer> chain) {
      if (layer.isFolder) {
        for (final child in layer.children.reversed) {
          visit(child, [...chain, layer]);
        }
        return;
      }
      final own = _blendOf(layer, where);
      var blend = own;
      // An isolating folder decides how what it holds meets what lies
      // under it: for a layer alone in it, the folder's blend IS the
      // layer's, and the outermost one decides last. The cel's own folder
      // is the exception when the animation folder isolates: one cel shows
      // at a time, so the cel meets nothing but that folder's empty group,
      // where every blend draws the same.
      for (final inside in chain.reversed) {
        if (inside.composite != _passThrough &&
            !(identical(inside, cel) && folder.composite != _passThrough)) {
          blend = _blendOf(inside, where);
        }
      }
      out.add(
        _Leaf(
          layer: layer,
          visible: layer.isShown && chain.every((inside) => inside.isShown),
          opacity: chain.fold(
            layer.opacity / _fullOpacity,
            (value, inside) => value * inside.opacity / _fullOpacity,
          ),
          blend: blend,
          spread:
              blend != own ||
              chain.any((inside) => inside.opacity < _fullOpacity),
        ),
      );
    }

    visit(cel, const []);
    return out;
  }

  void _sayAboutCels(
    ClipLayer folder,
    List<ClipLayer> cels,
    List<List<_Leaf>> leaves,
  ) {
    for (var c = 0; c < cels.length; c += 1) {
      for (final leaf in leaves[c]) {
        _sayWhatIsNotDrawn(leaf.layer, '${folder.name} / ${cels[c].name}');
      }
    }
    if (cels.any((cel) => cel.isFolder)) {
      warnings.add(
        ImportWarning(
          'clipCelLayers',
          '{name}: the layers inside its cels became rows by their place '
          'from the top — their own names and folders are not kept.',
          {'name': folder.name},
        ),
      );
    }
    _sayCount(
      'clipSpread',
      '{name}: in {count} cels a folder\'s opacity or blend went to each of '
      'its layers — where those layers overlap they can look different.',
      folder.name,
      leaves
          .where((cel) => cel.length > 1 && cel.any((leaf) => leaf.spread))
          .length,
    );
  }

  /// Says [count] of something about [name] — when there is any.
  void _sayCount(String key, String template, String name, int count) {
    if (count > 0) {
      warnings.add(
        ImportWarning(key, template, {'name': name, 'count': '$count'}),
      );
    }
  }

  /// Says what a layer of a kind with no picture here leaves out.
  void _sayWhatIsNotDrawn(ClipLayer layer, String name) {
    final (key, template) = switch (layer.kind) {
      ClipLayerKind.vector => (
        'clipVector',
        '{name}: vector layer — not drawn.',
      ),
      ClipLayerKind.lettering => (
        'clipText',
        '{name}: text layer — not drawn.',
      ),
      ClipLayerKind.paper => (
        'clipPaper',
        '{name}: paper layer — its colour not applied.',
      ),
      ClipLayerKind.fill => ('clipFill', '{name}: fill layer — not drawn.'),
      ClipLayerKind.sound => ('clipSound', '{name}: sound layer not imported.'),
      ClipLayerKind.other => (
        'clipUnknownLayer',
        '{name}: a kind of layer this import does not read.',
      ),
      ClipLayerKind.root ||
      ClipLayerKind.folder ||
      ClipLayerKind.raster ||
      ClipLayerKind.picture => (null, null),
    };
    if (key != null && template != null) {
      warnings.add(ImportWarning(key, template, {'name': name}));
    }
  }

  /// [layer]'s blend here, said once when there is none. Pass-through is a
  /// folder's word: a layer carrying it draws as normal.
  LayerBlendMode _blendOf(ClipLayer layer, String name) {
    final mode = clipBlendModes[layer.composite];
    if (mode == null) {
      if (_blendsSaid.add(layer.id)) {
        warnings.add(
          ImportWarning(
            'clipBlend',
            '{name}: blend mode {mode} has no equivalent — set to normal.',
            {'name': name, 'mode': '${layer.composite}'},
          ),
        );
      }
      return LayerBlendMode.normal;
    }
    return mode == LayerBlendMode.passThrough && !layer.isFolder
        ? LayerBlendMode.normal
        : mode;
  }
}
