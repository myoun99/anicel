// 🚨Every colour mode's planes pack into the RGBA its rule names, pixel by
// pixel, with the alpha plane or without (card psd-planes-pack-on-the-engine,
// 2026-11-16: the pack went to a run of pixels at a time, and four of the
// eight modes had no pin). Each pixel is checked against its mode's rule
// worked by hand — Lab's against the same pixel packed alone, its colour
// sums pinned by `psd_lab_is_the_same_on_every_device_test.dart`.
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/import/import_warning.dart';
import 'package:anicel/src/services/photoshop/psd_pixels.dart';

void main() {
  const width = 37;
  const height = 11;
  const count = width * height;
  var seed = 0x2545f491;
  Uint8List noise(int length) => Uint8List.fromList([
    for (var i = 0; i < length; i += 1)
      (seed = (seed * 1103515245 + 12345) & 0x7fffffff) >> 16 & 255,
  ]);
  final planes = [for (var i = 0; i < 4; i += 1) noise(count)];
  final alpha = noise(count);
  final palette = noise(768);

  ({Uint8List rgba, List<String> said}) packed(
    PsdColorMode mode, {
    required Uint8List? alphaPlane,
    Uint8List? palette,
    int width = width,
    int height = height,
    List<Uint8List>? colour,
  }) {
    final warnings = <ImportWarning>[];
    final rgba = psdPlanesToRgba(
      mode: mode,
      colorPlanes: colour ?? planes.sublist(0, mode.colorPlaneCount),
      alphaPlane: alphaPlane,
      width: width,
      height: height,
      palette: palette,
      warnings: warnings,
    );
    return (rgba: rgba, said: [for (final warning in warnings) warning.key]);
  }

  int clamp(int value) => value < 0 ? 0 : (value > 255 ? 255 : value);
  List<int> grey(int i) => List.filled(3, planes[0][i]);
  final rules =
      <String, (PsdColorMode, Uint8List?, List<int> Function(int))>{
        'rgb': (
          PsdColorMode.rgb,
          null,
          (i) => [planes[0][i], planes[1][i], planes[2][i]],
        ),
        'grayscale': (PsdColorMode.grayscale, null, grey),
        'duotone': (PsdColorMode.duotone, null, grey),
        'bitmap': (PsdColorMode.bitmap, null, grey),
        'multichannel': (PsdColorMode.multichannel, null, grey),
        'indexed': (
          PsdColorMode.indexed,
          palette,
          (i) => [
            for (final at in [0, 256, 512]) palette[at + planes[0][i]],
          ],
        ),
        'indexed, no palette': (PsdColorMode.indexed, null, grey),
        'cmyk': (
          PsdColorMode.cmyk,
          null,
          (i) => [
            for (final ink in planes.sublist(0, 3))
              clamp(ink[i] + planes[3][i] - 255),
          ],
        ),
      };

  for (final MapEntry(key: name, value: (mode, palette, rule))
      in rules.entries) {
    for (final withAlpha in [true, false]) {
      final alphaSaid = withAlpha ? 'with' : 'without';
      test('$name $alphaSaid alpha: each pixel its rule', () {
        final (:rgba, said: _) = packed(
          mode,
          alphaPlane: withAlpha ? alpha : null,
          palette: palette,
        );
        expect(rgba.length, count * 4);
        for (var i = 0; i < count; i += 1) {
          final want = [...rule(i), if (withAlpha) alpha[i] else 255];
          expect(
            rgba.sublist(i * 4, i * 4 + 4),
            want,
            reason: '$name pixel $i',
          );
        }
      });
    }
  }

  test('lab: each pixel is that pixel packed alone', () {
    for (final withAlpha in [true, false]) {
      final (:rgba, said: _) = packed(
        PsdColorMode.lab,
        alphaPlane: withAlpha ? alpha : null,
      );
      for (var i = 0; i < count; i += 1) {
        final (rgba: one, said: _) = packed(
          PsdColorMode.lab,
          alphaPlane: withAlpha ? Uint8List.fromList([alpha[i]]) : null,
          width: 1,
          height: 1,
          colour: [
            for (final plane in planes.sublist(0, 3))
              Uint8List.fromList([plane[i]]),
          ],
        );
        expect(
          rgba.sublist(i * 4, i * 4 + 4),
          one,
          reason: 'pixel $i, alpha $withAlpha',
        );
      }
    }
  });

  test('a mode it can only convert says so, once', () {
    String said(PsdColorMode mode, {Uint8List? palette}) =>
        packed(mode, alphaPlane: null, palette: palette).said.join(',');
    expect(said(PsdColorMode.rgb), '');
    expect(said(PsdColorMode.grayscale), '');
    expect(said(PsdColorMode.bitmap), '');
    expect(said(PsdColorMode.indexed, palette: palette), '');
    expect(said(PsdColorMode.duotone), 'psdDuotone');
    expect(said(PsdColorMode.multichannel), 'psdMultichannel');
    expect(said(PsdColorMode.indexed), 'psdIndexedNoPalette');
    expect(
      said(PsdColorMode.indexed, palette: palette.sublist(0, 767)),
      'psdIndexedNoPalette',
    );
    expect(said(PsdColorMode.cmyk), 'psdCmyk');
    expect(said(PsdColorMode.lab), 'psdLab');
  });

  test('a colour plane the file left out reads as zero', () {
    final (:rgba, said: _) = packed(
      PsdColorMode.rgb,
      alphaPlane: null,
      colour: [planes[0]],
    );
    for (var i = 0; i < count; i += 1) {
      expect(rgba.sublist(i * 4, i * 4 + 4), [planes[0][i], 0, 0, 255]);
    }
  });

  // 🚨A layer cut a row at a time is its whole picture, cropped: each row
  // of the crop packed and its mask baked where it lies — a mask over part
  // of the layer, and past its rectangle its default (0: hidden). The
  // import cuts these rows into tiles and never holds the whole.
  test("a layer's rows are its whole picture's, cropped", () {
    final layer = PsdLayerPicture(
      PsdPlanes(
        mode: PsdColorMode.rgb,
        colorPlanes: planes.sublist(0, 3),
        alphaPlane: alpha,
        width: width,
        height: height,
        palette: null,
        warnings: <ImportWarning>[],
      ),
      left: 100,
      top: 50,
      mask: (
        plane: noise(20 * 6),
        left: 110,
        top: 53,
        width: 20,
        height: 6,
        defaultColor: 0,
      ),
    );
    final whole = layer.rgba();
    final (fromX, fromY, cropWidth, cropHeight) = (5, 2, 25, 8);
    final seen = <int>[];
    Uint8List? buffer;
    layer.rows(
      fromX: fromX,
      fromY: fromY,
      width: cropWidth,
      height: cropHeight,
      row: (y, rgba) {
        seen.add(y);
        expect(identical(buffer ?? rgba, rgba), isTrue, reason: 'one buffer');
        buffer = rgba;
        final from = ((fromY + y) * width + fromX) * 4;
        expect(rgba, whole.sublist(from, from + cropWidth * 4), reason: '$y');
      },
    );
    expect(seen, [for (var y = 0; y < cropHeight; y += 1) y]);
    final hidden = whole[(0 * width + 0) * 4 + 3];
    expect(hidden, 0, reason: 'past the mask, its default hides');
  });
}
