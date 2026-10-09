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
///   — the top layer of every cel (Q2: 「맨 위 레이어가 기준」), one cel per
///   CLIP STUDIO cel, named as there — and BELOW it the attach rows the
///   cels' other layers make, synced to the base, named `A-1`, `A-2` … as
///   the app names them: a layer whose name another cel wears stands in that
///   name's row, any other by its place from the top ([_Planner._lined]).
///   Hidden layers come too (Q3: 「모든 레이어를 가져오는게 목표」), lined up
///   the same way with their eyes off, in the animation folder with the
///   rest. ↩️They stood in a folder of their own, named in the program
///   language — a folder the file never had (유저 10-09: 「이 숨김이라는
///   폴더는 뭐지? … 레이어 구조든 폴더구조든 뭐든 최대한 구조적으론 원본
///   그대로를 원해」).
/// * **The look is kept by baking** (Q5, answered twice — the second: 「그림에
///   구워 넣는다(행은 100%)」, 「그냥 불투명도 낮은건 그냥 낮은채로
///   구워버려서 더이상 진해지지 못하는거 받아들기게 … 최대한 보기 같은걸
///   원한다」): a cel's row stands at 100%, and every cel's picture is baked
///   at its own opacity — what CLIP STUDIO showed, and no fainter cel can be
///   made strong again by its row. ↩️The row first took its strongest cel's
///   opacity and baked the others by the difference: the same first look,
///   but a row that was not at 100%, and a 10% rough that a row could raise.
///   A blend cannot be baked, so a line of cels that blends two ways is two
///   rows — and one shown in some cels and hidden in others, as a row has
///   one eye (「법 통일」).
/// * A layer outside the cels is an image row (「단일그림은 … 그에 대응하는
///   이미지레이어로」) — unless some timeline shows it on PART of a cut
///   only: then it is an animation row holding its one picture where it
///   shows, and nothing where it does not (Q8: 「일부 구간만 보이는 레이어만
///   애니메이션 레이어로」). The 겸용 cuts share the row, so a layer shown in
///   part on one timeline is that row on all of them. A cel placed on no
///   timeline is not imported (「임포트 안해도 상관없고」), and what there is
///   no place for is said, never dropped quietly — a kind of layer this app
///   does not carry in every decoder's one word ([unsupportedLayerKind]).
library;

import 'dart:collection';
import 'dart:math' as math;

import '../../models/attached_layer_resolve.dart'
    show attachedLayerNameAmong, attachedMirrorCelId;
import '../../models/attached_mode.dart';
import '../../models/attached_placement.dart';
import '../../models/audio_clip.dart';
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
    required this.label,
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

  /// What a warning calls it: the layer's name — or, for a layer inside a
  /// cel, whose own name has no row to stand on, its animation folder and
  /// cel (`A / 3`).
  final String label;

  /// What the picture's alpha is multiplied by: the layer's own opacity
  /// times its folders' in the cel — its row stands at 100% (Q5 — 「낮은채로
  /// 구워버려서」).
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
/// [name] names the one cut of a file with no timeline. Link members carry
/// [trackId], the track the cuts land on. [soundPaths] is where each sound
/// the file holds was taken out to, by its [ClipSound.objectUuid] — the
/// file its SE rows play; a sound with none is said, not played.
ClipImportPlan planClipImport({
  required ClipDocument document,
  required String name,
  required TrackId trackId,
  required ImportIdMint mint,
  Map<String, String> soundPaths = const {},
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
    warnings: warnings,
    soundPaths: soundPaths,
  )
    ..walk(document.root, null, const [])
    ..nameAttachRows();
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
          layers: [
            for (final row in planner.rows) row.layerIn(i, views[i]),
            // Each cut's sound as SE rows of its own, the way the file
            // keeps it — the door lifts them onto the track.
            ...planner.soundRowsIn(views[i]),
          ],
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
          label: bake.label,
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

  /// What the row is called in every cut.
  String get name;

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

  @override
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
    required this.shownInPart,
  });

  final ClipLayer source;

  /// The folders above [source] — whose clips are its clips too.
  final List<ClipLayer> folders;
  final Frame frame;
  final LayerBlendMode blend;

  /// Whether some timeline shows it on PART of a cut only — the row is then
  /// an animation row holding its picture where it shows (Q8). The 겸용
  /// cuts share the row, so one such timeline makes it that on all of them.
  final bool shownInPart;

  @override
  String get name => source.name;

  @override
  Layer layerIn(int cut, _CutView view) {
    final shown = view.within([...folders, source]);
    return Layer(
      id: ids[cut],
      name: name,
      kind: shownInPart ? LayerKind.animation : LayerKind.image,
      frames: [frame],
      timeline: shownInPart
          ? {
              for (final span in shown)
                span.start: TimelineExposure.drawing(
                  frame.id,
                  length: span.end - span.start,
                ),
            }
          // Held from the head; the covering law shapes it into the image
          // row's one cel and its hold (`cutWithCoveringImageRows`).
          : shown.isEmpty
          ? const {}
          : {0: TimelineExposure.drawing(frame.id, length: view.duration)},
      isVisible: source.isShown,
      opacity: source.opacity / _fullOpacity,
      blendMode: blend,
      folderId: parent?.ids[cut],
    );
  }
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
    required this.blend,
    required this.visible,
  });

  final ClipLayer folder;

  /// The folders above [folder] — whose clips cut its cels down.
  final List<ClipLayer> folders;

  /// One cel per CLIP STUDIO cel, named as there.
  final List<Frame> bank;
  final LayerBlendMode blend;

  /// The eye of the top layers it holds — off where most cels' top layer
  /// is hidden.
  final bool visible;

  @override
  String get name => folder.name;

  @override
  Layer layerIn(int cut, _CutView view) => rederiveRunBehaviors(
    Layer(
      id: ids[cut],
      name: name,
      frames: bank,
      timeline: _exposures(view),
      blendMode: blend,
      isVisible: visible,
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
    required this.blend,
    required this.visible,
  });

  final _BaseRow base;

  /// Given once every row is planned ([_Planner.nameAttachRows]).
  @override
  late final String name;
  final LayerBlendMode blend;

  /// Off for a line of the cels' hidden layers.
  final bool visible;

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
    blendMode: blend,
    isVisible: visible,
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
    required this.where,
  });

  final ClipLayer layer;

  /// Its animation folder and cel, as a warning names it (`A / 3`).
  final String where;

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

