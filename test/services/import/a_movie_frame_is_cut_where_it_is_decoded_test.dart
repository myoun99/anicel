// A movie's frame laid on a cel is read where the movie is decoded
// (card a-raster-import-goes-gpu-cpu-gpu-cpu): laid 1:1 — a movie row's
// cel — it is cut into the cel's tiles there and only the tiles' blocks
// come back; laid otherwise it is cut into tiles of its own there, which
// the lay reads. ↩️A frame within the engine's side was uploaded
// premultiplied and laid from the engine's image: rastered, read back, cut,
// laid on the engine and read back again.
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:anicel/src/core/rgba_premultiply.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/native/qa_video_decoder.dart';
import 'package:anicel/src/services/guide_geometry.dart' show GuideTransform;
import 'package:anicel/src/services/import/cel_picture.dart';
import 'package:anicel/src/services/import/raster_cel_import.dart';
import 'package:anicel/src/services/import/tile_cutter.dart';
import 'package:anicel/src/services/media/video_decode_worker.dart';
import 'package:anicel/src/services/persistence/brush_drawing_binary_codec.dart'
    show laidCelSurface;
import 'package:anicel/src/services/straight_rgba_image.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_video_backend.dart';
import '../../helpers/os_video_codec.dart';

void main() {
  const width = 150;
  const height = 90;
  const canvas = CanvasSize(width: 64, height: 48);

  /// A [width] × [height] frame that shows a slip anywhere: each pixel its
  /// own colour, a clear corner a tile wide — opaque, as a movie's frames
  /// are, unless [partial] makes a band of it half clear.
  Uint8List frameOf({bool partial = false}) {
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
        rgba[i + 3] = partial && x < 80 ? 128 : 255;
      }
    }
    return rgba;
  }

  /// [ours] against [theirs] tile for tile, byte for byte.
  void expectSameCel(BitmapSurface ours, BitmapSurface theirs) {
    expect(ours.laidBounds, theirs.laidBounds);
    expect(ours.tiles.keys, unorderedEquals(theirs.tiles.keys));
    for (final MapEntry(key: coord, value: tile) in theirs.tiles.entries) {
      expect(
        Uint8List.fromList(ours.tiles[coord]!.pixels),
        orderedEquals(Uint8List.fromList(tile.pixels)),
        reason: '$coord',
      );
    }
  }

  const oneToOne = GuideTransform(1, 0, 0, 1, 37, 21);
  const halved = GuideTransform(0.5, 0, 0, 0.5, 3, 2);

  Future<BitmapSurface> laid(CelPicture picture, GuideTransform placement) =>
      layCelPicture(
        picture: picture,
        canvas: canvas,
        placement: placement,
        whole: true,
      );

  group('laid 1:1 — a movie row\'s cel', () {
    late List<Uint8List> uploaded;

    setUp(() {
      uploaded = [];
      debugRawRgbaUploader =
          (rgba, {required width, required height, targetWidth, targetHeight}) {
            uploaded.add(Uint8List.fromList(rgba));
            return Future<ui.Image>.error(StateError('uploaded'));
          };
    });
    tearDown(() => debugRawRgbaUploader = null);

    testWidgets('🎯is cut where the frame is decoded: the frame itself never '
        'comes here, nor is it made an engine image', (tester) async {
      await tester.runAsync(() async {
        final backend = _Asked(frameOf());
        final ours = await laid(backend.picture(2), oneToOne);

        expect(backend.forms, ['cut 2']);
        expect(uploaded, isEmpty);
        expect(ours.tiles, isNotEmpty);
      });
    });

    testWidgets('its tiles are the ones the engine laid from the frame '
        'uploaded as its decoder\'s side premultiplied it', (tester) async {
      await tester.runAsync(() async {
        final frame = frameOf();
        final ours = await laid(_Asked(frame).picture(2), oneToOne);
        debugRawRgbaUploader = null;
        final engine = EnginePicture(
          await uploadRawRgba(
            premultipliedRgbaCopy(frame),
            width: width,
            height: height,
          ),
        );
        final theirs = await laid(engine, oneToOne);
        engine.dispose();

        expectSameCel(ours, theirs);
      });
    });

    testWidgets('a frame that is not opaque keeps its colours as the decoder '
        'gave them', (tester) async {
      await tester.runAsync(() async {
        final frame = frameOf(partial: true);
        final ours = await laid(_Asked(frame).picture(2), oneToOne);

        expectSameCel(
          ours,
          await laid(
            PixelsPicture(frame, width: width, height: height),
            oneToOne,
          ),
        );
      });
    });
  });

  testWidgets('🎯laid otherwise, the frame is cut into its own tiles where '
      'it is decoded, and laid from them as a picture in hand is', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final frame = frameOf(partial: true);
      final backend = _Asked(frame);
      final ours = await laid(backend.picture(2), halved);

      expect(backend.forms, ['cut 2']);
      expectSameCel(
        ours,
        await laid(PixelsPicture(frame, width: width, height: height), halved),
      );
    });
  });

  test('a frame its decoder does not give is said as it is laid, either '
      'way', () async {
    final backend = _Asked(frameOf())..held.add(2);
    for (final placement in [oneToOne, halved]) {
      await expectLater(
        laid(backend.picture(2), placement),
        throwsA(
          isA<MovieFrameUnread>().having(
            (unread) => '$unread',
            'said',
            'Movie frame 2 did not decode.',
          ),
        ),
      );
    }
  });

  group('the decoder\'s side', () {
    const movie = 'test/fixtures/tone_with_video.mp4';

    tearDown(QaVideoDecoder.instance.close);

    /// The cut of a [info]-sized frame laid 1:1 at (5, 3) on a cel of its
    /// own size and more.
    PictureCut cutOf(QaVideoInfo info) {
      final layout = (
        canvas: CanvasSize(width: info.width + 5, height: info.height + 3),
        tileSize: 128,
        tiles: (
          firstX: 0,
          lastX: (info.width + 4) ~/ 128,
          firstY: 0,
          lastY: (info.height + 2) ~/ 128,
        ),
        laid: null,
      );
      return (left: 5, top: 3, layout: layout);
    }

    test('🎯the worker cuts the frame its frame arm hands, and only the '
        'tiles cross back', () async {
      if (osVideoDecoderOrSkip() == null) {
        return;
      }
      final worker = IsolateVideoDecodeBackend();
      final opened = (await worker.open(movie))!;
      final cut = cutOf(opened.info);
      final tiles = await worker.cutFrame(opened.token, 3, tileCutOf(cut));
      final straight = (await worker.frame(opened.token, 3))!;
      await worker.close(opened.token);

      expect(tiles, isNotNull, reason: await worker.lastError());
      expectSameCel(
        laidCelSurface(laidCelOf(cut.layout, tiles!)),
        laidCelSurface(
          cutPixels(
            PixelsPicture(
              straight,
              width: opened.info.width,
              height: opened.info.height,
            ),
            cut,
          ),
        ),
      );
    });

    test('the caller\'s own decode cuts as the worker does', () async {
      if (osVideoDecoderOrSkip() == null) {
        return;
      }
      const direct = DirectVideoDecodeBackend();
      final here = (await direct.open(movie))!;
      final cut = cutOf(here.info);
      final fromHere = await direct.cutFrame(here.token, 3, tileCutOf(cut));
      await direct.close(here.token);

      final worker = IsolateVideoDecodeBackend();
      final there = (await worker.open(movie))!;
      final fromThere = await worker.cutFrame(there.token, 3, tileCutOf(cut));
      await worker.close(there.token);

      expectSameCel(
        laidCelSurface(laidCelOf(cut.layout, fromHere!)),
        laidCelSurface(laidCelOf(cut.layout, fromThere!)),
      );
    });

    test('a frame that is not there is cut into nothing and said so', () async {
      if (osVideoDecoderOrSkip() == null) {
        return;
      }
      final worker = IsolateVideoDecodeBackend();
      final opened = (await worker.open(movie))!;
      final missing = await worker.cutFrame(
        opened.token + 1,
        3,
        tileCutOf(cutOf(opened.info)),
      );
      await worker.close(opened.token);

      expect(missing, isNull);
    });
  });
}

/// A movie of one painted frame that records which form was asked for.
final class _Asked extends FakeVideoBackend {
  _Asked(this.painted)
    : super(width: 150, height: 90, paint: (_) => painted);

  final Uint8List painted;

  final List<String> forms = [];

  /// Frame [index] of this movie as a picture an import lays.
  MovieFramePicture picture(int index) => MovieFramePicture(
    this,
    1,
    index,
    QaVideoInfo(
      width: width,
      height: height,
      frameCount: frameCount,
      fpsNumerator: fpsNumerator,
      fpsDenominator: fpsDenominator,
    ),
  );

  @override
  Future<Uint8List?> frame(int token, int index) async {
    forms.add('straight $index');
    return held.contains(index) ? null : Uint8List.fromList(painted);
  }

  @override
  Future<CutTiles?> cutFrame(int token, int index, TileCut cut) async {
    forms.add('cut $index');
    return held.contains(index)
        ? null
        : cutRgbaRows(painted, width: width, height: height, cut: cut);
  }
}
