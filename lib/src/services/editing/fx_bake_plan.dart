import 'dart:collection' show SplayTreeMap;

import '../../models/cut.dart';
import '../../models/cut_id.dart';
import '../../models/frame.dart';
import '../../models/frame_id.dart';
import '../../models/layer.dart';
import '../../models/layer_blend_mode.dart';
import '../../models/layer_effect.dart';
import '../../models/layer_id.dart';
import '../../models/pasteboard_bounds.dart';
import '../../models/project.dart';
import '../../models/timeline_coverage.dart' show exposedFrameIdAt;
import '../../models/timeline_exposure.dart';
import '../../models/timeline_repeat.dart'
    show ghostFreeTimeline, rederiveRunBehaviors;
import '../../models/timeline_splice.dart' show splitTimelineAt;
import '../../models/track_conte_laying.dart' show conteBaseOf;
import '../../models/track_transitions.dart' show cutDrawnFrameCount;
import '../../models/transform_track.dart';
import '../commands/link_mirror.dart' show existenceMirrorTargets;
import '../cut_frame_composite_plan.dart' show exposedCelIdAt;
import '../playback/cut_frame_composite_spans.dart';
import '../project_lookup.dart' show requireCut;
import 'layer_merge_plan.dart'
    show
        CelReads,
        LayerMergePicture,
        kindHoldingPictures,
        picturesCutAtTheWall,
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

/// What ONE press of RASTERIZE in a row's fx group header takes: the row,
/// and the fx — the transform, where [effectId] is null.
final class FxBakeTaking {
  const FxBakeTaking._(this.cut, this.row, this.effectId, this._drawnFrames);

  /// The cut it was taken of.
  final Cut cut;

  /// The row it bakes.
  final Layer row;

  /// The fx it bakes; null for the transform.
  final EffectId? effectId;

  /// The cut's drawn length, which the row's holds and repeats fill to.
  final int _drawnFrames;
}

/// What a press of RASTERIZE in [rowId]'s group header for [effectId] — the
/// transform's, where null — takes of [cutId] in [project]: null where it
/// bakes nothing.
///
/// 🗣️I-120-Q8 (유저 2026-11-04 「폴더 · 조정 레이어 둘 다 버튼이 꺼진다」): a
/// row with no picture of its own bakes nothing — a folder, an adjustment
/// row, the camera.
///
/// ⚠️Rows this round (② of the card's) does not bake yet stand down, as a
/// merge's did until the round that took them: a row whose cels another
/// cut shows too (④, Q6 — every use baked together), a row of a track's
/// conte (④, Q7), a row that rides another or is ridden (②b — 「어태치
/// 레이어는 주인과 같이 굽는다」, 07-21), and a reference row (⑤, Q5 · Q11).
/// The card's order, not a law of the verb.
FxBakeTaking? takeFxToBake({
  required Project project,
  required CutId cutId,
  required LayerId rowId,
  required EffectId? effectId,
}) {
  final cut = requireCut(project, cutId);
  final row = cut.layers.byId(rowId);
  if (row == null || !row.kind.isDrawingCel) {
    return null;
  }
  if (effectId != null && !row.effects.any((fx) => fx.id == effectId)) {
    return null;
  }
  if (_waitsForALaterRound(project, cut, row)) {
    return null;
  }
  return FxBakeTaking._(
    cut,
    row,
    effectId,
    cutDrawnFrameCount(project, cutId) ?? cut.duration,
  );
}

/// A row of the conte rides it ([Layer.conteKey]), so the rider's wait is
/// its wait too.
bool _waitsForALaterRound(Project project, Cut cut, Layer row) =>
    existenceMirrorTargets(project, cutId: cut.id, layerId: row.id).length >
        1 ||
    conteBaseOf(cut)?.id == row.id ||
    row.attachedToLayerId != null ||
    cut.layers.any((other) => other.attachedToLayerId == row.id) ||
    row.mediaReference != null;

/// What a press of RASTERIZE makes of [taking]'s row: its pictures with the
/// fx baked in, and the row after.
class FxBakePlan {
  const FxBakePlan._({
    required this.cut,
    required this.row,
    required this.pictures,
    required this.changes,
  });

  /// The cut it was planned of, as it was.
  final Cut cut;

  /// The row after: its cels the baked pictures, the fx at its defaults.
  final Layer row;

  /// Every new cel's picture, still to be laid: each drawn of the row
  /// wearing the baked fx alone ([_wearingOnly]).
  final List<LayerMergePicture> pictures;

  final Set<FxBakeChange> changes;

