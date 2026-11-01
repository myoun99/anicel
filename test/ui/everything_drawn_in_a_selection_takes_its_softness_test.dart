import 'dart:typed_data';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/brush_dab.dart';
import 'package:anicel/src/models/brush_stamp_image.dart';
import 'package:anicel/src/models/brush_tip_shape.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_shape_kind.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/models/shape_tool_options.dart';
import 'package:anicel/src/services/brush_frame_editing_coordinator.dart';
import 'package:anicel/src/services/canvas_color_sampler.dart';
import 'package:anicel/src/services/canvas_flood_fill.dart';
import 'package:anicel/src/services/canvas_selection.dart';
import 'package:anicel/src/services/canvas_selection_region.dart';
import 'package:anicel/src/services/selection_clip.dart';
import 'package:anicel/src/ui/brush/brush_canvas_panel.dart';
import 'package:anicel/src/ui/brush/brush_edit_cache_invalidation_sink.dart';
import 'package:anicel/src/ui/brush/brush_tool_state.dart';
import 'package:anicel/src/ui/brush/canvas_selection_commands.dart';

import '../helpers/brush_canvas_fixture.dart';
import '../helpers/device_viewport.dart';

/// 🚨★★★brush-fidelity-Q11 · Q12 (유저 2026-10-18), through the real panel:
/// 브러시 · 지우개 · 채우기 · 도형 — the tool settings' 확장 · 페더 · AA reach
/// each of them, and at the moment it starts: the softness is set here after
/// the panel built, with nothing rebuilding it.
void main() {
  const viewKey = ValueKey<String>('brush-canvas-view');
  const layerKey = ValueKey<String>('canvas-selection-layer');
  const canvasSize = CanvasSize(width: 200, height: 120);
  final selected = CanvasSelectionRegion.shape(
    CanvasSelectionShape.rect(left: 40, top: 20, right: 160, bottom: 100),
  );

  BrushDab wholeCanvasDab(int color) {
    final rgba = Uint8List(200 * 120 * 4);
    for (var alpha = 3; alpha < rgba.length; alpha += 4) {
      rgba[alpha] = 255;
    }
    return BrushDab(
      center: CanvasPoint(x: 100, y: 60),
      color: color,
      size: 200,
      opacity: 1,
      flow: 1,
      hardness: 1,
      tipShape: BrushTipShape.square,
      pressure: 1,
      sequence: 0,
      stamp: BrushStampImage(id: 'whole', width: 200, height: 120, rgba: rgba),
    );
  }

  Future<BrushFrameEditingCoordinator> pumpPanel(
    WidgetTester tester,
    CanvasTool tool, {
    required ValueNotifier<SelectionMaskOptions> softness,
    CanvasSelectionRegion? selection,
    BrushToolState Function(BrushToolState)? brush,
  }) async {
    final frameKeys = BrushCanvasFixture.createFrameKeys();
    final coordinator = BrushCanvasFixture.createCoordinator(
      frameKeys: frameKeys,
      canvasSize: canvasSize,
    );
    final state = BrushToolState.defaults.copyWith(
      tool: tool,
      fillShape: CanvasShapeKind.rect,
      fillOpacity: 1,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BrushCanvasPanel(
            coordinator: coordinator,
            canvasSize: canvasSize,
            availableFrameKeys: frameKeys,
            cacheInvalidationSink: BrushEditCacheInvalidationSink(),
            brushToolState: ValueNotifier(brush?.call(state) ?? state),
            selectionCommands: CanvasSelectionCommands()
              ..setRegion(selection ?? selected),
            selectionMaskOptions: softness,
            fillDabsAt: (_, color, _) => [wholeCanvasDab(color)],
            shapeFillDabsFor: (area, color) => buildRegionFillDabs(
              region: area,
              color: color,
              opacity: 1,
              options: const FloodFillOptions(expandPx: 0, antiAlias: false),
            ),
            viewport: seedFromRender(tester, CanvasViewport()),
          ),
        ),
      ),
    );
    await tester.pump();
    return coordinator;
  }

  int alphaAt(BrushFrameEditingCoordinator coordinator, int x, int y) =>
      (surfacePixelRgba(
            coordinator.currentSurfaceOf(coordinator.activeFrameKey),
            x,
            y,
          ) ??
          0) &
      0xFF;

  Future<void> drag(
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
    await tester.pump();
  }

  /// The row at y = 60 as [options] cut it.
  List<int> edgeOf(
    BrushFrameEditingCoordinator coordinator,
    SelectionMaskOptions options,
  ) => SelectionClip.of(
    selected,
    wall: coordinator.sessionStore.pasteboard,
    options: options,
  ).maskFor(left: 0, top: 60, width: 200, height: 1);

  List<int> rowAt(BrushFrameEditingCoordinator coordinator) => [
    for (var x = 0; x < 200; x += 1) alphaAt(coordinator, x, 60),
  ];

  const feather = SelectionMaskOptions(featherPx: 8);

  testWidgets('a brush stroke over the edge lands the ramp', (tester) async {
    final softness = ValueNotifier(SelectionMaskOptions.none);
    final coordinator = await pumpPanel(
      tester,
      CanvasTool.brush,
      softness: softness,
    );
    softness.value = feather;
    await drag(
      tester,
      find.byKey(viewKey),
      const Offset(10, 60),
      const Offset(100, 60),
    );
    expect(alphaAt(coordinator, 39, 60), 0, reason: 'past the outline');
    expect(alphaAt(coordinator, 40, 60), greaterThan(0));
    expect(
      alphaAt(coordinator, 40, 60),
      lessThan(alphaAt(coordinator, 42, 60)),
      reason: 'a ramp, not a step',
    );
    expect(
      alphaAt(coordinator, 42, 60),
      lessThan(alphaAt(coordinator, 80, 60)),
      reason: 'deep inside it takes the stroke whole',
    );
  });

  testWidgets('the eraser leaves the ramp where it took the picture', (
    tester,
  ) async {
    final softness = ValueNotifier(SelectionMaskOptions.none);
    final coordinator = await pumpPanel(
      tester,
      CanvasTool.eraser,
      softness: softness,
    );
    coordinator.commitSourceStroke(sourceDabs: [wholeCanvasDab(0xFF000000)]);
    await tester.pump();
    softness.value = feather;
    await drag(
      tester,
      find.byKey(viewKey),
      const Offset(10, 60),
      const Offset(100, 60),
    );
    expect(alphaAt(coordinator, 39, 60), 255, reason: 'past the outline');
    expect(alphaAt(coordinator, 40, 60), lessThan(255));
    expect(
      alphaAt(coordinator, 40, 60),
      greaterThan(alphaAt(coordinator, 42, 60)),
      reason: 'a ramp, not a step',
    );
  });

  testWidgets('a fill lands the selection\'s own edge', (tester) async {
    final softness = ValueNotifier(SelectionMaskOptions.none);
    final coordinator = await pumpPanel(
      tester,
      CanvasTool.fill,
      softness: softness,
    );
    softness.value = feather;
    final origin = tester.getTopLeft(find.byKey(viewKey));
    await tester.tapAt(
      origin + const Offset(100, 60),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    await tester.pump();
    expect(rowAt(coordinator), edgeOf(coordinator, feather));
  });

  testWidgets('a shape lands the selection\'s own edge', (tester) async {
    final softness = ValueNotifier(SelectionMaskOptions.none);
    final coordinator = await pumpPanel(
      tester,
      CanvasTool.fillShape,
      softness: softness,
    );
    softness.value = feather;
    await drag(
      tester,
      find.byKey(layerKey),
      const Offset(10, 10),
      const Offset(190, 110),
    );
    expect(rowAt(coordinator), edgeOf(coordinator, feather));
  });

  testWidgets('the shape tool\'s area lands the selection\'s own edge', (
    tester,
  ) async {
    final softness = ValueNotifier(SelectionMaskOptions.none);
    final coordinator = await pumpPanel(
      tester,
      CanvasTool.shape,
      softness: softness,
      brush: (state) => state.copyWith(
        drawShape: CanvasShapeKind.rect,
        shapeOptions: const ShapeToolOptions(
          part: ShapePart.fill,
          opacity: 1,
          antiAlias: false,
        ),
      ),
    );
    softness.value = feather;
    await drag(
      tester,
      find.byKey(layerKey),
      const Offset(10, 10),
      const Offset(190, 110),
    );
    expect(rowAt(coordinator), edgeOf(coordinator, feather));
  });

  testWidgets('with no softness asked for, the outline is the edge', (
    tester,
  ) async {
    final softness = ValueNotifier(SelectionMaskOptions.none);
    final coordinator = await pumpPanel(
      tester,
      CanvasTool.fillShape,
      softness: softness,
    );
    await drag(
      tester,
      find.byKey(layerKey),
      const Offset(10, 10),
      const Offset(190, 110),
    );
    expect(rowAt(coordinator), edgeOf(coordinator, SelectionMaskOptions.none));
    expect(alphaAt(coordinator, 40, 60), 255);
  });
}