/// What lines a cel's layer up with other cels' layers: a [name] another
/// cel's layer wears too — the [index]th layer of that name in its cel —
/// or, with no [name], its [index]th place from the top.
typedef _LineKey = ({String? name, int index});

/// The base's key: every cel's top shown layer (Q2).
const _LineKey _top = (name: null, index: 0);

/// The cels of one line — a key, and a blend — on their way to one row.
final class _Line {
  _Line(this.key, this.blend, this.visible);

  final _LineKey key;
  final LayerBlendMode blend;

  /// Its layers' eye. A row has one eye as it has one blend, so a key whose
  /// layers are shown in some cels and hidden in others is two lines — the
  /// blend's law, not a rule of the hidden layers' own.
  final bool visible;

  /// Each with the cel it is in, by the cel's place in the bank, and its
  /// place from the top in that cel.
  final leaves = <(int, _Leaf, int)>[];

  /// How high its layers stand, on average.
  double get height =>
      leaves.fold(0, (sum, leaf) => sum + leaf.$3) / leaves.length;
}

/// What the planner bakes, before the cuts are made.
typedef _Bake = ({
  _Row row,
  FrameId frameId,
  ClipLayer source,
  String label,
  double alpha,
});

final class _Planner {
  _Planner({
    required this.views,
    required this.mint,
    required this.warnings,
    required this.soundPaths,
  });

  final List<_CutView> views;
  final ImportIdMint mint;
  final List<ImportWarning> warnings;

  /// Where each sound was taken out to, by its [ClipSound.objectUuid].
  final Map<String, String> soundPaths;

  /// Bottom first, the order a cut stores.
  final rows = <_Row>[];
  final bakes = <_Bake>[];

  /// The sound layers outside the cels, as the walk met them, each with
  /// the folders above it.
  final _sounds = <(ClipLayer, List<ClipLayer>)>[];

  /// The attach rows as they were made: each animation folder's from the
  /// top.
  final _attaches = <_AttachRow>[];

  /// Layers whose blend was already said to have no equivalent.
  final _blendsSaid = <int>{};

  List<LayerId> _ids() => [for (final _ in views) mint.nextLayerId()];

  /// Names every attach row as the app names one it adds below its base —
  /// `A-1`, `A-2` …, the first no row wears ([attachedLayerNameAmong]) —
  /// once every row is planned, so a name the file itself uses is passed
  /// over. 유저 10-09: 「레이어이름은 들쭉날쭉하니까 무시해도되. 그래서 그냥
  /// 우리방식대로 A라는 기준레이어랑 A-1 이런식으로 해줘」 — the cels' layers'
  /// own names differ cel to cel (measured on the samples). ↩️They were
  /// `A-2`, `A-3` from the top, MoArt's form — a second naming rule beside
  /// the app's own.
  void nameAttachRows() {
    final used = {
      for (final row in rows)
        if (row is! _AttachRow) row.name,
    };
    for (final row in _attaches) {
      row.name = attachedLayerNameAmong(
        row.base.name,
        used,
        AttachedPlacement.below,
      );
      used.add(row.name);
    }
  }

