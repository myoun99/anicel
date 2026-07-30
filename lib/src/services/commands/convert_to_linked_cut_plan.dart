import '../../models/cut.dart';
import '../../models/frame_id.dart';
import '../../models/layer.dart';
import '../../models/layer_id.dart';
import '../../models/layer_kind.dart';
import '../../models/project.dart';

/// The 겸용 변경 plan: what linking [targetCutId] to [originCutId] will
/// do, computed BEFORE executing — this is the data the friendly
/// confirmation dialog shows (링크 목록, 교체 장수, 새로 나타나는 항목,
/// 보존 팁, undo 명시), and the command's exact work order.
///
/// Rules (user-confirmed): matching is by NAME; conflicts resolve
/// **원본 승리** exactly once at conversion; unique frames JOIN the
/// shared bank both ways; layers present on one side only UNION into the
/// other with empty timelines (완전 미러).
class ConvertToLinkedCutPlan {
  const ConvertToLinkedCutPlan({
    required this.layerPairs,
    required this.originOnlyLayerIds,
    required this.targetOnlyLayerIds,
    required this.replacedFrameCount,
    required this.joiningFrameCount,
  });

  /// Name-matched (origin layer, target layer) pairs that will link.
  final List<({LayerId originLayerId, LayerId targetLayerId})> layerPairs;

  /// Origin drawing layers with no name match in the target — the target
  /// gains linked copies with empty timelines.
  final List<LayerId> originOnlyLayerIds;

  /// Target drawing layers with no name match in the origin — the origin
  /// gains linked copies with empty timelines.
  final List<LayerId> targetOnlyLayerIds;

  /// Frames whose name exists on both sides with DIFFERENT ids: the
  /// target's picture is REPLACED by the origin's ("같은 이름의 그림
  /// n장이 원본 컷의 그림으로 바뀝니다").
  final int replacedFrameCount;

  /// Target-only frames joining the shared bank (visible from the origin
  /// afterwards — the union is bidirectional).
  final int joiningFrameCount;

  bool get linksAnything =>
      layerPairs.isNotEmpty ||
      originOnlyLayerIds.isNotEmpty ||
      targetOnlyLayerIds.isNotEmpty;
}

/// Per matched layer pair: how the TARGET's frames map into the merged
/// bank (the command executes exactly this).
class LayerMergeResolution {
  const LayerMergeResolution({
    required this.originLayerId,
    required this.targetLayerId,
    required this.retargetedFrameIds,
    required this.joiningFrameIds,
  });

  final LayerId originLayerId;
  final LayerId targetLayerId;

  /// Target frame id → origin frame id, for same-NAME frames with
  /// different ids (원본 승리: exposures retarget, the target's own
  /// picture is superseded).
  final Map<FrameId, FrameId> retargetedFrameIds;

  /// Target-only frames whose cels move into the canonical bank.
  final List<FrameId> joiningFrameIds;
}

