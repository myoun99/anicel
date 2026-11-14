import 'layer.dart';
import 'layer_link_registry.dart';
import 'project.dart';

/// [project] with a link table that names only rows that stand: a member
/// with no row at its (cut, layer) address gone from its group, a group
/// left with one dissolved. [project] itself when every member stands.
///
/// 🚨A ROW AND ITS LINK LEAVE TOGETHER, at the one gate every write passes
/// (`ProjectRepository`), so no door can take one without the other.
/// ↩️Each door swept the table for itself, and one never did: a folder
/// dissolved in a 겸용 cut, or deleted with what it holds, left its group
/// with no row in it. The next row added took the id the folder freed
/// (the first free `layer-N`), so stood in that dead group ahead of its
/// own — the first group holding a member answers for it — and every
/// control written to a row's whole group threw on the member that was not
/// there (🗣️F-575, 유저 2026-11-09). A file saved in that state is repaired
/// here too, as it opens.
///
/// ⚠️It moves no cel. A group's pictures are kept under its first member,
/// so a row leaving a group that STAYS has them to hand on first
/// (`linksWithoutCuts`); a row taken out by itself has its whole group
/// taken with it (`linkMirrorTargets`), and owes nothing here.
///
/// ⛔Every timeline's cuts: a group reaches across them (동기컷).
Project projectWithItsLinksStanding(Project project) {
  final registry = project.linkRegistry;
  if (registry.groups.isEmpty) {
    return project;
  }
  final rowsOfCut = {
    for (final track in project.tracksOfEveryTimeline)
      for (final cut in track.cuts) cut.id: cut.layers,
  };
  bool stands(LayerLinkMember member) =>
      rowsOfCut[member.cutId]?.byId(member.layerId) != null;
  if (registry.groups.every((group) => group.members.every(stands))) {
    return project;
  }
  return project.copyWith(
    linkRegistry: registry.copyWith(
      groups: [
        for (final group in registry.groups)
          if (group.members.where(stands).toList() case final left
              when left.length >= 2)
            group.copyWith(members: left),
      ],
    ),
  );
}
