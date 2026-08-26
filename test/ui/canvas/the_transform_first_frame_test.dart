import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/brush_dab.dart';
import 'package:anicel/src/models/brush_tip_shape.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/services/brush_frame_editing_coordinator.dart';
import 'package:anicel/src/ui/brush/brush_canvas_panel.dart';
import 'package:anicel/src/ui/brush/brush_edit_cache_invalidation_sink.dart';
import 'package:anicel/src/ui/brush/brush_tool_state.dart';
import 'package:anicel/src/ui/brush/canvas_selection_commands.dart';
import 'package:anicel/src/ui/canvas/active_stroke_overlay.dart';
import 'package:anicel/src/ui/canvas/canvas_layer_stack_view.dart';
import 'package:anicel/src/ui/playback/layer_frame_image_cache.dart';

import '../../helpers/brush_canvas_fixture.dart';

/// F-38a — 유저 2026-08-27: 「선택 후 변형시 변형 시작할때 **1프레임, 기존
/// 그림의 일부? 만 보였다가 사라짐**. 비슷한게 옛날에도 있었어서 확정시에도
/// 보일거같은데 그러진 않고 정상적으로 안보임」.
///
/// 🚨THE COMPOSITE, not the panel's own painter. The float draws in the
/// ACTIVE LAYER'S SLOT of the composite tree (TS1: the rows above it have to
/// occlude it the way they occlude landed pixels), so a rig that paints only
/// `BitmapSurfacePainter` sees nothing at all after a lift — measured, and it
/// is why the first attempt at this test could not judge anything.
void main() {
  const size = Size(120, 120);

  BrushDab dab(double x, double y) => BrushDab(
    center: CanvasPoint(x: x, y: y),
    color: 0xFFFF0000,
    size: 12,
    opacity: 1,
    flow: 1,
    hardness: 1,
    tipShape: BrushTipShape.round,
    pressure: 1,
    sequence: 0,
  );

  /// The panel wired the way the editor wires it: merged mode, and an
  /// underlay that really builds the composite the float lives in.
  Future<({BrushFrameEditingCoordinator coordinator,
      CanvasSelectionCommands commands})> pumpComposite(
    WidgetTester tester,
  ) async {
    final frameKeys = BrushCanvasFixture.createFrameKeys();
    final coordinator = BrushCanvasFixture.createCoordinator(
      frameKeys: frameKeys,
    );
    coordinator.commitSourceStroke(
      sourceDabs: [dab(30, 30), dab(45, 45), dab(60, 60)],
    );
    final overlay = ActiveStrokeOverlayModel();
    addTearDown(overlay.dispose);
    final commands = CanvasSelectionCommands();
    addTearDown(commands.dispose);
    final imageCache = LayerFrameImageCache(
      frameStore: coordinator.frameStore,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: size.width,
            height: size.height,
            child: BrushCanvasPanel(
              coordinator: coordinator,
              availableFrameKeys: frameKeys,
              cacheInvalidationSink: BrushEditCacheInvalidationSink(),
              brushToolState: BrushToolState.defaults.copyWith(
                tool: CanvasTool.move,
              ),
              selectionCommands: commands,
              activeStrokeOverlayModel: overlay,
              viewportUnderlayBuilder:
                  (context, viewport, activeSurfacePainter, floatOverlay) =>
                      CanvasLayerStackView(
                        nodes: const [CanvasActiveLayerNode(opacity: 1)],
                        activeSurfacePainter: activeSurfacePainter,
                        floatOverlay: floatOverlay,
                        imageCache: imageCache,
                        canvasSize: BrushCanvasFixture.canvasSize,
                        viewport: viewport,
                      ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return (coordinator: coordinator, commands: commands);
  }

  /// How many pixels of the DRAWING the composite is showing.
  Future<int> drawnPixels(WidgetTester tester) async {
    final painters = tester
        .widgetList<CustomPaint>(
          find.descendant(
            of: find.byType(CanvasLayerStackView),
            matching: find.byType(CustomPaint),
          ),
        )
        .where((paint) => paint.painter != null)
        .toList();
    expect(
      painters,
      isNotEmpty,
      reason: '🚨the composite has to be mounted, or every count below is '
          'zero for a reason that has nothing to do with the transform',
    );
    final recorder = ui.PictureRecorder();
    painters.first.painter!.paint(Canvas(recorder), size);
    final picture = recorder.endRecording();
    final bytes = await tester.runAsync(() async {
      final image = await picture.toImage(
        size.width.toInt(),
        size.height.toInt(),
      );
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      image.dispose();
      return data!.buffer.asUint8List();
    });
    picture.dispose();
    var drawn = 0;
    for (var i = 0; i + 3 < bytes!.length; i += 4) {
      if (bytes[i] > 0xC8 && bytes[i + 1] < 0x40 && bytes[i + 2] < 0x40) {
        drawn += 1;
      }
    }
    return drawn;
  }

  testWidgets('opening a transform never shows a frame with only PART of the '
      'drawing on it', (tester) async {
    final env = await pumpComposite(tester);
    final before = await drawnPixels(tester);
    expect(
      before,
      greaterThan(0),
      reason: '🚨the fixture has to be showing the drawing before the '
          'transform, or "part of it" cannot be told from "none of it"',
    );

    env.commands.beginTransform();

    // EVERY frame of the opening, not just the settled one — the report is
    // about a single frame, and pumping to settle is exactly how a
    // one-frame artifact hides.
    final seen = <int>[];
    for (var i = 0; i < 6; i += 1) {
      await tester.pump(const Duration(milliseconds: 16));
      seen.add(await drawnPixels(tester));
    }

    expect(
      env.commands.transformActive,
      isTrue,
      reason: '🚨and the transform really opened — otherwise every count '
          'below is just the untouched drawing and proves nothing',
    );
    for (final count in seen) {
      expect(
        count,
        anyOf(0, before),
        reason: '유저: 「변형 시작할때 1프레임, 기존 그림의 일부? 만 보였다가 '
            '사라짐」 — a frame may show the whole drawing or none of it, '
            'never a piece. Saw: $seen (whole = $before)',
      );
    }
  });
}
