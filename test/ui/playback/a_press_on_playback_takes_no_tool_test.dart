
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/brush_stamp_image.dart';
import 'package:anicel/src/models/cut_piece.dart';
import 'package:anicel/src/services/canvas_selection_region.dart';
import 'package:anicel/src/services/canvas_selection_shape.dart';
import 'package:anicel/src/ui/brush/brush_tool_state.dart';
import 'package:anicel/src/ui/brush/paint_tool_state_notifier.dart';
import 'package:anicel/src/ui/canvas/canvas_selection_layer.dart';
import 'package:anicel/src/ui/editor_canvas_area.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/playback/canvas_playback_controller.dart';
import 'package:anicel/src/ui/theme/app_theme.dart';

import '../../helpers/panel_finders.dart';

/// Board `playback-tap-taken-by-tool-layer`, through the real app — T28-c
/// (유저): 「뭘 누르든 입력이 존재하면 정지 … 입력 일 안함」. While the canvas
/// plays, a press on it stops it whatever tool is in hand, and the tool does
/// nothing with the press.
void main() {
  const ink = 0xFF123456;

  Future<EditorSessionManager> pumpEditor(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(theme: buildAppTheme(), home: const HomePage()),
    );
    await tester.pumpAndSettle();
    final session = tester
        .widget<EditorCanvasArea>(find.byType(EditorCanvasArea))
        .session;
    // A cel under the playhead, so a tool that writes pixels has somewhere
    // to write them: 「nothing happened」 below is a tool declining the
    // press, not a tool with nothing to act on.
    session.createDrawingAtCurrentFrame();
    await tester.pumpAndSettle();
    return session;
  }

  EditorCanvasArea areaOf(WidgetTester tester) =>
      tester.widget<EditorCanvasArea>(find.byType(EditorCanvasArea));

  Future<PaintToolStateNotifier> arm(
    WidgetTester tester,
    CanvasTool tool,
  ) async {
    final tools = tester
        .widget<EditorWorkspace>(find.byType(EditorWorkspace))
        .brushTool!;
    tools.value = tools.value.copyWith(tool: tool, color: ink);
    await tester.pumpAndSettle();
    expect(tools.value.tool, tool);
    expect(tools.value.color, ink);
    return tools;
  }

  Future<void> play(WidgetTester tester, EditorSessionManager session) async {
    session.playbackRig.playback.play(scope: PlaybackScope.activeCut);
    await tester.pump(const Duration(milliseconds: 16));
    expect(session.playbackRig.playback.isPlaying, isTrue);
  }

  Future<void> settle(
    WidgetTester tester,
    EditorSessionManager session,
  ) async {
    session.playbackRig.transports.stopAll();
    await tester.pumpAndSettle();
  }

  /// A point on the canvas panel clear of the floating regions — where the
  /// D13 tap test presses.
  Offset onCanvas(WidgetTester tester) {
    final panel = tester.getRect(
      find.byKey(const ValueKey<String>('main-canvas-brush-host-container')),
    );
    return Offset(panel.center.dx, panel.top + panel.height / 4);
  }

  Future<void> press(
    WidgetTester tester, {
    PointerDeviceKind kind = PointerDeviceKind.mouse,
  }) async {
    await tester.tapAt(onCanvas(tester), kind: kind);
    await tester.pump(const Duration(milliseconds: 16));
  }

  CutPiece piece() => CutPiece(
    image: BrushStampImage(
      id: 'a-press-on-playback',
      width: 4,
      height: 4,
      rgba: Uint8List.fromList([
        for (var index = 0; index < 16; index += 1) ...[200, 40, 40, 255],
      ]),
    ),
    originLeft: 0,
    originTop: 0,
  );

  testWidgets('the eyedropper TOOL: a mouse press on the playing canvas stops '
      'it and picks nothing — and stopped, the same press picks', (
    tester,
  ) async {
    final session = await pumpEditor(tester);
    final tools = await arm(tester, CanvasTool.eyedropper);
    await play(tester, session);

    await press(tester);

    expect(
      session.playbackRig.playback.isPlaying,
      isFalse,
      reason: '「입력이 존재하면 정지」 — the press reached the playback view',
    );
    expect(
      tools.value.color,
      ink,
      reason: '「입력 일 안함」 — no colour was picked off the playing picture',
    );
    await settle(tester, session);

    await press(tester);
    await tester.pumpAndSettle();
    expect(
      tools.value.color,
      isNot(ink),
      reason: 'the canvas is back and so is the tool: this press picked, '
          'which is what the press above did not do',
    );
  });

  testWidgets('the eyedropper TOOL, by finger: the press stops and picks '
      'nothing', (tester) async {
    final session = await pumpEditor(tester);
    final tools = await arm(tester, CanvasTool.eyedropper);
    await play(tester, session);

    await press(tester, kind: PointerDeviceKind.touch);

    expect(session.playbackRig.playback.isPlaying, isFalse);
    expect(tools.value.color, ink);
    await settle(tester, session);
  });

  testWidgets('Alt held — the eyedropper by hold (I-15): the press stops and '
      'picks nothing', (tester) async {
    final session = await pumpEditor(tester);
    final tools = await arm(tester, CanvasTool.brush);
    await play(tester, session);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.pump();
    expect(
      tools.value.tool,
      CanvasTool.eyedropper,
      reason: 'the hold is the eyedropper, playing or not',
    );
    expect(
      session.playbackRig.playback.isPlaying,
      isTrue,
      reason: '「수식키는 혼자선 입력으로 치지 않는다」',
    );

    await press(tester);

    expect(session.playbackRig.playback.isPlaying, isFalse);
    expect(tools.value.color, ink);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    await settle(tester, session);
  });

  for (final tool in [
    CanvasTool.select,
    CanvasTool.move,
    CanvasTool.cut,
    CanvasTool.fillShape,
  ]) {
    testWidgets('${tool.name}: a press on the playing canvas stops it, and '
        'the tool does nothing', (tester) async {
      final session = await pumpEditor(tester);
      await arm(tester, tool);
      final undo = session.historyManager.undoCount;
      await play(tester, session);

      await press(tester);

      expect(
        session.playbackRig.playback.isPlaying,
        isFalse,
        reason: 'the selection tools\' layer took this press before',
      );
      expect(areaOf(tester).canvasSelectionCommands?.region, isNull);
      expect(session.historyManager.undoCount, undo);
      await settle(tester, session);
    });
  }

  testWidgets('select: a drag over the playing canvas draws no outline', (
    tester,
  ) async {
    final session = await pumpEditor(tester);
    await arm(tester, CanvasTool.select);
    await play(tester, session);

    final gesture = await tester.startGesture(
      onCanvas(tester),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump(const Duration(milliseconds: 16));
    for (var step = 0; step < 4; step += 1) {
      await gesture.moveBy(const Offset(30, 20));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 16));

    expect(
      areaOf(tester).canvasSelectionCommands?.region,
      isNull,
      reason: '「입력 일 안함」 — no marquee over the playing picture. Whether '
          'the drag stops playback is D13\'s question, not the tool\'s',
    );
    await settle(tester, session);
  });

  testWidgets('the stamp: a press on the playing canvas stops it and lays no '
      'piece', (tester) async {
    final session = await pumpEditor(tester);
    areaOf(tester).cutPieceSlot!.hold(piece());
    await arm(tester, CanvasTool.cutStamp);
    final undo = session.historyManager.undoCount;
    await play(tester, session);

    await press(tester);

    expect(session.playbackRig.playback.isPlaying, isFalse);
    expect(
      session.historyManager.undoCount,
      undo,
      reason: '「입력 일 안함」 — no stamp landed on the cel',
    );
    await settle(tester, session);
  });

  testWidgets('a selection stays drawn while the canvas plays: the selection '
      'layer stands down and the idle ants take the region', (tester) async {
    final session = await pumpEditor(tester);
    final tools = await arm(tester, CanvasTool.select);
    final selection = areaOf(tester).canvasSelectionCommands!;
    selection.setRegion(
      CanvasSelectionRegion.shape(
        CanvasSelectionShape.rect(left: 0, top: 0, right: 60, bottom: 40),
      ),
    );
    await tester.pump(const Duration(milliseconds: 16));
    final layer = inMainCanvas(find.byType(CanvasSelectionLayer));
    final ants = inMainCanvas(
      find.byKey(const ValueKey<String>('canvas-idle-selection-ants')),
    );
    expect(layer, findsOneWidget);
    expect(ants, findsNothing, reason: 'the layer draws its own');

    await play(tester, session);
    expect(
      layer,
      findsNothing,
      reason: 'no tool takes a press on the playing picture',
    );
    expect(
      ants,
      findsOneWidget,
      reason: 'and the selection is still a document fact on screen (R28-S)',
    );

    session.playbackRig.transports.stopAll();
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 16));
    expect(layer, findsOneWidget, reason: 'stopped, the tool is back');
    expect(ants, findsNothing);

    selection.setRegion(null);
    tools.value = tools.value.copyWith(tool: CanvasTool.brush);
    await tester.pumpAndSettle();
  });
}
