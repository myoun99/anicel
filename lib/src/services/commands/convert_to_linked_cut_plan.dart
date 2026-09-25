import 'package:collection/collection.dart' show IterableExtension;

import '../../models/cut.dart';
import '../../models/frame_id.dart';
import '../../models/layer.dart';
import '../../models/layer_id.dart';
import '../../models/project.dart';

/// The 겸용 변경 plan: what linking [targetCutId] to [originCutId] will
/// do, computed BEFORE executing — this is the data the friendly
/// confirmation dialog shows (링크 목록, 교체 장수, 새로 나타나는 항목,
/// 보존 팁, undo 명시), and the command's exact work order.
///
/// Rules (user-confirmed): matching is by NAME ([_partnersByOrigin] pairs
/// namesakes) — the SINGLETON kinds (one
/// conte row, one camera row a cut) by KIND; conflicts resolve
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

  /// Matched (origin layer, target layer) pairs that will link — by name,
  /// or by kind for a singleton kind.
  final List<({LayerId originLayerId, LayerId targetLayerId})> layerPairs;

  /// Origin drawing layers with no partner in the target — the target
  /// gains linked copies with empty timelines.
  final List<LayerId> originOnlyLayerIds;

  /// Target drawing layers with no partner in the origin — the origin
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
  // The CONVERT rule ([LayerKind.joinsLinkedCutConvert]), a shade narrower
  // than 겸용컷 생성's: a row this union APPENDS lands at the top with its
  // folder stripped, which an ADJUSTMENT row cannot survive (its position
  // is what it grades). The two rules used to be hand-written here and in
  // the create planner, and the copies had already drifted — this one had
  // no folder clause. Layer pairing stays by NAME — a singleton kind's by
  // KIND, below.
  bool linksIntoLinkedCut(Layer layer) => layer.kind.joinsLinkedCutConvert;
  final originDrawing = [
    for (final layer in originCut.layers)
      if (linksIntoLinkedCut(layer)) layer,
  ];
  final targetDrawing = [
    for (final layer in targetCut.layers)
      if (linksIntoLinkedCut(layer)) layer,
  ];
  bool alreadyLinked(Layer origin, Layer target) =>
      project.linkRegistry
          .groupOf(cutId: targetCut.id, layerId: target.id)
          ?.contains(cutId: originCut.id, layerId: origin.id) ??
      false;
  final partners = _partnersByOrigin(
    origins: originDrawing,
    targets: targetDrawing,
    alreadyLinked: alreadyLinked,
  );
  final matchedTargetIds = <LayerId>{};
  final matchedOriginIds = <LayerId>{};

  final pairs = <({LayerId originLayerId, LayerId targetLayerId})>[];
  var replaced = 0;
  var joining = 0;
  for (final origin in originDrawing) {
    final target = partners[origin.id];
    if (target == null) {
      continue;
    }
    matchedTargetIds.add(target.id);
    matchedOriginIds.add(origin.id);
    // Already linked to each other (e.g. a 겸용 re-run): nothing to do.
    if (alreadyLinked(origin, target)) {
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

/// Which target row each origin row links to, by origin id.
///
/// Rows pair within their NAME — and a SINGLETON kind within its KIND
/// (F-84): each cut holds one conte row and one camera row whatever they are
/// called, and pairing them by name would union a SECOND one into each cut
/// the moment the names differ.
///
/// 🗣️Several rows may share a name — image rows stack as BOOK, BOOK, …
/// (유저 2026-09-25: 「레이어이름+프레임이름 통해서 같은거끼리 짝짓고, 아니면
/// 쌓인 순서대로」). Within a name, rows pair in three passes: the rows
/// already linked to each other (a 겸용 re-run must find its own partner,
/// not a namesake), then the rows sharing a picture NAME, then the rest in
/// stacking order. ↩️It was one map by name, and of two namesakes the last
/// one silently won.
///
/// Pairs are SAME-KIND only: an image row and an animation row can wear one
/// name, and a cross-kind link group would hand a BG picture to a drawing
/// row (and make updateLayerKind's kind-mirror meaningless). A name
/// collision across kinds simply doesn't match.
Map<LayerId, Layer> _partnersByOrigin({
  required List<Layer> origins,
  required List<Layer> targets,
  required bool Function(Layer origin, Layer target) alreadyLinked,
}) {
  Object pairingKey(Layer layer) =>
      layer.kind.isSingletonPerCut ? layer.kind : (layer.kind, layer.name);
  final targetsByKey = <Object, List<Layer>>{};
  for (final target in targets) {
    targetsByKey.putIfAbsent(pairingKey(target), () => []).add(target);
  }
  final partners = <LayerId, Layer>{};
  final taken = <LayerId>{};
  void pairWhere(bool Function(Layer origin, Layer target) same) {
    for (final origin in origins) {
      if (partners.containsKey(origin.id)) {
        continue;
      }
      final target = targetsByKey[pairingKey(origin)]?.firstWhereOrNull(
        (target) => !taken.contains(target.id) && same(origin, target),
      );
      if (target != null) {
        partners[origin.id] = target;
        taken.add(target.id);
      }
    }
  }

  pairWhere(alreadyLinked);
  pairWhere(_shareAPictureName);
  pairWhere((_, _) => true);
  return partners;
}

/// Whether [origin] and [target] hold a cel of the same name — the name
/// that is a picture's identity on a row (「같은 이름 = 같은 그림」).
bool _shareAPictureName(Layer origin, Layer target) {
  final names = {
    for (final frame in origin.frames)
      if (frame.celNumber != null) frame.celNumber,
  };
  return target.frames.any((frame) => names.contains(frame.celNumber));
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
    this.canvasSizesDiffer = false,
  });

  final String targetCutName;
  final List<String> linkingLayerNames;
  final List<String> layerNamesAppearingInTarget;
  final List<String> layerNamesAppearingInOrigin;
  final int replacedFrameCount;
  final int joiningFrameCount;
  final bool linksAnything;

  /// The two cuts do not share a canvas size.
  ///
  /// Linking makes them show ONE physical cel, and a size they disagree on
  /// puts that one picture in two differently-shaped frames. Linking still
  /// goes ahead — the origin's size wins, like its pictures do — but the
  /// target's artwork can end up outside the frame, so the 안내문 says to
  /// match the sizes first.
  final bool canvasSizesDiffer;
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
      origin.kind.holdsSingleCel &&
      target.kind.holdsSingleCel &&
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
