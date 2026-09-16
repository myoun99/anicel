// A CANVAS SELECTION STAYS THROUGH EVERY MOVE, AND THE ARROW KEYS WALK THE
// SHEET WHATEVER IS SELECTED.
//
// F-86 — 유저 2026-09-12: 「선택툴 선택한채로 프레임이나 인덱스 이동하면
// 사라지는데 뭘 하든 안사라지도록. 다른 컷 가도. 그리고 선택툴 선택한채로
// 화살표키누르면 그림 이동되는데 왜 멋대로 넣은거지? 기능부터 잔존코드 싹 삭제」 ·
// 「화살표 이동하는거 변형툴일때도 작동하는거같은데 제발 멋대로 하지말고 그냥 싹
// 잔존 삭제」.
//
// ↩️`nudge_stands_down_while_stroking_test` stood where this does: it pinned
// that an arrow nudged the marquee except under a live pen. The nudge is gone,
// and the walk never had a pen guard to keep.
//
// ⚠️The region is asked of the CHANNEL (`hasRegion`), not of the layer
// (`hasSelection`): walking onto a row that takes no drawing unmounts the
// selection layer, and an unbound layer answers `hasSelection` false even
// while the channel still holds the region (R28-S).
import 'package:flutter/gestures.dart' show PointerDeviceKind, kPrimaryButton;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/services/canvas_selection_region.dart';
import 'package:anicel/src/services/canvas_selection_shape.dart';
import 'package:anicel/src/ui/brush/canvas_selection_commands.dart';
import 'package:anicel/src/ui/editor_canvas_area.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/theme/app_theme.dart';

import '../../helpers/panel_finders.dart' show visibleCanvasPoint;

