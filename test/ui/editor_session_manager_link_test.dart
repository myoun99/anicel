import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';

/// The session's link verbs (L4 wiring): 링크 복제, 독립시키기, 겸용컷
/// 생성/변경 — thin session entrances over the L2 coordinator verbs, plus
/// the badge/enablement queries the menu and rails read.
void main() {
  late EditorSessionManager session;

  setUp(() {
    session = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(session.dispose);
  });

  test('linkDuplicateActiveLayer links; the badge query sees both members; '
      'unlinkActiveLayer forks back out', () {
    final activeLayer = session.activeLayer!;
    final layersBefore = session.requireActiveCut.layers.length;
    expect(session.isLayerLinked(activeLayer.id), isFalse);
    expect(session.canUnlinkActiveLayer, isFalse);

    session.linkDuplicateActiveLayer();

    final cut = session.requireActiveCut;
    expect(cut.layers.length, layersBefore + 1);
    expect(session.isLayerLinked(activeLayer.id), isTrue);
    final copy = cut.layers.firstWhere(
      (layer) =>
          layer.name == activeLayer.name && layer.id != activeLayer.id,
    );
    expect(session.isLayerLinked(copy.id), isTrue);
    expect(session.canUnlinkActiveLayer, isTrue);

    session.unlinkActiveLayer();
    expect(session.isLayerLinked(activeLayer.id), isFalse);
    expect(session.isLayerLinked(copy.id), isFalse);
    expect(session.canUnlinkActiveLayer, isFalse);
  });

  test('createLinkedCutFromActiveCut adds a cut whose drawing layers are '
      'linked to the source (same names, shared pictures)', () {
    final sourceCutId = session.requireActiveCut.id;
    final cutsBefore = session.activeTrack.cuts.length;

    session.createLinkedCutFromActiveCut();

    expect(session.activeTrack.cuts.length, cutsBefore + 1);
    expect(
      session.requireActiveCut.id,
      isNot(sourceCutId),
      reason: 'the new linked cut becomes active',
    );
    expect(
      session.isLayerLinked(session.activeLayer!.id),
      isTrue,
      reason: 'the new cut\'s drawing layer links to the source\'s',
    );
  });

  test('convertToLinkedCutPreviewData resolves names for the 안내문 and '
      'convertActiveCutToLinked executes it', () {
    session.duplicateActiveCut();
    final targetCutId = session.activeTrack.cuts
        .firstWhere((cut) => cut.id != session.requireActiveCut.id)
        .id;

    final candidates = session.convertToLinkedCutCandidates;
    expect(candidates.map((candidate) => candidate.id), [targetCutId]);

    final data = session.convertToLinkedCutPreviewData(targetCutId)!;
    expect(data.linksAnything, isTrue);
    expect(
      data.linkingLayerNames,
      contains(session.activeLayer!.name),
      reason: 'the duplicated cut shares layer names with the origin',
    );

    session.convertActiveCutToLinked(targetCutId);
    expect(session.isLayerLinked(session.activeLayer!.id), isTrue);

    // Re-running has nothing left to do.
    final rerun = session.convertToLinkedCutPreviewData(targetCutId)!;
    expect(rerun.linksAnything, isFalse);
  });

  test('the preview is null for the active cut itself', () {
    expect(
      session.convertToLinkedCutPreviewData(session.requireActiveCut.id),
      isNull,
    );
  });
}
