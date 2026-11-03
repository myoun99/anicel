import '../../models/brush_frame_key.dart';
import '../../models/cut_id.dart';
import '../../models/layer_link_registry.dart';
import '../../models/project.dart';
import '../project_lookup.dart' show requireLayer;

/// A stored cel moved: from the address it was kept at, to the one taking
/// it over.
typedef CelRekey = (BrushFrameKey from, BrushFrameKey to);

/// 링크 정리 — WHAT THE LINK TABLE KEEPS ONCE [gone] CUTS LEAVE: every
/// member they hold removed, a group left with one dissolved. A group whose
/// CANONICAL member leaves promotes its first survivor, and the canonical's
/// cels re-key onto it ([rekeys]) so pixels keep routing — a lone survivor
/// too, or its now self-resolving reads find nothing. Survivors keep their
/// order, so the promoted canonical is exactly the one re-keyed onto.
///
/// ⛔Dead members must never linger in the table: mirror fan-outs would hit
/// missing layers. A cut deleted (`DeleteCutCommand`) and a timeline deleted
/// (I-150) leave the same way.
({LayerLinkRegistry registry, List<CelRekey> rekeys}) linksWithoutCuts(
  Project project,
  Set<CutId> gone,
) {
  final groups = <LayerLinkGroup>[];
  final rekeys = <CelRekey>[];
  for (final group in project.linkRegistry.groups) {
    final survivors = [
      for (final member in group.members)
        if (!gone.contains(member.cutId)) member,
    ];
    if (survivors.length >= 2) {
      groups.add(group.copyWith(members: survivors));
    }
    final canonical = group.canonical;
    if (survivors.isEmpty || !gone.contains(canonical.cutId)) {
      continue;
    }
    final promoted = survivors.first;
    final cels = requireLayer(
      project,
      cutId: canonical.cutId,
      layerId: canonical.layerId,
    ).frames;
    for (final cel in cels) {
      rekeys.add((
        BrushFrameKey(
          projectId: project.id,
          trackId: canonical.trackId,
          cutId: canonical.cutId,
          layerId: canonical.layerId,
          frameId: cel.id,
        ),
        BrushFrameKey(
          projectId: project.id,
          trackId: promoted.trackId,
          cutId: promoted.cutId,
          layerId: promoted.layerId,
          frameId: cel.id,
        ),
      ));
    }
  }
  return (registry: LayerLinkRegistry(groups: groups), rekeys: rekeys);
}
