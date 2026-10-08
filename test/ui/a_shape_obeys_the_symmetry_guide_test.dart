import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_shape_kind.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/models/drawing_guide.dart';
import 'package:anicel/src/models/shape_tool_options.dart';
import 'package:anicel/src/services/brush_frame_editing_coordinator.dart';
import 'package:anicel/src/services/canvas_color_sampler.dart';
import 'package:anicel/src/services/canvas_flood_fill.dart';
import 'package:anicel/src/services/history_manager.dart';
import 'package:anicel/src/ui/brush/brush_canvas_panel.dart';
import 'package:anicel/src/ui/brush/brush_edit_cache_invalidation_sink.dart';
import 'package:anicel/src/ui/brush/brush_tool_state.dart';
import 'package:anicel/src/ui/brush/canvas_selection_commands.dart';
import 'package:anicel/src/ui/canvas/selection_ants_painter.dart';

import '../helpers/brush_canvas_fixture.dart';
import '../helpers/device_viewport.dart';

/// 🗣️I-69-Q6 (유저 2026-10-08): 「따른다 — 도형 채우기도 같이 맞춘다」. A
/// symmetry guide copies what the SHAPE tool draws — its plain line, its
/// fill — and what the fill tool's shape fill fills, as it copies a stroke
/// and a selection: every drawing verb one law.
///
/// Driven through the real panel, so the wiring from the drag's copies to
/// the one area they land as is part of what is pinned.
void main() {
  const layerKey = ValueKey<String>('canvas-selection-layer');
  const canvasSize = CanvasSize(width: 200, height: 120);

  /// A vertical mirror down the middle of the canvas: x → 200 − x.
  CutGuides mirrorGuides() {
    final guide = DrawingGuide(
      id: const GuideId('mirror'),
      name: 'Mirror',
      shape: SymmetryShape(
        axis: GuideAxis(origin: CanvasPoint(x: 100, y: 60), angleDegrees: 90),
        lineCount: 2,
      ),
    );
    return CutGuides(guides: [guide], activeSymmetryId: guide.id);
  }

  Future<({BrushFrameEditingCoordinator coordinator, HistoryManager history})>
  pumpPanel(
    WidgetTester tester, {
    required CutGuides? guides,
    required CanvasTool tool,
    CanvasShapeKind shapeKind = CanvasShapeKind.rect,
    ShapeToolOptions shapeOptions = const ShapeToolOptions(),
  }) async {
    final frameKeys = BrushCanvasFixture.createFrameKeys();
    final coordinator = BrushCanvasFixture.createCoordinator(
      frameKeys: frameKeys,
      canvasSize: canvasSize,
    );
    final history = HistoryManager();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BrushCanvasPanel(
            coordinator: coordinator,
            canvasSize: canvasSize,
            availableFrameKeys: frameKeys,
            cacheInvalidationSink: BrushEditCacheInvalidationSink(),
            historyManager: history,
            brushToolState: ValueNotifier(
              BrushToolState.defaults.copyWith(
                tool: tool,
                fillShape: canvasShapeEncloses(shapeKind) ? shapeKind : null,
                drawShape: shapeKind,
                shapeOptions: shapeOptions,
                fillOpacity: 0.5,
              ),
            ),
            selectionCommands: CanvasSelectionCommands(),
            guides: guides,
            shapeFillDabsFor: (area, color) => buildRegionFillDabs(
              region: area,
              color: color,
              opacity: 0.5,
              options: const FloodFillOptions(expandPx: 0, antiAlias: false),
            ),
            // One screen pixel is one canvas pixel, so the drag numbers
            // below are canvas coordinates.
            viewport: seedFromRender(tester, CanvasViewport()),
          ),
        ),
      ),
    );
    await tester.pump();
    return (coordinator: coordinator, history: history);
  }

  Future<TestGesture> dragOnLayer(
    WidgetTester tester,
    Offset from,
    Offset to, {
    bool release = true,
  }) async {
    final origin = tester.getTopLeft(find.byKey(layerKey));
    final gesture = await tester.startGesture(origin + from);
    await tester.pump();
    await gesture.moveTo(origin + to);
    await tester.pump();
    if (release) {
      await gesture.up();
      await tester.pump();
    }
    return gesture;
  }

  int alphaAt(BrushFrameEditingCoordinator coordinator, int x, int y) =>
      (surfacePixelRgba(
            coordinator.currentSurfaceOf(coordinator.activeFrameKey),
            x,
            y,
          ) ??
          0) &
      0xFF;

  SelectionAntsPainter antsOn(WidgetTester tester) => tester
      .widgetList<CustomPaint>(find.byType(CustomPaint))
      .map((paint) => paint.painter)
      .whereType<SelectionAntsPainter>()
      .first;

  const plainLine = ShapeToolOptions(
    type: ShapeLineType.plain,
    size: 4,
    antiAlias: false,
  );
  const plainFill = ShapeToolOptions(
    part: ShapePart.fill,
    opacity: 0.5,
    antiAlias: false,
  );

  testWidgets('fixture premise: with no guide the plain line is drawn on '
      'one side', (tester) async {
    final env = await pumpPanel(
      tester,
      guides: null,
      tool: CanvasTool.shape,
      shapeOptions: plainLine,
    );
    await dragOnLayer(tester, const Offset(20, 20), const Offset(60, 60));

    expect(alphaAt(env.coordinator, 40, 20), 255, reason: 'its top');
    expect(alphaAt(env.coordinator, 160, 20), 0, reason: 'nothing mirrors');
  });

  testWidgets('under a mirror the plain line is drawn on both sides — a line '
      'still, nothing filled in — and it is ONE step back', (tester) async {
    final env = await pumpPanel(
      tester,
      guides: mirrorGuides(),
      tool: CanvasTool.shape,
      shapeOptions: plainLine,
    );
    final before = env.history.undoCount;
    await dragOnLayer(tester, const Offset(20, 20), const Offset(60, 60));

    expect(alphaAt(env.coordinator, 40, 20), 255, reason: 'its top');
    expect(alphaAt(env.coordinator, 160, 20), 255, reason: 'the mirror\'s');
    expect(alphaAt(env.coordinator, 140, 40), 255, reason: 'the mirror side');
    expect(alphaAt(env.coordinator, 160, 40), 0, reason: 'a line, unfilled');
    expect(alphaAt(env.coordinator, 100, 20), 0, reason: 'the gap between');
    expect(env.history.undoCount, before + 1);

    env.history.undo();
    await tester.pump();
    expect(alphaAt(env.coordinator, 40, 20), 0);
    expect(alphaAt(env.coordinator, 160, 20), 0, reason: 'they go together');
  });

  testWidgets('a LINE is copied too, and its ants show both copies while the '
      'drag runs', (tester) async {
    final env = await pumpPanel(
      tester,
      guides: mirrorGuides(),
      tool: CanvasTool.shape,
      shapeKind: CanvasShapeKind.line,
      shapeOptions: plainLine,
    );
    final gesture = await dragOnLayer(
      tester,
      const Offset(20, 30),
      const Offset(60, 30),
      release: false,
    );
    final trails = [
      for (final trail in antsOn(tester).openTrails)
        if (trail.isNotEmpty) trail,
    ];
    expect(trails, hasLength(2), reason: 'the preview is what will land');
    expect(trails.last.first.x, closeTo(180, 1));

    await gesture.up();
    await tester.pump();
    expect(alphaAt(env.coordinator, 40, 30), 255);
    expect(alphaAt(env.coordinator, 160, 30), 255);
  });

  testWidgets('the shape tool\'s FILL fills both sides, and where the copies '
      'overlap it is laid ONCE — no darker seam', (tester) async {
    final none = await pumpPanel(
      tester,
      guides: null,
      tool: CanvasTool.shape,
      shapeOptions: plainFill,
    );
    // Across the axis: x 80..120 is its own mirror.
    await dragOnLayer(tester, const Offset(80, 30), const Offset(120, 60));
    final once = alphaAt(none.coordinator, 100, 45);
    expect(once, inExclusiveRange(0, 255), reason: '⛔CONTROL: half strength');

    final env = await pumpPanel(
      tester,
      guides: mirrorGuides(),
      tool: CanvasTool.shape,
      shapeOptions: plainFill,
    );
    await dragOnLayer(tester, const Offset(80, 30), const Offset(120, 60));
    expect(alphaAt(env.coordinator, 100, 45), once);
    expect(alphaAt(env.coordinator, 90, 45), once);

    await dragOnLayer(tester, const Offset(20, 80), const Offset(40, 100));
    expect(alphaAt(env.coordinator, 30, 90), once, reason: 'the drag');
    expect(alphaAt(env.coordinator, 170, 90), once, reason: 'its mirror');
  });

  testWidgets('the fill tool\'s SHAPE FILL fills the mirrored outline too, '
      'as one step', (tester) async {
    final env = await pumpPanel(
      tester,
      guides: mirrorGuides(),
      tool: CanvasTool.fillShape,
    );
    final before = env.history.undoCount;
    await dragOnLayer(tester, const Offset(20, 20), const Offset(60, 60));

    expect(alphaAt(env.coordinator, 40, 40), isNonZero, reason: 'the drag');
    expect(alphaAt(env.coordinator, 160, 40), isNonZero, reason: 'the mirror');
    expect(alphaAt(env.coordinator, 100, 40), 0, reason: 'the gap between');
    expect(env.history.undoCount, before + 1);
  });

  testWidgets('a BRUSH-type shape is the stroke\'s, which copies itself — it '
      'is handed the drag alone, so it is ONE stroke on both sides', (
    tester,
  ) async {
    final env = await pumpPanel(
      tester,
      guides: mirrorGuides(),
      tool: CanvasTool.shape,
      shapeKind: CanvasShapeKind.line,
    );
    final before = env.history.undoCount;
    await dragOnLayer(tester, const Offset(20, 30), const Offset(60, 30));

    expect(alphaAt(env.coordinator, 40, 30), isNonZero, reason: 'the drag');
    expect(alphaAt(env.coordinator, 160, 30), isNonZero, reason: 'the mirror');
    expect(
      env.history.undoCount,
      before + 1,
      reason: 'handed every copy, it would draw a stroke for each',
    );
  });
}