/// Computes the 겸용 변경 plan. Pure — safe to call for the dialog and
/// again inside the command.
ConvertToLinkedCutPlan planConvertToLinkedCut({
  required Project project,
  required Cut originCut,
  required Cut targetCut,
}) {
  // The CONVERT rule ([layerKindJoinsLinkedCutConvert]), a shade narrower
  // than 겸용컷 생성's: a row this union APPENDS lands at the top with its
  // folder stripped, which an ADJUSTMENT row cannot survive (its position
  // is what it grades). The two rules used to be hand-written here and in
  // the create planner, and the copies had already drifted — this one had
  // no folder clause. Layer pairing stays by NAME.
  bool linksIntoLinkedCut(Layer layer) =>
      layerKindJoinsLinkedCutConvert(layer.kind);
  final originDrawing = [
    for (final layer in originCut.layers)
      if (linksIntoLinkedCut(layer)) layer,
  ];
  final targetDrawing = [
    for (final layer in targetCut.layers)
      if (linksIntoLinkedCut(layer)) layer,
  ];
  final targetByName = <String, Layer>{
    for (final layer in targetDrawing) layer.name: layer,
  };
  final matchedTargetIds = <LayerId>{};
  final matchedOriginIds = <LayerId>{};

  final pairs = <({LayerId originLayerId, LayerId targetLayerId})>[];
  var replaced = 0;
  var joining = 0;
  for (final origin in originDrawing) {
    final target = targetByName[origin.name];
    // Pairs are SAME-KIND only: image and animation rows draw names from
    // the same A/B/C pool, and a cross-kind link group would hand a BG
    // picture to a drawing row (and make updateLayerKind's kind-mirror
    // meaningless). A name collision across kinds simply doesn't match.
    if (target == null || target.kind != origin.kind) {
      continue;
    }
    matchedTargetIds.add(target.id);
    matchedOriginIds.add(origin.id);
    // Already linked to each other (e.g. a 겸용 re-run): nothing to do.
    final alreadyLinked =
        project.linkRegistry
            .groupOf(cutId: targetCut.id, layerId: target.id)
            ?.contains(cutId: originCut.id, layerId: origin.id) ??
        false;
    if (alreadyLinked) {
      continue;
    }
    pairs.add((originLayerId: origin.id, targetLayerId: target.id));
    final resolution = resolveLayerMerge(origin: origin, target: target);
    replaced += resolution.retargetedFrameIds.length;
    joining += resolution.joiningFrameIds.length;
  }

  return ConvertToLinkedCutPlan(
    layerPairs: pairs,
    // Name-matched but ALREADY-LINKED layers are neither pairs nor
    // "only" — filtering on matched ids (not pairs) keeps a 겸용 re-run
    // from inserting duplicate copies of already-linked layers.
    originOnlyLayerIds: [
      for (final origin in originDrawing)
        if (!matchedOriginIds.contains(origin.id)) origin.id,
    ],
    targetOnlyLayerIds: [
      for (final target in targetDrawing)
        if (!matchedTargetIds.contains(target.id)) target.id,
    ],
    replacedFrameCount: replaced,
    joiningFrameCount: joining,
  );
}

/// [ConvertToLinkedCutPlan] resolved to display strings — exactly what
/// the 안내문 dialog shows (the session builds this from the plan).
class ConvertToLinkedCutPreviewData {
  const ConvertToLinkedCutPreviewData({
    required this.targetCutName,
    required this.linkingLayerNames,
    required this.layerNamesAppearingInTarget,
    required this.layerNamesAppearingInOrigin,
    required this.replacedFrameCount,
    required this.joiningFrameCount,
    required this.linksAnything,
  });

  final String targetCutName;
  final List<String> linkingLayerNames;
  final List<String> layerNamesAppearingInTarget;
  final List<String> layerNamesAppearingInOrigin;
  final int replacedFrameCount;
  final int joiningFrameCount;
  final bool linksAnything;
}

/// The frame-level merge for one matched pair (원본 승리):
/// - same name, same id → already shared, nothing to do;
/// - same name, different id → RETARGET (target's picture superseded);
/// - target-only name → JOIN the bank.
LayerMergeResolution resolveLayerMerge({
  required Layer origin,
  required Layer target,
}) {
  final originByName = <String?, FrameId>{
    for (final frame in origin.frames) frame.name: frame.id,
  };
  final originIds = {for (final frame in origin.frames) frame.id};

  final retargeted = <FrameId, FrameId>{};
  final joiningIds = <FrameId>[];
  // The IMAGE-LAYER exception (§6-z23 ③, user-confirmed): an image row
  // holds ONE cel by definition and its name defaults to none, so the
  // single unnamed cels match each other by POSITION — the shared BG
  // links without anyone naming a frame. Guarded to the single-cel case
  // on both sides so ambiguity cannot arise; drawing layers keep the
  // unnamed-never-conflicts rule below (unnamed cels can be many).
  final imageSingleCelPair =
      layerKindHoldsSingleCel(origin.kind) &&
      layerKindHoldsSingleCel(target.kind) &&
      origin.frames.length == 1 &&
      target.frames.length == 1 &&
      origin.frames.single.name == null &&
      target.frames.single.name == null;
  for (final frame in target.frames) {
    if (originIds.contains(frame.id)) {
      continue; // Already the same physical cel.
    }
    if (imageSingleCelPair) {
      retargeted[frame.id] = origin.frames.single.id;
      continue;
    }
    final originId = originByName[frame.name];
    // UNNAMED frames never conflict (no identity to match on) — they
    // join the bank as the target's own cels.
    if (frame.name != null && originId != null) {
      retargeted[frame.id] = originId;
    } else {
      joiningIds.add(frame.id);
    }
  }
  return LayerMergeResolution(
    originLayerId: origin.id,
    targetLayerId: target.id,
    retargetedFrameIds: retargeted,
    joiningFrameIds: joiningIds,
  );
}
