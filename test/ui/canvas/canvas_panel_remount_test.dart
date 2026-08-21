import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/brush_frame_key.dart';
import 'package:anicel/src/ui/brush/main_canvas_brush_host.dart';
import 'package:anicel/src/ui/canvas/canvas_viewport_gesture_layer.dart';
import 'package:anicel/src/ui/canvas/flip_hud_controller.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/input/app_input_settings.dart';

import '../../helpers/panel_finders.dart';

/// The canvas panel must stay MOUNTED as the playhead crosses "no cel ↔
/// cel". It did not: the host wrapped the panel in a refusal [Listener]
/// only when there was nothing to draw on, and a [ValueKey] holds identity
/// only under the same parent — so the panel's whole State was rebuilt
/// every time a flip landed on a block.
///
/// Mid-gesture that is the bug the user reported (2026-08-06): the pointer
/// in flight keeps being delivered to the DISPOSED render object, which
/// asserts once per move in debug and writes to a disposed notifier in
/// release, and the gesture layer's own `dispose` ends the flip HUD — the
/// window vanished the instant a flip touched a block and stayed gone
/// until the finger lifted.
///
/// ⚠️ The oracle is the panel's ELEMENT, not anything you can see. A test
/// that asked "is the HUD on screen" passes against a panel that is torn
/// down and rebuilt between frames, which is exactly the defect.
void main() {
  tearDown(() {
    AppInput.settings.value = AppInputSettings.testCorpusBaseline;
  });

  // Several panels mount a canvas of their own (conte, timesheet, the cut
  // envelope); this key is the MAIN one's.
  final mainPanel = find.byKey(
    const ValueKey<String>('main-canvas-brush-host'),
  );
  final mainGestureLayer = find.descendant(
    of: mainPanel,
    matching: find.byType(CanvasViewportGestureLayer),
  );

  Future<_AppHandle> openApp(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1600, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const MaterialApp(home: HomePage()));
    await tester.pumpAndSettle();
    return _AppHandle(
      tester.widget<EditorWorkspace>(find.byType(EditorWorkspace)),
    );
  }

  /// What the host resolves as the editable cel — null on an empty frame.
  /// The fixture guard: without it a test that never crosses the boundary
  /// passes against the defect.
  BrushFrameKey? activeCel(WidgetTester tester) => tester
      .widget<MainCanvasBrushHost>(
        find.ancestor(
          of: mainPanel,
          matching: find.byType(MainCanvasBrushHost),
        ),
      )
      .resolvedActiveFrameKey;

  testWidgets('landing on a block keeps the canvas panel\'s element', (
    tester,
  ) async {
    final app = await openApp(tester);
    final session = app.session;

    // One block at frame 0; everything after it is empty paper.
    session.selectFrameIndex(0);
    session.createDrawingAtCurrentFrame();
    await tester.pumpAndSettle();
    expect(activeCel(tester), isNotNull, reason: 'frame 0 holds a cel');

    session.selectFrameIndex(4);
    await tester.pumpAndSettle();
    expect(
      activeCel(tester),
      isNull,
      reason: 'frame 4 is empty — the fixture crosses the boundary',
    );
    final onEmptyFrame = tester.element(mainPanel);

    session.selectFrameIndex(0);
    await tester.pumpAndSettle();
    expect(activeCel(tester), isNotNull);
    expect(
      identical(tester.element(mainPanel), onEmptyFrame),
      isTrue,
      reason: 'the panel must survive the cel appearing under the playhead',
    );

    // And back out again — the other direction is the same crossing.
    session.selectFrameIndex(4);
    await tester.pumpAndSettle();
    expect(activeCel(tester), isNull);
    expect(
      identical(tester.element(mainPanel), onEmptyFrame),
      isTrue,
      reason: 'and the cel going away',
    );
  });

  testWidgets('a flip that lands on a block leaves the HUD up, and the '
      'gesture in flight keeps its layer', (tester) async {
    AppInput.settings.value = AppInput.settings.value.copyWith(
      touchDragOneFinger: CanvasTouchDragAction.flip,
    );
    final app = await openApp(tester);
    final session = app.session;
    final hud = app.flipHud;

    session.selectFrameIndex(0);
    session.createDrawingAtCurrentFrame();
    session.selectFrameIndex(4);
    await tester.pumpAndSettle();
    expect(activeCel(tester), isNull, reason: 'standing on empty paper');

    final layerBefore = tester.element(mainGestureLayer);
    // ⛔The VISIBLE canvas, not the box centre: the canvas is full-bleed
    // under the floating region, and D37 opens that region at half the
    // window — so `getCenter` now lands on the timeline and the flip
    // gesture never starts. [visibleCanvasPoint] documents this trap.
    final finger = await tester.startGesture(
      visibleCanvasPoint(tester),
      kind: PointerDeviceKind.touch,
    );
    // Lock the horizontal axis without completing a step...
    await finger.moveBy(const Offset(-30, 2));
    await tester.pump();
    expect(hud.displayAxis, isNotNull, reason: 'the window opened on the lock');

    // ...then walk LEFT onto the block at frame 0, one column per 48px.
    for (var step = 0; step < 4; step += 1) {
      await finger.moveBy(const Offset(-48, 0));
      await tester.pump();
    }
    expect(
      session.currentFrameIndex,
      0,
      reason: 'the flip walked the columns onto the block',
    );
    expect(activeCel(tester), isNotNull, reason: 'and a cel is under it now');

    // The SYMPTOM first, so a regression reports what the user would see.
    //
    // ⚠️ `visible` alone would be VACUOUS at this instant: a spurious
    // `end()` nulls the LIVE axis at once but leaves the picture up for
    // the release hold, so the window still reads as visible for another
    // 350ms. The live axis is what fails the moment the gesture is torn
    // out from under the HUD.
    expect(
      hud.axis,
      isNotNull,
      reason: 'the drag still owns the window — nothing ended it',
    );
    // And the same thing at the user's own pace: the window is still there
    // a beat later, rather than fading out with the finger still down.
    await tester.pump(
      FlipHudController.holdAfterRelease + FlipHudController.fadeOut,
    );
    expect(hud.visible, isTrue, reason: 'no release hold ever started');
    expect(hud.displayAxis, isNotNull, reason: 'still on screen');

    // Then the CAUSE.
    expect(
      identical(tester.element(mainGestureLayer), layerBefore),
      isTrue,
      reason: 'the gesture in flight never lost its layer',
    );

    await finger.up();
    await tester.pump();
  });
}

/// Reaches the session and the shell-owned flip HUD behind the app.
class _AppHandle {
  _AppHandle(this._workspace);

  final EditorWorkspace _workspace;

  EditorSessionManager get session => _workspace.session;
  FlipHudController get flipHud => _workspace.flipHud!;
}
