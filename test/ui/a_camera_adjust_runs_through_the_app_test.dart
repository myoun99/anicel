import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/menu/editor_top_strip.dart';
import 'package:anicel/src/ui/session/canvas_adjust.dart';

import '../helpers/settings_flyout.dart' show hoverFlyoutRow;
import 'flyout_test_helpers.dart' show tapCommandButton;

/// I-80 through the app: ⚙ ▸ Project settings ▸ the camera row ▸
/// 「캔버스에서 조정」 stands the camera's frame in its box, and its pill, on
/// the canvas; Enter lands the size as the project camera's as its ✓ does
/// — 확정 is one verb (`ConfirmVerb`) — and Escape closes it as its ✕
/// does. The canvas holds ONE adjust: the canvas's own, opened, closes the
/// camera's.
void main() {
  Future<EditorSessionManager> pumpApp(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(home: HomePage(initialProject: createDefaultProject())),
    );
    await tester.pumpAndSettle();
    return tester
        .widget<EditorTopStrip>(find.byType(EditorTopStrip))
        .projects
        .active;
  }

  final pill = find.byKey(const ValueKey<String>('camera-adjust-pill'));

  Future<void> tapKey(WidgetTester tester, String key) async {
    final found = find.byKey(ValueKey<String>(key));
    await tester.ensureVisible(found);
    await tester.pumpAndSettle();
    await tester.tap(found);
    await tester.pumpAndSettle();
  }

  /// ⚙ ▸ Project settings ▸ the camera row ▸ 「캔버스에서 조정」.
  Future<void> openOnTheCanvas(WidgetTester tester) async {
    await tapKey(tester, 'top-strip-settings-button');
    await hoverFlyoutRow(tester, 'menu-project-settings');
    await tapKey(tester, 'project-settings-camera-size');
    await tapKey(tester, 'camera-size-adjust-on-canvas');
  }

  testWidgets('the camera window\'s 「캔버스에서 조정」 stands the frame on the '
      'canvas at the size it has, and Escape closes it', (tester) async {
    final session = await pumpApp(tester);
    final size = session.camera.cameraFrameSize;
    expect(pill, findsNothing, reason: '⛔전제: nothing open');

    await openOnTheCanvas(tester);
    expect(
      find.byKey(const ValueKey<String>('camera-size-dialog')),
      findsNothing,
      reason: 'closed',
    );
    expect(pill, findsOneWidget, reason: 'on the canvas showing the cut');
    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey<String>('camera-adjust-size')),
          )
          .data,
      '${size.width} × ${size.height}',
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(session.canvasAdjust.isOpen, isFalse);
    expect(pill, findsNothing);
    expect(session.camera.cameraFrameSize, size, reason: '✕ lands nothing');
  });

  testWidgets('🚨Enter lands the size as the project camera\'s — one step '
      'undo takes back', (tester) async {
    final session = await pumpApp(tester);
    final before = session.camera.cameraFrameSize;
    const after = CanvasSize(width: 1280, height: 720);
    expect(before, isNot(after), reason: '⛔전제: a size to change to');

    await openOnTheCanvas(tester);
    session.canvasAdjust.move(const CameraSizeDraft(size: after));
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(session.camera.cameraFrameSize, after);
    expect(session.canvasAdjust.isOpen, isFalse);
    expect(pill, findsNothing);

    session.undo();
    expect(session.camera.cameraFrameSize, before);
  });

  testWidgets('the frame is every cut\'s: the canvas showing another cut '
      'keeps it open', (tester) async {
    final session = await pumpApp(tester);
    final cut = session.requireActiveCut;
    await openOnTheCanvas(tester);
    expect(pill, findsOneWidget, reason: '⛔전제: open');

    session.cutVerbs.createCut();
    await tester.pump();
    await tester.pump();
    expect(
      session.requireActiveCut.id,
      isNot(cut.id),
      reason: '⛔전제: the canvas shows another cut',
    );
    expect(session.canvasAdjust.draft, isA<CameraSizeDraft>());
    expect(pill, findsOneWidget);
  });

  testWidgets('🚨the canvas holds one adjust — the canvas\'s own, opened, '
      'closes the camera\'s', (tester) async {
    final session = await pumpApp(tester);
    await openOnTheCanvas(tester);
    expect(pill, findsOneWidget, reason: '⛔전제: open');

    await tapCommandButton(
      tester,
      const ValueKey<String>('resize-cut-canvas-button'),
    );
    await tapKey(tester, 'canvas-size-adjust-on-canvas');

    expect(session.canvasAdjust.draft, isA<CanvasEdgesDraft>());
    expect(pill, findsNothing);
    expect(
      find.byKey(const ValueKey<String>('canvas-adjust-pill')),
      findsOneWidget,
    );
  });
}
