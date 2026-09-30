import 'package:flutter/gestures.dart' show PointerDeviceKind, kPrimaryButton;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/services/editing/default_cut_helpers.dart';
import 'package:anicel/src/ui/editor_canvas_area.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/theme/app_theme.dart';

import '../../helpers/panel_finders.dart';

/// 🗣️F-223 (유저 2026-09-28): 「카메라 레이어에 서있을때 변형툴쓰면
/// 콘티그림?이 옮겨짐. 그림이 없으면 아무것도 안하는 로직인건데.」
///
/// The camera row holds no picture. The canvas SHOWS the first drawn row's
/// cel while you stand on it (`Camera.cameraBackdropSelection`) — and the
/// transform tool's layer lies over the camera frame, so its press reached
/// that borrowed cel and lifted it. Standing on the camera row, the
/// transform tool has nothing of its own to lift.
void main() {
  testWidgets('standing on the camera row, the transform tool lifts nothing',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1600, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(theme: buildAppTheme(), home: const HomePage()),
    );
    await tester.pumpAndSettle();
    final area = tester.widget<EditorCanvasArea>(find.byType(EditorCanvasArea));
    final session = area.session;
    final commands = area.canvasSelectionCommands!;

    // Ink on the row the camera row will borrow: the first drawn row.
    final borrowed = session.activeCutOrNull!.layers.firstWhere(
      (layer) => layer.kind.paintsArtwork && layer.isVisible,
    );
    session.selectLayer(borrowed.id);
    await tester.pumpAndSettle();
    if (session.editingCanvas.activeBrushEditorSelection == null) {
      session.createDrawingAtCurrentFrame();
      await tester.pumpAndSettle();
    }
    final at = visibleCanvasPoint(tester);
    final pen = await tester.startGesture(
      at,
      kind: PointerDeviceKind.mouse,
      buttons: kPrimaryButton,
    );
    await tester.pump();
    await pen.moveTo(at + const Offset(40, 10));
    await tester.pump();
    await pen.up();
    await tester.pumpAndSettle();
    Layer row() => session.activeCutOrNull!.layers.firstWhere(
      (layer) => layer.id == borrowed.id,
    );
    final inkBefore = session.renderCaches.layerContentBoundsAt(row(), 0);
    expect(inkBefore, isNotNull, reason: 'the premise: there is ink to lift');

    session.selectLayer(cameraLayerIdForCut(session.activeCutOrNull!.id));
    await tester.pumpAndSettle();
    expect(
      session.camera.cameraBackdropSelection?.layerId,
      borrowed.id,
      reason: 'the premise: the camera row shows the inked cel',
    );
    final cameraBefore = session.camera.cameraPoseAtCurrentFrame.center;

    // Ctrl+T arms the transform tool; drag across the ink, then 확정.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyT);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    final drag = await tester.startGesture(
      at + const Offset(10, 3),
      kind: PointerDeviceKind.mouse,
      buttons: kPrimaryButton,
    );
    await tester.pump();
    await drag.moveTo(at + const Offset(60, 3));
    await tester.pump();
    await drag.up();
    await tester.pumpAndSettle();
    expect(commands.movePending, isFalse, reason: '그림이 없으면 아무것도 안한다');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(
      session.renderCaches.layerContentBoundsAt(row(), 0),
      inkBefore,
      reason: 'the borrowed cel\'s picture did not move',
    );
    expect(session.camera.cameraPoseAtCurrentFrame.center, cameraBefore);
    session.playbackRig.prerenderScheduler.cancel();
  });
}
