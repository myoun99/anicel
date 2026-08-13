import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/brush_dab.dart';
import 'package:anicel/src/models/brush_tip_shape.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/services/brush_frame_editing_coordinator.dart';
import 'package:anicel/src/services/canvas_color_sampler.dart';
import 'package:anicel/src/services/canvas_selection.dart';
import 'package:anicel/src/services/canvas_selection_region.dart';
import 'package:anicel/src/services/history_manager.dart';
import 'package:anicel/src/ui/brush/brush_canvas_panel.dart';
import 'package:anicel/src/ui/brush/brush_edit_cache_invalidation_sink.dart';
import 'package:anicel/src/ui/brush/brush_tool_state.dart';
import 'package:anicel/src/ui/brush/canvas_selection_commands.dart';
import 'package:anicel/src/ui/canvas/interactive_brush_edit_canvas_view.dart';
import 'package:anicel/src/ui/canvas/canvas_selection_layer.dart';

import '../helpers/brush_canvas_fixture.dart';

/// R28-S — the selection unification round.
///
/// Three contracts the old model could not hold, all of them the reason
/// R27 #19 read as "선택툴이 아예 작동 안 함":
///  1. the selection SURVIVES a tool switch (it was widget State inside a
///     layer that only mounted for selection tools);
///  2. its ants stay visible under every tool;
///  3. painting CLIPS to it (R26 #18).
void main() {
  const layerKey = ValueKey<String>('canvas-selection-layer');
  const idleAntsKey = ValueKey<String>('canvas-idle-selection-ants');

  BrushDab dab(double x, double y) => BrushDab(
    center: CanvasPoint(x: x, y: y),
    color: 0xFFFF0000,
    size: 4,
    opacity: 1,
    flow: 1,
    hardness: 1,
    tipShape: BrushTipShape.square,
    pressure: 1,
    sequence: 0,
  );

  Future<
    ({
      BrushFrameEditingCoordinator coordinator,
      HistoryManager history,
      CanvasSelectionCommands commands,
      Future<void> Function(CanvasTool tool) setTool,
    })
  >
  pumpPanel(WidgetTester tester, {CanvasTool tool = CanvasTool.select}) async {
    final frameKeys = BrushCanvasFixture.createFrameKeys();
    final coordinator = BrushCanvasFixture.createCoordinator(
      frameKeys: frameKeys,
    );
    final history = HistoryManager();
    final commands = CanvasSelectionCommands();

    Future<void> pumpWith(CanvasTool tool) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BrushCanvasPanel(
              coordinator: coordinator,
              availableFrameKeys: frameKeys,
              cacheInvalidationSink: BrushEditCacheInvalidationSink(),
              historyManager: history,
              brushToolState: BrushToolState.defaults.copyWith(tool: tool),
              selectionCommands: commands,
            ),
          ),
        ),
      );
      await tester.pump();
    }

    await pumpWith(tool);
    return (
      coordinator: coordinator,
      history: history,
      commands: commands,
      setTool: pumpWith,
    );
  }

  int inkAt(BrushFrameEditingCoordinator coordinator, int x, int y) =>
      surfacePixelRgba(
        coordinator.currentSurfaceOf(coordinator.activeFrameKey),
        x,
        y,
      ) ??
      0;

  Future<void> dragOnLayer(
    WidgetTester tester,
    Finder target,
    Offset from,
    Offset to,
  ) async {
    final origin = tester.getTopLeft(target);
    final gesture = await tester.startGesture(
      origin + from,
      kind: PointerDeviceKind.mouse,
      buttons: kPrimaryButton,
    );
    await tester.pump();
    await gesture.moveTo(origin + (from + to) / 2);
    await tester.pump();
    await gesture.moveTo(origin + to);
    await tester.pump();
    await gesture.up();
    await tester.pump();
  }

  testWidgets('the region survives a tool switch and its ants keep showing', (
    tester,
  ) async {
    final env = await pumpPanel(tester);
    await dragOnLayer(
      tester,
      find.byKey(layerKey),
      const Offset(20, 20),
      const Offset(70, 70),
    );
    expect(env.commands.region, isNotNull);
    expect(find.byKey(idleAntsKey), findsNothing, reason: 'the layer owns them');

    // Switch to the BRUSH: the interaction layer unmounts, the selection
    // does NOT (it used to die with the layer's State).
    await env.setTool(CanvasTool.brush);
    expect(find.byType(CanvasSelectionLayer), findsNothing);
    expect(env.commands.region, isNotNull);
    expect(find.byKey(idleAntsKey), findsOneWidget);

    // And coming back finds it again.
    await env.setTool(CanvasTool.select);
    expect(find.byKey(idleAntsKey), findsNothing);
    expect(env.commands.region, isNotNull);
  });

  testWidgets('R26 #18: with a selection the brush paints INSIDE it only', (
    tester,
  ) async {
    final env = await pumpPanel(tester);
    // Select the left half of a 200-wide band.
    env.commands.setRegion(
      CanvasSelectionRegion.shape(
        CanvasSelectionShape.rect(left: 0, top: 0, right: 40, bottom: 200),
      ),
    );
    await env.setTool(CanvasTool.brush);

    // One stroke straddling the boundary: 20 → 60.
    final view = find.byKey(const ValueKey<String>('brush-canvas-view'));
    await dragOnLayer(tester, view, const Offset(20, 50), const Offset(60, 50));

    expect(inkAt(env.coordinator, 22, 50), isNonZero, reason: 'inside lands');
    expect(inkAt(env.coordinator, 55, 50), 0, reason: 'outside is clipped');
  });

  testWidgets('a stroke entirely outside the selection lands NOTHING and '
      'records no history', (tester) async {
    final env = await pumpPanel(tester);
    env.commands.setRegion(
      CanvasSelectionRegion.shape(
        CanvasSelectionShape.rect(left: 0, top: 0, right: 20, bottom: 20),
      ),
    );
    await env.setTool(CanvasTool.brush);
    final entriesBefore = env.history.undoCount;

    final view = find.byKey(const ValueKey<String>('brush-canvas-view'));
    await dragOnLayer(
      tester,
      view,
      const Offset(100, 100),
      const Offset(140, 100),
    );

    expect(inkAt(env.coordinator, 120, 100), 0);
    expect(env.history.undoCount, entriesBefore);
  });

  testWidgets('deselecting restores unclipped painting', (tester) async {
    final env = await pumpPanel(tester);
    env.commands.setRegion(
      CanvasSelectionRegion.shape(
        CanvasSelectionShape.rect(left: 0, top: 0, right: 20, bottom: 20),
      ),
    );
    await env.setTool(CanvasTool.brush);
    env.commands.setRegion(null);
    await tester.pump();

    final view = find.byKey(const ValueKey<String>('brush-canvas-view'));
    await dragOnLayer(
      tester,
      view,
      const Offset(100, 100),
      const Offset(140, 100),
    );
    expect(inkAt(env.coordinator, 120, 100), isNonZero);
  });

  testWidgets('R26 #16: the marquee folds under the ACTIVE mode', (
    tester,
  ) async {
    final env = await pumpPanel(tester);
    final layer = find.byKey(layerKey);

    // Default 추가: two disjoint drags select BOTH lobes.
    expect(env.commands.combineMode, SelectionCombineMode.add);
    await dragOnLayer(tester, layer, const Offset(10, 10), const Offset(40, 40));
    await dragOnLayer(
      tester,
      layer,
      const Offset(80, 10),
      const Offset(110, 40),
    );
    var region = env.commands.region!;
    expect(region.containsPoint(CanvasPoint(x: 25, y: 25)), isTrue);
    expect(region.containsPoint(CanvasPoint(x: 95, y: 25)), isTrue);
    expect(region.containsPoint(CanvasPoint(x: 60, y: 25)), isFalse);

    // 삭제: a drag over the first lobe cuts it back out.
    env.commands.combineMode = SelectionCombineMode.subtract;
    await tester.pump();
    await dragOnLayer(tester, layer, const Offset(5, 5), const Offset(45, 45));
    region = env.commands.region!;
    expect(region.containsPoint(CanvasPoint(x: 25, y: 25)), isFalse);
    expect(region.containsPoint(CanvasPoint(x: 95, y: 25)), isTrue);

    // 갱신: the next drag is the whole selection again.
    env.commands.combineMode = SelectionCombineMode.replace;
    await tester.pump();
    await dragOnLayer(
      tester,
      layer,
      const Offset(140, 10),
      const Offset(170, 40),
    );
    region = env.commands.region!;
    expect(region.steps, hasLength(1));
    expect(region.containsPoint(CanvasPoint(x: 95, y: 25)), isFalse);
    expect(region.containsPoint(CanvasPoint(x: 155, y: 25)), isTrue);
  });

  testWidgets('the PS/CSP modifier chord overrides the mode for one drag', (
    tester,
  ) async {
    final env = await pumpPanel(tester);
    final layer = find.byKey(layerKey);
    env.commands.combineMode = SelectionCombineMode.replace;
    await tester.pump();

    await dragOnLayer(tester, layer, const Offset(10, 10), const Offset(40, 40));
    // SHIFT held: adds instead of replacing, even though the tool setting
    // says 갱신.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await dragOnLayer(
      tester,
      layer,
      const Offset(80, 10),
      const Offset(110, 40),
    );
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    var region = env.commands.region!;
    expect(region.containsPoint(CanvasPoint(x: 25, y: 25)), isTrue);
    expect(region.containsPoint(CanvasPoint(x: 95, y: 25)), isTrue);

    // ALT held: subtracts.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await dragOnLayer(tester, layer, const Offset(5, 5), const Offset(45, 45));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    region = env.commands.region!;
    expect(region.containsPoint(CanvasPoint(x: 25, y: 25)), isFalse);
    expect(region.containsPoint(CanvasPoint(x: 95, y: 25)), isTrue);
    expect(
      env.commands.combineMode,
      SelectionCombineMode.replace,
      reason: 'the chord overrides the drag, never the setting',
    );
  });

  testWidgets('every fold is ONE undo step, and undo restores the region '
      'even with the brush armed', (tester) async {
    final env = await pumpPanel(tester);
    final layer = find.byKey(layerKey);
    final entriesBefore = env.history.undoCount;

    await dragOnLayer(tester, layer, const Offset(10, 10), const Offset(40, 40));
    await dragOnLayer(
      tester,
      layer,
      const Offset(80, 10),
      const Offset(110, 40),
    );
    expect(env.history.undoCount, entriesBefore + 2);

    await env.setTool(CanvasTool.brush);
    env.history.undo();
    await tester.pump();
    final region = env.commands.region!;
    expect(
      region.containsPoint(CanvasPoint(x: 95, y: 25)),
      isFalse,
      reason: 'the second lobe undid',
    );
    expect(region.containsPoint(CanvasPoint(x: 25, y: 25)), isTrue);

    env.history.undo();
    await tester.pump();
    expect(env.commands.region, isNull);
  });

  testWidgets('the LIVE preview is armed with the region in the real app — '
      'the painter gets it while an actual stroke is in flight', (
    tester,
  ) async {
    // [[parity-tests-must-drive-real-input]]: the display half of R26 #18
    // is only worth anything if it is switched ON in the shipping widget
    // tree. The pixels themselves are pinned deterministically in
    // selection_live_clip_paint_test.dart; this pins the wiring, under a
    // real gesture, the way R27 #4's near-miss taught.
    final env = await pumpPanel(tester);
    final region = CanvasSelectionRegion.shape(
      CanvasSelectionShape.rect(left: 0, top: 0, right: 40, bottom: 200),
    );
    env.commands.setRegion(region);
    await env.setTool(CanvasTool.brush);

    final view = find.byKey(const ValueKey<String>('brush-canvas-view'));
    final origin = tester.getTopLeft(view);
    final gesture = await tester.startGesture(
      origin + const Offset(20, 50),
      kind: PointerDeviceKind.mouse,
      buttons: kPrimaryButton,
    );
    await tester.pump();
    await gesture.moveTo(origin + const Offset(35, 50));
    await tester.pump();

    expect(
      tester
          .widget<InteractiveBrushEditCanvasView>(
            find.byType(InteractiveBrushEditCanvasView),
          )
          .selectionRegion,
      region,
      reason: 'the stroke rasterizer masks with this region',
    );

    await gesture.up();
    await tester.pump();

    // And with no selection the mask is OFF — the kernel then takes its
    // null-mask path, which is byte-identical to the no-selection
    // pipeline the R27 #4 parity suites pin.
    env.commands.setRegion(null);
    await tester.pump();
    expect(
      tester
          .widget<InteractiveBrushEditCanvasView>(
            find.byType(InteractiveBrushEditCanvasView),
          )
          .selectionRegion,
      isNull,
    );
  });

  testWidgets('the lift honours the composite region: a subtracted hole '
      'stays behind when the selection moves', (tester) async {
    final env = await pumpPanel(tester);
    env.coordinator.commitSourceStroke(
      sourceDabs: [for (var x = 20; x <= 60; x += 2) dab(x.toDouble(), 40)],
    );
    // Everything from 10..70 EXCEPT a hole around x = 40.
    env.commands.setRegion(
      CanvasSelectionRegion.shape(
        CanvasSelectionShape.rect(left: 10, top: 20, right: 70, bottom: 60),
      ).combinedWith(
        CanvasSelectionShape.rect(left: 36, top: 20, right: 46, bottom: 60),
        SelectionCombineMode.subtract,
      )!,
    );
    await env.setTool(CanvasTool.move);
    await tester.pump();

    await dragOnLayer(
      tester,
      find.byKey(layerKey),
      const Offset(30, 40),
      const Offset(30, 140),
    );
    expect(env.commands.movePending, isTrue);
    expect(
      inkAt(env.coordinator, 40, 40),
      isNonZero,
      reason: 'the hole was never selected, so its ink never lifted',
    );
    expect(
      inkAt(env.coordinator, 24, 40),
      0,
      reason: 'selected ink lifted away from the origin',
    );
  });

  group('the open polygon trace lives on the channel', () {
    // It has to outlive the layer that draws it: 유저 확정 says a trace
    // survives a frame change AND a cut change, and changing cuts remounts
    // the layer outright.
    CanvasSelectionCommands commandsWith(int points) {
      final commands = CanvasSelectionCommands();
      for (var i = 0; i < points; i += 1) {
        commands.addPolygonPoint(CanvasPoint(x: i * 10, y: i * 10));
      }
      return commands;
    }

    test('undo takes the last vertex back, redo puts it there again', () {
      final commands = commandsWith(3);
      expect(commands.undoPolygonPoint(), isTrue);
      expect(commands.polygonPoints, hasLength(2));
      expect(commands.canClosePolygon, isFalse);
      expect(commands.redoPolygonPoint(), isTrue);
      expect(commands.polygonPoints, hasLength(3));
      expect(commands.polygonPoints.last, CanvasPoint(x: 20, y: 20));
    });

    test('undo past the first vertex hands the key back', () {
      // The rule that keeps undo from ever being a dead key: once the
      // trace is empty the channel says no and the caller lets undo mean
      // what it usually means.
      final commands = commandsWith(1);
      expect(commands.undoPolygonPoint(), isTrue);
      expect(commands.undoPolygonPoint(), isFalse);
      expect(commands.redoPolygonPoint(), isTrue);
    });

    test('a fresh vertex ends the redo road', () {
      final commands = commandsWith(2);
      commands.undoPolygonPoint();
      commands.addPolygonPoint(CanvasPoint(x: 99, y: 99));
      expect(commands.redoPolygonPoint(), isFalse);
      expect(commands.polygonPoints, hasLength(2));
    });

    test('two vertices enclose nothing, so confirming just ends the trace', () {
      final commands = commandsWith(2);
      expect(commands.takePolygonShape(), isNull);
      expect(commands.hasOpenPolygon, isFalse);
    });

    test('three vertices make the outline, and the trace is over', () {
      final commands = commandsWith(3);
      final shape = commands.takePolygonShape();
      expect(shape, isNotNull);
      expect(shape!.points, hasLength(3));
      expect(commands.hasOpenPolygon, isFalse);
      expect(commands.redoPolygonPoint(), isFalse, reason: 'redo went too');
    });

    test('closePolygon says whether it spent the confirm', () {
      // False means the confirm was not for a polygon, and its usual
      // meaning gets to run.
      final commands = CanvasSelectionCommands();
      expect(commands.closePolygon(), isFalse);
      commands.addPolygonPoint(CanvasPoint(x: 0, y: 0));
      expect(commands.closePolygon(), isTrue);
      expect(commands.hasOpenPolygon, isFalse);
    });
  });
}
