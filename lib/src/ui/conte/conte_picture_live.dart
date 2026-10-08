import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';

import '../../models/bitmap_surface.dart';
import '../../models/canvas_viewport.dart';
import '../../models/pasteboard_bounds.dart' show PasteboardBounds;
import '../../models/sheet_marks.dart';
import '../../services/cel_surface_as_shown.dart';
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
/// layers cropped at the canvas — and the camera's work written over it
/// again, since it covers what the page wrote.
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
              painter: _CameraWork(
                marks: [
                  for (final picture in pictures) ...picture.cameraWork,
                ],
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

  /// [picture] composited into a raster of its print's size
  /// ([pictureRasterOf]) and laid where its print is laid ([pictureLaid]),
  /// filtered as its print is ([sheetPictureQuality]) — the brush switch
  /// changes nothing on screen (🗣️F-215-Q1, 유저 2026-10-08: 「둘 다 카메라
  /// 해상도로」; F-215: 「on하든off하든 바뀌는게 없어야」).
  ///
  /// ↩️It drew the canvas's pixels straight onto the screen: magnified past
  /// the camera it showed more than the film has, and sharper than the
  /// print beside it (10-02: 「끄면 부드럽고 켜면 선명」).
  Widget _live(ContePicture picture) {
    final raster = pictureRasterOf(
      SheetDeviceGrid.through(
        viewport,
        effectiveRatio,
      ).printedPicture(picture.mark),
      effectiveRatio,
      picture.original,
    );
    final box = Size(
      raster.width / effectiveRatio,
      raster.height / effectiveRatio,
    );
    final frame = picture.mark.frame;
    // The canvas → the raster: through the paper, the picture's frame
    // filling the raster's width as the print's camera fills its own.
    final rasterPerPaper = box.width / frame.width;
    final canvasToBox =
        Matrix4.diagonal3Values(rasterPerPaper, rasterPerPaper, 1)
          ..multiply(Matrix4.translationValues(-frame.left, -frame.top, 0))
          ..multiply(picture.window.canvasToPaper);
    final laid = pictureLaid(picture.mark, viewport);
    return ClipPath(
      clipper: _shotOf(picture),
      child: Stack(
        children: [
          Positioned(
            left: 0,
            top: 0,
            width: box.width,
            height: box.height,
            child: Transform(
              transform: Matrix4.translationValues(laid.left, laid.top, 0)
                ..multiply(
                  Matrix4.diagonal3Values(
                    laid.width / box.width,
                    laid.height / box.height,
                    1,
                  ),
                ),
              filterQuality: sheetPictureQuality(
                raster.width,
                laid,
                effectiveRatio,
              ),
              child: _composite(picture, canvasToBox),
            ),
          ),
        ],
      ),
    );
  }

  /// What [picture]'s raster holds: the frame's ground, and its canvas
  /// composited through [canvasToBox] — the canvas into the raster — cut
  /// to the canvas's outline.
  Widget _composite(ContePicture picture, Matrix4 canvasToBox) {
    final window = picture.window;
    final drawn = session.editingCanvas.stackAt(
      cut: picture.cut,
      frameIndex: picture.frame,
      drawingLayerId: picture.layer.id,
    );
    final canvas = picture.cut.canvasSize;
    final corners = canvas.canvasRect;
    return Stack(
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
                MatrixUtils.transformPoint(canvasToBox, corner),
            ]),
            child: CanvasLayerStackView(
              key: ValueKey<String>('conte-picture-live-${window.id}'),
              nodes: drawn.nodes,
              imageCache: session.renderCaches.layerFrameImageCache,
              canvasSize: canvas,
              viewport: viewportOfSimilarity(canvasToBox)!,
              activeSurfacePainter: BitmapSurfacePainter(
                surface: celSurfaceAsShown(
                  surfaceOf(picture),
                  drawn.activeSourceEffects,
                ),
                overlayModel: window.overlay,
                showTransparentBackground: false,
                lineage: (window.key.layerId, window.key.frameId),
              ),
              onBufferBytes: (bytes) => _count(window.id, bytes),
              // The page prints this picture under it: taking over from the
              // print, the live one shows no less on its first frame.
              alreadyShown: true,
            ),
          ),
        ),
      ],
    );
  }

  /// Where [picture] shows on the screen: the camera's frame in its slot,
  /// cut INSIDE on the page's grid ([SheetDeviceGrid.livePicture], F-197),
  /// the one call the paper's ink around it stops at too (F-216).
  _Outline _shotOf(ContePicture picture) {
    final shot = SheetDeviceGrid.through(
      viewport,
      effectiveRatio,
    ).livePicture(picture.mark);
    return _Outline([
      shot.topLeft,
      shot.topRight,
      shot.bottomRight,
      shot.bottomLeft,
    ]);
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

/// An outline on screen: a picture's shot, or the canvas in it — turned
/// when the camera is.
///
/// ⛔Never a rect clipper, even for the square shot: a
/// `CustomClipper<Rect>` is the ink window's clip, and there is one
/// (`one_sheet_ink_layer_test`).
class _Outline extends CustomClipper<Path> {
  const _Outline(this.corners);

  final List<Offset> corners;

  @override
  Path getClip(Size size) => Path()..addPolygon(corners, true);

  @override
  bool shouldReclip(_Outline oldClipper) =>
      !listEquals(oldClipper.corners, corners);
}

/// The camera's work over the live pictures — its frames, the trails of
/// their corners and its keys' names — printed as the page prints it.
class _CameraWork extends CustomPainter {
  const _CameraWork({
    required this.marks,
    required this.viewport,
    required this.effectiveRatio,
    required this.paper,
  });

  final List<SheetMark> marks;
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
        ), marks);
  }

  @override
  bool shouldRepaint(_CameraWork oldDelegate) =>
      !listEquals(oldDelegate.marks, marks) ||
      oldDelegate.viewport != viewport ||
      oldDelegate.effectiveRatio != effectiveRatio ||
      oldDelegate.paper != paper;
}
