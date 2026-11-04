import 'dart:collection' show SplayTreeMap;

import '../../models/attached_layer_resolve.dart'
    show attachedMirrorCelId, fxCarrierOf, isSyncedAttachedLayer;
import '../../models/audio_clip.dart';
import '../../models/canvas_point.dart';
import '../../models/conte_group.dart' show ridesTheConte;
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
import '../commands/link_mirror.dart' show existenceMirrorTargets;
import '../cut_frame_composite_plan.dart' show exposedCelIdAt;
import '../playback/cut_frame_composite_signature.dart'
    show BrushFrameRevisionResolver;
import '../playback/cut_frame_composite_spans.dart';
import '../project_lookup.dart' show requireCut;
import 'layer_merge_plan.dart'
    show
        CelReads,
        LayerMergePicture,
        drawnBare,
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

/// The frames a press of RASTERIZE bakes, from [start] to [end]
/// (exclusive).
typedef BakedFrames = ({int start, int end});

/// What ONE press of RASTERIZE in a row's fx group header takes: the row,
/// the fx — the transform, where [effectId] is null — the rows riding the
/// row that wear it, and the [frames] it bakes.
final class FxBakeTaking {
  const FxBakeTaking._(
    this.cut,
    this.row,
    this.effectId,
    this._riders,
    this._drawnFrames,
    this.frames,
  );

  /// The cut it was taken of.
  final Cut cut;

  /// The row it bakes.
  final Layer row;

  /// The fx it bakes; null for the transform.
  final EffectId? effectId;

  /// The rows riding [row] that wear its fx and its transform
  /// ([fxCarrierOf]), baked with it (I-120 ②b — 「어태치 레이어는 주인과
  /// 같이 굽는다」, 07-21).
  final List<Layer> _riders;

  /// The cut's drawn length, which the rows' holds and repeats fill to.
  final int _drawnFrames;

  /// The frames it bakes: the band's, where one scopes the press, else
  /// every frame the cut draws (🗣️I-120-Q3 「범위 안만 굽고, 범위 밖은
  /// 보이던 그대로」 — with no band the range is the row, and the one code
  /// clears every key).
  final BakedFrames frames;

  /// Whether a frame the cut draws lies outside [frames].
  bool get _keepsAFrame => !_coversEvery(frames, _drawnFrames);

  /// Whether it bakes a part of the row an fx that draws at its defaults —
  /// the cel number's, a plugin's — would go on drawing outside: its switch
  /// has no key, so it cannot be off for [frames] alone. 🗣️I-120-Q14, its
  /// recommendation while it is asked 「막고 경고」 (Q6's law for what one
  /// picture cannot hold): it bakes nothing, and says why.
  bool get cannotKeepTheRest =>
      _keepsAFrame &&
      row.effects.any(
        (fx) => fx.id == effectId && !fx.kind.changesNothingAtItsDefaults,
      );

  /// It scoped to the frames of its own [band] holds — the band scoping the
  /// press (Q3) — as it is where none does, and null where the band holds
  /// none of them.
  FxBakeTaking? over(BakedFrames? band) {
    if (band == null) {
      return this;
    }
    final start = band.start < frames.start ? frames.start : band.start;
    final end = band.end > frames.end ? frames.end : band.end;
    return start < end
        ? FxBakeTaking._(
            cut,
            row,
            effectId,
            _riders,
            _drawnFrames,
            (start: start, end: end),
          )
        : null;
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
/// ⚠️Rows this round (② of the card's) does not bake yet stand down, as a
/// merge's did until the round that took them, wherever the press reaches
/// one — its row or a row riding it: a row whose cels another cut shows too
/// (④, Q6 — every use baked together), a row of a track's conte — the conte
/// and the rows riding it, which wear fx of their own (④, Q7 · I-99) — and
/// a reference row (⑤, Q5 · Q11). The card's order, not a law of the verb.
///
/// It bakes every frame the cut draws; a band scoping the press narrows it
/// ([FxBakeTaking.over]).
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
  final riders = [
    for (final other in cut.layers)
      if (other.id != row.id &&
          other.kind.isDrawingCel &&
          fxCarrierOf(other, cut.layers)?.id == row.id)
        other,
  ];
  if (_waitsForALaterRound(project, cut, [row, ...riders])) {
    return null;
  }
  final drawn = cutDrawnFrameCount(project, cutId) ?? cut.duration;
  return FxBakeTaking._(
    cut,
    row,
    effectId,
    riders,
    drawn,
    (start: 0, end: drawn),
  );
}

bool _waitsForALaterRound(Project project, Cut cut, List<Layer> reached) =>
    reached.any(
      (row) =>
          existenceMirrorTargets(
                project,
                cutId: cut.id,
                layerId: row.id,
              ).length >
              1 ||
          conteBaseOf(cut)?.id == row.id ||
          ridesTheConte(row, cut.layers) ||
          row.mediaReference != null,
    );

/// What a press of RASTERIZE makes of [taking]'s row: its pictures with the
/// fx baked in, and the row after.
class FxBakePlan {
  const FxBakePlan._({
    required this.cut,
    required this.row,
    required this.riders,
    required this.pictures,
    required this.changes,
  });

