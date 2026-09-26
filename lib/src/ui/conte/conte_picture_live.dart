import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';

import '../../models/bitmap_surface.dart';
import '../../models/canvas_viewport.dart';
import '../../models/pasteboard_bounds.dart' show PasteboardBounds;
import '../../models/sheet_marks.dart';
import '../../services/cel_source_effect_pass.dart'
    show celSurfaceWithSourceEffects;
import '../../services/viewport_transform_matrix.dart';
import '../canvas/bitmap_surface_painter.dart';
import '../canvas/canvas_layer_stack_view.dart';
import '../editor_session_manager.dart';
import '../export/export_frame_renderer.dart' show exportFrameGround;
import '../sheet_painting.dart';
import 'conte_fonts.dart';
import 'conte_picture_ink.dart';

/// The pictures the brush draws into, painted LIVE while the conte's brush
/// is on (유저 답 conte-picture-display-Q1 「실시간 합성 (정확)」): the cut at
/// the picture's frame through the camera, composited by the editing
/// canvas's own painter with the block's conte layer standing in the tree
/// as the live row — so a stroke shows where, and how, the composite will
/// have it, and the pen-up changes nothing.
///
/// Laid over the printed picture as the picture is printed: the camera's
/// frame on the ground the picture renders on ([exportFrameGround]), the
/// layers cropped at the canvas, inside the slot's rounded corners — and
/// the camera's labels printed over it again, since it covers the ones the
/// page printed.
class ContePictureLive extends StatelessWidget {
  const ContePictureLive({
    super.key,
    required this.pictures,
    required this.session,
    required this.surfaceOf,
    required this.viewport,
    required this.effectiveRatio,
    required this.paper,
  });

  final List<ContePicture> pictures;
  final EditorSessionManager session;

  /// The cel each picture draws — its window's own session, so the live
  /// row is the surface the pen is drawing on.
  final BitmapSurface Function(ContePicture picture) surfaceOf;

  /// The page's own transform — paper to screen.
  final CanvasViewport viewport;
  final double effectiveRatio;

  /// The page's size in paper units.
  final Size paper;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Stack(
        children: [
          for (final picture in pictures)
            Positioned.fill(child: _live(picture)),
          Positioned.fill(
            child: CustomPaint(
              painter: _CameraLabels(
                labels: [for (final picture in pictures) ...picture.labels],
                viewport: viewport,
                effectiveRatio: effectiveRatio,
                paper: paper,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _live(ContePicture picture) {
    final window = picture.window;
    final paperToScreen = viewportTransformMatrix(viewport);
    final canvasToScreen = paperToScreen.multiplied(window.canvasToPaper);
    final drawn = session.editingCanvas.stackAt(
      cut: picture.cut,
      frameIndex: picture.frame,
      drawingLayerId: picture.layer.id,
    );
    final canvas = picture.cut.canvasSize;
    final corners = canvas.canvasRect;
    return ClipPath(
      clipper: _Shot(
        slot: window.screenRect(viewport),
        radius: picture.mark.cornerRadius * viewport.zoom,
        shown: MatrixUtils.transformRect(paperToScreen, picture.shown),
      ),
      child: Stack(
        children: [
          const Positioned.fill(child: ColoredBox(color: exportFrameGround)),
          Positioned.fill(
            child: ClipPath(
              clipper: _Outline([
                for (final corner in [
                  corners.topLeft,
                  corners.topRight,
                  corners.bottomRight,
                  corners.bottomLeft,
                ])
                  MatrixUtils.transformPoint(canvasToScreen, corner),
              ]),
              child: CanvasLayerStackView(
                key: ValueKey<String>('conte-picture-live-${window.id}'),
                nodes: drawn.nodes,
                imageCache: session.renderCaches.layerFrameImageCache,
                canvasSize: canvas,
                viewport: viewportOfSimilarity(canvasToScreen)!,
                activeSurfacePainter: BitmapSurfacePainter(
                  surface: celSurfaceWithSourceEffects(
                    surfaceOf(picture),
                    drawn.activeSourceEffects,
                  ),
                  overlayModel: window.overlay,
                  showTransparentBackground: false,
                  lineage: (window.key.layerId, window.key.frameId),
                ),
                onBufferBytes: (bytes) => _count(window.id, bytes),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Picture [id]'s display buffer, on the census — pushed: the census
  /// cannot reach a widget State; the session can.
  void _count(String id, int bytes) {
    final buffers = session.renderCaches.livePictureBufferBytes;
    if (bytes == 0) {
      buffers.remove(id);
    } else {
      buffers[id] = bytes;
    }
  }
}

/// A picture's shot on screen: the camera's frame where the slot shows
/// it, inside the slot's rounded corners.
class _Shot extends CustomClipper<Path> {
  const _Shot({required this.slot, required this.radius, required this.shown});

  final Rect slot;
  final double radius;
  final Rect shown;

  @override
  Path getClip(Size size) => Path.combine(
    PathOperation.intersect,
    Path()
      ..addRSuperellipse(
        ui.RSuperellipse.fromRectAndRadius(slot, Radius.circular(radius)),
      ),
    Path()..addRect(shown),
  );

  @override
  bool shouldReclip(_Shot oldClipper) =>
      oldClipper.slot != slot ||
      oldClipper.radius != radius ||
      oldClipper.shown != shown;
}

/// The canvas on screen — turned when the camera is.
class _Outline extends CustomClipper<Path> {
  const _Outline(this.corners);

  final List<Offset> corners;

  @override
  Path getClip(Size size) => Path()..addPolygon(corners, true);

  @override
  bool shouldReclip(_Outline oldClipper) =>
      !listEquals(oldClipper.corners, corners);
}

/// The camera's labels over the live pictures, printed as the page prints
/// them.
class _CameraLabels extends CustomPainter {
  const _CameraLabels({
    required this.labels,
    required this.viewport,
    required this.effectiveRatio,
    required this.paper,
  });

  final List<SheetMark> labels;
  final CanvasViewport viewport;
  final double effectiveRatio;
  final Size paper;

  @override
  void paint(Canvas canvas, Size size) {
    const SheetCanvasPrinter(style: conteTextStyle, images: SheetMarkImages())
        .paint(canvas, size, (
          viewport: viewport,
          devicePixelRatio: effectiveRatio,
          paper: paper,
        ), labels);
  }

  @override
  bool shouldRepaint(_CameraLabels oldDelegate) =>
      !listEquals(oldDelegate.labels, labels) ||
      oldDelegate.viewport != viewport ||
      oldDelegate.effectiveRatio != effectiveRatio ||
      oldDelegate.paper != paper;
}
