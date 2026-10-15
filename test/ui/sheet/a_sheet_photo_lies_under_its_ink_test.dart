import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/models/cel_photo.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/envelope/cut_envelope_ink_keys.dart';
import 'package:anicel/src/models/media_reference.dart';
import 'package:anicel/src/models/rgba_color.dart';
import 'package:anicel/src/models/sheet_marks.dart';
import 'package:anicel/src/models/sheet_paint_layer.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/models/transform_pose.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/services/bitmap_tile_rgba.dart';
import 'package:anicel/src/ui/sheet/sheet_ink_layer.dart';
import 'package:flutter/material.dart' show Canvas, Color, Rect, Size;
import 'package:flutter_test/flutter_test.dart';

/// I-97 (유저 2026-10-15, I-97-Q1 b): a photo laid on a sheet stays a photo
/// — under the pen's ink, drawn from its own file where its reference
/// stands it. These ask the print (`printSheetInkAsLive`) one pixel at a
/// time, one surface pixel to a screen pixel; the brush switch's own pins
/// hold the live window to the very same pixels
/// (`the_brush_switch_repaints_nothing_test`,
/// `a_picture_takes_the_pen_into_its_blocks_cel_test`).
void main() {
  const canvas = CanvasSize(width: 16, height: 16);
  const path = 'C:/pool/cyan.png';
  final key = envelopeInkBoxKey(const CutId('c'), 'box');

  /// A [width]×[height] file all cyan.
  Future<ui.Image> cyanFile(int width, int height) {
    final recorder = ui.PictureRecorder();
    Canvas(
      recorder,
    ).drawColor(const Color(0xFF00FFFF), ui.BlendMode.src);
    return recorder.endRecording().toImage(width, height);
  }

  /// A photo of [path], [size] of its own, posed by [pose].
  CelPhoto photo(TransformPose pose, CanvasSize size) => CelPhoto(
    id: 1,
    reference: MediaReference(assetPath: path, pose: pose, pictureSize: size),
  );

  /// The ink: one red pixel at (5, 5).
  BitmapSurface ink() => BitmapSurface(
    canvasSize: canvas,
    tileSize: 8,
    tiles: {
      TileCoord(x: 0, y: 0): writeRgbaColorToBitmapTile(
        tile: BitmapTile.blank(size: 8),
        x: 5,
        y: 5,
        color: RgbaColor(r: 255, g: 0, b: 0, a: 255),
      ),
    },
  );

  /// [surface] printed through a window over the whole paper, one surface
  /// pixel to a screen pixel — its RGBA bytes, row by row.
  Future<Uint8List> printed(
    BitmapSurface surface,
    ui.Image? Function(String assetPath)? imageFor,
  ) async {
    final recorder = ui.PictureRecorder();
    printSheetInkAsLive(
      Canvas(recorder),
      [
        SheetInk(
          SheetPaintLayer.ink,
          key: key,
          placement: const SheetInkPlacement(
            window: Rect.fromLTWH(0, 0, 16, 16),
            scale: 1,
          ),
        ),
      ],
      (_) => surface,
      (
        viewport: CanvasViewport(),
        devicePixelRatio: 1,
        size: const Size(16, 16),
        above: const [],
        imageFor: imageFor,
      ),
    );
    final image = await recorder.endRecording().toImage(16, 16);
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    image.dispose();
    return data!.buffer.asUint8List();
  }

  List<int> at(Uint8List bytes, int x, int y) {
    final o = (y * 16 + x) * 4;
    return [bytes[o], bytes[o + 1], bytes[o + 2], bytes[o + 3]];
  }

  const cyan = [0, 255, 255, 255];
  const red = [255, 0, 0, 255];
  const nothing = [0, 0, 0, 0];

  testWidgets('a photo stands where its reference stands it — its own '
      'pixels scaled about its centre — and the ink lies over it', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final file = await cyanFile(4, 2);
      addTearDown(file.dispose);
      // 4×2 of its own, twice the size, centred at (8, 6): x 4–12, y 4–8.
      final surface = ink().withPhotos([
        photo(
          TransformPose(
            center: CanvasPoint(x: 8, y: 6),
            scaleX: 2,
            scaleY: 2,
          ),
          const CanvasSize(width: 4, height: 2),
        ),
      ]);

      final bytes = await printed(surface, (asked) => file);

      expect(at(bytes, 4, 4), cyan, reason: 'its top-left pixel');
      expect(at(bytes, 11, 7), cyan, reason: 'its bottom-right pixel');
      expect(at(bytes, 3, 4), nothing, reason: 'left of it');
      expect(at(bytes, 12, 7), nothing, reason: 'right of it');
      expect(at(bytes, 8, 3), nothing, reason: 'above it');
      expect(at(bytes, 8, 8), nothing, reason: 'below it');
      expect(at(bytes, 5, 5), red, reason: 'the ink over it');
    });
  });

  testWidgets('a turned photo turns about its centre', (tester) async {
    await tester.runAsync(() async {
      final file = await cyanFile(4, 2);
      addTearDown(file.dispose);
      // 4×2 turned a quarter about (8, 8): 2 wide and 4 tall, x 7–9, y 6–10.
      final surface = ink().withPhotos([
        photo(
          TransformPose(center: CanvasPoint(x: 8, y: 8), rotationDegrees: 90),
          const CanvasSize(width: 4, height: 2),
        ),
      ]);

      final bytes = await printed(surface, (asked) => file);

      expect(at(bytes, 7, 6), cyan);
      expect(at(bytes, 8, 9), cyan);
      expect(at(bytes, 6, 8), nothing);
      expect(at(bytes, 9, 8), nothing);
      expect(at(bytes, 8, 5), nothing);
      expect(at(bytes, 8, 10), nothing);
    });
  });

  testWidgets('a file that is not decoded yet leaves its place empty, and '
      'the ink prints as it did', (tester) async {
    await tester.runAsync(() async {
      final surface = ink().withPhotos([
        photo(
          TransformPose(center: CanvasPoint(x: 8, y: 6), scaleX: 2, scaleY: 2),
          const CanvasSize(width: 4, height: 2),
        ),
      ]);

      final waiting = await printed(surface, (asked) => null);
      final none = await printed(surface, null);

      expect(at(waiting, 4, 4), nothing);
      expect(at(none, 4, 4), nothing);
      expect(at(waiting, 5, 5), red);
    });
  });
}
