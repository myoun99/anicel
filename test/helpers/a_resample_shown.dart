import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:anicel/src/models/brush_dab.dart';
import 'package:anicel/src/models/brush_stamp_image.dart';
import 'package:anicel/src/models/brush_tip_shape.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/dirty_region.dart';
import 'package:anicel/src/ui/canvas/float_warp.dart';

/// [rgba] — straight, a row [region]'s width — as an open warp shows a
/// resample that lands on [region] ([FloatResampleShown.of]).
FloatResampleShown resampleShownOn(DirtyRegion region, Uint8List rgba) =>
    FloatResampleShown.of(
      BrushDab(
        center: CanvasPoint(
          x: region.left + region.width / 2,
          y: region.top + region.height / 2,
        ),
        color: 0xFF000000,
        size: 1,
        opacity: 1,
        flow: 1,
        hardness: 1,
        tipShape: BrushTipShape.square,
        pressure: 1,
        sequence: 0,
        stamp: BrushStampImage(
          id: 'resample',
          width: region.width,
          height: region.height,
          rgba: rgba,
        ),
      ),
    );

/// [where] — whole pixels — all of [colour], straight, as an open warp
/// shows a resample landing there ([resampleShownOn]).
FloatResampleShown resampleShownOver(ui.Rect where, List<int> colour) {
  final region = DirtyRegion(
    left: where.left.round(),
    top: where.top.round(),
    rightExclusive: where.right.round(),
    bottomExclusive: where.bottom.round(),
  );
  final rgba = Uint8List(region.width * region.height * 4);
  for (var at = 0; at < rgba.length; at += 4) {
    rgba.setRange(at, at + 4, colour);
  }
  return resampleShownOn(region, rgba);
}
