import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';

import '../../models/camera_path_settings.dart';
import '../../models/camera_pose.dart';
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
/// It only draws. What the export writes of a camera's path — its trails,
/// and every key's frame, cross and label ([cameraPathMarks]) — lies on the
/// picture's pixels, as large as the export prints it ([printedAt]); the
/// rest, and a path no export writes, at the size the screen reads it
/// whatever the zoom.
///
/// 🗣️F-421 (유저 2026-10-20): 「캔버스 확대해도 축소해도 크기 안바뀌는
/// 벡터?느낌인데 크기는 100%인 상태에서 고정되도록」 · 「사각형 라인도
/// 글자도 픽셀에 올리고싶단느낌」 — and F-421-Q1: 「출력시 남는 것만 캔버스
/// 픽셀에 올리고싶은게 목적임. 이유는 출력할때 선의 굵기같은게 참고가
/// 되기때문」. ↩️It was all drawn at the screen's size.
class CameraPathOverlay extends StatelessWidget {
  const CameraPathOverlay({
    super.key,
    required this.path,
    required this.playhead,
    required this.settings,
    required this.viewport,
    required this.standing,
    this.printedAt,
    this.toCanvas,
  });

  /// How large the export writes a camera's work, in its file's pixels
  /// (I-89-Q20 「캔버스와 같은 픽셀 수」): the mock of the confirmed spec
  /// (5판), its words twice that (🗣️F-421: 「글자 3배는 너무큰거같으니
  /// 2배로」) — and the canvas, off the picture's pixels, in the screen's.
  static const CameraMarkSizes sizes = CameraMarkSizes(
    frameWidth: 1.8,
    trailWidth: 1.4,
    labelSize: 24,
    crossArm: 5,
    crossWidth: 1.6,
    labelInset: 4,
  );

  /// [sizes] in canvas pixels, where the camera stands at [pose]: the
  /// export's file is the camera's frame, so a pixel of it is `1 / zoom` of
  /// the canvas's.
  static CameraMarkSizes sizesOnTheCanvas(CameraPose pose) =>
      sizes.scaledBy(1 / pose.zoom);

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

  /// The camera's pose where its path is printed — the frame the playhead
  /// stands on: the marks the export writes ([cameraPathMarks]) are drawn
  /// as large on the picture as it writes them there
  /// ([sizesOnTheCanvas]). Null for a path no export writes — a layer's —
  /// all of it at the screen's size.
  final CameraPose? printedAt;

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

  /// [sizes] on the screen: on the picture's pixels where the path is
  /// printed ([printedAt]), else as they are.
  CameraMarkSizes get _shownSizes {
    final printed = printedAt;
    return printed == null
        ? sizes
        : sizesOnTheCanvas(printed).scaledBy(viewport.zoom);
  }

  /// What it draws, in screen pixels.
  List<SheetMark> get marks {
    final (:from, :to) = settings.framesShownAt(playhead);
    return [
      ...cameraPathMarks(
        path,
        place: _place,
        sizes: _shownSizes,
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
