import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:anicel/src/models/export_format_selection.dart';
import 'package:anicel/src/services/media/png_writing.dart';
import 'package:anicel/src/ui/export/still_image_encoders.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/png_chunks.dart';

/// 🗣️F-335 (유저 10-10): 「알파채널 아예없는걸 원하거든? RGBA가 아닌 RGB는
/// 그게 효율적이잖아」 → 「그렇게하자」 — a PNG the export window or Save As
/// writes in RGB has no alpha channel in the file. They all ask the one
/// encoder ([stillEncoderFor]), so it is pinned here.
void main() {
  const rgb = ExportFormatSelection(
    kind: ExportMediaKind.still,
    channels: ExportChannels.rgb,
  );

  Future<ui.Image> paint(
    int width,
    int height,
    void Function(ui.Canvas canvas) draw,
  ) {
    final recorder = ui.PictureRecorder();
    draw(ui.Canvas(recorder));
    return recorder.endRecording().toImage(width, height);
  }

  Future<Uint8List> written(
    ui.Image image,
    ExportFormatSelection format,
  ) async {
    final bytes = await stillEncoderFor(format)!(image);
    image.dispose();
    return Uint8List.fromList(bytes!);
  }

  /// [png] through the engine's codec: the RGBA of the pixel at [x], [y].
  Future<List<int>> pixelAt(Uint8List png, int x, int y) async {
    final codec = await ui.instantiateImageCodec(png);
    final image = (await codec.getNextFrame()).image;
    final data = await image.toByteData(
      format: ui.ImageByteFormat.rawStraightRgba,
    );
    final at = (y * image.width + x) * 4;
    image.dispose();
    codec.dispose();
    return Uint8List.sublistView(data!, at, at + 4).toList();
  }

  test('🎯three channels, the sRGB stamp, and the ground where the picture '
      'has nothing', () async {
    final png = await written(
      await paint(4, 2, (canvas) {
        canvas.drawRect(
          const ui.Rect.fromLTWH(0, 0, 2, 2),
          ui.Paint()..color = const ui.Color(0xFF204060),
        );
      }),
      rgb,
    );

    expect(pngColourTypeOf(png), 2, reason: 'RGB: no alpha in the file');
    expect(
      [for (final chunk in pngChunksOf(png)) chunk.type],
      ['IHDR', 'sRGB', 'gAMA', 'cHRM', 'IDAT', 'IEND'],
      reason: 'C1-v1: every PNG handed out says its colours are sRGB',
    );
    expect(await pixelAt(png, 0, 0), [0x20, 0x40, 0x60, 255]);
    expect(
      await pixelAt(png, 3, 1),
      [255, 255, 255, 255],
      reason: 'the format\'s ground (white unless asked)',
    );
  });

  test('a pixel half there is laid over the ground as it shows — the '
      'read-back is premultiplied', () async {
    final png = await written(
      await paint(2, 1, (canvas) {
        canvas.drawRect(
          const ui.Rect.fromLTWH(0, 0, 2, 1),
          ui.Paint()..color = const ui.Color(0x80FF0000),
        );
      }),
      rgb,
    );

    expect(
      await pixelAt(png, 0, 0),
      [255, 127, 127, 255],
      reason: 'half red over white — the straight-alpha sum made it 191',
    );
  });

  group('the rows are kept as whichever packs smaller', () {
    const width = 512;
    const height = 256;
    const stride = width * 3;

    /// [image]'s rows — opaque, so its RGB as it is — deflated both ways
    /// here: (filtered, unfiltered) sizes.
    Future<(int, int)> bothWays(ui.Image image) async {
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      final rgba = Uint8List.sublistView(data!);
      final filtered = PngImageData(width: width, bytesPerPixel: 3);
      final unfiltered = PngImageData(
        width: width,
        bytesPerPixel: 3,
        filtered: false,
      );
      final row = Uint8List(stride);
      for (var y = 0; y < height; y += 1) {
        for (var x = 0; x < width; x += 1) {
          row.setRange(x * 3, x * 3 + 3, rgba, (y * width + x) * 4);
        }
        filtered.add(row);
        unfiltered.add(row);
      }
      return (filtered.finish().length, unfiltered.finish().length);
    }

    test('a cel — flat colours inside drawn lines: unfiltered', () async {
      final image = await paint(width, height, (canvas) {
        canvas.drawPaint(ui.Paint()..color = const ui.Color(0xFFFFFFFF));
        final random = math.Random(5);
        for (var i = 0; i < 14; i += 1) {
          final centre = ui.Offset(
            random.nextDouble() * width,
            random.nextDouble() * height,
          );
          final path = ui.Path()
            ..addOval(
              ui.Rect.fromCenter(
                center: centre,
                width: 40 + random.nextDouble() * 160,
                height: 30 + random.nextDouble() * 120,
              ),
            );
          canvas
            ..drawPath(
              path,
              ui.Paint()
                ..color = ui.Color(0xFF000000 | random.nextInt(1 << 24)),
            )
            ..drawPath(
              path,
              ui.Paint()
                ..color = const ui.Color(0xFF101010)
                ..style = ui.PaintingStyle.stroke
                ..strokeWidth = 2.2,
            );
        }
      });
      final (filtered, unfiltered) = await bothWays(image);
      expect(unfiltered, lessThan(filtered), reason: '⛔fixture premise');

      final png = await written(image, rgb);
      expect(pngRowFiltersOf(png, stride: stride), List.filled(height, 0));
    });

    test('a gradient: filtered', () async {
      final image = await paint(width, height, (canvas) {
        canvas.drawPaint(
          ui.Paint()
            ..shader = ui.Gradient.radial(
              const ui.Offset(width / 3, height / 2),
              width * 0.8,
              const [ui.Color(0xFF000000), ui.Color(0xFFFFE0C0)],
            ),
        );
      });
      final (filtered, unfiltered) = await bothWays(image);
      expect(filtered, lessThan(unfiltered), reason: '⛔fixture premise');

      final png = await written(image, rgb);
      expect(pngRowFiltersOf(png, stride: stride), contains(isNot(0)));
    });
  });
}