void main() {
  /// The editor with a stroke on the current frame, the select tool up, and
  /// the whole canvas selected — so the stroke is under the region wherever
  /// it landed.
  Future<({EditorSessionManager session, CanvasSelectionCommands commands})>
  inkUnderASelection(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(theme: buildAppTheme(), home: const HomePage()),
    );
    await tester.pumpAndSettle();
    final area = tester.widget<EditorCanvasArea>(find.byType(EditorCanvasArea));
    final session = area.session;
    final commands = area.canvasSelectionCommands!;

    session.createDrawingAtCurrentFrame();
    await tester.pumpAndSettle();
    final at = visibleCanvasPoint(tester);
    final pen = await tester.startGesture(
      at,
      kind: PointerDeviceKind.mouse,
      buttons: kPrimaryButton,
    );
    await tester.pump();
    await pen.moveTo(at + const Offset(24, 6));
    await tester.pump();
    await pen.moveTo(at + const Offset(48, 12));
    await tester.pump();
    await pen.up();
    await tester.pumpAndSettle();

    // ⛔A SECOND DRAWING, so that moving a frame moves to ANOTHER CEL.
    // The token the selection layer watches is the CEL's, not the frame
    // index: one drawing held across the cut answers the same token at
    // every frame, so a move inside it reaches no reset at all. 🧪Measured
    // — with a single drawing, removing `keepRegion: true` outright left
    // every case green, because the line was never reached.
    session.frameVerbs.selectNextFrame();
    await tester.pump();
    session.createDrawingAtCurrentFrame();
    await tester.pumpAndSettle();
    session.frameVerbs.selectPreviousFrame();
    await tester.pumpAndSettle();

    // W: the select tool mounts the selection layer. Single frames from
    // here: the ants march for as long as the region exists.
    await tester.sendKeyEvent(LogicalKeyboardKey.keyW);
    await tester.pumpAndSettle();
    final canvas = session.activeCutOrNull!.canvasSize;
    commands.applyRegion(
      CanvasSelectionRegion.shape(
        CanvasSelectionShape.rect(
          left: 0,
          top: 0,
          right: canvas.width.toDouble(),
          bottom: canvas.height.toDouble(),
        ),
      ),
    );
    await tester.pump();
    expect(commands.hasSelection, isTrue, reason: 'the layer took the region');
    expect(commands.movePending, isFalse);
    return (session: session, commands: commands);
  }

  /// Leaves the editor as it was found: no float and no region, and the
  /// resample a lift scheduled runs before the tree is torn down.
  Future<void> letGo(
    WidgetTester tester,
    CanvasSelectionCommands commands,
  ) async {
    if (commands.movePending) {
      commands.revertPendingMove();
      await tester.pump();
    }
    commands.deselect();
    await tester.pumpAndSettle();
  }

  testWidgets('↑ with a live selection walks the rows — and lifts nothing', (
    tester,
  ) async {
    final (:session, :commands) = await inkUnderASelection(tester);
    final rowBefore = session.activeLayerId;

    // The drawing row is the bottom of the stack, so the walk goes UP.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();

    expect(
      commands.movePending,
      isFalse,
      reason: '유저: 「화살표키누르면 그림 이동되는데 왜 멋대로 넣은거지?」',
    );
    expect(
      session.activeLayerId,
      isNot(rowBefore),
      reason: 'the arrow walked the sheet',
    );
    expect(commands.hasRegion, isTrue, reason: 'and the region stayed');

    await letGo(tester, commands);
  });

  testWidgets('with the free-transform box open an arrow still walks — it '
      'does not push the box', (tester) async {
    final (:session, :commands) = await inkUnderASelection(tester);
    commands.beginTransform();
    await tester.pump();
    expect(commands.transformActive, isTrue, reason: 'fixture premise');
    final rowBefore = session.activeLayerId;

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();

    expect(
      session.activeLayerId,
      isNot(rowBefore),
      reason: '유저: 「화살표 이동하는거 변형툴일때도 작동하는거같은데」',
    );
    expect(commands.hasRegion, isTrue);

    await letGo(tester, commands);
  });

  testWidgets('the selection stays through a frame, a row and a cut', (
    tester,
  ) async {
    final (:session, :commands) = await inkUnderASelection(tester);

    session.frameVerbs.selectNextFrame();
    await tester.pump();
    expect(
      commands.hasRegion,
      isTrue,
      reason: '유저: 「프레임이나 인덱스 이동하면 사라지는데 뭘 하든 안사라지도록」',
    );

    final otherRow = session.layers.firstWhere(
      (layer) => layer.id != session.activeLayerId,
    );
    session.selectLayer(otherRow.id);
    await tester.pump();
    expect(session.activeLayerId, otherRow.id, reason: 'fixture premise');
    expect(commands.hasRegion, isTrue, reason: 'another row');

    final cutBefore = session.activeCutOrNull?.id;
    session.cutVerbs.createCut();
    await tester.pump();
    await tester.pump();
    expect(
      session.activeCutOrNull?.id,
      isNot(cutBefore),
      reason: 'fixture premise: a new cut was made and stood on',
    );
    expect(commands.hasRegion, isTrue, reason: '유저: 「다른 컷 가도」');

    await letGo(tester, commands);
  });

  testWidgets('선택 해제 still lets go of the marquee — the split is about who '
      'asks, not about two buttons', (tester) async {
    final (:session, :commands) = await inkUnderASelection(tester);

    session.clearAllSelections();
    await tester.pump();

    expect(
      commands.hasRegion,
      isFalse,
      reason: '유저 2026-08-27: 「선택해제 타임라인에 중복으로 존재하는거」 — '
          '두 버튼이 서로 다른 절반만 놓던 사고의 답이라, 버튼의 「놓는다」는 '
          '다섯 종류 전부다',
    );

    await letGo(tester, commands);
  });

  testWidgets('a kept region lifts again from the cel it comes back to', (
    tester,
  ) async {
    // ⛔THE PLAYHEAD DOES NOT MOVE UNDER A LIVE SELECTION INTERACTION
    // (R15-⑤): `selectFrameIndex` refuses the seek outright while one is
    // held, and an OPEN transform box — like a pending move — holds one.
    // 🧪A first draft of this case opened the box and then asked for the
    // next frame: measured, the playhead stayed at 0 of 24, so the case
    // proved nothing and its own premise said so. The state the user
    // reported losing is this one — a region, no float, no open box.
    final (:session, :commands) = await inkUnderASelection(tester);

    session.frameVerbs.selectNextFrame();
    await tester.pump();
    expect(
      session.currentFrameIndex,
      1,
      reason: 'fixture premise: with nothing held, the seek lands',
    );
    expect(
      commands.hasRegion,
      isTrue,
      reason: '유저 2026-09-12: 「프레임이나 인덱스 이동하면 사라지는데 뭘 '
          '하든 안사라지도록」 — the move keeps it',
    );
    expect(
      commands.hasSelection,
      isTrue,
      reason: '⛔AND THE LAYER KEPT IT, not just the channel. The channel '
          'outlives the layer, so `hasRegion` alone stays true even when '
          'the reset forgot the region — which is the very line this round '
          'added. We are on the same row, so the layer is still mounted '
          'and its answer means what it says.',
    );

    session.frameVerbs.selectPreviousFrame();
    await tester.pump();

    commands.beginTransform();
    await tester.pump();
    expect(
      commands.transformActive,
      isTrue,
      reason: 'and it lifts again from the cel it came back to',
    );
    expect(
      commands.movePending,
      isTrue,
      reason: '🚨AND THE LIFT IS A FRESH ONE — opening the box is not the '
          'proof. A region that came back still BELIEVING itself lifted '
          'opens a box just the same and then moves pixels it no longer '
          'holds; a pending move says the lift actually happened.',
    );

    commands.cancelTransform();
    await tester.pump();

    await letGo(tester, commands);
  });
}
