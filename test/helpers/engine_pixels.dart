import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';

/// Every frame the engine's decoder hands back for [bytes] — what the app's
/// own readers of a picture past the engine's side are held against.
Future<List<({Uint8List rgba, int width, int height, Duration duration})>>
engineFrames(Uint8List bytes) async {
  final codec = await ui.instantiateImageCodec(bytes);
  try {
    return [
      for (var i = 0; i < codec.frameCount; i += 1)
        await _straight(await codec.getNextFrame()),
    ];
  } finally {
    codec.dispose();
  }
}

Future<({Uint8List rgba, int width, int height, Duration duration})>
_straight(ui.FrameInfo frame) async {
  final image = frame.image;
  try {
    final data = await image.toByteData(
      format: ui.ImageByteFormat.rawStraightRgba,
    );
    return (
      rgba: data!.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      width: image.width,
      height: image.height,
      duration: frame.duration,
    );
  } finally {
    image.dispose();
  }
}

/// What the engine's decoder hands back for [png], as straight RGBA.
Future<Uint8List> engineRgba(Uint8List png) async =>
    (await engineFrames(png)).first.rgba;

/// [ours] against the engine's [theirs], pixel by pixel: the alpha exactly,
/// and the colour exactly where the pixel is opaque or clear. Where the
/// engine keeps a pixel partly clear it premultiplies on the way, and its
/// straight colour comes back off by up to what one step of alpha spans.
/// [colourSlack] is what two decoders of a lossy format may differ by on
/// top of that.
void expectSamePixels(
  Uint8List ours,
  Uint8List theirs, {
  int colourSlack = 0,
}) {
  expect(ours.length, theirs.length);
  for (var i = 0; i < ours.length; i += 4) {
    final alpha = theirs[i + 3];
    final slack =
        (alpha == 0 || alpha == 255 ? 0 : 255 ~/ alpha + 1) + colourSlack;
    var apart = (ours[i + 3] - alpha).abs() * 1000;
    for (var c = 0; c < 3; c += 1) {
      final channel = (ours[i + c] - theirs[i + c]).abs();
      apart = channel > apart ? channel : apart;
    }
    if (apart > slack) {
      fail(
        'pixel ${i ~/ 4}: ${ours.sublist(i, i + 4)} where the engine '
        'reads ${theirs.sublist(i, i + 4)}',
      );
    }
  }
}
