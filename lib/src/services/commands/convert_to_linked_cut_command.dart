import '../../models/brush_frame_key.dart';
import '../../models/cut_id.dart';
import '../../models/frame.dart';
import '../../models/frame_id.dart';
import '../../models/layer.dart';
import '../../models/layer_id.dart';
import '../../models/layer_link_join.dart';
import '../../models/layer_link_registry.dart';
import '../../models/project.dart';
import '../../models/project_id.dart';
import '../../models/timeline_exposure.dart';
import '../../models/track_id.dart';
import '../brush_frame_store.dart';
import '../command.dart';
import '../editing/default_layer_helpers.dart';
import '../project_lookup.dart';
import '../project_tree_editor.dart';
import '../project_repository.dart';
import 'convert_to_linked_cut_plan.dart';

/// 겸용 변경 (L2b): links [targetCutId] to [originCutId] AFTER both were
/// drawn — the "타이밍까지 통째 겸용 = 복제→변경" path and the standalone
/// convert. Matches drawing layers by name and merges their banks with
/// **원본 승리**: conflicting target cels are superseded by the origin's;
/// unique target cels JOIN the shared bank; one-side-only layers UNION
/// into the other with empty timelines (완전 미러). The target's timeline
/// numbers stay put — only the pictures link ("겸용 설정은 그림만 잇는다").
///
/// Undo is snapshot-based: every changed layer's before-state, the
/// registry, the joined-cel rekeys, and the union-copy ids — restored in
/// reverse. One undo step for the whole conversion.
class ConvertToLinkedCutCommand implements Command {
  ConvertToLinkedCutCommand({
    required this.repository,
    required this.brushFrameStore,
    required this.originCutId,
    required this.targetCutId,
    required this.unionLayerIdMap,
    required this.newGroupIdBySource,
    required this.coveringFrameIdBySource,
  });

  final ProjectRepository repository;
  final BrushFrameStore brushFrameStore;
  final CutId originCutId;
  final CutId targetCutId;

  /// Planned ids for the union copies: source (cut, layer) → new layer id
  /// in the OTHER cut. Keyed by the owning cut so origin-only and
  /// target-only copies never collide.
  final Map<(CutId, LayerId), LayerId> unionLayerIdMap;

  /// Planned registry group ids for pairs/unions not linked yet, keyed by
  /// the origin-side (or origin-only / target-only) source layer id.
  final Map<LayerId, String> newGroupIdBySource;

  /// The planned fresh panel of each union copy born covering the cut it
  /// lands in (F-99), keyed like [unionLayerIdMap].
  final Map<(CutId, LayerId), FrameId> coveringFrameIdBySource;

  LayerLinkRegistry? _registryBefore;
  final List<(BrushFrameKey, BrushFrameKey)> _rekeys = [];
  bool _hasExecuted = false;

  @override
  String get description => 'Convert cut $targetCutId to link $originCutId';

