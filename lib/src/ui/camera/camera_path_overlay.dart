import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';

import '../../models/camera_path_settings.dart';
import '../../models/camera_work_marks.dart';
import '../../models/canvas_point.dart';
import '../../models/canvas_viewport.dart';
import '../../models/sheet_marks.dart';
import '../../models/sheet_paint_layer.dart';
import '../../services/camera_path.dart';
import '../canvas/canvas_viewport_offset.dart';
import '../conte/conte_fonts.dart' show conteTextStyle;
import '../effective_device_pixel_ratio.dart';
import '../sheet_painting.dart';

/// The camera's path over the canvas (I-89 ④): the trail its centre draws,
/// every key's frame with its cross and its label ([cameraPathMarks]) and,
/// shown in time, a cross every so many frames ([cameraPathTicks]) — as
/// [settings] say, around [playhead] where they keep to it.
///
/// It only draws, at the size the screen reads it whatever the zoom.
class CameraPathOverlay extends StatelessWidget {
  const CameraPathOverlay({
    super.key,
    required this.path,
    required this.playhead,
    required this.settings,
    required this.viewport,
  });

  /// How large the canvas writes a camera's work, in screen pixels (the
  /// mock of the confirmed spec, 5판).
  static const CameraMarkSizes sizes = CameraMarkSizes(
    frameWidth: 1.8,
    trailWidth: 1.4,
    labelSize: 12,
    crossArm: 5,
    crossWidth: 1.6,
    labelInset: 4,
  );

  /// A cross in time: smaller than a key's — it marks a frame, not a key.
  static const double tickArm = 3;
  static const double tickWidth = 1.1;

  final CameraPath path;
  final int playhead;
  final CameraPathSettings settings;
  final CanvasViewport viewport;

  /// What it draws, in screen pixels.
  List<SheetMark> get marks {
    Offset place(Offset point) => viewport.canvasToViewportOffset(
      CanvasPoint(x: point.dx, y: point.dy),
    );
    final around = settings.range == CameraPathRange.aroundPlayhead
        ? settings.around
        : null;
    final from = around == null ? null : playhead - around;
    final to = around == null ? null : playhead + around;
    return [
      ...cameraPathMarks(
        path,
        place: place,
        sizes: sizes,
        layer: SheetPaintLayer.picture,
        from: from,
        to: to,
      ),
      if (settings.show == CameraPathShow.spaceAndTime)
        ...cameraPathTicks(
          path,
          place: place,
          every: settings.tickEvery,
          playhead: playhead,
          arm: tickArm,
          width: tickWidth,
          layer: SheetPaintLayer.picture,
          from: from,
          to: to,
        ),
    ];
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: CustomPaint(
      key: const ValueKey<String>('camera-path-overlay'),
      painter: _CameraPathPainter(
        marks: marks,
        devicePixelRatio: EffectiveDevicePixelRatio.of(context),
      ),
      // A bare CustomPaint sizes to zero under loose constraints; the path
      // is drawn over the whole viewport.
      child: const SizedBox.expand(),
    ),
  );
}

/// [marks] printed as the sheets print theirs ([SheetCanvasPrinter]), in
/// the screen's own pixels.
class _CameraPathPainter extends CustomPainter {
  const _CameraPathPainter({
    required this.marks,
    required this.devicePixelRatio,
  });

  final List<SheetMark> marks;
  final double devicePixelRatio;

  @override
  void paint(Canvas canvas, Size size) {
    const SheetCanvasPrinter(style: conteTextStyle).paint(canvas, size, (
      viewport: CanvasViewport(),
      devicePixelRatio: devicePixelRatio,
      paper: size,
    ), marks);
  }

  @override
  bool shouldRepaint(_CameraPathPainter oldDelegate) =>
      !listEquals(oldDelegate.marks, marks) ||
      oldDelegate.devicePixelRatio != devicePixelRatio;
}
