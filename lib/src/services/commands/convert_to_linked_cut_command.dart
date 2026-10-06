import '../../models/attached_layer_resolve.dart'
    show isAttachedLayer, newAttachedRowIndex;
import '../../models/attached_placement.dart';
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

/// One of the two cuts a conversion works on: where it lives, the working
/// copy of its rows, and how long it runs.
typedef _ConvertSide = ({
  TrackId trackId,
  CutId cutId,
  List<Layer> layers,
  int duration,
});

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
    // 생성되는데 그 법 그대로 재사용/통일」 — a row BORN WITH A FRAME, the
    // conte row and (F-98) the image row, is born covering the cut it lands
    // in with a fresh panel instead, and the panel joins the bank of the row
    // it came from (`_unionCopyOf`).
    final originSide = (
      trackId: originTrack.id,
      cutId: originCutId,
      layers: originLayers,
      duration: originCut.duration,
    );
    final targetSide = (
      trackId: targetTrack.id,
      cutId: targetCutId,
      layers: targetLayers,
      duration: targetCut.duration,
    );
    groups = _unionInto(
      groups,
      from: originSide,
      into: targetSide,
      onlyIds: plan.originOnlyLayerIds,
    );
    groups = _unionInto(
      groups,
      from: targetSide,
      into: originSide,
      onlyIds: plan.targetOnlyLayerIds,
    );

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

  /// The rows only [from] holds ([onlyIds]), each given a linked copy in
  /// [into] — step 2 of [execute], once for each way round — and [groups]
  /// with the links that makes.
  ///
  /// The side a row comes FROM is canonical for it (it holds the pixels);
  /// the other side gets the copy.
  List<LayerLinkGroup> _unionInto(
    List<LayerLinkGroup> groups, {
    required _ConvertSide from,
    required _ConvertSide into,
    required List<LayerId> onlyIds,
  }) {
    for (final sourceId in _ridersAfterTheRest(from.layers, onlyIds)) {
      final index = from.layers.indexWhere((layer) => layer.id == sourceId);
      final union = _unionCopyOf(
        from.layers[index],
        copyId: unionLayerIdMap[(from.cutId, sourceId)]!,
        panel: coveringFrameIdBySource[(from.cutId, sourceId)],
        cutDuration: into.duration,
      );
      from.layers[index] = union.source;
      final copy = _seatedOnItsBase(
        union.copy,
        from: from,
        into: into,
        registry: LayerLinkRegistry(groups: groups),
      );
      into.layers.insert(_landingIndex(into.layers, copy), copy);
      groups = linkGroupsJoined(
        groups,
        origin: LayerLinkMember(
          trackId: from.trackId,
          cutId: from.cutId,
          layerId: sourceId,
        ),
        joiner: LayerLinkMember(
          trackId: into.trackId,
          cutId: into.cutId,
          layerId: copy.id,
        ),
        plannedGroupId: newGroupIdBySource[sourceId],
      );
    }
    return groups;
  }

  /// [onlyIds] in the order their copies are made: a row that rides a base
  /// after every row that rides none — its base among them — and outward
  /// from the base, the rows above it bottom-up and the rows below it
  /// top-down. Each then lands at its group's outer end ([_landingIndex]),
  /// and the group keeps the order it stood in.
  List<LayerId> _ridersAfterTheRest(List<Layer> layers, List<LayerId> onlyIds) {
    final rows = [
      for (final id in onlyIds) layers.firstWhere((layer) => layer.id == id),
    ];
    bool ridesBelow(Layer row) =>
        isAttachedLayer(row) &&
        row.attachedPlacement == AttachedPlacement.below;
    bool ridesAbove(Layer row) => isAttachedLayer(row) && !ridesBelow(row);
    return [
      for (final row in rows)
        if (!isAttachedLayer(row)) row.id,
      for (final row in rows)
        if (ridesAbove(row)) row.id,
      for (final row in rows.reversed)
        if (ridesBelow(row)) row.id,
    ];
  }

  /// [copy] riding the row its base is linked to in [into], in that row's
  /// folder — or [copy] as it is when it rides nothing.
  ///
  /// 「An attach row without its base is not a row at all」 — the add's own
  /// rule (`planAddLayerCommandInput`). ↩️The union copied the row with its
  /// link as it stood, naming the base in the cut it CAME from, so in the cut
  /// it joined it rode nothing: a row the rail and the composite both skip
  /// (found 2026-10-04, measured, with F-278 on the bench). Its base is
  /// always there to ride by now: paired in step 1, linked before this
  /// conversion, or copied a moment ago ([_ridersAfterTheRest]).
  ///
  /// The folder comes with the seat: the group shares its base's folder, and
  /// a row with none inside a folder's run breaks the run
  /// (`FoldersAndAttachments.addAttachedLayer`).
  ///
  /// ⚠️A row whose base is already gone in [from] finds no counterpart and
  /// stays the dangling row it was.
  Layer _seatedOnItsBase(
    Layer copy, {
    required _ConvertSide from,
    required _ConvertSide into,
    required LayerLinkRegistry registry,
  }) {
    final baseId = copy.attachedToLayerId;
    if (baseId == null) {
      return copy;
    }
    final seatId = registry.counterpartIn(
      cutId: from.cutId,
      layerId: baseId,
      targetCutId: into.cutId,
    );
    final seat = into.layers.where((layer) => layer.id == seatId).firstOrNull;
    return seat == null
        ? copy
        : copy.copyWith(attachedToLayerId: seat.id, folderId: seat.folderId);
  }

  /// Where [copy] goes in [layers], the stack it joins: a row that rides a
  /// base where a new attach row is added ([newAttachedRowIndex]), any other
  /// row on top — a z-order choice (`LayerKind.joinsLinkedCutConvert`).
  int _landingIndex(List<Layer> layers, Layer copy) {
    final baseId = copy.attachedToLayerId;
    return baseId == null
        ? layers.length
        : newAttachedRowIndex(baseId, layers, copy.attachedPlacement);
  }

  /// [source]'s union copy with [copyId] — an EMPTY timeline, the bank
  /// shared — and [source] itself. A row born with a frame is born over its
  /// new cut's [cutDuration] frames with [panel] instead, and the panel joins
  /// [source]'s bank too (F-99).
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
