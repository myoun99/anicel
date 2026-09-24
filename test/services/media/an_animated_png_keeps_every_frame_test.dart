import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:anicel/src/services/media/animated_png_writer.dart';
import 'package:flutter_test/flutter_test.dart';

/// The piece a trimmed animated image is carried as (유저 2026-09-23: 「비디오든
/// 이미지든 오디오든 관계없이 법 하나로」). What it has to promise is that the
/// app reads back EXACTLY what was cut — every pixel, every delay — through
/// the same codec that shows it.
void main() {
  const width = 5;
  const height = 3;

  Uint8List frameOf(int Function(int x, int y) colourAt) {
    final rgba = Uint8List(width * height * 4);
    final data = ByteData.sublistView(rgba);
    for (var y = 0; y < height; y += 1) {
      for (var x = 0; x < width; x += 1) {
        data.setUint32((y * width + x) * 4, colourAt(x, y));
      }
    }
    return rgba;
  }

  Future<List<({Uint8List rgba, Duration duration})>> decoded(
    Uint8List png,
  ) async {
    final codec = await ui.instantiateImageCodec(png);
    final frames = <({Uint8List rgba, Duration duration})>[];
    for (var i = 0; i < codec.frameCount; i += 1) {
      final frame = await codec.getNextFrame();
      final data = await frame.image.toByteData(
        format: ui.ImageByteFormat.rawStraightRgba,
      );
      frames.add((rgba: data!.buffer.asUint8List(), duration: frame.duration));
      frame.image.dispose();
    }
    codec.dispose();
    return frames;
  }

  /// IHDR's colour type byte: 3 = palette, 6 = RGBA.
  int colourTypeOf(Uint8List png) => png[8 + 8 + 9];

  test('🎯a few colours come back frame for frame, delay for delay — and as a '
      'PALETTE, so the piece is not bigger than what it was cut from', () async {
    final frames = [
      (
        rgba: frameOf((x, y) => x.isEven ? 0xFF0000FF : 0x00000000),
        duration: const Duration(milliseconds: 40),
      ),
      (
        rgba: frameOf((x, y) => y == 1 ? 0x00FF0080 : 0xFF0000FF),
        duration: const Duration(milliseconds: 100),
      ),
      (
        rgba: frameOf((x, y) => 0x0000FFFF),
        duration: const Duration(milliseconds: 250),
      ),
    ];

    final png = encodeAnimatedPng(width: width, height: height, frames: frames);
    final back = await decoded(png);

    expect(colourTypeOf(png), 3, reason: 'four colours fit a palette');
    expect(back, hasLength(3));
    for (var i = 0; i < frames.length; i += 1) {
      expect(back[i].rgba, frames[i].rgba, reason: 'frame $i pixels');
      expect(back[i].duration, frames[i].duration, reason: 'frame $i delay');
    }
  });

  test('🚨past 256 colours it is RGBA — and still every pixel', () async {
    final frames = [
      for (var f = 0; f < 20; f += 1)
        (
          rgba: frameOf(
            (x, y) =>
                ((f * 13 + x * 7) & 0xFF) << 24 |
                ((y * 31 + f) & 0xFF) << 16 |
                ((x * y + f * 3) & 0xFF) << 8 |
                0xFF,
          ),
          duration: const Duration(milliseconds: 50),
        ),
    ];

    final png = encodeAnimatedPng(width: width, height: height, frames: frames);
    final back = await decoded(png);

    expect(colourTypeOf(png), 6, reason: 'the frames use more than 256');
    expect(back, hasLength(frames.length));
    for (var i = 0; i < frames.length; i += 1) {
      expect(back[i].rgba, frames[i].rgba, reason: 'frame $i pixels');
    }
  });

  test('🚨a delay longer than sixteen bits of milliseconds is still that '
      'long', () async {
    final frames = [
      (
        rgba: frameOf((x, y) => 0xFFFFFFFF),
        duration: const Duration(seconds: 90),
      ),
      (
        rgba: frameOf((x, y) => 0x000000FF),
        duration: const Duration(milliseconds: 20),
      ),
    ];

    final back = await decoded(
      encodeAnimatedPng(width: width, height: height, frames: frames),
    );

    expect(back[0].duration, const Duration(seconds: 90));
    expect(back[1].duration, const Duration(milliseconds: 20));
  });
}
