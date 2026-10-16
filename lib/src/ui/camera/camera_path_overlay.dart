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
import '../dashed_path.dart' show DashPattern, dashesAlong;
import '../effective_device_pixel_ratio.dart';
import '../sheet_painting.dart';
import '../theme/app_theme.dart' show AppColors;

/// The camera's path over the canvas (I-89 ④): the trail each corner of its
/// frame draws, every key's frame with its cross and its label
/// ([cameraPathMarks]), the line its middle walks while one is [standing]
/// ([centreTrail]) and, shown in time while one stands, a cross every so
/// many frames with the frame beside it ([cameraPathTicks]) — as
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
    required this.standing,
    this.toCanvas,
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

  /// The frame a cross in time wears beside it: smaller than a key's label,
  /// as its cross is, and clear of the cross's line.
  static const double tickLabelSize = 10;
  static const double tickLabelGap = 2;

  /// The line the camera's middle walks ([centreTrail]): dashed, in the
  /// handles' colour, a cross's width (the F-368-Q1 mock's A).
  static const double centreTrailWidth = 1.6;
  static const DashPattern centreTrailDashes = DashPattern(on: 5, off: 3);

  final CameraPath path;
  final int playhead;
  final CameraPathSettings settings;
  final CanvasViewport viewport;

  /// Whether one stands on the camera's row, where its frame is worked: the
  /// crosses in time are drawn there alone, as the path's handles are (유저
  /// 2026-10-12: 「nf마다의 작은 십자가, 핸들 이런게 서있으면 보여주도록」),
  /// and the line its middle walks ([centreTrail]). Elsewhere the path is
  /// what the export writes of it (「출력할때랑 동일한 상태를 보여줌」).
  final bool standing;

  /// Where a point of [path] stands on the canvas — a layer's position
  /// through the folders over it (I-89-Q9). A camera's frames are on the
  /// canvas already.
  final CanvasPoint Function(CanvasPoint point)? toCanvas;

  /// [point] of [path] on the screen.
  Offset _place(Offset point) {
    final at = CanvasPoint(x: point.dx, y: point.dy);
    return viewport.canvasToViewportOffset(toCanvas?.call(at) ?? at);
  }

  /// The line the camera's middle walks, in screen pixels, while one
  /// stands on it — in space and in space and time alike: the handles'
  /// line, which is where the path is (🗣️F-368, 유저 2026-10-16: 「공간이든
  /// 공간+시간이든 공간이라는 정보로서」 · F-368-Q1 A 「중앙 궤적 선 +
  /// 핸들(두 모드 공통, 서 있을 때)」). None on a point's path
  /// ([CameraPath.centreTrailBetween]).
  List<Offset> get centreTrail {
    if (!standing) {
      return const [];
    }
    final (:from, :to) = settings.framesShownAt(playhead);
    return [
      for (final point in path.centreTrailBetween(
        from ?? path.firstFrame,
        to ?? path.lastFrame,
      ))
        _place(point),
    ];
  }

  /// What it draws, in screen pixels.
  List<SheetMark> get marks {
    final (:from, :to) = settings.framesShownAt(playhead);
    return [
      ...cameraPathMarks(
        path,
        place: _place,
        sizes: sizes,
        layer: SheetPaintLayer.picture,
        from: from,
        to: to,
      ),
      if (standing && settings.show == CameraPathShow.spaceAndTime)
        ...cameraPathTicks(
          path,
          place: _place,
          every: settings.tickEvery,
          playhead: playhead,
          arm: tickArm,
          width: tickWidth,
          labelSize: tickLabelSize,
          labelGap: tickLabelGap,
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
        centreTrail: centreTrail,
        // The handles' colour: a row's box wears the accent
        // (F-222-box-Q5, `RowTransformBox`).
        centreTrailColor: AppColors.accent,
        devicePixelRatio: EffectiveDevicePixelRatio.of(context),
      ),
      // A bare CustomPaint sizes to zero under loose constraints; the path
      // is drawn over the whole viewport.
      child: const SizedBox.expand(),
    ),
  );
}

/// [marks] printed as the sheets print theirs ([SheetCanvasPrinter]), in
/// the screen's own pixels, and over them the [centreTrail] — an editing
/// line no sheet prints — in dashes of [centreTrailColor].
class _CameraPathPainter extends CustomPainter {
  const _CameraPathPainter({
    required this.marks,
    required this.centreTrail,
    required this.centreTrailColor,
    required this.devicePixelRatio,
  });

  final List<SheetMark> marks;
  final List<Offset> centreTrail;
  final Color centreTrailColor;
  final double devicePixelRatio;

  @override
  void paint(Canvas canvas, Size size) {
    const SheetCanvasPrinter(style: conteTextStyle).paint(canvas, size, (
      viewport: CanvasViewport(),
      devicePixelRatio: devicePixelRatio,
      paper: size,
    ), marks);
    if (centreTrail.length < 2) {
      return;
    }
    final ink = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = CameraPathOverlay.centreTrailWidth
      ..color = centreTrailColor;
    for (final dash in dashesAlong(
      Path()..addPolygon(centreTrail, false),
      CameraPathOverlay.centreTrailDashes,
    )) {
      canvas.drawPath(dash, ink);
    }
  }

  @override
  bool shouldRepaint(_CameraPathPainter oldDelegate) =>
      !listEquals(oldDelegate.marks, marks) ||
      !listEquals(oldDelegate.centreTrail, centreTrail) ||
      oldDelegate.centreTrailColor != centreTrailColor ||
      oldDelegate.devicePixelRatio != devicePixelRatio;
}
