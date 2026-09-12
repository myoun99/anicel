// A LINKED CEL IS ONE PICTURE — on every row you can stand on.
//
// 🗣️유저 2026-09-12, with the repro in their own order: an EMPTY cut1 made
// into a 겸용 pair, a cel + drawing in each cut, joined by giving both the
// name "1" — 「여기까지는 그림이 그대로 링크되어 전달됬어. 이제 여기서
// 추가로 그림그려. 그 다음 컷2가서 확인해보면 컷1에서 그린 그림이
// 안그려져있어 … 근데 여기서 재생하면 컷1에서 그린 그림이 표시되네?」
//
// ★THAT SPLIT IS THE ORACLE: playback reads the frame store (which folds
// every key onto the physical cel), while the row you STAND on is painted
// from the edit SESSION. The sessions were held per ROW ADDRESS, so the
// sibling kept the pre-stroke surface for ever. The test therefore asks
// the session — through the sibling's own key — for the same object the
// store calls the truth.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/brush_dab.dart';
import 'package:anicel/src/models/brush_frame_key.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/home_page.dart';

void main() {
  testWidgets('a stroke made in one 겸용 cut is the SAME picture in the '
      'other — the row you stand on reads it too, not just playback', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(home: HomePage(initialProject: createDefaultProject())),
    );
    await tester.pumpAndSettle();

    final session = tester
        .widget<EditorWorkspace>(find.byType(EditorWorkspace))
        .session;
    final store = session.renderCaches.brushFrameStore;

    Layer rowIn(CutId cutId) => session.activeTrack.cuts
        .firstWhere((cut) => cut.id == cutId)
        .layers
        .firstWhere((layer) => layer.kind == LayerKind.animation);

    BrushFrameKey keyOf(CutId cutId) {
      final layer = rowIn(cutId);
      return BrushFrameKey(
        projectId: session.repository.requireProject().id,
        trackId: session.activeTrack.id,
        cutId: cutId,
        layerId: layer.id,
        frameId: layer.timeline[0]!.frameId!,
      );
    }

    void stroke(double x) {
      final outcome = session.pixelEditingCoordinator!.commitSourceStroke(
        sourceDabs: [
          BrushDab(
            center: CanvasPoint(x: x, y: 20),
            color: 0xFF112233,
            size: 8,
            opacity: 1,
            flow: 1,
            hardness: 1,
            pressure: 1,
            sequence: 0,
          ),
        ],
        cacheInvalidationSink: session.renderCaches.cacheInvalidationHub,
      );
      expect(outcome, isNotNull, reason: 'LIVENESS — the stroke landed');
    }

    /// What the canvas would paint standing on [cutId]'s row, against what
    /// the store calls the cel's truth. Same object = one picture.
    void expectOnePicture(CutId cutId, {required String when}) {
      final key = keyOf(cutId);
      final surface = session.pixelEditingCoordinator!.currentSurfaceOf(key);
      expect(
        identical(surface, store.bakedSurfaceOrNull(store.canonicalKeyOf(key))),
        isTrue,
        reason: '⛔$when: the session this row paints from is NOT the cel — '
            'a linked cel has one picture, and the canvas has to see the '
            'same one playback does',
      );
    }

    // ① an EMPTY cut1 becomes a 겸용 pair.
    final cut1 = session.requireActiveCut.id;
    session.cutVerbs.createLinkedCutFromActiveCut();
    final cut2 = session.requireActiveCut.id;

    // ② a cel and a drawing in cut2, named "1".
    session.createDrawingAtCurrentFrame();
    await tester.pumpAndSettle();
    stroke(20);
    session.frameVerbs.renameSelectedFrame('1');
    await tester.pumpAndSettle();

    // ③ a cel and a drawing in cut1 — then the join, by the same name.
    session.selectCut(cut1);
    await tester.pumpAndSettle();
    session.createDrawingAtCurrentFrame();
    await tester.pumpAndSettle();
    stroke(60);
    final conflict = session.frameVerbs.renameSelectedFrame('1');
    expect(
      conflict,
      isNotNull,
      reason: 'LIVENESS — the same name has to be caught as a join offer',
    );
    session.frameVerbs.linkSelectedFrame(conflict!);
    await tester.pumpAndSettle();
    expectOnePicture(cut1, when: 'right after the join');
    expectOnePicture(cut2, when: 'right after the join');

    // ④ 「이제 여기서 추가로 그림그려」 — the stroke that used to vanish.
    stroke(100);
    await tester.pumpAndSettle();
    expectOnePicture(cut1, when: 'after the extra stroke, in the cut it was '
        'drawn in');
    expectOnePicture(cut2, when: 'after the extra stroke, seen from the '
        'other cut');

    // ⑤ 「그 다음 컷2가서 확인해보면」 — and standing there changes nothing.
    session.selectCut(cut2);
    await tester.pumpAndSettle();
    expectOnePicture(cut2, when: 'standing in the other cut');
    expectOnePicture(cut1, when: 'standing in the other cut');
  });
}
