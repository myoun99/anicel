import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_blend_mode.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/session/layer_verbs.dart';

/// The session's link verbs (L4 wiring): 링크 복제, 독립시키기, 겸용컷
/// 생성/변경 — thin session entrances over the L2 coordinator verbs, plus
/// the badge/enablement queries the menu and rails read.
void main() {
  late EditorSessionManager session;

  /// The verbs under test, held BY THEIR OWN TYPE (2026-09-08).
  ///
  /// 🚨`tool/mutation_run.dart` picks a file's witnesses by which tests
  /// IMPORT it. A collaborator only ever spelled `session.layerVerbs` is
  /// one the campaign reports UNNAMED and never runs a mutant against —
  /// 「a link shares the drawing, not the eye」 lives in that file.
  late LayerVerbs layerVerbs;

  setUp(() {
    session = EditorSessionManager(initialProject: createDefaultProject());
    layerVerbs = session.layerVerbs;
    addTearDown(session.dispose);
  });

  test('linkDuplicateActiveLayer links; the badge query sees both members; '
      'unlinking the row forks back out', () {
    final activeLayer = session.activeLayer!;
    bool groupLinked() =>
        layerVerbs.groupIsLinked(session.activeLayer!, session.requireActiveCut);
    final layersBefore = session.requireActiveCut.layers.length;
    expect(layerVerbs.isLayerLinked(activeLayer.id), isFalse);
    expect(groupLinked(), isFalse);

    layerVerbs.linkDuplicateActiveLayer();

    final cut = session.requireActiveCut;
    expect(cut.layers.length, layersBefore + 1);
    expect(layerVerbs.isLayerLinked(activeLayer.id), isTrue);
    final copy = cut.layers.firstWhere(
      (layer) =>
          layer.name == activeLayer.name && layer.id != activeLayer.id,
    );
    expect(layerVerbs.isLayerLinked(copy.id), isTrue);
    expect(groupLinked(), isTrue);

    layerVerbs.unlinkLayers([activeLayer.id]);
    expect(layerVerbs.isLayerLinked(activeLayer.id), isFalse);
    expect(layerVerbs.isLayerLinked(copy.id), isFalse);
    expect(groupLinked(), isFalse);
  });

  test('🗣️the badge NAMES the partner — its cut and its name — and a '
      'row that is not linked names none', () {
    // 유저 2026-09-25: 「링크버튼통해서 어디랑 링크되고있는지만 제대로
    // 표시하게」.
    final activeLayer = session.activeLayer!;
    expect(layerVerbs.linkPartnersOf(activeLayer.id), isEmpty);

    layerVerbs.linkDuplicateActiveLayer();

    final cut = session.requireActiveCut;
    expect(layerVerbs.linkPartnersOf(activeLayer.id), [
      '${cut.name} · ${activeLayer.name}',
    ], reason: 'the copy, in this cut, wearing the same name');
  });

  test('createLinkedCutFromActiveCut adds a cut whose drawing layers are '
      'linked to the source (same names, shared pictures)', () {
    final sourceCutId = session.requireActiveCut.id;
    final cutsBefore = session.activeTrack.cuts.length;

    session.cutVerbs.createLinkedCutFromActiveCut();

    expect(session.activeTrack.cuts.length, cutsBefore + 1);
    expect(
      session.requireActiveCut.id,
      isNot(sourceCutId),
      reason: 'the new linked cut becomes active',
    );
    expect(
      layerVerbs.isLayerLinked(session.activeLayer!.id),
      isTrue,
      reason: 'the new cut\'s drawing layer links to the source\'s',
    );
  });

  test('convertToLinkedCutPreviewData resolves names for the 안내문 and '
      'convertActiveCutToLinked executes it', () {
    session.cutVerbs.duplicateActiveCut();
    final targetCutId = session.activeTrack.cuts
        .firstWhere((cut) => cut.id != session.requireActiveCut.id)
        .id;

    final candidates = session.cutVerbs.convertToLinkedCutCandidates;
    expect(candidates.map((candidate) => candidate.id), [targetCutId]);

    final data = session.cutVerbs.convertToLinkedCutPreviewData(targetCutId)!;
    expect(data.linksAnything, isTrue);
    expect(
      data.linkingLayerNames,
      contains(session.activeLayer!.name),
      reason: 'the duplicated cut shares layer names with the origin',
    );

    session.cutVerbs.convertActiveCutToLinked(targetCutId);
    expect(layerVerbs.isLayerLinked(session.activeLayer!.id), isTrue);

    // Re-running has nothing left to do.
    final rerun = session.cutVerbs.convertToLinkedCutPreviewData(targetCutId)!;
    expect(rerun.linksAnything, isFalse);
  });

  test('the preview is null for the active cut itself', () {
    expect(
      session.cutVerbs.convertToLinkedCutPreviewData(session.requireActiveCut.id),
      isNull,
    );
  });

  /// 🚨T9 (유저 2026-08-13) — 「비지블/정적불투명도는 독립되게 하고싶음. 지금
  /// 하나 바꾸면 링크된 레이어들 바꿈」. ⛔This REVERSES the old 「레인만 각자,
  /// 나머지는 하나」: a link shares the DRAWING, and how loudly a given use
  /// shows that drawing is that use's own business.
  ///
  /// ↩️THE BLEND AND THE STATIC OPACITY WENT BACK TO THE GROUP (유저
  /// 2026-10-04, F-278: 「겸용컷 블렌드모드도 공유하도록 하자. 지금 블렌드모드
  /// 겸용컷끼리 같은레이어인데 독립적이야. 불투명도도 공유하도록할까
  /// 생각하는데 어떻지? 보이기만 독립적으로 하고」, then 「불투명도 공유도 같이
  /// 작업한거지? 블렌드 공유랑 같이?」). Both were pinned per-use here with
  /// the eye — the opacity by the quote above, the blend with it though that
  /// quote never named it.
  test('a link shares the drawing and how it is laid in — its blend and its '
      'static opacity — and each use keeps its own eye', () {
    final origin = session.activeLayer!;
    layerVerbs.linkDuplicateActiveLayer();
    final copy = session.requireActiveCut.layers.firstWhere(
      (layer) => layer.name == origin.name && layer.id != origin.id,
    );
    expect(layerVerbs.isLayerLinked(origin.id), isTrue);

    Layer read(LayerId id) =>
        session.requireActiveCut.layers.firstWhere((layer) => layer.id == id);

    final originVisibleBefore = read(origin.id).isVisible;
    session.layerSwitches.toggleLayerVisibility(copy.id);
    expect(read(copy.id).isVisible, !originVisibleBefore);
    expect(
      read(origin.id).isVisible,
      originVisibleBefore,
      reason: 'the other use of the same cel keeps its own eye',
    );

    // A row link-duplicated in the SAME cut is a member of the group like
    // any other — there is no narrower 「the other cut's row」 to mirror to.
    session.opacityVerbs.setLayerOpacity(layerId: copy.id, opacity: 0.2);
    expect(read(copy.id).opacity, closeTo(0.2, 1e-9));
    expect(read(origin.id).opacity, closeTo(0.2, 1e-9));
    expect(
      read(origin.id).isVisible,
      originVisibleBefore,
      reason: '⛔전제 kept: the opacity\'s mirror did not carry the eye',
    );

    session.layerSwitches.setLayerBlendMode(copy.id, LayerBlendMode.multiply);
    expect(read(copy.id).blendMode, LayerBlendMode.multiply);
    expect(read(origin.id).blendMode, LayerBlendMode.multiply);

    // ⚠️And the LINK itself survives all three — none of them is an unlink.
    // The two rows are still one drawing.
    expect(layerVerbs.isLayerLinked(origin.id), isTrue);
    expect(layerVerbs.isLayerLinked(copy.id), isTrue);
  });

  /// The 겸용 cut never had an answer of its own — it went through the same
  /// registry — so what a link shares reaches it without a second edit
  /// (유저: 「겸용컷 에서도 같은 로직 쓰지? 똑같이 적용되도록」).
  ///
  /// ↩️It pinned the opacity as each cut's own (T9); see the test above.
  test('the same holds across a 겸용 cut: the eye is each cut\'s own, the '
      'static opacity one value', () {
    final origin = session.activeLayer!;
    final originCutId = session.requireActiveCut.id;
    session.cutVerbs.createLinkedCutFromActiveCut();

    final linkedCut = session.activeTrack.cuts.firstWhere(
      (cut) => cut.id != originCutId,
    );
    final twin = linkedCut.layers.firstWhere(
      (layer) => layer.name == origin.name,
    );
    expect(layerVerbs.isLayerLinked(twin.id), isTrue);

    session.layerSwitches.toggleLayerVisibility(twin.id);
    session.opacityVerbs.setLayerOpacity(layerId: twin.id, opacity: 0.35);

    Layer inCut(CutId cutId, LayerId layerId) => session
        .cutById(cutId)!
        .layers
        .firstWhere((layer) => layer.id == layerId);
    expect(inCut(linkedCut.id, twin.id).opacity, closeTo(0.35, 1e-9));
    expect(inCut(originCutId, origin.id).opacity, closeTo(0.35, 1e-9));
    expect(inCut(linkedCut.id, twin.id).isVisible, !origin.isVisible);
    expect(
      inCut(originCutId, origin.id).isVisible,
      origin.isVisible,
      reason: '「보이기만 독립적으로」',
    );
  });
}
