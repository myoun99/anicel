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
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/models/transform_pose.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/services/bitmap_tile_rgba.dart';
import 'package:anicel/src/ui/sheet/sheet_image_cache.dart'
    show SheetImageLookup;
import 'package:anicel/src/ui/sheet/sheet_ink_layer.dart';
import 'package:anicel/src/ui/sheet/sheet_photos.dart';
import 'package:anicel/src/ui/sheet_painting.dart' show paintSheetInkWindow;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/a_canvas_standing_on_a_frame.dart';
import '../../helpers/checker_sampling.dart';

/// I-97 (유저 2026-10-15, I-97-Q1 b): a photo laid on a sheet stays a photo
/// — under the pen's ink, drawn from its own file where its reference
/// stands it. These ask what the sheet's ink shows ([SheetInkScreens]) one
/// pixel at a time, one surface pixel to a screen pixel — the one widget
/// that shows it with the brush on or off (F-215) — and the last group
/// holds an export's window to it.
void main() {
  opensTheEnginesScreens();
  const canvas = CanvasSize(width: 16, height: 16);
  const path = 'C:/pool/cyan.png';
  final key = envelopeInkBoxKey(const CutId('c'), 'box');
  final screen = GlobalKey();

  /// A [width]×[height] file all cyan, made off the test's clock.
  Future<ui.Image> cyanFile(WidgetTester tester, int width, int height) async {
    final recorder = ui.PictureRecorder();
    Canvas(
      recorder,
    ).drawColor(const Color(0xFF00FFFF), ui.BlendMode.src);
    final picture = recorder.endRecording();
    final file = (await tester.runAsync(() => picture.toImage(width, height)))!;
    picture.dispose();
    addTearDown(file.dispose);
    return file;
  }

  /// A [side]-pixel checker file ([checkerImage]), made off the test's
  /// clock.
  Future<ui.Image> checkerFile(WidgetTester tester, int side) async {
    final file = (await tester.runAsync(() => checkerImage(side)))!;
    addTearDown(file.dispose);
    return file;
  }

  /// A photo of [path], [size] of its own, posed by [pose].
  CelPhoto photo(TransformPose pose, CanvasSize size) => CelPhoto(
    id: 1,
    reference: MediaReference(assetPath: path, pose: pose, pictureSize: size),
  );

  /// The ink: one red pixel at (5, 5).
  BitmapSurface ink() => BitmapSurface(
    canvasSize: canvas,
    tileSize: 128,
    tiles: {
      TileCoord(x: 0, y: 0): writeRgbaColorToBitmapTile(
        tile: BitmapTile.blank(size: 128),
        x: 5,
        y: 5,
        color: RgbaColor(r: 255, g: 0, b: 0, a: 255),
      ),
    },
  );

  /// What [recorder] drew on 16×16 pixels: its RGBA bytes, row by row.
  Future<Uint8List> bytesOf(
    WidgetTester tester,
    ui.PictureRecorder recorder,
  ) async {
    final picture = recorder.endRecording();
    final bytes = (await tester.runAsync(() async {
      final image = await picture.toImage(16, 16);
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      image.dispose();
      return data!.buffer.asUint8List();
    }))!;
    picture.dispose();
    return bytes;
  }

  /// [surface] as the sheet's ink shows it through a window over the whole
  /// paper — or through [window] — one surface pixel to a screen pixel, or
  /// [zoom] of them, over nothing.
  Future<Uint8List> shown(
    WidgetTester tester,
    BitmapSurface surface,
    SheetImageLookup? imageFor, {
    double zoom = 1,
    Rect window = const Rect.fromLTWH(0, 0, 16, 16),
  }) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    final strokes = SheetInkStrokes();
    addTearDown(strokes.dispose);
    await tester.pumpWidget(
      onAScreen(
        screen,
        size: const Size(16, 16),
        under: const Color(0x00000000),
        view: SheetInkScreens(
          windows: [
            SheetInkWindow(
              id: 'box',
              key: key,
              placement: SheetInkPlacement(window: window, scale: 1),
            ),
          ],
          keyPrefix: 'envelope',
          viewport: CanvasViewport(zoom: zoom),
          surfaceOf: (_) => surface,
          strokes: strokes,
          inkChanges: Listenable.merge(const []),
          imageFor: imageFor,
        ),
      ),
    );
    await tester.pump();
    return (await shotOf(tester, screen)).rgba;
  }

  /// [photos] and the [raster] over them as an export draws the window
  /// [shown] shows (`paintSheetInkWindow`): in the paper's own space, a
  /// unit of it [zoom] pixels.
  Future<Uint8List> exported(
    WidgetTester tester,
    List<CelPhoto> photos,
    ui.Image? raster,
    SheetImageLookup? imageFor, {
    double zoom = 1,
    Rect window = const Rect.fromLTWH(0, 0, 16, 16),
  }) {
    final recorder = ui.PictureRecorder();
    paintSheetInkWindow(
      Canvas(recorder)..scale(zoom),
      raster,
      SheetInkPlacement(window: window, scale: 1),
      photos: photos,
      photoFiles: imageFor,
      displayScale: zoom,
    );
    return bytesOf(tester, recorder);
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
    final file = await cyanFile(tester, 4, 2);
    // 4×2 of its own, twice the size, centred at (8, 6): x 4–12, y 4–8.
    final surface = ink().withPhotos([
      photo(
        TransformPose(center: CanvasPoint(x: 8, y: 6), scaleX: 2, scaleY: 2),
        const CanvasSize(width: 4, height: 2),
      ),
    ]);

    final bytes = await shown(tester, surface, (asked, {width}) => file);

    expect(at(bytes, 4, 4), cyan, reason: 'its top-left pixel');
    expect(at(bytes, 11, 7), cyan, reason: 'its bottom-right pixel');
    expect(at(bytes, 3, 4), nothing, reason: 'left of it');
    expect(at(bytes, 12, 7), nothing, reason: 'right of it');
    expect(at(bytes, 8, 3), nothing, reason: 'above it');
    expect(at(bytes, 8, 8), nothing, reason: 'below it');
    expect(at(bytes, 5, 5), red, reason: 'the ink over it');
  });

  testWidgets('a turned photo turns about its centre', (tester) async {
    final file = await cyanFile(tester, 4, 2);
    // 4×2 turned a quarter about (8, 8): 2 wide and 4 tall, x 7–9, y 6–10.
    final surface = ink().withPhotos([
      photo(
        TransformPose(center: CanvasPoint(x: 8, y: 8), rotationDegrees: 90),
        const CanvasSize(width: 4, height: 2),
      ),
    ]);

    final bytes = await shown(tester, surface, (asked, {width}) => file);

    expect(at(bytes, 7, 6), cyan);
    expect(at(bytes, 8, 9), cyan);
    expect(at(bytes, 6, 8), nothing);
    expect(at(bytes, 9, 8), nothing);
    expect(at(bytes, 8, 5), nothing);
    expect(at(bytes, 8, 10), nothing);
  });

  testWidgets('a file that is not decoded yet leaves its place empty, and '
      'the ink shows as it did', (tester) async {
    final surface = ink().withPhotos([
      photo(
        TransformPose(center: CanvasPoint(x: 8, y: 6), scaleX: 2, scaleY: 2),
        const CanvasSize(width: 4, height: 2),
      ),
    ]);

    final waiting = await shown(tester, surface, (asked, {width}) => null);
    expect(at(waiting, 4, 4), nothing);
    expect(at(waiting, 5, 5), red);
    final none = await shown(tester, surface, null);
    expect(at(none, 4, 4), nothing);
  });

  test('a window\'s photos repaint when they change, and not when the same '
      'photos come again in a new list — as every build hands them', () {
    SheetPhotosPainter painterOf(List<CelPhoto> photos) => SheetPhotosPainter(
      photos: photos,
      viewport: CanvasViewport(),
      devicePixelRatio: 1,
      imageFor: (asked, {width}) => null,
    );
    CelPhoto at(double x) => photo(
      TransformPose(center: CanvasPoint(x: x, y: 8)),
      const CanvasSize(width: 4, height: 2),
    );

    expect(painterOf([at(9)]).shouldRepaint(painterOf([at(8)])), isTrue);
    expect(painterOf([at(8)]).shouldRepaint(painterOf([at(8)])), isFalse);
  });

  /// A 16×16 checker file's photo over the whole surface, laid at [scale].
  CelPhoto checkerOf(double scale) => photo(
    TransformPose(
      center: CanvasPoint(x: 8, y: 8),
      scaleX: scale,
      scaleY: scale,
    ),
    const CanvasSize(width: 16, height: 16),
  );

  /// A surface with no ink: [photos] alone.
  BitmapSurface bare(List<CelPhoto> photos) =>
      BitmapSurface(canvasSize: canvas, tileSize: 128, tiles: const {})
          .withPhotos(photos);

  bool grey(List<int> pixel) => pixel[0] > 100 && pixel[0] < 156;

  // The display's law (`filterQualityForDisplayScale`), asked of the photo's
  // own pixels: how many screen pixels one of them is — the view's zoom and
  // the photo's own scale both.
  group('a photo is sampled as the canvas samples a picture', () {
    for (final (name, zoom, scale, x, y) in const [
      ('the view shows it at half', 0.5, 1.0, 2, 2),
      ('it is laid at half', 1.0, 0.5, 5, 5),
    ]) {
      testWidgets('$name: smoothed, every pixel of it showing', (
        tester,
      ) async {
        final file = await checkerFile(tester, 16);

        final bytes = await shown(
          tester,
          bare([checkerOf(scale)]),
          (asked, {width}) => file,
          zoom: zoom,
        );

        expect(at(bytes, x, y), predicate(grey), reason: 'two of each');
      });
    }

    for (final (name, zoom, scale) in const [
      ('the view shows it at twice', 2.0, 1.0),
      ('it is laid at twice', 1.0, 2.0),
    ]) {
      testWidgets('$name: its pixels, hard-edged', (tester) async {
        final file = await checkerFile(tester, 16);

        final bytes = await shown(
          tester,
          bare([checkerOf(scale)]),
          (asked, {width}) => file,
          zoom: zoom,
        );

        for (var y = 0; y < 16; y += 1) {
          for (var x = 0; x < 16; x += 1) {
            expect(at(bytes, x, y)[0], predicate(isPure), reason: '($x, $y)');
          }
        }
      });
    }
  });

  // An export has no view to draw a window through: it lays the photos in
  // the paper's own space (`paintSheetInkWindow`) — and draws what the
  // screen shows at the same scale (유저 2026-09-17: 「보이는 중이랑
  // 결과랑 절대로 다르면 안 되」).
  group('an export draws a window\'s photos as the screen shows them', () {
    /// The raster an export composes of [ink]: one red pixel at (5, 5).
    Future<ui.Image> inkRaster(WidgetTester tester) async {
      final recorder = ui.PictureRecorder();
      Canvas(recorder).drawRect(
        const Rect.fromLTWH(5, 5, 1, 1),
        ui.Paint()..color = const Color(0xFFFF0000),
      );
      final picture = recorder.endRecording();
      final raster = (await tester.runAsync(() => picture.toImage(16, 16)))!;
      picture.dispose();
      addTearDown(raster.dispose);
      return raster;
    }

    testWidgets('where its reference stands it, under the ink', (
      tester,
    ) async {
      final file = await cyanFile(tester, 4, 2);
      final raster = await inkRaster(tester);
      final photos = [
        photo(
          TransformPose(center: CanvasPoint(x: 8, y: 6), scaleX: 2, scaleY: 2),
          const CanvasSize(width: 4, height: 2),
        ),
      ];

      final bytes = await exported(
        tester,
        photos,
        raster,
        (asked, {width}) => file,
      );

      expect(at(bytes, 4, 4), cyan, reason: 'LIVENESS: it exported');
      expect(at(bytes, 5, 5), red, reason: 'the ink over it');
      expect(
        bytes,
        await shown(
          tester,
          ink().withPhotos(photos),
          (asked, {width}) => file,
        ),
      );
    });

    testWidgets('turned, and with no ink of its own', (tester) async {
      final file = await cyanFile(tester, 4, 2);
      final photos = [
        photo(
          TransformPose(center: CanvasPoint(x: 8, y: 8), rotationDegrees: 90),
          const CanvasSize(width: 4, height: 2),
        ),
      ];

      final bytes = await exported(
        tester,
        photos,
        null,
        (asked, {width}) => file,
      );

      expect(at(bytes, 7, 6), cyan, reason: 'LIVENESS: it exported');
      expect(
        bytes,
        await shown(tester, bare(photos), (asked, {width}) => file),
      );
    });

    testWidgets('cut by its window', (tester) async {
      final file = await cyanFile(tester, 4, 2);
      // x 4–12, through a window 8 wide.
      final photos = [
        photo(
          TransformPose(center: CanvasPoint(x: 8, y: 6), scaleX: 2, scaleY: 2),
          const CanvasSize(width: 4, height: 2),
        ),
      ];
      const window = Rect.fromLTWH(0, 0, 8, 16);

      final bytes = await exported(
        tester,
        photos,
        null,
        (asked, {width}) => file,
        window: window,
      );

      expect(at(bytes, 7, 4), cyan, reason: 'inside the window');
      expect(at(bytes, 8, 4), nothing, reason: 'past it');
      expect(
        bytes,
        await shown(
          tester,
          bare(photos),
          (asked, {width}) => file,
          window: window,
        ),
      );
    });

    for (final (name, zoom, scale, x, y) in const [
      ('shown at half', 0.5, 1.0, 2, 2),
      ('shown at twice', 2.0, 1.0, 8, 8),
      ('laid at half', 1.0, 0.5, 5, 5),
    ]) {
      testWidgets('sampled as the screen samples it — $name', (tester) async {
        final file = await checkerFile(tester, 16);
        final photos = [checkerOf(scale)];

        final bytes = await exported(
          tester,
          photos,
          null,
          (asked, {width}) => file,
          zoom: zoom,
        );

        expect(at(bytes, x, y), isNot(nothing), reason: 'LIVENESS');
        expect(
          bytes,
          await shown(
            tester,
            bare(photos),
            (asked, {width}) => file,
            zoom: zoom,
          ),
        );
      });
    }
  });
}
