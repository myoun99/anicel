import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/brush_bitmap_materialization_history_state.dart';
import 'package:anicel/src/models/brush_edit_session_state.dart';
import 'package:anicel/src/models/brush_dab.dart';
import 'package:anicel/src/models/brush_tip_shape.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/canvas_surface_state.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/ui/canvas/active_stroke_overlay.dart';
import 'package:anicel/src/ui/canvas/bitmap_surface_painter.dart';
import 'package:anicel/src/ui/canvas/brush_edit_canvas_view.dart';

void main() {
  group('BrushEditCanvasView', () {
    testWidgets('renders one composite painter in a keyed RepaintBoundary', (
      tester,
    ) async {
      final sessionState = _sessionState(
        BitmapSurface(canvasSize: CanvasSize(width: 12, height: 8)),
      );

      await tester.pumpWidget(
        _app(BrushEditCanvasView(sessionState: sessionState)),
      );

      expect(
        find.byKey(const ValueKey<String>('brush-edit-canvas-view-boundary')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('brush-edit-canvas-custom-paint')),
        findsOneWidget,
      );
      // The canvas-bounds outline was removed: the paper edge is the
      // boundary, and the stroked rect read as a stray 1px line.
      expect(
        find.byKey(const ValueKey<String>('brush-edit-canvas-bounds')),
        findsNothing,
      );

      final canvasViewFinder = find.byType(BrushEditCanvasView);
      expect(
        find.descendant(of: canvasViewFinder, matching: find.byType(Listener)),
        findsNothing,
      );
      expect(
        find.descendant(
          of: canvasViewFinder,
          matching: find.byType(GestureDetector),
        ),
        findsNothing,
      );
      // The viewport transform lives inside the painter, not the widget tree:
      // a Transform widget would make the compositor resample layer textures
      // at fractional zoom, jittering pixels while drawing.
      expect(
        find.descendant(of: canvasViewFinder, matching: find.byType(Transform)),
        findsNothing,
      );
    });

    testWidgets(
      'passes surface, viewport, overlay, and background to painter',
      (tester) async {
        final surface = BitmapSurface(
          canvasSize: CanvasSize(width: 7, height: 5),
        );
        final sessionState = _sessionState(surface);
        final viewport = CanvasViewport(zoom: 1.25, panX: 3, panY: 4);
        final overlayModel = ActiveStrokeOverlayModel()..dabs.add(_dab());
        addTearDown(overlayModel.dispose);

        await tester.pumpWidget(
          _app(
            BrushEditCanvasView(
              sessionState: sessionState,
              viewport: viewport,
              overlayModel: overlayModel,
              showTransparentBackground: false,
              staleScope: 'scope-a',
            ),
          ),
        );

        final customPaint = tester.widget<CustomPaint>(
          find.byKey(const ValueKey<String>('brush-edit-canvas-custom-paint')),
        );
        final painter = customPaint.painter! as BitmapSurfacePainter;

        // ⛔R11 retired the hint. The Skia raster cache bakes this picture
        // again, and that is now safe: the cached layer's integer-snapped
        // origin is where layout puts it anyway. Read the history at the
        // top of `bypass_raster_cache_wiring_test.dart` before restoring.
        expect(customPaint.willChange, isFalse);
        expect(identical(painter.surface, surface), isTrue);
        expect(painter.viewport, viewport);
        expect(identical(painter.overlayModel, overlayModel), isTrue);
        expect(painter.showTransparentBackground, isFalse);
        expect(painter.staleScope, 'scope-a');
        expect(painter.overlayModel!.dabs, hasLength(1));
      },
    );
  });
}

BrushDab _dab() => BrushDab(
  center: CanvasPoint(x: 4, y: 1),
  color: 0xFF000000,
  size: 1,
  opacity: 1,
  flow: 1,
  hardness: 1,
  tipShape: BrushTipShape.round,
  pressure: 1,
  sequence: 0,
);

BrushEditSessionState _sessionState(BitmapSurface surface) {
  return BrushEditSessionState(
    canvasState: CanvasSurfaceState(currentSurface: surface),
    materializationHistoryState: BrushBitmapMaterializationHistoryState(),
  );
}

Widget _app(Widget child) {
  return MaterialApp(
    home: Scaffold(
      body: Align(alignment: Alignment.topLeft, child: child),
    ),
  );
}
