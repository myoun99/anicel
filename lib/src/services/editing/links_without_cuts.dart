import '../../models/brush_frame_key.dart';
import '../../models/cut_id.dart';
import '../../models/cut_sync.dart';
import '../../models/cut_sync_alignment.dart' show sheetInkKeyOfCut;
import '../../models/layer_link_registry.dart';
import '../../models/project.dart';
import '../brush_frame_store.dart';
import '../project_lookup.dart' show requireLayer;

/// A stored cel moved: from the address it was kept at, to the one taking
/// it over.
typedef CelRekey = (BrushFrameKey from, BrushFrameKey to);

/// A 동기컷's sheets moved: the handwriting kept under [from] — its sync's
/// canonical cut, gone — kept under [to], the cut that takes it over
/// ([CutSync.canonical]).
typedef SheetInkMove = (CutId from, CutId to);

/// What the link table keeps once cuts leave ([linksWithoutCuts]), and what
/// moves so the pictures and the sheets keep routing.
typedef LinksLeft = ({
  LayerLinkRegistry registry,
  List<CelRekey> rekeys,
  List<SheetInkMove> inkMoves,
});

/// 링크 정리 — WHAT THE LINK TABLE KEEPS ONCE [gone] CUTS LEAVE: every
/// member they hold removed, a group left with one dissolved. A group whose
/// CANONICAL member leaves promotes its first survivor, and the canonical's
/// cels re-key onto it ([rekeys]) so pixels keep routing — a lone survivor
/// too, or its now self-resolving reads find nothing. Survivors keep their
/// order, so the promoted canonical is exactly the one re-keyed onto.
///
/// The SYNCS ([CutSync]) the same way: the cuts gone leave theirs, a sync
/// left with one is a cut of its own again, and a sync whose CANONICAL
/// leaves gives its sheets' handwriting to its first survivor
/// ([inkMoves]) — the paper the others were writing on.
///
/// ⛔Dead members must never linger in the table: mirror fan-outs would hit
/// missing layers. A cut deleted (`DeleteCutCommand`) and a timeline deleted
/// (I-150) leave the same way.
LinksLeft linksWithoutCuts(Project project, Set<CutId> gone) {
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
  final syncs = <CutSync>[];
  final inkMoves = <SheetInkMove>[];
  for (final sync in project.linkRegistry.syncs) {
    final left = [
      for (final cut in sync.cuts)
        if (!gone.contains(cut)) cut,
    ];
    if (left.length >= 2) {
      syncs.add(sync.copyWith(cuts: left));
    }
    if (left.isNotEmpty && gone.contains(sync.canonical)) {
      inkMoves.add((sync.canonical, left.first));
    }
  }
  return (
    registry: project.linkRegistry.copyWith(groups: groups, syncs: syncs),
    rekeys: rekeys,
    inkMoves: inkMoves,
  );
}

/// [moves] made in each of [stores]: every sheet ink a gone canonical kept —
/// a conte block's, a timesheet page's — kept under the cut taking it over,
/// the same block, the same page ([sheetInkKeyOfCut]). A store holding no
/// such ink is left as it was.
void moveSheetInk(
  Iterable<BrushFrameStore> stores,
  List<SheetInkMove> moves,
) {
  if (moves.isEmpty) {
    return;
  }
  for (final store in stores) {
    final pairs = <CelRekey>[
      for (final (from, to) in moves)
        for (final key in store.celKeysOfCut(from))
          if (sheetInkKeyOfCut(key, to) case final moved?) (key, moved),
    ];
    if (pairs.isNotEmpty) {
      store.rekeyFrames(pairs);
    }
  }
}

/// [moves] the other way round — what undoing them moves.
List<SheetInkMove> sheetInkMovesBack(List<SheetInkMove> moves) => [
  for (final (from, to) in moves) (to, from),
];
