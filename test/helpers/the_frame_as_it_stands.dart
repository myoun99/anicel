import 'package:flutter/widgets.dart';
import 'package:anicel/src/models/brush_frame_key.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/models/composite_tree.dart';
import 'package:anicel/src/models/pasteboard_bounds.dart';
import 'package:anicel/src/models/project_background.dart';
import 'package:anicel/src/ui/canvas/bitmap_surface_painter.dart';
import 'package:anicel/src/ui/canvas/canvas_layer_stack_view.dart';
import 'package:anicel/src/ui/canvas/selection_float_overlay.dart';
import 'package:anicel/src/ui/effective_device_pixel_ratio.dart';
import 'package:anicel/src/ui/playback/layer_frame_image_cache.dart';
import 'package:anicel/src/ui/playback/stacked_frame_picture.dart';

/// The frame [nodes] stack, as a canvas that stands draws it on the screen
/// while its picture is not there, and where a stroke's patch is still on
/// its way ([StackedFrame.paintOnScreen]): every row from its cel as
/// [imageCache] stores it, and the rows a pen, a float or a lift holds —
/// [activeSurfacePainter], [floatOverlay], [liftedRows] — drawn live.
///
/// Every cel is read in hand ([LayerFrameImageCache.storedSurfaceOrNull]):
/// the frame whose rows have all been read, as `FramePictureView` stands
/// on it once they have.
class TheFrameAsItStands extends StatefulWidget {
  const TheFrameAsItStands({
    super.key,
    required this.nodes,
    required this.imageCache,
    required this.canvasSize,
    this.pasteboardReach = PasteboardReach.whole,
    required this.viewport,
    this.activeSurfacePainter,
    this.floatOverlay,
    this.liftedRows = const {},
    this.paintPaper = false,
    this.paperBackground = ProjectBackground.defaultBackground,
    this.debugDisableSingleBuffer = false,
  });

  final List<CompositeNode<CanvasStackRow>> nodes;
  final LayerFrameImageCache imageCache;
  final CanvasSize canvasSize;
  final PasteboardReach pasteboardReach;
  final CanvasViewport viewport;
  final BitmapSurfacePainter? activeSurfacePainter;
  final SelectionFloatOverlay? floatOverlay;
  final Map<BrushFrameKey, LiftedCel> liftedRows;
  final bool paintPaper;
  final ProjectBackground paperBackground;

  /// The direct walk in place of the one buffer
  /// ([StackedFrame.paintOnScreen]).
  final bool debugDisableSingleBuffer;

  @override
  State<TheFrameAsItStands> createState() => _TheFrameAsItStandsState();
}

class _TheFrameAsItStandsState extends State<TheFrameAsItStands> {
  /// Kept across builds, as a screen keeps them ([LiftedRowPainters]).
  final LiftedRowPainters _painters = LiftedRowPainters();

  @override
  Widget build(BuildContext context) {
    final frame = stackedFrameOf(
      widget.nodes,
      page: (
        canvasSize: widget.canvasSize,
        pasteboardReach: widget.pasteboardReach,
        paintPaper: widget.paintPaper,
        paperBackground: widget.paperBackground,
      ),
      surfaceOf: (cel) => widget.imageCache.storedSurfaceOrNull(
        cel,
        canvasSize: widget.canvasSize,
      ),
      live: (
        rows: (
          activeSurfacePainter: widget.activeSurfacePainter,
          floatOverlay: widget.floatOverlay,
          liftedRows: widget.liftedRows,
        ),
        painters: _painters,
      ),
    );
    return CustomPaint(
      painter: _OnScreen(
        frame,
        viewport: widget.viewport,
        devicePixelRatio: EffectiveDevicePixelRatio.of(context),
        debugDisableSingleBuffer: widget.debugDisableSingleBuffer,
      ),
      child: const SizedBox.expand(),
    );
  }
}

class _OnScreen extends CustomPainter {
  _OnScreen(
    this.frame, {
    required this.viewport,
    required this.devicePixelRatio,
    required this.debugDisableSingleBuffer,
  }) : super(repaint: frame.changes);

  final StackedFrame frame;
  final CanvasViewport viewport;
  final double devicePixelRatio;
  final bool debugDisableSingleBuffer;

  @override
  void paint(Canvas canvas, Size size) => frame.paintOnScreen(
    canvas,
    size,
    viewport: viewport,
    devicePixelRatio: devicePixelRatio,
    debugDisableSingleBuffer: debugDisableSingleBuffer,
  );

  // Each build is the frame as it stands then.
  @override
  bool shouldRepaint(_OnScreen oldDelegate) => true;
}
