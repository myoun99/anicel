import 'package:flutter/material.dart';

import '../../models/brush_edit_session_state.dart';
import '../../models/canvas_viewport.dart';
import 'active_stroke_overlay.dart';
import 'bitmap_surface_painter.dart';
import '../effective_device_pixel_ratio.dart';

/// Displays the brush canvas: committed artwork from the session surface
/// plus the live in-progress stroke, rendered by one [BitmapSurfacePainter]
/// that applies the viewport zoom/pan inside the picture.
///
/// Rendering everything in a single picture at final resolution is what
/// keeps every zoom level pixel-stable: there is no per-layer texture that
/// the compositor could resample differently between idle and drawing
/// frames (the source of the fractional-zoom pixel jitter).
class BrushEditCanvasView extends StatelessWidget {
  const BrushEditCanvasView({
    super.key,
    required this.sessionState,
    this.viewport,
    this.showTransparentBackground = true,
    this.overlayModel,
    this.staleScope,
  });

  final BrushEditSessionState sessionState;

  /// Zoom/pan applied inside the painter; `null` renders at identity.
  final CanvasViewport? viewport;

  final bool showTransparentBackground;

  /// Live overlay state owned by the interactive view; pointer moves repaint
  /// the painter through this model without rebuilding widgets.
  final ActiveStrokeOverlayModel? overlayModel;

  /// Surface lineage identity for the stale tile fallback; see
  /// [BitmapSurfacePainter.staleScope].
  final Object? staleScope;



  @override
  Widget build(BuildContext context) {
    // No canvas-bounds outline here: the paper edge over the dark backdrop
    // IS the boundary, and the stroked rect showed up as a stray 1px line
    // that the blank-canvas placeholder (PlaybackFramePainter) never drew.
    return RepaintBoundary(
      key: const ValueKey<String>('brush-edit-canvas-view-boundary'),
      child: CustomPaint(
        key: const ValueKey<String>('brush-edit-canvas-custom-paint'),
        // Keep the Skia raster cache from baking this picture while
        // idle: the cached layer's origin snaps to integer device
        // pixels while direct rendering uses the fractional layout
        // offset, so the cached<->live transition shifted the artwork
        // by a subpixel at fractional zoom (and a focus switch purges
        // the cache, which is why the shift appeared after switching
        // apps).
        willChange: true,
        painter: BitmapSurfacePainter(
          surface: sessionState.canvasState.currentSurface,
          viewport: viewport,
          overlayModel: overlayModel,
          showTransparentBackground: showTransparentBackground,
          staleScope: staleScope,
          // The pan-phase snap's device grid — MediaQuery, the same source
          // the merged stack painter reads, so this route and the merged
          // route snap to the same phase.
          devicePixelRatio: EffectiveDevicePixelRatio.of(context),
        ),
        child: const SizedBox.expand(),
      ),
    );
  }
}
