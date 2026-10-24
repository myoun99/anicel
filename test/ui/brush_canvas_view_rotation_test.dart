import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/canvas_pill.dart';
import 'package:anicel/src/models/app_input_settings.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/models/viewport_point.dart';
import 'package:anicel/src/ui/brush/brush_canvas_panel.dart';
import 'package:anicel/src/ui/brush/brush_edit_cache_invalidation_sink.dart';
import 'package:anicel/src/ui/brush/brush_tool_state.dart';
import 'package:anicel/src/ui/brush/canvas_floor_insets.dart';
import 'package:anicel/src/ui/brush/canvas_view_commands.dart';
import 'package:anicel/src/ui/canvas/canvas_viewport_gesture_layer.dart';
import 'package:anicel/src/ui/canvas/interactive_brush_edit_canvas_view.dart';
import 'package:anicel/src/ui/theme/app_theme.dart' show AppColors;

import '../helpers/app_icon_button_probe.dart';
import '../helpers/brush_canvas_fixture.dart';
import '../helpers/pinch_recognised_at.dart';

/// P8: canvas view rotation + horizontal flip — toolbar buttons, the
/// shortcut command channel, Fit's reset, pointer round-trip through a
/// rotated view, and the two-finger rotation gesture.
void main() {
  CanvasViewport viewportOf(WidgetTester tester) => tester
      .widget<InteractiveBrushEditCanvasView>(
        find.byType(InteractiveBrushEditCanvasView),
      )
      .viewport;

  Future<CanvasViewCommands> pumpPanel(
    WidgetTester tester, {
    int? Function(CanvasPoint point)? sampleColorAt,
    ValueChanged<int>? onEyedropperPick,
    BrushToolState brushToolState = BrushToolState.defaults,
  }) async {
    final frameKeys = BrushCanvasFixture.createFrameKeys();
    final commands = CanvasViewCommands();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BrushCanvasPanel(
            coordinator: BrushCanvasFixture.createCoordinator(
              frameKeys: frameKeys,
            ),
            availableFrameKeys: frameKeys,
            cacheInvalidationSink: BrushEditCacheInvalidationSink(),
            // A canvas standing on its own IS the floor, and that is where the
            // view controls live (법: 뷰 컨트롤은 바닥에만).
            floorCover: EdgeInsets.zero,
            brushToolState: ValueNotifier(brushToolState),
            viewCommands: commands,
            sampleColorAt: sampleColorAt,
            onEyedropperPick: onEyedropperPick,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return commands;
  }

  /// Rotate and flip live in the pill's settings list now (유저 확정
  /// 2026-08-13). They are ROWS there, so pressing one leaves the list
  /// open — opening it when it is already open would close it, so this
  /// only opens when the control is not on screen yet.
  Future<void> tapToolbarButton(WidgetTester tester, String key) async {
    final finder = find.byKey(ValueKey<String>(key));
    if (!tester.any(finder)) {
      await openViewSettings(tester);
    }
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  testWidgets('the angle readout still takes a DRAG inside the settings '
      'list', (tester) async {
    // 🚩The hazard this repo keeps meeting: a scrollable ancestor claims a
    // drag in the gesture arena before the control under the finger ever
    // sees it, and the control just stops working with no error at all
    // (see [[ui-round-r6]] ①/⑤). The settings list is a popup MENU, which
    // is scrollable — so moving the angle readout into it put the readout's
    // 1°/px drag on exactly that ground.
    //
    // Measured here rather than assumed: the readout keeps the drag, and
    // the row redraws while the list is open, which is the whole point of
    // [PanelFlyoutRow] carrying a listenable.
    await pumpPanel(tester);
    await openViewSettings(tester);

    final label = find.byKey(
      const ValueKey<String>('canvas-viewport-rotation-label'),
    );
    expect(label, findsOneWidget);
    expect(find.text('0.00°'), findsOneWidget, reason: 'starts straight');

    await tester.drag(label, const Offset(40, 0));
    await tester.pumpAndSettle();

    expect(
      find.text('0.00°'),
      findsNothing,
      reason: 'the menu must not have swallowed the drag',
    );
  });

  testWidgets('the rotate/flip buttons carry the STATE ACCENT ink '
      '(UI-R21 #1): rotated left accents the left button, right the '
      'right, flips accent while active', (tester) async {
    await pumpPanel(tester);
    // Rotate and flip live in the settings list now, and a knob does not
    // close it — so the whole accent sequence runs with it open, which is
    // also how a person uses it (straighten, look, flip, look).
    await openViewSettings(tester);
    // The PAINTED glyph colour — the ink its face draws — at the alpha it
    // is drawn with. 🚨The flyout row used to dim it to 38% as a side effect
    // of being a disabled PopupMenuItem (traced 2026-09-10: an IconTheme with
    // opacity 0.38, forty ancestors up); 유저 asked to see it undimmed
    // (「한번 그냥 흐리지않게 해보자」), so full alpha IS the assertion now —
    // see `_ControlsAtFullStrength` in panel_flyout.dart.
    Color? inkOf(String key) =>
        tester.glyphInkOf(find.byKey(ValueKey<String>(key)));

    // Straight, unflipped: everything rests on the default ink.
    for (final key in [
      'canvas-viewport-rotate-ccw',
      'canvas-viewport-rotate-cw',
      'canvas-viewport-flip',
      'canvas-viewport-flip-vertical',
    ]) {
      expect(inkOf(key), isNot(AppColors.accent), reason: '$key rests unaccented');
      expect(inkOf(key)!.a, 1.0, reason: '$key is at full strength in the flyout row');
    }

    await tapToolbarButton(tester, 'canvas-viewport-rotate-cw');
    expect(inkOf('canvas-viewport-rotate-cw'), AppColors.accent);
    expect(inkOf('canvas-viewport-rotate-ccw'), isNot(AppColors.accent));

    await tapToolbarButton(tester, 'canvas-viewport-rotate-ccw');
    await tapToolbarButton(tester, 'canvas-viewport-rotate-ccw');
    expect(inkOf('canvas-viewport-rotate-ccw'), AppColors.accent);
    expect(inkOf('canvas-viewport-rotate-cw'), isNot(AppColors.accent));

    await tapToolbarButton(tester, 'canvas-viewport-flip');
    expect(inkOf('canvas-viewport-flip'), AppColors.accent);
    await tapToolbarButton(tester, 'canvas-viewport-flip-vertical');
    expect(inkOf('canvas-viewport-flip-vertical'), AppColors.accent);
    await tapToolbarButton(tester, 'canvas-viewport-flip');
    expect(inkOf('canvas-viewport-flip'), isNot(AppColors.accent));
  });

  testWidgets('…and ON THE PILL, where the memo cannot help them', (
    tester,
  ) async {
    // 🚨The same accents, on the floor's own bar, and this is the harder
    // half. The pill is MEMOIZED and its token deliberately does not carry
    // rotation — it left the day these controls moved into the flyout, and
    // putting it back would throw thirteen buttons away on every frame of a
    // rotate drag. So the inline row listens to the viewport signal the way
    // the flyout row does, and this is the test that says so: press rotate
    // and the accent has to move with NOTHING having invalidated the bar.
    //
    // Delete the listener and the buttons keep working while the ink stays
    // where it was, until an unrelated pan or resize happens to rebuild the
    // pill — which is the same shape of bug the surface swatches had.
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.binding.setSurfaceSize(const Size(1200, 700));
    final frameKeys = BrushCanvasFixture.createFrameKeys();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 900,
            height: 600,
            child: CanvasFloorInsets(
              insets: EdgeInsets.zero,
              child: BrushCanvasPanel(
                coordinator: BrushCanvasFixture.createCoordinator(
                  frameKeys: frameKeys,
                ),
                availableFrameKeys: frameKeys,
                cacheInvalidationSink: BrushEditCacheInvalidationSink(),
                floorCover: EdgeInsets.zero,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // The PAINTED glyph colour — the ink its face draws — at the alpha it
    // is drawn with. 🚨The flyout row used to dim it to 38% as a side effect
    // of being a disabled PopupMenuItem (traced 2026-09-10: an IconTheme with
    // opacity 0.38, forty ancestors up); 유저 asked to see it undimmed
    // (「한번 그냥 흐리지않게 해보자」), so full alpha IS the assertion now —
    // see `_ControlsAtFullStrength` in panel_flyout.dart.
    Color? inkOf(String key) =>
        tester.glyphInkOf(find.byKey(ValueKey<String>(key)));

    // No list to open: the controls are on the bar (유저 확정 2026-08-13).
    expect(
      find.byKey(const ValueKey<String>('canvas-viewport-settings')),
      findsNothing,
    );
    expect(inkOf('canvas-viewport-rotate-cw'), isNot(AppColors.accent));

    await tester.tap(
      find.byKey(const ValueKey<String>('canvas-viewport-rotate-cw')),
    );
    await tester.pumpAndSettle();
    expect(inkOf('canvas-viewport-rotate-cw'), AppColors.accent);
    expect(inkOf('canvas-viewport-rotate-ccw'), isNot(AppColors.accent));

    await tester.tap(
      find.byKey(const ValueKey<String>('canvas-viewport-flip')),
    );
    await tester.pumpAndSettle();
    expect(inkOf('canvas-viewport-flip'), AppColors.accent);

    // The readout is the same story told in numbers.
    expect(find.text('15.00°'), findsOneWidget);
  });

  testWidgets('toolbar buttons rotate in 15° steps and toggle the flip', (
    tester,
  ) async {
    await pumpPanel(tester);
    expect(viewportOf(tester).rotationDegrees, 0);

    await tapToolbarButton(tester, 'canvas-viewport-rotate-cw');
    expect(viewportOf(tester).rotationDegrees, 15);
    expect(
      find.byKey(const ValueKey<String>('canvas-viewport-rotation-label')),
      findsOneWidget,
    );

    await tapToolbarButton(tester, 'canvas-viewport-rotate-ccw');
    expect(viewportOf(tester).rotationDegrees, 0);
    // The angle readout is ALWAYS on now (UI-R18 #20) — it reads 0°.
    expect(
      find.byKey(const ValueKey<String>('canvas-viewport-rotation-label')),
      findsOneWidget,
    );
    expect(find.text('0.00°'), findsOneWidget);

    await tapToolbarButton(tester, 'canvas-viewport-flip');
    expect(viewportOf(tester).flipHorizontal, isTrue);
    await tapToolbarButton(tester, 'canvas-viewport-flip');
    expect(viewportOf(tester).flipHorizontal, isFalse);
  });

  testWidgets('the command channel drives rotation/flip (R/Shift+R/H)', (
    tester,
  ) async {
    final commands = await pumpPanel(tester);

    commands.rotateStep(clockwise: true);
    await tester.pumpAndSettle();
    expect(viewportOf(tester).rotationDegrees, 15);

    commands.rotateStep(clockwise: false);
    commands.rotateStep(clockwise: false);
    await tester.pumpAndSettle();
    expect(viewportOf(tester).rotationDegrees, -15);

    commands.toggleFlipHorizontal();
    await tester.pumpAndSettle();
    expect(viewportOf(tester).flipHorizontal, isTrue);
  });

  group('🗣️F-391: ⟲ / ⟳ and the keys step by the ONE rotation snap, on '
      'its grid 「회전 스냅은 하나만」', () {
    tearDown(() {
      AppInput.settings.value = AppInputSettings.testCorpusBaseline;
    });

    /// Types [degrees] into the pill's angle readout — a view off the grid
    /// in one move, the way a person puts it there.
    Future<void> typeAngle(WidgetTester tester, String degrees) async {
      final pencil = find.byKey(
        const ValueKey<String>('canvas-viewport-rotation-label-edit'),
      );
      if (!tester.any(pencil)) {
        await openViewSettings(tester);
      }
      await tester.ensureVisible(pencil);
      await tester.pumpAndSettle();
      await tester.tap(pencil);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(
          const ValueKey<String>('canvas-viewport-rotation-label-input'),
        ),
        degrees,
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
    }

    testWidgets('from an angle off the grid, a step lands on the grid\'s '
        'next line — the button and the key alike', (tester) async {
      final commands = await pumpPanel(tester);

      await typeAngle(tester, '7');
      expect(viewportOf(tester).rotationDegrees, 7);
      await tapToolbarButton(tester, 'canvas-viewport-rotate-cw');
      expect(
        viewportOf(tester).rotationDegrees,
        15,
        reason: 'the line past 7, not 7 + 15 = 22',
      );

      await typeAngle(tester, '7');
      expect(viewportOf(tester).rotationDegrees, 7);
      commands.rotateStep(clockwise: false);
      await tester.pumpAndSettle();
      expect(
        viewportOf(tester).rotationDegrees,
        0,
        reason: 'the key presses the same step — not 7 − 15 = −8',
      );

      await typeAngle(tester, '-7');
      expect(viewportOf(tester).rotationDegrees, -7);
      await tapToolbarButton(tester, 'canvas-viewport-rotate-ccw');
      expect(viewportOf(tester).rotationDegrees, -15);
    });

    testWidgets('the step IS the setting — a 30° snap turns the button and '
        'the key by 30°', (tester) async {
      AppInput.settings.value = AppInputSettings.testCorpusBaseline.copyWith(
        rotationSnapDegrees: 30,
      );
      final commands = await pumpPanel(tester);

      await tapToolbarButton(tester, 'canvas-viewport-rotate-cw');
      expect(viewportOf(tester).rotationDegrees, 30);

      commands.rotateStep(clockwise: true);
      await tester.pumpAndSettle();
      expect(viewportOf(tester).rotationDegrees, 60);
    });
  });

  testWidgets('Fit resets rotation and flip (v1: Fit straightens)', (
    tester,
  ) async {
    final commands = await pumpPanel(tester);
    for (var step = 0; step < 3; step += 1) {
      commands.rotateStep(clockwise: true);
    }
    commands.toggleFlipHorizontal();
    await tester.pumpAndSettle();
    expect(viewportOf(tester).rotationDegrees, 45);

    await tapToolbarButton(tester, 'canvas-viewport-fit');
    expect(viewportOf(tester).rotationDegrees, 0);
    expect(viewportOf(tester).flipHorizontal, isFalse);
  });

  testWidgets('tool taps land on the right canvas point through a rotated '
      'view (input round-trip)', (tester) async {
    final sampledPoints = <CanvasPoint>[];
    final commands = await pumpPanel(
      tester,
      brushToolState: BrushToolState.defaults.copyWith(
        tool: CanvasTool.eyedropper,
      ),
      sampleColorAt: (point) {
        sampledPoints.add(point);
        return null;
      },
      onEyedropperPick: (_) {},
    );
    for (var step = 0; step < 6; step += 1) {
      commands.rotateStep(clockwise: true);
    }
    commands.toggleFlipHorizontal();
    await tester.pumpAndSettle();
    final viewport = viewportOf(tester);
    expect(viewport.rotationDegrees, 90);

    final tapLayer = find.byKey(
      const ValueKey<String>('canvas-tool-tap-layer'),
    );
    const localOffset = Offset(50, 80);
    await tester.tapAt(tester.getTopLeft(tapLayer) + localOffset);
    await tester.pump();

    // The tap layer converts through the SAME viewport that painted the
    // view — the sampled point must be exactly viewportToCanvas(local).
    final expected = viewport.viewportToCanvas(
      ViewportPoint(x: localOffset.dx, y: localOffset.dy),
    );
    expect(sampledPoints, hasLength(1));
    expect(sampledPoints.single.x, closeTo(expected.x, 1e-6));
    expect(sampledPoints.single.y, closeTo(expected.y, 1e-6));
  });

  group('two-finger rotation gesture', () {
    /// The second finger sweeps from (200, 100) around the first at
    /// (100, 100) — from where the pinch was RECOGNISED there (F-260), or,
    /// with [recognised] false, from where the two fingers merely landed.
    Future<CanvasViewport?> runTwoFingerArc(
      WidgetTester tester, {
      required Offset secondFingerEnd,
      bool recognised = true,
    }) async {
      CanvasViewport? emitted;
      await tester.pumpWidget(
        MaterialApp(
          home: CanvasViewportGestureLayer(
            viewport: CanvasViewport(),
            onViewportChanged: (viewport) => emitted = viewport,
            child: const SizedBox(width: 400, height: 400),
          ),
        ),
      );

      const firstAt = Offset(100, 100);
      const secondAt = Offset(200, 100);
      final (first, second) = recognised
          ? await pinchRecognisedAt(tester, firstAt, secondAt)
          : (
              await tester.startGesture(
                firstAt,
                kind: PointerDeviceKind.touch,
              ),
              await tester.startGesture(
                secondAt,
                kind: PointerDeviceKind.touch,
              ),
            );
      await tester.pump();
      await second.moveTo(secondFingerEnd);
      await tester.pump();
      await first.up();
      await second.up();
      await tester.pump();
      return emitted;
    }

    testWidgets('past the deadzone the view rotates (minus the deadzone)', (
      tester,
    ) async {
      // Second finger sweeps 60° around the first at constant distance
      // (no zoom): raw 60° − 5° deadzone = 55°.
      final emitted = await runTwoFingerArc(
        tester,
        secondFingerEnd: const Offset(150, 186.60254),
      );
      expect(emitted, isNotNull);
      expect(emitted!.rotationDegrees, closeTo(55, 0.01));
    });

    testWidgets('inside the deadzone a pinch stays level', (tester) async {
      // A mostly-radial move — ~1.4° of angle on a 40px travel: below the
      // 5° deadzone, no rotation (the zoom may change, that is not this
      // pin).
      final emitted = await runTwoFingerArc(
        tester,
        secondFingerEnd: const Offset(240, 103.42),
      );
      expect(emitted, isNotNull);
      expect(emitted!.rotationDegrees, 0);
    });

    testWidgets('small engaged angles snap back to 0°', (tester) async {
      // ~8° sweep on a 43px travel: engaged (past the 5° deadzone),
      // effective ~3° — inside the zero-snap window.
      final emitted = await runTwoFingerArc(
        tester,
        secondFingerEnd: const Offset(238.64, 119.48),
      );
      expect(emitted, isNotNull);
      expect(emitted!.rotationDegrees, 0);
    });

    testWidgets('sub-slop two-finger travel emits nothing — the lock slop '
        'keeps two-finger TAPS clean (PEN-12 #4 engine contract)', (
      tester,
    ) async {
      final emitted = await runTwoFingerArc(
        tester,
        // ~5px of travel: under the 18px lock slop.
        secondFingerEnd: const Offset(199.86, 105.23),
        recognised: false,
      );
      expect(emitted, isNull);
    });
  });
}