  @override
  void execute() {
    final project = repository.requireProject();
    final origin = requireCutPosition(project, originCutId);
    final originTrack = origin.track;
    final originCut = origin.cut;
    final target = requireCutPosition(project, targetCutId);
    final targetTrack = target.track;
    final targetCut = target.cut;
    final plan = planConvertToLinkedCut(
      project: project,
      originCut: originCut,
      targetCut: targetCut,
    );

    if (_registryBefore == null) {
      // Capture the exact pre-conversion state once (redo re-runs from
      // the restored state, so re-capturing would be wrong).
      _registryBefore = project.linkRegistry;
      _snapshotOrigin = [...originCut.layers];
      _snapshotTarget = [...targetCut.layers];
    }
    var groups = [...project.linkRegistry.groups];

    // Working copies of the two cuts' layer lists we mutate in place.
    final originLayers = [...originCut.layers];
    final targetLayers = [...targetCut.layers];

    // 1. Matched pairs: merge banks (origin wins) and link.
    for (final pair in plan.layerPairs) {
      final origin = originLayers.firstWhere(
        (layer) => layer.id == pair.originLayerId,
      );
      final target = targetLayers.firstWhere(
        (layer) => layer.id == pair.targetLayerId,
      );
      final resolution = resolveLayerMerge(origin: origin, target: target);

      // The joining cels move to the canonical (origin) key; the resolver
      // is not installed for these keys yet, so raw rekey is exact.
      final joiningFrames = <Frame>[];
      for (final frameId in resolution.joiningFrameIds) {
        _rekeys.add((
          _celKey(project.id, targetTrack.id, targetCutId, target.id, frameId),
          _celKey(project.id, originTrack.id, originCutId, origin.id, frameId),
        ));
        joiningFrames.add(
          target.frames.firstWhere((frame) => frame.id == frameId),
        );
      }
      final mergedBank = [...origin.frames, ...joiningFrames];

      // Origin (and every existing member of its group) adopts the bank;
      // here we set the origin layer — other members re-derive lazily
      // through the shared FrameIds (their own frame lists gain the
      // joiners on their next bank edit; the registry link already routes
      // pixels correctly).
      final originIndex = originLayers.indexWhere(
        (layer) => layer.id == origin.id,
      );
      originLayers[originIndex] = origin.copyWith(frames: mergedBank);

      // Target adopts the merged bank; its exposures RE-TARGET conflicting
      // frames onto the origin's (원본 승리) — the timeline numbers stay.
      final targetIndex = targetLayers.indexWhere(
        (layer) => layer.id == target.id,
      );
      targetLayers[targetIndex] = target.copyWith(
        frames: mergedBank,
        timeline: {
          for (final entry in target.timeline.entries)
            entry.key: _retargetExposure(
              entry.value,
              resolution.retargetedFrameIds,
            ),
        },
      );

      groups = linkGroupsJoined(
        groups,
        origin: LayerLinkMember(
          trackId: originTrack.id,
          cutId: originCutId,
          layerId: origin.id,
        ),
        joiner: LayerLinkMember(
          trackId: targetTrack.id,
          cutId: targetCutId,
          layerId: target.id,
        ),
        plannedGroupId: newGroupIdBySource[origin.id],
      );
    }

    // 2. Union: a layer on ONE side only gets a linked copy on the other
    //    (empty timeline — the bank is shared, the rhythm is fresh).
    //
    // ↩️F-99 (유저 2026-09-12): 「콘티레이어 생성시 기본적으로 프레임
    // 생성되는데 그 법 그대로 재사용/통일」 — a row that cannot stand empty,
    // the conte row, is born covering the cut it lands in with a fresh panel
    // instead, and the panel joins the bank of the row it came from
    // (`_unionCopyOf`).
    for (final originLayerId in plan.originOnlyLayerIds) {
      final index = originLayers.indexWhere(
        (layer) => layer.id == originLayerId,
      );
      final union = _unionCopyOf(
        originLayers[index],
        copyId: unionLayerIdMap[(originCutId, originLayerId)]!,
        panel: coveringFrameIdBySource[(originCutId, originLayerId)],
        cutDuration: targetCut.duration,
      );
      originLayers[index] = union.source;
      targetLayers.add(union.copy);
      final copyId = union.copy.id;
      groups = linkGroupsJoined(
        groups,
        origin: LayerLinkMember(
          trackId: originTrack.id,
          cutId: originCutId,
          layerId: originLayerId,
        ),
        joiner: LayerLinkMember(
          trackId: targetTrack.id,
          cutId: targetCutId,
          layerId: copyId,
        ),
        plannedGroupId: newGroupIdBySource[originLayerId],
      );
    }
    for (final targetLayerId in plan.targetOnlyLayerIds) {
      final index = targetLayers.indexWhere(
        (layer) => layer.id == targetLayerId,
      );
      final union = _unionCopyOf(
        targetLayers[index],
        copyId: unionLayerIdMap[(targetCutId, targetLayerId)]!,
        panel: coveringFrameIdBySource[(targetCutId, targetLayerId)],
        cutDuration: originCut.duration,
      );
      targetLayers[index] = union.source;
      originLayers.add(union.copy);
      final copyId = union.copy.id;
      groups = linkGroupsJoined(
        groups,
        // The TARGET side is canonical for a target-only layer (it holds
        // the pixels); the origin gets the copy.
        origin: LayerLinkMember(
          trackId: targetTrack.id,
          cutId: targetCutId,
          layerId: targetLayerId,
        ),
        joiner: LayerLinkMember(
          trackId: originTrack.id,
          cutId: originCutId,
          layerId: copyId,
        ),
        plannedGroupId: newGroupIdBySource[targetLayerId],
      );
    }

    // Move the joining cels to canonical keys BEFORE the resolver links
    // them (raw rekey).
    brushFrameStore.rekeyFrames(_rekeys);

    repository.updateProject(
      (current) => _withBothCutsLayers(
        current,
        origin: originLayers,
        target: targetLayers,
      ).copyWith(linkRegistry: LayerLinkRegistry(groups: groups)),
    );
    _hasExecuted = true;
  }

