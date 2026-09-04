import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_size.dart';

/// 🚨THE HEIGHT NEVER REACHES ZERO.
///
/// Three renders ask a camera size for "this aspect, at this width" — the
/// storyboard thumbnail, the conte cell pictures and the PDF's pictures.
/// Each used to clamp the rounded height itself, so a very wide, very
/// short camera was one forgotten `max` away from an export that throws
/// on a zero-tall raster.
void main() {
  test('the aspect is kept, and the width is the one asked for', () {
    const camera = CanvasSize(width: 1920, height: 1080);
    expect(camera.scaledToWidth(640), const CanvasSize(width: 640, height: 360));
  });

  test('a taller-than-wide size scales the same way', () {
    const portrait = CanvasSize(width: 600, height: 900);
    expect(
      portrait.scaledToWidth(200),
      const CanvasSize(width: 200, height: 300),
    );
  });

  test('the height rounds rather than truncating', () {
    const camera = CanvasSize(width: 3, height: 2);
    // 10 * 2 / 3 = 6.67 — a truncating render would letterbox by a pixel.
    expect(camera.scaledToWidth(10), const CanvasSize(width: 10, height: 7));
  });

  test('a height that would round to zero becomes one pixel', () {
    const veryWide = CanvasSize(width: 4000, height: 3);
    expect(
      veryWide.scaledToWidth(64).height,
      1,
      reason: 'a zero-tall raster is one the backends refuse',
    );
  });

  test('scaling to the size it already is changes nothing', () {
    const camera = CanvasSize(width: 1280, height: 720);
    expect(camera.scaledToWidth(1280), camera);
  });
}
