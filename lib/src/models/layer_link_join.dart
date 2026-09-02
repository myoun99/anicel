import 'layer_link_registry.dart';

/// [groups] with [joiner] added to the group that holds [origin], or a
/// new group of the two under [plannedGroupId] when [origin] is in none.
/// A missing planned id is a programming error: the planner names a
/// group for every origin it hands out.
///
/// 🚨ONE law. The linked-cut creation, the linked-cut conversion and the
/// link-duplicate each carried this join-or-open (the audit's clone
/// scan, 2026-09-03); the conversion's private helper is the one that
/// stays.
List<LayerLinkGroup> linkGroupsJoined(
  List<LayerLinkGroup> groups, {
  required LayerLinkMember origin,
  required LayerLinkMember joiner,
  required String? plannedGroupId,
}) {
  final existingIndex = groups.indexWhere(
    (group) => group.contains(cutId: origin.cutId, layerId: origin.layerId),
  );
  if (existingIndex != -1) {
    final existing = groups[existingIndex];
    return [
      for (var i = 0; i < groups.length; i += 1)
        if (i == existingIndex)
          existing.copyWith(members: [...existing.members, joiner])
        else
          groups[i],
    ];
  }
  return [
    ...groups,
    LayerLinkGroup(
      id:
          plannedGroupId ??
          (throw StateError('No planned group id for ${origin.layerId}')),
      members: [origin, joiner],
    ),
  ];
}
