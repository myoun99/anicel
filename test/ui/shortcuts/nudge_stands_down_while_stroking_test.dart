// THE ARROW KEYS DO NOT NUDGE A SELECTION WHILE A STROKE IS LIVE.
//
// A survivor of the mutation campaign (2026-09-04, the _invokeAction cut):
// the `brushInputActive` guard inside the nudge arm was silenced and every
// shortcut test stayed green — none of them held a stroke while pressing
// an arrow. R16-③ is why the guard exists: rewriting the lift under the
// pen froze both. This pin inks the canvas, selects all of it, flags the
// stroke, and asks whether the arrow lifted anything.
import 'package:flutter/gestures.dart' show PointerDeviceKind, kPrimaryButton;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/services/canvas_selection_region.dart';
import 'package:anicel/src/services/canvas_selection_shape.dart';
import 'package:anicel/src/ui/editor_canvas_area.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/theme/app_theme.dart';

import '../../helpers/panel_finders.dart' show visibleCanvasPoint;

void main() {
  testWidgets('an arrow nudges the marquee only while no stroke is live', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(theme: buildAppTheme(), home: const HomePage()),
    );
    await tester.pumpAndSettle();
    final area = tester.widget<EditorCanvasArea>(
      find.byType(EditorCanvasArea),
    );
    final session = area.session;
    final commands = area.canvasSelectionCommands!;

    // Ink to move: a cel on the current frame and one brush stroke on it.
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

    // M: rectangle select mounts the selection layer; the whole canvas is
    // the region, so the stroke is under it wherever it landed. Single
    // frames from here: the ants march for as long as the region exists.
    await tester.sendKeyEvent(LogicalKeyboardKey.keyM);
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

    // A live stroke: the arrow stands down — nothing lifts.
    session.brushInputActive.value = true;
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(
      commands.movePending,
      isFalse,
      reason: 'the nudge stands down under the pen (R16-③)',
    );

    // The stroke lifted: the same arrow nudges — the ink floats, awaiting
    // its confirm.
    session.brushInputActive.value = false;
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(
      commands.movePending,
      isTrue,
      reason: 'the nudge lifts the ink under the region and floats it',
    );

    // Leave the editor as it was found: the float goes back where it was
    // lifted from, the region goes, and the resample the lift scheduled
    // runs before the tree is torn down.
    commands.revertPendingMove();
    await tester.pump();
    commands.deselect();
    await tester.pumpAndSettle();
  });
}
