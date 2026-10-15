import 'dart:ui' as ui;

/// A [side]×[side] picture of one-pixel squares, black and white — what
/// shows how a picture was sampled: drawn hard-edged, at its own pixels or
/// larger, every pixel of it is black or white ([isPure]); smoothed, some
/// mix the two ([isGrey]).
///
/// ⚠️Call it inside `tester.runAsync` — `toImage` is real async work.
Future<ui.Image> checkerImage(int side) {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder)
    ..drawColor(const ui.Color(0xFFFFFFFF), ui.BlendMode.src);
  final black = ui.Paint()..color = const ui.Color(0xFF000000);
  for (var y = 0; y < side; y += 1) {
    for (var x = y % 2; x < side; x += 2) {
      canvas.drawRect(
        ui.Rect.fromLTWH(x.toDouble(), y.toDouble(), 1, 1),
        black,
      );
    }
  }
  return recorder.endRecording().toImage(side, side);
}

/// A checker pixel's red, sampled hard-edged: black or white.
bool isPure(int red) => red == 0 || red == 255;

/// A checker pixel's red, smoothed: black and white mixed.
bool isGrey(int red) => red > 40 && red < 215;

/// The red of each pixel of [image] within [radius] of ([x], [y]), row by
/// row — a block well inside a checker laid there.
Future<List<int>> redsAround(
  ui.Image image,
  int x,
  int y, {
  int radius = 4,
}) async {
  final data = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  return [
    for (var row = y - radius; row <= y + radius; row += 1)
      for (var column = x - radius; column <= x + radius; column += 1)
        data.getUint8((row * image.width + column) * 4),
  ];
}
