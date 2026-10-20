import 'dart:io';
import 'dart:typed_data';

import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/core/on_a_worker.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/dirty_region.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/media_asset.dart';
import 'package:anicel/src/services/brush_stroke_blend.dart'
    show bitmapSurfaceRegionPixels;
import 'package:anicel/src/services/guide_geometry.dart' show GuideTransform;
import 'package:anicel/src/services/import/cel_picture.dart';
import 'package:anicel/src/services/import/media_import_planner.dart';
import 'package:anicel/src/services/import/psd_expand_import.dart';
import 'package:anicel/src/services/import/raster_cel_import.dart';
import 'package:anicel/src/services/media/animated_png_writer.dart';
import 'package:anicel/src/services/media/png_writing.dart'
    show pngChunk, pngRgba, pngSignature, pngUint32;
import 'package:anicel/src/services/straight_rgba_image.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import '../../helpers/engine_pixels.dart';
import '../../helpers/psd_fixture.dart';
import '../../helpers/temp_dir.dart';

/// 🗣️유저 2026-10-18 (a-picture-past-the-texture-limit-is-decoded-squashed
/// -Q1): 「원본 해상도 그대로 — GPU 를 거치지 않는 디코더로 블록씩 읽는다」 ·
/// 「메모리/시간관련 대가는 최대한 개선하면서 해결」. A picture longer on a
/// side than this device's engine hands back is held off it at its own size
/// and laid as the engine lays a picture it holds. 🧪The test engine cuts
/// nothing, so the side is named here ([debugPictureSideLimit]): a picture
/// past 64 in these tests is one past 16384 on the Surface.
void main() {
  setUp(() => debugPictureSideLimit = 64);
  tearDown(() {
    debugPictureSideLimit = null;
    debugLayRasterSide = null;
    debugWorkersRunHere = true;
  });

  /// [width] × [height] of straight RGBA that shows a slip anywhere: each
  /// pixel its own colour, a clear corner a tile wide, a band half clear.
  Uint8List patterned(int width, int height) {
    final rgba = Uint8List(width * height * 4);
    for (var y = 0; y < height; y += 1) {
      for (var x = 0; x < width; x += 1) {
        if (x < 64 && y < 64) {
          continue;
        }
        final i = (y * width + x) * 4;
        rgba[i] = x * 5 % 256;
        rgba[i + 1] = y * 9 % 256;
        rgba[i + 2] = (x + y) * 3 % 256;
        rgba[i + 3] = x < 80 ? 128 : 255;
      }
    }
    return rgba;
  }

  img.Image imageOf(Uint8List rgba, int width, int height) => img.Image.fromBytes(
    width: width,
    height: height,
    bytes: rgba.buffer,
    numChannels: 4,
  );

  Uint8List pngOf(Uint8List rgba, int width, int height) =>
      img.encodePng(imageOf(rgba, width, height));

  /// [rgba] as an interlaced PNG, which the image package reads and does not
  /// write: Adam7's seven passes, each row unfiltered.
  Uint8List interlacedPngOf(Uint8List rgba, int width, int height) {
    const passes = [
      (x: 0, y: 0, dx: 8, dy: 8),
      (x: 4, y: 0, dx: 8, dy: 8),
      (x: 0, y: 4, dx: 4, dy: 8),
      (x: 2, y: 0, dx: 4, dy: 4),
      (x: 0, y: 2, dx: 2, dy: 4),
      (x: 1, y: 0, dx: 2, dy: 2),
      (x: 0, y: 1, dx: 1, dy: 2),
    ];
    final rows = BytesBuilder();
    for (final pass in passes) {
      for (var y = pass.y; y < height && pass.x < width; y += pass.dy) {
        rows.addByte(0);
        for (var x = pass.x; x < width; x += pass.dx) {
          final at = (y * width + x) * 4;
          rows.add(Uint8List.sublistView(rgba, at, at + 4));
        }
      }
    }
    return Uint8List.fromList([
      ...pngSignature,
      ...pngChunk('IHDR', [
        ...pngUint32(width),
        ...pngUint32(height),
        8, // bit depth
        pngRgba,
        0, 0, 1, // compression, filter, interlace (Adam7)
      ]),
      ...pngChunk('IDAT', zlib.encode(rows.takeBytes())),
      ...pngChunk('IEND', const []),
    ]);
  }

  /// [rgba] as the engine holds it.
  Future<EnginePicture> engineOf(Uint8List rgba, int width, int height) async =>
      EnginePicture(
        await decodeStraightRgbaImage(rgba: rgba, width: width, height: height),
      );

  /// [ours] against [theirs] tile for tile: the same tiles, where the same
  /// picture says it lies, each the same pixels ([expectSamePixels]) —
  /// [colourSlack] apart where a raster resamples.
  void expectSameCel(
    BitmapSurface ours,
    BitmapSurface theirs, {
    int colourSlack = 0,
  }) {
    expect(ours.laidBounds, theirs.laidBounds);
    expect(ours.tiles.keys, unorderedEquals(theirs.tiles.keys));
    for (final MapEntry(key: coord, value: tile) in theirs.tiles.entries) {
      expectSamePixels(
        Uint8List.fromList(ours.tiles[coord]!.pixels),
        Uint8List.fromList(tile.pixels),
        colourSlack: colourSlack,
      );
    }
  }

  group('held off the engine', () {
    testWidgets('🎯a picture longer than the side is held at its own size; '
        'one at the side is the engine\'s', (tester) async {
      await tester.runAsync(() async {
        final past = await decodeImageFrames(
          pngOf(patterned(100, 20), 100, 20),
        );
        final at = await decodeImageFrames(pngOf(patterned(64, 20), 64, 20));

        expect(past.single.picture, isA<FilePicture>());
        expect(
          past.single.picture.size,
          const CanvasSize(width: 100, height: 20),
        );
        expect(at.single.picture, isA<EnginePicture>());
        at.single.picture.dispose();
      });
    });

    /// What [decodeImageFrames] holds of [bytes], frame for frame, against
    /// what the engine decodes of them.
    Future<void> readAsTheEngine(
      Uint8List bytes, {
      int colourSlack = 0,
    }) async {
      final theirs = await engineFrames(bytes);
      final ours = await decodeImageFrames(bytes);
      expect(ours, hasLength(theirs.length));
      for (final (i, frame) in ours.indexed) {
        expect(frame.picture, isNot(isA<EnginePicture>()), reason: '$i');
        expect(
          frame.picture.size,
          CanvasSize(width: theirs[i].width, height: theirs[i].height),
        );
        expect(frame.duration, theirs[i].duration, reason: 'frame $i');
        expectSamePixels(
          await frame.picture.straightRgba(),
          theirs[i].rgba,
          colourSlack: colourSlack,
        );
      }
    }

    /// 100 × 20, opaque — what a BMP or a JPEG holds.
    img.Image opaque() {
      final image = img.Image(width: 100, height: 20);
      for (final p in image) {
        p
          ..r = p.x * 5 % 256
          ..g = p.y * 9 % 256
          ..b = (p.x + p.y) * 3 % 256;
      }
      return image;
    }

    testWidgets('a PNG, read a row at a time', (tester) async {
      await tester.runAsync(
        () => readAsTheEngine(pngOf(patterned(100, 20), 100, 20)),
      );
    });

    testWidgets('a BMP', (tester) async {
      await tester.runAsync(() => readAsTheEngine(img.encodeBmp(opaque())));
    });

    /// 100 × 20 whose clear pixels still carry a colour, as a file's may.
    Uint8List clearKeepingColour() {
      final rgba = patterned(100, 20);
      for (var i = 0; i < rgba.length; i += 4) {
        if (rgba[i + 3] == 0) {
          rgba
            ..[i] = 200
            ..[i + 1] = 100
            ..[i + 2] = 50;
        }
      }
      return rgba;
    }

    testWidgets('a BMP that has alpha, a clear pixel all zero', (
      tester,
    ) async {
      await tester.runAsync(
        () => readAsTheEngine(
          img.encodeBmp(imageOf(clearKeepingColour(), 100, 20)),
        ),
      );
    });

    testWidgets('an interlaced PNG, read whole by the package', (
      tester,
    ) async {
      await tester.runAsync(
        () => readAsTheEngine(interlacedPngOf(clearKeepingColour(), 100, 20)),
      );
    });

    testWidgets('a GIF with a clear colour, a clear pixel all zero', (
      tester,
    ) async {
      final image = img.Image(
        width: 100,
        height: 20,
        withPalette: true,
        numChannels: 4,
      );
      for (var i = 0; i < 256; i += 1) {
        image.palette!.setRgba(
          i,
          i * 53 % 256,
          i * 97 % 256,
          i * 31 % 256,
          i == 1 ? 0 : 255,
        );
      }
      for (var y = 0; y < 20; y += 1) {
        for (var x = 0; x < 100; x += 1) {
          image.setPixelR(x, y, (x + y * 3) % 256);
        }
      }
      await tester.runAsync(() => readAsTheEngine(img.encodeGif(image)));
    });

    testWidgets('a JPEG', (tester) async {
      await tester.runAsync(
        () => readAsTheEngine(
          img.encodeJpg(opaque(), quality: 95),
          colourSlack: 8,
        ),
      );
    });

    testWidgets('a JPEG its EXIF turns, turned as the engine turns it', (
      tester,
    ) async {
      final turned = opaque()..exif.imageIfd.orientation = 6;
      await tester.runAsync(
        () => readAsTheEngine(
          img.encodeJpg(turned, quality: 95),
          colourSlack: 8,
        ),
      );
    });

    testWidgets('a GIF, every frame as long as it shows', (tester) async {
      final gif = opaque()..frameDuration = 40;
      for (final (shift, duration) in [(40, 80), (90, 120)]) {
        final frame = img.Image(width: 100, height: 20)
          ..frameDuration = duration;
        for (final p in frame) {
          p
            ..r = (p.x + shift) * 5 % 256
            ..g = p.y * 9 % 256
            ..b = 200;
        }
        gif.addFrame(frame);
      }
      await tester.runAsync(() => readAsTheEngine(img.encodeGif(gif)));
    });

    testWidgets('an animated PNG, every frame as long as it shows', (
      tester,
    ) async {
      final second = patterned(100, 20);
      for (var i = 0; i < second.length; i += 4) {
        second[i + 2] = 255 - second[i + 2];
      }
      final png = encodeAnimatedPng(
        width: 100,
        height: 20,
        frames: [
          (
            rgba: patterned(100, 20),
            duration: const Duration(milliseconds: 40),
          ),
          (rgba: second, duration: const Duration(milliseconds: 80)),
        ],
      );
      await tester.runAsync(() => readAsTheEngine(png));
    });
  });

  group('laid 1:1, its rows are cut into the tiles the engine lays', () {
    const canvas = CanvasSize(width: 64, height: 48);

    for (final (dx, dy) in [(0, 0), (37, 21), (-130, -7)]) {
      for (final whole in [false, true]) {
        testWidgets('at ($dx, $dy)${whole ? ', laid whole' : ''}', (
          tester,
        ) async {
          await tester.runAsync(() async {
            final rgba = patterned(150, 90);
            final placement = GuideTransform(
              1,
              0,
              0,
              1,
              dx.toDouble(),
              dy.toDouble(),
            );
            Future<BitmapSurface> laid(CelPicture picture) => layCelPicture(
              picture: picture,
              canvas: canvas,
              placement: placement,
              tileSize: 64,
              whole: whole,
            );
            final engine = await engineOf(rgba, 150, 90);
            final theirs = await laid(engine);
            engine.dispose();

            expectSameCel(
              await laid(FilePicture(pngOf(rgba, 150, 90), width: 150, height: 90)),
              theirs,
            );
            expectSameCel(
              await laid(PixelsPicture(rgba, width: 150, height: 90)),
              theirs,
            );
          });
        });
      }
    }

    testWidgets('on a real worker, in the blocks of the isolate that keeps '
        'them', (tester) async {
      await tester.runAsync(() async {
        final rgba = patterned(150, 90);
        const placement = GuideTransform(1, 0, 0, 1, 37, 21);
        final engine = await engineOf(rgba, 150, 90);
        final theirs = await layCelPicture(
          picture: engine,
          canvas: canvas,
          placement: placement,
          tileSize: 64,
          whole: true,
        );
        engine.dispose();

        debugWorkersRunHere = false;
        expectSameCel(
          await layCelPicture(
            picture: FilePicture(
              pngOf(rgba, 150, 90),
              width: 150,
              height: 90,
            ),
            canvas: canvas,
            placement: placement,
            tileSize: 64,
            whole: true,
          ),
          theirs,
        );
      });
    });
  });

  group('laid otherwise, resampled as the engine resamples', () {
    const canvas = CanvasSize(width: 256, height: 192);

    Future<BitmapSurface> laid(CelPicture picture, GuideTransform placement) =>
        layCelPicture(
          picture: picture,
          canvas: canvas,
          placement: placement,
          tileSize: 64,
          whole: true,
        );

    // A part's reach is what one raster takes: at the side named, a block of
    // tiles is laid from parts of the picture, never the picture whole. A
    // part is drawn where it lies in the picture, and a pixel resampled from
    // it can round a step apart — as one laid in a block of tiles of its own
    // does (`raster_identity_test`).
    for (final (how, width, side, placement) in [
      ('shrunk by 0.6', 300, 256, const GuideTransform(0.6, 0, 0, 0.6, 10, 5)),
      (
        '🎯shrunk past half, read whole as the engine reads it — not halved',
        300,
        256,
        const GuideTransform(0.3, 0, 0, 0.3, 3, 7),
      ),
      (
        'shrunk past half across alone',
        1200,
        512,
        const GuideTransform(0.2, 0, 0, 0.9, 3, 7),
      ),
    ]) {
      testWidgets('$how, a part at a time', (tester) async {
        await tester.runAsync(() async {
          final rgba = patterned(width, 200);
          debugLayRasterSide = side;
          final engine = await engineOf(rgba, width, 200);
          debugLayRasters = 0;
          final theirs = await laid(engine, placement);
          final blocks = debugLayRasters;
          engine.dispose();

          for (final held in [
            PixelsPicture(rgba, width: width, height: 200),
            FilePicture(pngOf(rgba, width, 200), width: width, height: 200),
          ]) {
            debugLayRasters = 0;
            expectSameCel(await laid(held, placement), theirs, colourSlack: 1);
            expect(debugLayRasters, greaterThan(blocks), reason: 'in parts');
          }
        });
      });
    }
  });

  group('a Photoshop document past the side', () {
    testWidgets('its composite is held at its own size', (tester) async {
      await tester.runAsync(() async {
        final frames = await decodeImageFrames(
          buildPsd(
            width: 100,
            height: 60,
            compositePlanes: psdSolidPlanes(100, 60, [200, 30, 0]),
          ),
        );
        final picture = frames.single.picture;
        expect(picture, isA<PixelsPicture>());
        expect(picture.size, const CanvasSize(width: 100, height: 60));
        final rgba = await picture.straightRgba();
        expect(rgba.sublist(0, 4), [200, 30, 0, 255]);
        expect(rgba.sublist(rgba.length - 4), [200, 30, 0, 255]);
      });
    });

    testWidgets('its layers are laid as the engine lays them', (tester) async {
      Future<BitmapSurface> expandedLayer() async {
        var layers = 0;
        var frames = 0;
        final expansion = await readPsdExpansion(
          bytes: buildPsd(
            width: 100,
            height: 60,
            layers: [
              PsdTestLayer(
                name: 'wide',
                left: -10,
                top: 5,
                right: 90,
                bottom: 55,
                planes: [
                  for (final step in [5, 9, 3])
                    Uint8List.fromList([
                      for (var y = 0; y < 50; y += 1)
                        for (var x = 0; x < 100; x += 1) (x + y) * step % 256,
                    ]),
                ],
              ),
            ],
          ),
          displayName: 'wide.psd',
          cutId: const CutId('c'),
          duration: 12,
          canvas: const CanvasSize(width: 1, height: 1),
          fit: MediaFitMode.none,
          mint: ImportIdMint(
            nextLayerId: () => LayerId('L${layers += 1}'),
            nextFrameId: (_) => FrameId('F${frames += 1}'),
            nextCutId: () => const CutId('C1'),
          ),
          canvasFromDocument: true,
        );
        return expansion!.cels.single.surface;
      }

      await tester.runAsync(() async {
        final held = await expandedLayer();
        debugPictureSideLimit = null;
        expectSameCel(held, await expandedLayer());
      });
    });
  });

  group('through the door', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('anicel-past-the-side');
    });

    tearDown(() => deleteTempQuietly(tempDir));

    testWidgets('🎯opened as a cut, a picture past the side makes the cut, '
        'the reference and the cel at its own size — the file\'s pixels', (
      tester,
    ) async {
      final s = EditorSessionManager(initialProject: createDefaultProject());
      addTearDown(s.dispose);
      final rgba = patterned(100, 20);
      final path = '${tempDir.path}/wide.png';
      await tester.runAsync(() => File(path).writeAsBytes(pngOf(rgba, 100, 20)));

      final landed = await tester.runAsync(
        () => s.importDoors.importImageFile(
          path: path,
          destination: ImportDestination.newCut,
          copyIntoProject: false,
        ),
      );

      expect(landed, isTrue);
      final cut = s.requireActiveCut;
      expect(cut.canvasSize, const CanvasSize(width: 100, height: 20));
      final row = cut.layers.firstWhere(
        (layer) => layer.mediaReference != null,
      );
      expect(
        row.mediaReference!.pictureSize,
        const CanvasSize(width: 100, height: 20),
      );
      final cel = s.renderCaches.brushFrameStore.bakedSurfaceOrNull(
        s.brushFrameKeyForCut(cut, row.id, row.frames.single.id),
      );
      expectSamePixels(
        bitmapSurfaceRegionPixels(
          cel!,
          DirtyRegion(
            left: 0,
            top: 0,
            rightExclusive: 100,
            bottomExclusive: 20,
          ),
        ),
        rgba,
      );
      await tester.pump(const Duration(minutes: 1));
      s.playbackRig.prerenderScheduler.cancel();
      await tester.pump();
    });
  });
}