  /// [view]'s cut's SE rows: one per sound layer its timeline plays, a block
  /// for each clip of the layer's track — from where the clip's cue starts
  /// the sound, or the cut's head, to the clip's end, cut down where the
  /// folders above do not show — playing the sound from the second the cue
  /// says, at its volume. A hidden layer is a MUTED row: a CLIP STUDIO sound
  /// layer's eye is whether it is heard, and an SE row's mute is the audio
  /// counterpart of an eye ([Layer.muted]).
  List<Layer> soundRowsIn(_CutView view) {
    final fps = view.timeline?.fps ?? 0;
    final out = <Layer>[];
    for (final (layer, folders) in _sounds) {
      final placed = <(ClipSoundCue, ClipSpan, String)>[];
      for (final cue in view.trackOf(layer)?.sounds ?? const <ClipSoundCue>[]) {
        final path = soundPaths[cue.player];
        final held = view.inCut((start: cue.frame, end: cue.span.end));
        if (path == null || held == null) {
          continue;
        }
        for (final block in _overlap([held], view.within(folders))) {
          placed.add((cue, block, path));
        }
      }
      if (placed.isEmpty) {
        continue;
      }
      final id = mint.nextLayerId();
      final frames = <Frame>[];
      final clips = <AudioClip>[];
      final timeline = SplayTreeMap<int, TimelineExposure>();
      for (final (cue, block, path) in placed) {
        final frameId = mint.nextFrameId(id);
        frames.add(Frame(id: frameId, duration: 1, strokes: const []));
        clips.add(
          AudioClip(
            filePath: path,
            frameId: frameId,
            // The cue's second, and the frames the block starts past it.
            offsetFrames: math.max(
              0,
              (cue.startSeconds * fps).round() +
                  block.start +
                  view.start -
                  cue.frame,
            ),
            gain: math.max(0, cue.volume),
          ),
        );
        timeline[block.start] = TimelineExposure.drawing(
          frameId,
          length: block.end - block.start,
        );
      }
      out.add(
        Layer(
          id: id,
          name: layer.name,
          kind: LayerKind.se,
          frames: frames,
          timeline: timeline,
          audioClips: clips,
          muted: !(layer.isShown && folders.every((folder) => folder.isShown)),
        ),
      );
    }
    return out;
  }