  /// The cut it was planned of, as it was.
  final Cut cut;

  /// The row after: its cels the baked pictures, the fx at its defaults.
  final Layer row;

  /// The rows riding [row] after, their cels the pictures they showed
  /// wearing the fx ([_riderBaked]).
  final List<Layer> riders;

  /// Every new cel's picture, still to be laid: each drawn of the row
  /// wearing the baked fx alone ([_wearingOnly]), or of a rider riding it
  /// so ([_ridingOnly]).
  final List<LayerMergePicture> pictures;

  final Set<FxBakeChange> changes;

  /// The cut's rows after: [row] and [riders] where they stood.
  List<Layer> get layers {
    final after = {row.id: row, for (final rider in riders) rider.id: rider};
    return [for (final layer in cut.layers) after[layer.id] ?? layer];
  }
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
/// drawing row (I-120: 「애니메이션레이어로 전환」). The rows riding the row
/// wear its fx, so they are baked with it ([_riderBaked]).
///
/// [reads] says how the cut's cels are read; [mintFrameId] names each new
/// cel; [reach] is how far past the canvas the wall stands.
FxBakePlan planFxBake(
  FxBakeTaking taking, {
  required CelReads reads,
  required FrameId Function(LayerId row) mintFrameId,
  required PasteboardReach reach,
}) {
  assert(!taking.cannotKeepTheRest, 'it bakes nothing, and says why');
  final FxBakeTaking(:cut, :row, :effectId, :frames) = taking;
  final shown = _wearingOnly(cut, row, effectId);
  final runs = runsByPicture(shown, [
    shown.layers.byId(row.id)!,
  ], reads.revisionOf);
  final bank = _bankOf(
    cut,
    row,
    (cut: shown, runs: runs, baked: frames),
    (_) => mintFrameId(row.id),
  );
  final baked = _rowBaked(taking, bank);
  final riders = [
    for (final rider in taking._riders)
      _riderBaked(taking, rider, (runs: runs, bank: bank), (
        revisionOf: reads.revisionOf,
        mintFrameId: mintFrameId,
      )),
  ];
  final pictures = [
    ...bank.pictures,
    for (final rider in riders) ...rider.pictures,
  ];
  return FxBakePlan._(
    cut: cut,
    row: baked,
    riders: [for (final rider in riders) rider.row],
    pictures: pictures,
    changes: {
      if (_runsAfterAnFxOn(row, effectId)) FxBakeChange.order,
      if (picturesCutAtTheWall(pictures, (
        wall: cut.canvasSize.pasteboardAt(reach),
        inkOf: reads.inkOf,
      )))
        FxBakeChange.wall,
    },
  );
}

/// [taking]'s row after its bake: its cels [bank], its blocks parted where
/// its pictures are, and each of its FX bundles kept showing what it showed
/// ([_Keeping]) — the one baked at rest over the frames baked.
Layer _rowBaked(FxBakeTaking taking, _Bank bank) {
  final FxBakeTaking(:cut, :row, :effectId, :frames) = taking;
  final parted = row.copyWith(
    kind: kindHoldingPictures(row.kind, bank.cels.length),
    frames: bank.cels,
    timeline: _timelineShowing(row, bank.celAt, taking._drawnFrames),
  );
  _Keeping keeping(FxBasis basis, {required bool baked}) => _Keeping(
    taking._drawnFrames,
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
    audioClips: _clipsAfter(row, bank),
  );
}

/// The cels a bake leaves a row: [cels] its bank, [celAt] the cel each
/// frame shows, [pictures] each new cel's picture still to be laid, and
/// [firstOf] the first picture each cel baked became.
typedef _Bank = ({
  List<Frame> cels,
  Map<int, FrameId> celAt,
  List<LayerMergePicture> pictures,
  Map<FrameId, FrameId> firstOf,
});

/// A row as a bake draws it: the [cut] it is drawn of, the [runs] of
/// frames it shows one picture over there ([runsByPicture]), and the frames
/// [baked] of them.
typedef _Shown = ({
  Cut cut,
  List<List<CutFrameCompositeSpan>> runs,
  BakedFrames baked,
});

/// [row]'s bank after the bake, as [shown] shows it — each new cel named
/// [idOf] its run, its picture laid into [into]: each cel it does not show
/// over the frames baked kept as it is, each it shows there parted into its
/// pictures — and kept besides where it still shows outside them, its
/// pictures all new (🗣️I-120-Q3 「범위 밖은 보이던 그대로」).
_Bank _bankOf(
  Cut into,
  Layer row,
  _Shown shown,
  FrameId Function(List<CutFrameCompositeSpan> run) idOf,
) {
  final (:baked, :celAt) = _bakedRuns(row, shown);
  final outside = {
    for (final MapEntry(key: frame, value: cel) in celAt.entries)
      if (frame < shown.baked.start || frame >= shown.baked.end) cel,
  };
  final held = {for (final cel in row.frames) ?celNumberOf(cel.name)};
  final bank = <Frame>[];
  final pictures = <LayerMergePicture>[];
  final firstOf = <FrameId, FrameId>{};
  for (final cel in row.frames) {
    final parts = baked[cel.id] ?? const [];
    // The first picture keeps the place of a cel shown nowhere else.
    final kept = parts.isEmpty || outside.contains(cel.id);
    if (kept) {
      bank.add(cel);
    }
    for (final (index, spans) in parts.indexed) {
      final made = Frame(
        id: idOf(spans),
        duration: spans.first.length,
        name: index == 0 && !kept ? cel.name : _tailed(held, cel.name),
        strokes: const [],
      );
      bank.add(made);
      if (index == 0 && !kept) {
        firstOf[cel.id] = made.id;
      }
      for (final span in spans) {
        for (var frame = span.start; frame < span.endExclusive; frame += 1) {
          celAt[frame] = made.id;
        }
      }
      pictures.add((
        into: into,
        rowId: row.id,
        frameId: made.id,
        from: shown.cut,
        frameIndex: spans.first.start,
      ));
    }
  }
  return (cels: bank, celAt: celAt, pictures: pictures, firstOf: firstOf);
}

/// [row]'s runs as [shown] shows them: each of its cels' runs over the
/// frames baked ([baked]), and the cel it shows at every frame it shows
/// one ([celAt]). A run [row] shows nothing over is none of its.
({
  Map<FrameId, List<List<CutFrameCompositeSpan>>> baked,
  Map<int, FrameId> celAt,
})
_bakedRuns(Layer row, _Shown shown) {
  final baked = <FrameId, List<List<CutFrameCompositeSpan>>>{};
  final celAt = <int, FrameId>{};
  for (final spans in shown.runs) {
    final cel = exposedCelIdAt(
      cut: shown.cut,
      layerId: row.id,
      frameIndex: spans.first.start,
    );
    if (cel == null) {
      continue;
    }
    final inside = [for (final span in spans) ?_within(span, shown.baked)];
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

/// [row]'s sounds after [bank]: a cel baked takes its sounds to its first
/// picture.
List<AudioClip> _clipsAfter(Layer row, _Bank bank) => [
  for (final clip in row.audioClips)
    switch (bank.firstOf[clip.frameId]) {
      final made? => clip.copyWith(frameId: made),
      null => clip,
    },
];

/// What the rows riding a baked row are baked against: the row's [runs]
/// by picture, and its [bank] after.
typedef _Ridden = ({List<List<CutFrameCompositeSpan>> runs, _Bank bank});

/// What a new cel is made under: what each cel holds as the composite
/// signature reads it, and the minting of a row's new cel.
typedef _Minting = ({
  BrushFrameRevisionResolver revisionOf,
  FrameId Function(LayerId row) mintFrameId,
});

/// [rider] after [taking]'s bake, and the pictures its new cels are baked
/// from — each drawn of the row it rides wearing what is baked
/// ([_ridingOnly]), as a merge draws a rider of its base (I-78).
///
/// A free rider parts where its own picture does, as the row does. A synced
/// one rides the row's cels one for one ([ridden]): a cel for each of the
/// row's new ones it shows one over, under the id its mirror of that cel is
/// minted by ([attachedMirrorCelId]), as a merge's synced rider takes.
({Layer row, List<LayerMergePicture> pictures}) _riderBaked(
  FxBakeTaking taking,
  Layer rider,
  _Ridden ridden,
  _Minting minting,
) {
  final alone = _ridingOnly(taking, rider);
  final synced = isSyncedAttachedLayer(rider);
  final bank = synced
      ? _bankOf(
          taking.cut,
          rider,
          (cut: alone, runs: ridden.runs, baked: taking.frames),
          (run) => attachedMirrorCelId(
            rider.id,
            ridden.bank.celAt[run.first.start]!,
          ),
        )
      : _bankOf(
          taking.cut,
          rider,
          (
            cut: alone,
            runs: runsByPicture(alone, [rider], minting.revisionOf),
            baked: taking.frames,
          ),
          (_) => minting.mintFrameId(rider.id),
        );
  final after = rider.copyWith(
    kind: kindHoldingPictures(rider.kind, bank.cels.length),
    frames: bank.cels,
    audioClips: _clipsAfter(rider, bank),
  );
  return (
    row: synced
        ? after.copyWith(baseFrameLinks: _linksAfter(rider, ridden.bank, bank))
        : after.copyWith(
            timeline: _timelineShowing(rider, bank.celAt, taking._drawnFrames),
          ),
    pictures: bank.pictures,
  );
}

/// A synced [rider]'s links after its base's bake ([base]) and its own
/// ([bank]): each of the base's cels kept to the cel it showed — its first
/// picture, where that was baked — and each of the base's new cels to the
/// rider's cel over it.
Map<FrameId, FrameId> _linksAfter(Layer rider, _Bank base, _Bank bank) => {
  for (final MapEntry(key: baseCel, value: cel)
      in rider.baseFrameLinks.entries)
    if (!base.firstOf.containsKey(baseCel)) baseCel: bank.firstOf[cel] ?? cel,
  for (final MapEntry(key: frame, value: cel) in bank.celAt.entries)
    base.celAt[frame]!: cel,
};

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

/// [taking]'s cut holding [rider] as it rides, drawn bare out of any folder
/// over its row hidden wearing what is baked ([_wearingOnly]) — so what the
/// rider is drawn of the row is what it wore of it: the fx alone, or the
/// transform alone. A row's eye is its own (UI-R24 #5), so the row hidden
/// hides nothing of the rider.
Cut _ridingOnly(FxBakeTaking taking, Layer rider) {
  final FxBakeTaking(:cut, :row, :effectId) = taking;
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

  bool _bakes(int frame) => switch (baked) {
    (:final start, :final end) => start <= frame && frame < end,
    null => false,
  };

  /// Each run of the frames it does not bake that read at a frame of their
  /// own after the bake — each from the [head] of the block it parted.
  late final List<({int start, int end, int head})> _parted = () {
    final runs = <({int start, int end, int head})>[];
    for (var frame = 0; frame < frames; frame += 1) {
      final head = reads.was(frame);
      if (reads.now(frame) == head || _bakes(frame)) {
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
          _bakes(frame) ? rest : shown(track, reads.was(frame), before),
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
