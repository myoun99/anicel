import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'tool_cursor_look.dart';

/// R11-②: the eyedropper's hover swatch — the colour under the pointer in a
/// white ring with a soft shadow, up-right of the point being sampled.
///
/// 🚨★★★F-130: IT SAMPLES IN `paint`, ONCE PER FRAME. The colour used to
/// be read from the composite on every pointer EVENT (a stylus reports
/// 200+ a second) and written into a notifier the swatch rebuilt from. A
/// frame shows one colour, so one read per frame is every read that can be
/// seen; the aim arrives through [position] and the read happens here,
/// where the frame is.
///
/// It is a `repaint`-driven painter: the aim's notifier is its `repaint`,
/// so the sprite wearing it re-records the (tiny) picture when the aim
/// moves instead of only re-offsetting it — the colour may have changed.
class EyedropperSwatchPainter extends CustomPainter {
  EyedropperSwatchPainter({required this.position, required this.sample})
    : super(repaint: position);

  /// The aim, panel-local.
  final ValueListenable<Offset?> position;

  /// The composite colour under a panel-local point, or null off the
  /// canvas — the swatch then paints nothing.
  final int? Function(Offset viewportPosition) sample;

  /// The swatch: a 26px disc. Its `BoxShadow` blurred 3px past the disc,
  /// so the box leaves that much room on every side.
  static const double _disc = 26;
  static const double _room = 8;
  static const Size extent = Size(_disc + 2 * _room, _disc + 2 * _room);

  /// The disc sits 14px right and 34px up of the pointer; the pointer's
  /// point is therefore outside the box, left of it and below.
  static const Offset hotspot = Offset(-14 + _room, 34 + _room);

  /// The colour the last `paint` showed, for tests; null when it showed
  /// nothing.
  int? debugLastColor;

  @override
  void paint(Canvas canvas, Size size) {
    final at = position.value;
    final color = at == null ? null : sample(at);
    debugLastColor = color;
    if (color == null) {
      return;
    }
    final centre = Offset(size.width / 2, size.height / 2);
    const radius = _disc / 2;
    canvas.drawCircle(
      centre,
      radius,
      const BoxShadow(color: Colors.black38, blurRadius: 3).toPaint(),
    );
    canvas.drawCircle(centre, radius, Paint()..color = Color(0xFF000000 | color));
    canvas.drawCircle(
      centre,
      radius - 1,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = Colors.white,
    );
  }

  /// A fresh painter per panel build (the sampler is a closure) — the
  /// picture is a disc, so repainting it on a rebuild costs nothing worth
  /// a comparison.
  @override
  bool shouldRepaint(EyedropperSwatchPainter oldDelegate) => true;
}

/// The swatch as a look for the sprite.
ToolCursorLook eyedropperSwatchLook({
  required ValueListenable<Offset?> position,
  required int? Function(Offset viewportPosition) sample,
}) => ToolCursorLook(
  key: 'eyedropper-swatch',
  painter: EyedropperSwatchPainter(position: position, sample: sample),
  extent: EyedropperSwatchPainter.extent,
  hotspot: EyedropperSwatchPainter.hotspot,
);