  /// Says what of [layer]'s sound does not come over: a clip whose sound
  /// the file does not hold, one CLIP STUDIO plays at another speed —
  /// played at its own — and one whose volume moves within it — held
  /// where it starts.
  void _saySoundsOf(ClipLayer layer) {
    final cues = [
      for (final view in views) ...?view.trackOf(layer)?.sounds,
    ];
    void say(bool Function(ClipSoundCue cue) when, String key, String text) {
      if (cues.any(when)) {
        warnings.add(ImportWarning(key, text, {'name': layer.name}));
      }
    }

    say(
      (cue) => soundPaths[cue.player] == null,
      'clipSoundMissing',
      '{name}: its sound is not in the file — not played.',
    );
    say(
      (cue) => (cue.speed - 1).abs() > 0.001,
      'clipSoundSpeed',
      '{name}: CLIP STUDIO plays it at another speed — it plays at its own '
          'here.',
    );
    say(
      (cue) => cue.volumeVaries,
      'clipSoundVolume',
      '{name}: its volume moves within its clip — held where the clip '
          'starts.',
    );
  }

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
    // A sound plays on each cut's SE rows ([soundRowsIn]), not in a row of
    // pictures (유저 10-09: 「소리도 가져오게 못하나? 단일파일안에있을거아냐」).
    if (layer.kind == ClipLayerKind.sound) {
      _sounds.add((layer, folders));
      _saySoundsOf(layer);
      return;
    }
    if (!_comesIn(layer, layer.name)) {
      return;
    }
    final ids = _ids();
    final frame = Frame(
      id: mint.nextFrameId(ids.first),
      duration: 1,
      strokes: const [],
      // Named, as a 겸용 cut's image row links by its picture's name
      // (F-98 · F-278: 「이름이 같아야만 링크」) — so an edit in one cut is
      // the picture every timeline shows, as it is in CLIP STUDIO. Named
      // `1`, not after its layer: 유저 10-09 — 「같은이름 공유시켜서
      // 수정하면 다른겸용컷 반영하려고 … 그런거라면 프레임이름 넣어도되」 ·
      // 「이름을 레이어이름이아니라 1이란던가 좀 심플하게」.
      name: '1',
    );
    final row = _PictureRow(
      parent,
      ids,
      source: layer,
      folders: folders,
      frame: frame,
      blend: _blendOf(layer, layer.name),
      shownInPart: views.any((view) {
        final shown = view.within([...folders, layer]).fold(
          0,
          (frames, span) => frames + span.end - span.start,
        );
        return shown > 0 && shown < view.duration;
      }),
    );
    rows.add(row);
    if (layer.hasPicture) {
      bakes.add((
        row: row,
        frameId: frame.id,
        source: layer,
        label: layer.name,
        alpha: 1,
      ));
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
    final (:lines, :crossed) = _lined(leaves);
    // The base is the line most top layers stand in — the first of the top
    // lines, which nothing stands above. A folder whose cels hold no layer
    // still has its base, empty.
    final baseLine = lines.firstOrNull?.key == _top ? lines.removeAt(0) : null;
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
      blend: baseLine?.blend ?? LayerBlendMode.normal,
      visible: baseLine?.visible ?? true,
    );
    if (baseLine != null) {
      _bake(base, baseLine, (cel) => base.bank[cel].id);
    }
    final attaches = [
      for (final line in lines) _attachRowOf(base, line, folderRow),
    ];
    _attaches.addAll(attaches);
    // Bottom first: the attach rows from the lowest line up, the base, and
    // the folder row over them all.
    rows.addAll([...attaches.reversed, base, folderRow]);
    _sayAboutCels(folder, cels, leaves);
    _sayCount(
      'clipLineOrder',
      '{name}: in {count} cels two layers stand in the other order than in '
      'CLIP STUDIO — where they overlap they can look different.',
      folder.name,
      crossed,
    );
  }

  /// [line]'s row in [parent] below [base] — its pictures baked in, its
  /// name given once every row is planned ([nameAttachRows]).
  _AttachRow _attachRowOf(_BaseRow base, _Line line, _FolderRow parent) {
    final row = _AttachRow(
      parent,
      _ids(),
      base: base,
      blend: line.blend,
      visible: line.visible,
    );
    _bake(row, line, (cel) => row.mirrorOf(base.bank[cel].id));
    return row;
  }

  /// [cels]' layers — each cel's from the top — in lines, the lines from
  /// the top, and how many cels' shown layers those lines [crossed].
  ///
  /// Each cel's top layer stands in the base's line whatever its name (Q2:
  /// 「맨 위 레이어가 기준, 나머지는 기준 아래 어태치」). Below it — 유저 10-09:
  /// 「클튜에서 같은이름 레이어면 최대한 같은 레이어에 묶는것 … 같은이름 있으면
  /// 같은행 없으면 전처럼 위치관계기준」 — a layer whose name a layer of another
  /// cel wears too stands in that name's line, and one whose name no other
  /// cel wears by its place from the top. A key whose layers blend two ways,
  /// or are shown in some cels and hidden in others, is two lines: a row
  /// has one blend and one eye. ↩️Every layer stood by its place alone, so
  /// one cel with an extra layer pushed its same-named layers into other
  /// cels' rows (a 46-cel sample did) — and the hidden ones were counted
  /// apart, a rule of their own (유저 10-09: 「숨긴레이어 이상한 규칙
  /// 만들지말고 그냥 눈만 끄게하면되는거야」).
  ({List<_Line> lines, int crossed}) _lined(List<List<_Leaf>> cels) {
    // The cels each name — its nth layer of that name — stands in.
    final wearers = <(String, int), Set<int>>{};
    final named = [for (final cel in cels) _namedIn(cel)];
    for (var cel = 0; cel < cels.length; cel += 1) {
      for (final name in named[cel].nonNulls) {
        (wearers[name] ??= {}).add(cel);
      }
    }
    final lines = <(_LineKey, LayerBlendMode, bool), _Line>{};
    final stacks = <List<_Line>>[];
    for (var cel = 0; cel < cels.length; cel += 1) {
      final stack = <_Line>[];
      for (var place = 0; place < cels[cel].length; place += 1) {
        final leaf = cels[cel][place];
        final name = named[cel][place];
        final key = name != null && wearers[name]!.length > 1
            ? (name: name.$1, index: name.$2)
            : (name: null, index: place);
        final line = lines.putIfAbsent(
          (key, leaf.blend, leaf.visible),
          () => _Line(key, leaf.blend, leaf.visible),
        );
        line.leaves.add((cel, leaf, place));
        stack.add(line);
      }
      stacks.add(stack);
    }
    final ordered = _ordered(lines.values.toList(), stacks);
    final at = {for (final (i, line) in ordered.indexed) line: i};
    bool crosses(List<_Line> stack) {
      final shown = [
        for (final line in stack)
          if (line.visible) at[line]!,
      ];
      return [
        for (var i = 1; i < shown.length; i += 1) shown[i - 1] > shown[i],
      ].any((crossed) => crossed);
    }

    return (lines: ordered, crossed: stacks.where(crosses).length);
  }

  /// Each of [cel]'s layers below its top as its name and how many before
  /// it in the cel wear that name — the top's null: only its place counts.
  static List<(String, int)?> _namedIn(List<_Leaf> cel) {
    final seen = <String, int>{};
    return [
      for (var place = 0; place < cel.length; place += 1)
        if (place == 0)
          null
        else
          (
            cel[place].layer.name,
            seen.update(
              cel[place].layer.name,
              (count) => count + 1,
              ifAbsent: () => 0,
            ),
          ),
    ];
  }

  /// [lines] from the top. A line comes once every line some cel stacks
  /// right above it has come ([stacks]: each cel's lines, top to bottom), so
  /// no cel's own order is crossed where the cels agree; of the lines free
  /// to come — or of all left, where the cels disagree — the one whose
  /// layers stand highest on average comes first, then the one more cels
  /// stand in, then the one made first.
  static List<_Line> _ordered(List<_Line> lines, List<List<_Line>> stacks) {
    final above = {for (final line in lines) line: <_Line>{}};
    for (final stack in stacks) {
      for (var i = 1; i < stack.length; i += 1) {
        above[stack[i]]!.add(stack[i - 1]);
      }
    }
    final made = {for (final (i, line) in lines.indexed) line: i};
    bool before(_Line a, _Line b) {
      if (a.height != b.height) {
        return a.height < b.height;
      }
      if (a.leaves.length != b.leaves.length) {
        return a.leaves.length > b.leaves.length;
      }
      return made[a]! < made[b]!;
    }

    final left = [...lines];
    final out = <_Line>[];
    final done = <_Line>{};
    while (left.isNotEmpty) {
      final free = [
        for (final line in left)
          if (above[line]!.every(done.contains)) line,
      ];
      final next = (free.isEmpty ? left : free).reduce(
        (a, b) => before(b, a) ? b : a,
      );
      out.add(next);
      done.add(next);
      left.remove(next);
    }
    return out;
  }

  /// Bakes [line]'s pictures into [row] — each at its own opacity, the row
  /// at 100% (Q5).
  void _bake(_Row row, _Line line, FrameId Function(int cel) frameOf) {
    for (final (cel, leaf, _) in line.leaves) {
      if (leaf.layer.hasPicture) {
        bakes.add((
          row: row,
          frameId: frameOf(cel),
          source: leaf.layer,
          label: leaf.where,
          alpha: leaf.opacity,
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
      // Left out before it takes a place, so the layers under it line up
      // as if it were not there.
      if (!_comesIn(layer, where)) {
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
          where: where,
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
    if (cels.any((cel) => cel.isFolder)) {
      warnings.add(
        ImportWarning(
          'clipCelLayers',
          '{name}: the layers inside its cels became rows — by their names '
          'where cels share them, else by their place from the top; their '
          'own names and folders are not kept.',
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

  /// Whether [layer] comes in — said by [name] when it comes in short, or
  /// not at all. A kind this app does not carry is left out in every
  /// decoder's one word (유저 10-09); a sound belongs on the SE rows.
  bool _comesIn(ClipLayer layer, String name) {
    final (said, comes) = switch (layer.kind) {
      ClipLayerKind.vector => (
        ImportWarning(
          'clipVector',
          '{name}: vector layer — drawn with a round pen; its brush\'s '
              'shape and texture are not kept.',
          {'name': name},
        ),
        true,
      ),
      ClipLayerKind.sound => (
        ImportWarning('clipSound', '{name}: sound layer not imported.', {
          'name': name,
        }),
        false,
      ),
      ClipLayerKind.lettering ||
      ClipLayerKind.paper ||
      ClipLayerKind.fill ||
      ClipLayerKind.other => (unsupportedLayerKind(name), false),
      ClipLayerKind.root ||
      ClipLayerKind.folder ||
      ClipLayerKind.raster ||
      ClipLayerKind.picture => (null, true),
    };
    if (said != null) {
      warnings.add(said);
    }
    return comes;
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
