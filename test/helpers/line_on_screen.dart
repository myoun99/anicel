import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show OffsetLayer;
import 'package:flutter_test/flutter_test.dart';

/// How much of [line]'s length the screen shows in the theme's primary colour,
/// from 0 to 1, read off the pixels the frame painted.
///
/// 🔬Where a widget stands says nothing of whether it was seen: a line stood
/// at the right place in the tree while the rows after it painted over it,
/// and no test of its rect could tell (sheet-gap-stands-inside-open-lanes,
/// 11-01).
Future<double> lineOnScreen(WidgetTester tester, Finder line) async {
  final view = tester.binding.renderViews.first;
  final scale = view.configuration.devicePixelRatio;
  final colour = Theme.of(tester.element(line)).colorScheme.primary.toARGB32();
  final at = tester.getRect(line);
  final screen = (Offset.zero & view.size).intersect(at);
  final width = (view.size.width * scale).round();
  final height = (view.size.height * scale).round();
  final layer = view.debugLayer! as OffsetLayer;
  final pixels = await tester.runAsync(() async {
    final shot = await layer.toImage(
      Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    );
    final bytes = await shot.toByteData();
    shot.dispose();
    return bytes;
  });
  bool isLine(int x, int y) {
    final byte = (y * width + x) * 4;
    final argb =
        pixels!.getUint8(byte + 3) << 24 |
        pixels.getUint8(byte) << 16 |
        pixels.getUint8(byte + 1) << 8 |
        pixels.getUint8(byte + 2);
    return argb == colour;
  }

  final across = at.width >= at.height;
  final left = (screen.left * scale).round();
  final top = (screen.top * scale).round();
  final right = (screen.right * scale).round();
  final bottom = (screen.bottom * scale).round();
  final length = across ? right - left : bottom - top;
  var shown = 0;
  for (var along = 0; along < length; along += 1) {
    final hit = across
        ? [for (var y = top; y < bottom; y += 1) isLine(left + along, y)]
        : [for (var x = left; x < right; x += 1) isLine(x, top + along)];
    if (hit.contains(true)) {
      shown += 1;
    }
  }
  return shown / length;
}