  /// The cut's rows after: [row] where it stood.
  List<Layer> get layers => [
    for (final layer in cut.layers)
      if (layer.id == row.id) row else layer,
  ];
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
///
/// A cel that shows one picture is that picture — its name, its place in
/// the bank. A cel shown as several takes a new cel for each after the
/// first, named with the tail a merge names a parted picture with (I-78-Q10
/// 「갈라진 곳은 꼬리 번호」), its blocks split where the picture changes
/// ([splitTimelineAt]: the head keeps the memo and the marks). A hold or a
/// repeat that would show a cel where another picture belongs is made of
/// blocks of its own. An image row holding more than one picture becomes a
/// drawing row (I-120: 「애니메이션레이어로 전환」).
///
/// [reads] says how the cut's cels are read; [mintFrameId] names each new
/// cel; [reach] is how far past the canvas the wall stands.
FxBakePlan planFxBake(
  FxBakeTaking taking, {
  required CelReads reads,
  required FrameId Function(LayerId row) mintFrameId,
  required PasteboardReach reach,
}) {
  final FxBakeTaking(:cut, :row, :effectId) = taking;
  final shown = _wearingOnly(cut, row, effectId);
  final bank = _bankOf(
    taking,
    shown,
    runsByPicture(shown, [shown.layers.byId(row.id)!], reads.revisionOf),
    mintFrameId,
  );
  final baked = row.copyWith(
    kind: kindHoldingPictures(row.kind, bank.cels.length),
    frames: bank.cels,
    timeline: _timelineShowing(row, bank.celAt, taking._drawnFrames),
    effects: [
      for (final fx in row.effects)
        if (fx.id == effectId) _atItsDefaults(fx) else fx,
    ],
    transformTrack: effectId == null
        ? TransformTrack.empty()
        : row.transformTrack,
    // A cel baked takes its sounds to its first picture.
    audioClips: [
      for (final clip in row.audioClips)
        switch (bank.firstOf[clip.frameId]) {
          final made? => clip.copyWith(frameId: made),
          null => clip,
        },
    ],
  );
  return FxBakePlan._(
    cut: cut,
    row: baked,
    pictures: bank.pictures,
    changes: {
      if (_runsAfterAnFxOn(row, effectId)) FxBakeChange.order,
      if (picturesCutAtTheWall(bank.pictures, (
        wall: cut.canvasSize.pasteboardAt(reach),
        inkOf: reads.inkOf,
      )))
        FxBakeChange.wall,
    },
  );
}

/// The cels a bake leaves its row: [cels] its bank, [celAt] the cel each
/// frame shows, [pictures] each new cel's picture still to be laid, and
/// [firstOf] the first picture each cel baked became.
typedef _Bank = ({
  List<Frame> cels,
  Map<int, FrameId> celAt,
  List<LayerMergePicture> pictures,
  Map<FrameId, FrameId> firstOf,
});

/// [taking]'s row's bank after the bake, [runs] being the pictures [shown]
/// shows it as ([planFxBake]): each cel it does not show kept as it is,
/// each it shows parted into its pictures.
_Bank _bankOf(
  FxBakeTaking taking,
  Cut shown,
  List<List<CutFrameCompositeSpan>> runs,
  FrameId Function(LayerId row) mintFrameId,
) {
  final FxBakeTaking(:cut, :row) = taking;
  // Each picture, by the cel it was baked of: the first keeps the cel's
  // place, the rest are new.
  final byCel = <FrameId, List<List<CutFrameCompositeSpan>>>{};
  for (final spans in runs) {
    final cel = exposedCelIdAt(
      cut: shown,
      layerId: row.id,
      frameIndex: spans.first.start,
    )!;
    (byCel[cel] ??= []).add(spans);
  }
  final held = {for (final cel in row.frames) ?celNumberOf(cel.name)};
  final bank = <Frame>[];
  final celAt = <int, FrameId>{};
  final pictures = <LayerMergePicture>[];
  for (final cel in row.frames) {
    final parts = byCel[cel.id];
    if (parts == null) {
      bank.add(cel);
      continue;
    }
    for (final (index, spans) in parts.indexed) {
      final made = Frame(
        id: mintFrameId(row.id),
        duration: spans.first.length,
        name: index == 0 ? cel.name : _tailed(held, cel.name),
        strokes: const [],
      );
      bank.add(made);
      for (final span in spans) {
        for (var frame = span.start; frame < span.endExclusive; frame += 1) {
          celAt[frame] = made.id;
        }
      }
      pictures.add((
        into: cut,
        rowId: row.id,
        frameId: made.id,
        from: shown,
        frameIndex: spans.first.start,
      ));
    }
  }
  return (
    cels: bank,
    celAt: celAt,
    pictures: pictures,
    firstOf: {
      for (final MapEntry(key: cel, value: parts) in byCel.entries)
        cel: celAt[parts.first.first.start]!,
    },
  );
}

/// [cut] holding [row] alone as it is drawn into its cels: shown, laying
/// nothing of its own over them — no strength, blend, clip or folder — and
/// wearing the fx [effectId] alone, or the transform alone where null. The
/// rows the fx reads (a lens blur's map) stand by it hidden, read as they
/// are (🗣️I-132-Q23 「꺼도 맵으로 읽는다」).
Cut _wearingOnly(Cut cut, Layer row, EffectId? effectId) {
  final fx = [
    for (final effect in row.effects)
      if (effect.id == effectId) effect,
  ];
  final read = {
    for (final effect in fx) ...effect.layers.values.nonNulls,
  }..remove(row.id);
  return cut.copyWith(
    layers: [
      for (final layer in cut.layers)
        if (read.contains(layer.id))
          layer.copyWith(isVisible: false, folderId: null)
        else if (layer.id == row.id)
          row.copyWith(
            isVisible: true,
            opacity: 1,
            blendMode: LayerBlendMode.normal,
            clipsToBelow: false,
            folderId: null,
            effects: fx,
            transformTrack: effectId == null
                ? row.transformTrack
                : TransformTrack.empty(),
          ),
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

/// [fx] with every value and key back at its default — and switched off
/// where its defaults still change the picture (Q4), so the cels it was
/// baked into do not wear it twice.
LayerEffect _atItsDefaults(LayerEffect fx) => LayerEffect(
  id: fx.id,
  kind: fx.kind,
  plugin: fx.plugin,
  enabled: fx.enabled && fx.kind.changesNothingAtItsDefaults,
  basis: fx.basis,
);

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
