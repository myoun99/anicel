import '../../models/cut_id.dart';
import '../../models/layer_link_registry.dart';
import '../../models/timeline_id.dart';
import '../brush_frame_store.dart';
import '../project_repository.dart';
import 'link_group_parts.dart';
import 'link_registry_snapshot_command.dart';

/// A link group's rows in two timelines are one only through a 동기컷 — the
/// cut standing in both (🗣️I-150-Q3, 유저 2026-11-03: 「일단 다른
/// 타임라인끼리는 단순 겸용컷 작동안하게」). A cut leaving its sync —
/// deleted, or by 동기 해제 — can leave a 겸용 it had where it stood joined to
/// the sync's other cuts with nothing between. This parts each of
/// [groupIds] so: its rows by timeline, the timelines a sync still joins
/// together, each part keeping its pictures ([partLinkGroup]).
class PartLinksAcrossTimelinesCommand extends LinkRegistrySnapshotCommand {
  PartLinksAcrossTimelinesCommand({
    required super.repository,
    required BrushFrameStore? brushFrameStore,
    required this.groupIds,
  }) : _copies = LinkPartCopies(brushFrameStore);

  /// The parting [leaving] call for as they leave — deleted, or by 동기 해제
  /// — or null where none of them is a 동기컷. Its groups are named NOW,
  /// before they go.
  static PartLinksAcrossTimelinesCommand? forLeaving({
    required ProjectRepository repository,
    required BrushFrameStore? brushFrameStore,
    required Set<CutId> leaving,
  }) {
    final registry = repository.requireProject().linkRegistry;
    if (!leaving.any((cutId) => registry.syncOf(cutId) != null)) {
      return null;
    }
    return PartLinksAcrossTimelinesCommand(
      repository: repository,
      brushFrameStore: brushFrameStore,
      groupIds: {
        for (final group in registry.groups)
          if (group.members.any((member) => leaving.contains(member.cutId)))
            group.id,
      },
    );
  }

  /// The groups the leaving cuts had rows in.
  final Set<String> groupIds;

  final LinkPartCopies _copies;

  @override
  String get description => 'Part links across timelines';

  @override
  void execute() {
    final project = repository.requireProject();
    final registry = project.linkRegistry;
    final timelineOf = {
      for (final timeline in project.timelines)
        for (final track in timeline.tracks)
          for (final cut in track.cuts) cut.id: timeline.id,
    };
    final groups = <LayerLinkGroup>[];
    final copiers = <LayerLinkMember>[];
    for (final group in registry.groups) {
      if (!groupIds.contains(group.id)) {
        groups.add(group);
        continue;
      }
      final parts = _joinedOnlyBySyncs(group, registry, timelineOf);
      final parted = partLinkGroup(
        group,
        [for (final (_, members) in parts) members],
        idOf: (part) => '${group.id}@${parts[part].$1?.value}',
      );
      groups.addAll(parted.groups);
      copiers.addAll(parted.copiers);
    }
    snapshotRegistry(project);
    if (copiers.isNotEmpty) {
      final taken = _copies.take(project, copiers);
      repository.updateProject(
        (current) => current.copyWith(
          linkRegistry: current.linkRegistry.copyWith(groups: groups),
        ),
      );
      _copies.keep(taken);
    }
    markExecuted();
  }

  @override
  void undoBeforeRegistry() => _copies.takeBack();
}

/// [group]'s rows by timeline, a sync's timelines one — each part in the
/// group's order, the part of its first member first, with the timeline it
/// is named after.
List<(TimelineId?, List<LayerLinkMember>)> _joinedOnlyBySyncs(
  LayerLinkGroup group,
  LayerLinkRegistry registry,
  Map<CutId, TimelineId> timelineOf,
) {
  final root = <TimelineId?, TimelineId?>{};
  TimelineId? find(TimelineId? timeline) {
    var at = timeline;
    while (root[at] != at) {
      at = root[at];
    }
    return at;
  }

  for (final member in group.members) {
    final timeline = timelineOf[member.cutId];
    root.putIfAbsent(timeline, () => timeline);
  }
  final cuts = {for (final member in group.members) member.cutId};
  for (final sync in registry.syncs) {
    final joined = [
      for (final cut in sync.cuts)
        if (cuts.contains(cut)) find(timelineOf[cut]),
    ];
    for (final other in joined.skip(1)) {
      root[other] = find(joined.first);
    }
  }
  final parts = <TimelineId?, List<LayerLinkMember>>{};
  for (final member in group.members) {
    parts.putIfAbsent(find(timelineOf[member.cutId]), () => []).add(member);
  }
  return [for (final MapEntry(:key, :value) in parts.entries) (key, value)];
}
