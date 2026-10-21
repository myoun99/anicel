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
/// The origin's other 겸용 siblings take the rows the origin takes in from
/// the target the same way, each its own copy linked with them, and the
/// target's siblings the rows the target takes in; a target 겸용 already
/// brings its family into the origin's (F-398).
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
    this.siblingUnionLayerIdMap = const {},
    this.siblingCoveringFrameIds = const {},
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

  /// Planned ids for the copies the two cuts' other 겸용 siblings take of
  /// the rows only the other side holds: (sibling, source layer) → copy id.
  final Map<(CutId, LayerId), LayerId> siblingUnionLayerIdMap;

  /// The planned fresh panel of each sibling copy born covering its cut,
  /// keyed like [siblingUnionLayerIdMap].
  final Map<(CutId, LayerId), FrameId> siblingCoveringFrameIds;

  /// The siblings this conversion copies into, in plan order.
  List<CutId> get _siblings => [
    ...{for (final (sibling, _) in siblingUnionLayerIdMap.keys) sibling},
  ];

  LayerLinkRegistry? _registryBefore;
  final List<(BrushFrameKey, BrushFrameKey)> _rekeys = [];
  bool _hasExecuted = false;

  @override
  String get description => 'Convert cut $targetCutId to link $originCutId';

  @override
  void execute() {
    final project = repository.requireProject();
    final plan = planConvertToLinkedCut(
      project: project,
      originCut: requireCut(project, originCutId),
      targetCut: requireCut(project, targetCutId),
    );

    // Capture the exact pre-conversion state once (redo re-runs from the
    // restored state, so re-capturing would be wrong) — the rows of each
    // cut as [rows] first touches it.
    _registryBefore ??= project.linkRegistry;
    final rows = _ConvertRows(project, _snapshots);
    var groups = [...project.linkRegistry.groups];

    // 1. Matched pairs: merge banks (origin wins) and link.
    for (final pair in plan.layerPairs) {
      groups = _linkPair(pair, rows, groups);
    }
    groups = _unionOneSided(groups, rows, plan);

    // Move the joining cels to canonical keys BEFORE the resolver links
    // them (raw rekey).
    brushFrameStore.rekeyFrames(_rekeys);

    repository.updateProject(
      (current) => _withCutsLayers(
        current,
        rows.layersByCut,
      ).copyWith(linkRegistry: LayerLinkRegistry(groups: groups)),
    );
    _hasExecuted = true;
  }

  /// Step 2 of [execute]: a layer on ONE side only gets a linked copy on the
  /// other (empty timeline — the bank is shared, the rhythm is fresh) — and
  /// [groups] with the links that makes.
  ///
  /// ↩️F-99 (유저 2026-09-12): 「콘티레이어 생성시 기본적으로 프레임
  /// 생성되는데 그 법 그대로 재사용/통일」 — a row BORN WITH A FRAME, the
  /// conte row and (F-98) the image row, is born covering the cut it lands
  /// in with a fresh panel instead, and the panel joins the bank of the row
  /// it came from (`_unionCopyOf`).
  List<LayerLinkGroup> _unionOneSided(
    List<LayerLinkGroup> groups,
    _ConvertRows rows,
    ConvertToLinkedCutPlan plan,
  ) {
    final originSide = rows.sideOf(originCutId);
    final targetSide = rows.sideOf(targetCutId);
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
    // Each sibling takes the rows planned for it: the origin's what the
    // origin takes in, the target's what the target does (F-398 ④⑤).
    for (final sibling in _siblings) {
      final side = rows.sideOf(sibling);
      for (final (from, onlyIds) in [
        (targetSide, plan.targetOnlyLayerIds),
        (originSide, plan.originOnlyLayerIds),
      ]) {
        groups = _unionInto(
          groups,
          from: from,
          into: side,
          onlyIds: [
            for (final id in onlyIds)
              if (siblingUnionLayerIdMap.containsKey((sibling, id))) id,
          ],
        );
      }
    }
    return groups;
  }

  /// [pair] linked — step 1 of [execute] — and [groups] with the link: the
  /// target row adopts the merged bank, its superseded drawings re-aimed at
  /// the origin's, and so does every row it was 겸용 with already (F-398 ⑤:
  /// the target's family joins the origin's, and its rows would still show
  /// the drawings the origin's replaced).
  List<LayerLinkGroup> _linkPair(
    ({LayerId originLayerId, LayerId targetLayerId}) pair,
    _ConvertRows rows,
    List<LayerLinkGroup> groups,
  ) {
    final originSide = rows.sideOf(originCutId);
    final targetSide = rows.sideOf(targetCutId);
    final origin = originSide.layers.firstWhere(
      (layer) => layer.id == pair.originLayerId,
    );
    final target = targetSide.layers.firstWhere(
      (layer) => layer.id == pair.targetLayerId,
    );
    final resolution = resolveLayerMerge(origin: origin, target: target);
    final mergedBank = _mergedBank(rows, origin, target, resolution);

    // Origin (and every existing member of its group) adopts the bank;
    // here we set the origin layer — other members re-derive lazily
    // through the shared FrameIds (their own frame lists gain the
    // joiners on their next bank edit; the registry link already routes
    // pixels correctly).
    final originIndex = originSide.layers.indexWhere(
      (layer) => layer.id == origin.id,
    );
    originSide.layers[originIndex] = origin.copyWith(frames: mergedBank);

    for (final joiner in _targetFamily(rows, target.id)) {
      final layers = rows.of(joiner.cutId);
      final index = layers.indexWhere((layer) => layer.id == joiner.layerId);
      layers[index] = _joinedRow(
        layers[index],
        origin: origin,
        bank: mergedBank,
        retargets: resolution.retargetedFrameIds,
      );
    }

    return linkGroupsJoined(
      groups,
      origin: LayerLinkMember(
        trackId: originSide.trackId,
        cutId: originCutId,
        layerId: origin.id,
      ),
      joiner: LayerLinkMember(
        trackId: targetSide.trackId,
        cutId: targetCutId,
        layerId: target.id,
      ),
      plannedGroupId: newGroupIdBySource[origin.id],
    );
  }

  /// The origin's bank with the target's joining cels after it — the cels
  /// moved, as [_rekeys], from where the target's family keeps them to
  /// where the origin's does: the canonical keys of the registry as it
  /// stood, which the resolver reads them under. ↩️F-398 ⑤: they moved from
  /// the rows' own keys, which hold nothing when another of the group keeps
  /// the pictures — the move found nothing, and the drawing was gone.
  List<Frame> _mergedBank(
    _ConvertRows rows,
    Layer origin,
    Layer target,
    LayerMergeResolution resolution,
  ) {
    final before = rows.project.linkRegistry;
    final originSide = rows.sideOf(originCutId);
    final targetSide = rows.sideOf(targetCutId);
    final joiningFrames = <Frame>[];
    for (final frameId in resolution.joiningFrameIds) {
      _rekeys.add((
        before.canonicalCelKey(_celKey(targetSide, target.id, frameId)),
        before.canonicalCelKey(_celKey(originSide, origin.id, frameId)),
      ));
      joiningFrames.add(
        target.frames.firstWhere((frame) => frame.id == frameId),
      );
    }
    return [...origin.frames, ...joiningFrames];
  }

  /// The target row [targetId] and every row it was 겸용 with already — the
  /// target's family, which a pair joins to the origin's (F-398 ⑤). None of
  /// it is the origin's: a pair 겸용 already is no pair
  /// ([planConvertToLinkedCut]).
  List<LayerLinkMember> _targetFamily(_ConvertRows rows, LayerId targetId) =>
      rows.project.linkRegistry
          .groupOf(cutId: targetCutId, layerId: targetId)
          ?.members ??
      [
        LayerLinkMember(
          trackId: rows.sideOf(targetCutId).trackId,
          cutId: targetCutId,
          layerId: targetId,
        ),
      ];

  /// [row], a row of the target's family, joined to [origin]'s: it adopts
  /// the merged [bank] and its exposures RE-TARGET conflicting frames onto
  /// the origin's ([retargets], 원본 승리) — the timeline numbers stay.
  Layer _joinedRow(
    Layer row, {
    required Layer origin,
    required List<Frame> bank,
    required Map<FrameId, FrameId> retargets,
  }) => row.copyWith(
    frames: bank,
    timeline: {
      for (final entry in row.timeline.entries)
        entry.key: _retargetExposure(entry.value, retargets),
    },
    // F-302: a row that joins a link group folds and twirls as its
    // group does — the origin's, which every use of it wears. ↩️The
    // rail's view made the twirls agree after a command
    // (`RailView.followLinks`) until F-360 put them on the rows.
    collapsed: origin.collapsed,
    lanesExpanded: origin.lanesExpanded,
    expandedLaneGroups: origin.expandedLaneGroups,
  );

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
    // Restore the cuts' original layer lists and the registry.
    repository.updateProject(
      (current) => _withCutsLayers(
        current,
        _snapshots,
      ).copyWith(linkRegistry: registryBefore),
    );
  }

  /// [current] with each cut of [layers] holding its list — execute and
  /// undo swap the same lists.
  static Project _withCutsLayers(
    Project current,
    Map<CutId, List<Layer>> layers,
  ) => layers.entries.fold(
    current,
    (next, entry) =>
        updateCutAnywhere(
          next,
          entry.key,
          (cut) => cut.copyWith(layers: entry.value),
        ) ??
        (throw StateError('Cut not found: ${entry.key}')),
  );

  // The exact pre-conversion layer lists of every cut the conversion
  // writes, captured on the first execute.
  final Map<CutId, List<Layer>> _snapshots = {};

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
      final planned = _plannedCopy(from, into, sourceId);
      final union = _unionCopyOf(
        from.layers[index],
        copyId: planned.copyId,
        panel: planned.panel,
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

  /// The planned id and panel of [into]'s copy of [from]'s row [sourceId]:
  /// the other cut's of the two, keyed by the cut it comes from — a
  /// sibling's, keyed by the sibling.
  ({LayerId copyId, FrameId? panel}) _plannedCopy(
    _ConvertSide from,
    _ConvertSide into,
    LayerId sourceId,
  ) {
    if (into.cutId == originCutId || into.cutId == targetCutId) {
      return (
        copyId: unionLayerIdMap[(from.cutId, sourceId)]!,
        panel: coveringFrameIdBySource[(from.cutId, sourceId)],
      );
    }
    return (
      copyId: siblingUnionLayerIdMap[(into.cutId, sourceId)]!,
      panel: siblingCoveringFrameIds[(into.cutId, sourceId)],
    );
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

  BrushFrameKey _celKey(_ConvertSide side, LayerId layerId, FrameId frameId) =>
      BrushFrameKey(
        projectId: repository.requireProject().id,
        trackId: side.trackId,
        cutId: side.cutId,
        layerId: layerId,
        frameId: frameId,
      );
}

/// The rows of every cut a conversion writes, as it writes them: each cut's
/// working copy, made the first time the conversion touches the cut — and
/// the rows it had then kept in [_before] for the undo, the first time only
/// (a redo re-runs from the restored state).
final class _ConvertRows {
  _ConvertRows(this.project, this._before);

  /// The project as it stood before the conversion.
  final Project project;

  final Map<CutId, List<Layer>> _before;

  /// Each touched cut's working rows — what the conversion writes.
  final layersByCut = <CutId, List<Layer>>{};

  /// [cutId]'s working rows.
  List<Layer> of(CutId cutId) => layersByCut.putIfAbsent(cutId, () {
    final layers = requireCut(project, cutId).layers;
    _before.putIfAbsent(cutId, () => [...layers]);
    return [...layers];
  });

  /// [cutId] as a side a conversion works on.
  _ConvertSide sideOf(CutId cutId) {
    final position = requireCutPosition(project, cutId);
    return (
      trackId: position.track.id,
      cutId: cutId,
      layers: of(cutId),
      duration: position.cut.duration,
    );
  }
}
