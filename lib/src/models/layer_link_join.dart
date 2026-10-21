import 'layer_link_registry.dart';

/// [groups] with [joiner] added to the group that holds [origin], or a
/// new group of the two under [plannedGroupId] when [origin] is in none.
/// A missing planned id is a programming error: the planner names a
/// group for every origin it hands out.
///
/// 🚨A ROW STANDS IN ONE GROUP. A [joiner] that is in a group already
/// brings its whole group along, after [origin]'s members — the origin's
/// side keeps the pictures (its first member stays the canonical) — and
/// its old group is gone. 🗣️F-398 ⑤ (유저 2026-10-18: 「관련 링크안되는것들
/// 다른것도 조사 법 통일」): a cut converted to 겸용 with a cut 겸용 already
/// put the target's row in the origin's group while it stood in its own.
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
  int indexOf(LayerLinkMember member) => groups.indexWhere(
    (group) => group.contains(cutId: member.cutId, layerId: member.layerId),
  );
  final originIndex = indexOf(origin);
  final joinerIndex = indexOf(joiner);
  if (originIndex != -1 && originIndex == joinerIndex) {
    return groups;
  }
  final joining = joinerIndex == -1 ? [joiner] : groups[joinerIndex].members;
  if (originIndex != -1) {
    final existing = groups[originIndex];
    return [
      for (var i = 0; i < groups.length; i += 1)
        if (i == originIndex)
          existing.copyWith(members: [...existing.members, ...joining])
        else if (i != joinerIndex)
          groups[i],
    ];
  }
  return [
    for (var i = 0; i < groups.length; i += 1)
      if (i != joinerIndex) groups[i],
    LayerLinkGroup(
      id:
          plannedGroupId ??
          (throw StateError('No planned group id for ${origin.layerId}')),
      members: [origin, ...joining],
    ),
  ];
}
