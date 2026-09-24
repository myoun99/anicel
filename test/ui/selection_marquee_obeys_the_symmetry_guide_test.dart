import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/models/drawing_guide.dart';
import 'package:anicel/src/ui/brush/brush_canvas_panel.dart';
import 'package:anicel/src/ui/brush/brush_edit_cache_invalidation_sink.dart';
import 'package:anicel/src/ui/brush/brush_tool_state.dart';
import 'package:anicel/src/ui/brush/canvas_selection_commands.dart';
import 'package:anicel/src/ui/canvas/selection_ants_painter.dart';

import '../helpers/brush_canvas_fixture.dart';
import '../helpers/device_viewport.dart';

/// **A marquee drag under a symmetry guide selects every copy.**
///
/// The guide replicates strokes; the two things it did not replicate were
/// the fill and the selection. This is the selection half, driven through
/// the real panel so the wiring is part of what is pinned — the model law
/// itself lives in `selection_copies_fold_as_one_step_test`.
///
/// 🚨The PREVIEW is pinned alongside the commit. A drag that traces one
/// rectangle and then commits two is a promise broken at pointer-up, and
/// the ants painter is where that promise is made, so the assertion reads
/// the mounted painter rather than the model.
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

  Future<CanvasSelectionCommands> pumpPanel(
    WidgetTester tester, {
    required CutGuides? guides,
  }) async {
    final frameKeys = BrushCanvasFixture.createFrameKeys();
    final coordinator = BrushCanvasFixture.createCoordinator(
      frameKeys: frameKeys,
      canvasSize: canvasSize,
    );
    final commands = CanvasSelectionCommands();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BrushCanvasPanel(
            coordinator: coordinator,
            canvasSize: canvasSize,
            availableFrameKeys: frameKeys,
            cacheInvalidationSink: BrushEditCacheInvalidationSink(),
            brushToolState: ValueNotifier(BrushToolState.defaults.copyWith(
              tool: CanvasTool.select,
            )),
            selectionCommands: commands,
            guides: guides,
            // One screen pixel is one canvas pixel, so the drag numbers
            // below are canvas coordinates.
            viewport: seedFromRender(tester, CanvasViewport()),
          ),
        ),
      ),
    );
    await tester.pump();
    return commands;
  }

  Future<void> dragOnLayer(
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
  }

  SelectionAntsPainter antsOn(WidgetTester tester) => tester
      .widgetList<CustomPaint>(find.byType(CustomPaint))
      .map((paint) => paint.painter)
      .whereType<SelectionAntsPainter>()
      .first;

  testWidgets('fixture premise: with no guide the drag selects one box', (
    tester,
  ) async {
    final commands = await pumpPanel(tester, guides: null);
    await dragOnLayer(tester, const Offset(20, 20), const Offset(60, 60));

    final region = commands.region!;
    expect(region.containsPoint(CanvasPoint(x: 40, y: 40)), isTrue);
    expect(
      region.containsPoint(CanvasPoint(x: 160, y: 40)),
      isFalse,
      reason: 'nothing is mirroring it',
    );
  });

  testWidgets('under a mirror the same drag selects the mirrored box too', (
    tester,
  ) async {
    final commands = await pumpPanel(tester, guides: mirrorGuides());
    await dragOnLayer(tester, const Offset(20, 20), const Offset(60, 60));

    final region = commands.region!;
    expect(region.containsPoint(CanvasPoint(x: 40, y: 40)), isTrue);
    expect(
      region.containsPoint(CanvasPoint(x: 160, y: 40)),
      isTrue,
      reason: 'x 20..60 mirrors to 140..180 about x = 100',
    );
    expect(
      region.containsPoint(CanvasPoint(x: 100, y: 40)),
      isFalse,
      reason: 'the gap between the copies is not selected',
    );
  });

  testWidgets('it is ONE undo step, not one per copy', (tester) async {
    final commands = await pumpPanel(tester, guides: mirrorGuides());
    await dragOnLayer(tester, const Offset(20, 20), const Offset(60, 60));

    expect(commands.region!.steps, hasLength(1));
    expect(commands.region!.steps.first.shapes, hasLength(2));
  });

  testWidgets('and the ants show both copies WHILE the drag runs', (
    tester,
  ) async {
    await pumpPanel(tester, guides: mirrorGuides());
    await dragOnLayer(
      tester,
      const Offset(20, 20),
      const Offset(60, 60),
      release: false,
    );

    final shapes = antsOn(tester).marqueeShapes;
    expect(
      shapes,
      hasLength(2),
      reason: 'the preview traces what pointer-up will commit',
    );
    final xs = [for (final shape in shapes) shape.points.first.x];
    expect(xs.any((x) => x < 100), isTrue);
    expect(xs.any((x) => x > 100), isTrue);
  });
}
