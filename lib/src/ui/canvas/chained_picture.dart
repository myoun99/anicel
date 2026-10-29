import 'dart:ui' as ui;

/// 🚨★★★DRAWN REDUCED, A PICTURE IS SAMPLED FROM THE ENGINE'S MIP CHAIN —
/// SO ONE DRAWN REDUCED HAS TO CARRY ONE (one-picture-per-frame ②-5b-2,
/// 2026-10-25; 유저 D7-2-Q2 「배율이 어떻든 항상 원본 한장」).
///
/// A frame's one picture is a render (`toImage`), and the engine gives
/// every render its whole chain: at or under half the display samples it
/// `medium`, from the chain ([filterQualityForDisplayScale]). A tile's
/// picture comes up through the door (`pictureOf`), and on Impeller an
/// upload has NO chain — `medium` samples it as `low` does. 🔬Measured on
/// the real Windows app (Impeller OpenGLES, release; a 512² line drawing in
/// 256 tiles against its one picture drawn by the same law): door tiles
/// drawn reduced were 15295 of 16384 pixels apart at 25%, up to 132/255;
/// the same tiles remade here were 0 apart at 1/2, 1/4, 1/8 and 0.75, and
/// elsewhere only on the one-pixel band along each tile edge (0.45: 23 ·
/// 0.33: 5 · 0.2: 11 · 0.6: 39 at the most) — where a tile is filtered
/// with no neighbour to sample. A `toImageSync` render is the same bytes as
/// a `toImage` one at every scale, chain and all; so is the test runner's
/// Vulkan (`--enable-impeller`). The test runner's Skia chains a door
/// picture by itself when it is drawn `medium`.
///
/// ⛔ONLY WHERE IT IS DRAWN REDUCED: a chain is a third more of the
/// picture, and a tile drawn at 100% — into a frame's picture, into a
/// display buffer — never samples it. A picture gains one the first time a
/// screen draws it reduced, and is that picture from then on.
///
/// [source] is the picture's part of [image] where it shares one — a
/// tile's slot of a page; null is the whole of [image].
ui.Image chainedPictureOf(ui.Image image, {ui.Rect? source}) {
  if (source == null && carriesChain(image)) {
    return image;
  }
  final from =
      source ??
      ui.Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble());
  final recorder = ui.PictureRecorder();
  // 1:1 — the same bytes; what the render adds is the engine's chain.
  ui.Canvas(recorder).drawImageRect(
    image,
    from,
    ui.Offset.zero & from.size,
    ui.Paint()..filterQuality = ui.FilterQuality.none,
  );
  final width = from.width.round();
  final height = from.height.round();
  final picture = recorder.endRecording();
  try {
    final chained = picture.toImageSync(width, height);
    _chained[chained] = true;
    return chained;
  } finally {
    picture.dispose();
  }
}

/// Whether [image] was made by [chainedPictureOf].
bool carriesChain(ui.Image image) => _chained[image] ?? false;

final Expando<bool> _chained = Expando<bool>('chainedPicture');

/// What [image] holds on the device: its pixels, and a third more where it
/// carries its chain ([chainedPictureOf]).
int pictureBytesOf(ui.Image image) {
  final pixels = image.width * image.height * 4;
  return carriesChain(image) ? pixels + pixels ~/ 3 : pixels;
}