  @override
  void undo() {
    final registryBefore = _registryBefore;
    if (!_hasExecuted || registryBefore == null) {
      throw StateError('Command has not been executed.');
    }
    // Invert the cel moves first (keys self-resolve with the link gone).
    brushFrameStore.rekeyFrames([
      for (final (from, to) in _rekeys) (to, from),
    ]);
    // Restore both cuts' original layer lists and the registry.
    repository.updateProject(
      (current) => _withBothCutsLayers(
        current,
        origin: _snapshotOrigin,
        target: _snapshotTarget,
      ).copyWith(linkRegistry: registryBefore),
    );
  }

  /// [current] with the origin cut holding [origin] and the target cut
  /// holding [target] — execute and undo swap the same two lists.
  Project _withBothCutsLayers(
    Project current, {
    required List<Layer> origin,
    required List<Layer> target,
  }) {
    final withOrigin =
        updateCutAnywhere(
          current,
          originCutId,
          (cut) => cut.copyWith(layers: origin),
        ) ??
        (throw StateError('Cut not found: $originCutId'));
    return updateCutAnywhere(
          withOrigin,
          targetCutId,
          (cut) => cut.copyWith(layers: target),
        ) ??
        (throw StateError('Cut not found: $targetCutId'));
  }

  // The exact pre-conversion layer lists, captured on the first execute.
  List<Layer> _snapshotOrigin = const [];
  List<Layer> _snapshotTarget = const [];

  TimelineExposure _retargetExposure(
    TimelineExposure exposure,
    Map<FrameId, FrameId> retargets,
  ) {
    final frameId = exposure.frameId;
    if (frameId == null) {
      return exposure;
    }
    final replacement = retargets[frameId];
    return replacement == null ? exposure : exposure.copyWith(frameId: replacement);
  }

  /// [source]'s union copy with [copyId] — an EMPTY timeline, the bank
  /// shared — and [source] itself. A row that cannot stand empty is born
  /// over its new cut's [cutDuration] frames with [panel] instead, and the
  /// panel joins [source]'s bank too (F-99).
  ({Layer source, Layer copy}) _unionCopyOf(
    Layer source, {
    required LayerId copyId,
    required FrameId? panel,
    required int cutDuration,
  }) {
    final copy = source.copyWith(
      id: copyId,
      timeline: const {},
      folderId: null,
    );
    if (panel == null) {
      return (source: source, copy: copy);
    }
    final cel = coveringCelFor(frameId: panel, cutDuration: cutDuration);
    final bank = [...source.frames, cel.frame];
    return (
      source: source.copyWith(frames: bank),
      copy: copy.copyWith(frames: bank, timeline: cel.timeline),
    );
  }

  BrushFrameKey _celKey(
    ProjectId projectId,
    TrackId trackId,
    CutId cutId,
    LayerId layerId,
    FrameId frameId,
  ) {
    return BrushFrameKey(
      projectId: projectId,
      trackId: trackId,
      cutId: cutId,
      layerId: layerId,
      frameId: frameId,
    );
  }
}
