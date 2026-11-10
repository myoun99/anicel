import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/layer_blend_mode.dart';
import 'package:anicel/src/models/layer_effect.dart';
import 'package:anicel/src/models/pasteboard_bounds.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/models/transform_pose.dart';
import 'package:anicel/src/services/import/cel_picture.dart';
import 'package:anicel/src/ui/canvas/image_pieces.dart';
import 'package:anicel/src/ui/canvas/layer_image_draw.dart';
import 'package:anicel/src/ui/canvas/tiled_surface_compose.dart';

import '../../helpers/placement_reading.dart';

/// 🚨★★★A PICTURE LONGER ON A SIDE THAN THE ENGINE HOLDS IS HELD IN PIECES,
/// AND SHOWS THE PIXELS IT WOULD SHOW WHOLE (🗣️유저 2026-10-21, board
/// a-cel-past-the-device-side-composes-smaller-Q1: 「나눠 든다」).
///
/// On the device a compose past the side came back SHRUNK — 20096×1152 asked,
/// 16384×939 made on the Surface Pro 11 — so the cel played and exported at
/// 0.815 of its resolution. The test engine shrinks nothing (65536×1 comes
/// back whole), which is what lets these pins stand a cel at a side of 64 and
/// hold what it makes in pieces to what the same cel makes whole.

/// How far a rounding of the draw's quad moves a byte of the test's noise on
/// the test's Vulkan, at the most ([expectShownAsWhole]).
const int _roundingMoves = 9;

/// How far the engine's blur lands a row's byte from the whole's when the
/// part it blurs is the smaller input, at the most ([expectShownAsWhole]).
const int _blurRatioMoves = 60;

void main() {
  // A cel of 16-pixel noise tiles whose content is 192×96 (the canvas is 88
  // high; the tiles reach 96) — past a side of 64 both ways: six pieces.
  const tileSize = 16;
  const canvasSize = CanvasSize(width: 192, height: 88);
  const side = 64;
  const wholeSide = 1 << 16;

  tearDown(() => debugPictureSideLimit = wholeSide);

  BitmapSurface noise() {
    var surface = BitmapSurface(canvasSize: canvasSize, tileSize: tileSize);
    // ⚠️Not a hand-rolled LCG: its low bits cycle every four draws, and
    // `% 4` came out 0 at every pixel — a cel of alpha 0 everywhere.
    final random = math.Random(7);
    for (var y = 0; y < 6; y += 1) {
      for (var x = 0; x < 12; x += 1) {
        final pixels = Uint8List(tileSize * tileSize * 4);
        for (var index = 0; index < pixels.length; index += 4) {
          final alpha = random.nextInt(4) == 0 ? 0 : 128 + random.nextInt(128);
          // At most the alpha, so the bytes are a pixel premultiplied or not.
          pixels[index] = random.nextInt(alpha + 1);
          pixels[index + 1] = random.nextInt(alpha + 1);
          pixels[index + 2] = random.nextInt(alpha + 1);
          pixels[index + 3] = alpha;
        }
        surface = surface.putTiles([
          (
            coord: TileCoord(x: x, y: y),
            tile: BitmapTile(size: tileSize, pixels: pixels),
          ),
        ]);
      }
    }
    return surface;
  }

  Future<Uint8List> bytesOf(ui.Image image) async {
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    return data!.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  }

  /// How many bytes of [a] differ from [b], and by how much at most — a
  /// piece laid a texel off moves the noise by far more than one.
  ({int count, int most}) differences(Uint8List a, Uint8List b) {
    var count = 0;
    var most = 0;
    for (var index = 0; index < a.length && index < b.length; index += 1) {
      final by = (a[index] - b[index]).abs();
      if (by > 0) {
        count += 1;
        most = math.max(most, by);
      }
    }
    return (count: count, most: most);
  }

  String differ(Uint8List a, Uint8List b) {
    final (:count, :most) = differences(a, b);
    return '$count bytes differ, by at most $most';
  }

  /// [shown] is [whole] byte for byte — or, drawn through a pose, a
  /// rounding apart at a few pixels and no more. 🔬Measured 2026-10-21:
  /// posed at half, 1 byte of 7680 one apart; posed and blurred, 2 of 4032.
  /// 🔬Measured again 2026-11-04, once a posed image is drawn a sixty-fourth
  /// of a texel past its pose (`applyLayerPlacement`,
  /// an-enlarged-row-at-half-comes-apart-from-its-frame): posed and blurred,
  /// 7 of 4032 one apart, every run (2 with the offset taken out); turned
  /// and grown, 1; every other pose 0. ↩️Held to 0.1% until then; held now
  /// to 0.4%, twice the worst as 0.1% was to the 10-21 two — the offset
  /// moves where a sample falls, not how far a part lies, so the difference
  /// stays one (a-cel-past-the-side-resamples-a-hair-apart, 캔버스 베이스 패널
  /// 2026-11-04: 「되돌리지 않고 이 핀의 기준을 다시 잰다」).
  /// A pose resamples, and the part is drawn from a quad of its own — a
  /// smaller quad rounds its texture coordinates differently, the reason a
  /// posed crop gets its whole laid back ([inkCropDrawsTheSame]). A picture
  /// past the side has no whole to lay back on the device, so the rounding
  /// stays.
  ///
  /// 🔬ON IMPELLER THAT ROUNDING IS LARGER, and reaches every resample, so
  /// the test's Impeller is held to what a rounding can do rather than to a
  /// byte (impeller-sweep-canvas-reds, 공통 2026-10-30). Measured on noise,
  /// the same turned draw: the part under its own quad is up to 6/255 from
  /// the whole on the test's Vulkan and 2 on the Windows app's GLES, a few
  /// pixels flipping to their neighbour under `none`; under the WHOLE's
  /// quad, 3 bytes of 3024 by 1 on both — so it is the quad, not the texture
  /// (a bigger texture under one quad is 1 apart) and not an edge (the bytes
  /// lie all over the frame). ⛔No draw takes that quad: `drawImageRect`
  /// cuts a source past its image back to the part's, and an image shader
  /// over the whole's lands up to 68/255 from `drawImageRect` on GLES.
  /// A rounding moved no byte past [_roundingMoves] but those flips, under
  /// 2% of them; a part laid a texel off moves most of them.
  ///
  /// 🗣️A row's blur between two levels of the camera is held to
  /// [_blurRatioMoves] alone, and only on Impeller (유저 2026-10-30, board
  /// impeller-sweep-canvas-reds-Q1: 「받아들인다」): the engine's blur scales
  /// its input by a size rounded up (`gaussian_blur_filter_contents.cc`), so
  /// a smaller part blurs at another ratio. 🔬237 of these 640 bytes moved,
  /// by up to 56 here and 58 on the Windows app's GLES, under a blur of noise.
  void expectShownAsWhole(
    Uint8List shown,
    Uint8List whole, {
    required bool posed,
    bool blursAtAnotherRatio = false,
  }) {
    if (ui.ImageFilter.isShaderFilterSupported) {
      if (blursAtAnotherRatio) {
        expect(
          differences(shown, whole).most <= _blurRatioMoves,
          isTrue,
          reason: differ(shown, whole),
        );
        return;
      }
      var moved = 0;
      for (var index = 0; index < shown.length; index += 1) {
        if ((shown[index] - whole[index]).abs() > _roundingMoves) {
          moved += 1;
        }
      }
      expect(
        moved <= shown.length ~/ 50,
        isTrue,
        reason: '$moved moved past a rounding: ${differ(shown, whole)}',
      );
      return;
    }
    if (!posed) {
      expect(shown, whole, reason: differ(shown, whole));
      return;
    }
    final (:count, :most) = differences(shown, whole);
    expect(
      (most <= 1, count <= shown.length ~/ 250),
      (true, true),
      reason: differ(shown, whole),
    );
  }

  /// [pieces] laid side by side into one image — each texel where it lands,
  /// the oracle the pins read a picture in pieces through.
  Future<Uint8List> together(List<ImagePiece> pieces) async {
    final union = pieces.worldRect;
    final texels = pieces.first.image.width / pieces.first.worldRect.width;
    final recorder = ui.PictureRecorder();
    final into = ui.Canvas(recorder);
    for (final piece in pieces) {
      into.drawImage(
        piece.image,
        ui.Offset(
          (piece.worldRect.left - union.left) * texels,
          (piece.worldRect.top - union.top) * texels,
        ),
        ui.Paint()..filterQuality = ui.FilterQuality.none,
      );
    }
    final picture = recorder.endRecording();
    final image = await picture.toImage(
      (union.width * texels).round(),
      (union.height * texels).round(),
    );
    picture.dispose();
    try {
      return await bytesOf(image);
    } finally {
      image.dispose();
    }
  }

  group('the cut', () {
    test('a picture inside the side is one piece, the whole of it', () {
      const over = ui.Rect.fromLTWH(-64, 0, 16384, 1152);
      expect(piecesOver(over, side: 16384), [over]);
      // A side that is no power of two holds a picture as long as it.
      const asLong = ui.Rect.fromLTWH(0, 0, 12000, 10);
      expect(piecesOver(asLong, side: 12000), [asLong]);
    });

    test('past it, the longest power of two inside the side across, from the '
        'corner — the last what is left', () {
      // The Surface Pro 11's measure: 20096×1152 asked.
      expect(
        piecesOver(const ui.Rect.fromLTWH(-64, 0, 20096, 1152), side: 16384),
        const [
          ui.Rect.fromLTRB(-64, 0, 16320, 1152),
          ui.Rect.fromLTRB(16320, 0, 20032, 1152),
        ],
      );
      // A side that is no power of two cuts at the one below it.
      expect(
        piecesOver(const ui.Rect.fromLTWH(0, 0, 20000, 10), side: 12000),
        const [
          ui.Rect.fromLTRB(0, 0, 8192, 10),
          ui.Rect.fromLTRB(8192, 0, 16384, 10),
          ui.Rect.fromLTRB(16384, 0, 20000, 10),
        ],
      );
    });

    test('both ways, row by row', () {
      expect(
        piecesOver(const ui.Rect.fromLTWH(0, 0, 96, 48), side: 32),
        const [
          ui.Rect.fromLTRB(0, 0, 32, 32),
          ui.Rect.fromLTRB(32, 0, 64, 32),
          ui.Rect.fromLTRB(64, 0, 96, 32),
          ui.Rect.fromLTRB(0, 32, 32, 48),
          ui.Rect.fromLTRB(32, 32, 64, 48),
          ui.Rect.fromLTRB(64, 32, 96, 48),
        ],
      );
    });
  });

  group('composed in pieces, the same bytes as whole', () {
    /// ↩️And halved, and made now beside its snapshot, until no row image was
    /// made (one-picture-per-frame ②-5b-1).
    testWidgets('asynchronously, at full size', (tester) async {
      await tester.runAsync(() async {
        final surface = noise();
        final content = surfaceContentWorldRect(surface);
        expect(content, const ui.Rect.fromLTWH(0, 0, 192, 96), reason: '전제');

        final whole = (await composePositionedSurfaceImage(surface))!;
        debugPictureSideLimit = side;
        final pieces = (await composePositionedSurfaceImage(surface))!;
        debugPictureSideLimit = wholeSide;

        expect(whole.pieces, hasLength(1));
        expect(
          [for (final piece in pieces.pieces) piece.worldRect],
          piecesOver(content, side: side),
        );
        expect(pieces.worldRect, whole.worldRect);
        expect(
          pieces.pieces.every(
            (piece) => !isPastTheSide(
              piece.image.width,
              piece.image.height,
              side,
            ),
          ),
          isTrue,
        );
        expect(
          await together(pieces.pieces),
          await together(whole.pieces),
        );
        expect(
          pieces.pieces.estimatedBytes,
          whole.pieces.estimatedBytes,
          reason: 'weighed as the one picture they are',
        );
        for (final made in [whole, pieces]) {
          made.pieces.disposeAll();
        }
      });
    });

    testWidgets('a piece pictures only the blocks that land on it', (
      tester,
    ) async {
      await tester.runAsync(() async {
        // Four tiles a block apart ([tileBlockEdge]), on a canvas four
        // blocks wide: at a side of one block, one block a piece.
        var surface = BitmapSurface(
          canvasSize: const CanvasSize(width: 1024, height: tileSize),
          tileSize: tileSize,
        );
        for (var x = 0; x < 4; x += 1) {
          surface = surface.putTiles([
            (
              coord: TileCoord(x: x * 16, y: 0),
              tile: BitmapTile(
                size: tileSize,
                pixels: Uint8List(tileSize * tileSize * 4)
                  ..fillRange(0, tileSize * tileSize * 4, 0xFF),
              ),
            ),
          ]);
        }
        // One tick a block with no picture visited: the clock of a run
        // ([tilePictureRun]) is read once before the loop and once a block.
        var ticks = 0;
        debugTilePictureClock = () => ticks += 1;
        addTearDown(() => debugTilePictureClock = null);
        (await composePositionedSurfaceImage(surface))!.pieces.disposeAll();
        expect(ticks, 1 + 4, reason: '전제: four blocks, one compose');
        ticks = 0;
        debugPictureSideLimit = 256;
        final pieces = (await composePositionedSurfaceImage(surface))!.pieces;
        expect(pieces, hasLength(4), reason: '전제');
        pieces.disposeAll();

        expect(
          ticks,
          4 * (1 + 1),
          reason: 'each piece visits the one block that lands on it, not '
              'all four',
        );
      });
    });
  });

  group('drawn in pieces, the same picture as whole', () {
    // Small, so what it sees of the cel fits the side, with a blur's reach
    // round it — and across a cut both ways.
    const frame = ui.Size(36, 28);

    /// [draw] of [surface] composed at [at] onto a frame of [frame] over a
    /// grey ground — on a canvas that says what it can land on, unless
    /// [bounded] is false.
    Future<Uint8List> drawnAt(
      int at,
      BitmapSurface surface,
      void Function(ui.Canvas canvas, List<ImagePiece> pieces, ui.Rect extent)
      draw, {
      bool bounded = true,
    }) async {
      debugPictureSideLimit = at;
      try {
        final composed = (await composePositionedSurfaceImage(surface))!;
        final recorder = ui.PictureRecorder();
        final canvas = bounded
            ? ui.Canvas(recorder, ui.Offset.zero & frame)
            : ui.Canvas(recorder);
        canvas.drawColor(const ui.Color(0xFF808890), ui.BlendMode.src);
        // Part of the cel off the frame, so what the frame sees is a part.
        canvas.translate(-50, -40);
        draw(canvas, composed.pieces, surfaceContentWorldRect(surface));
        final picture = recorder.endRecording();
        composed.pieces.disposeAll();
        // ⚠️Through `toImageSync`: the part laid is a deferred image, the
        // whole a snapshot, and onto a snapshot's target this runner blends
        // the two ±1 apart (`a_cropped_cel_draws_the_same_bytes_test.dart`
        // says why; on Impeller they are the same texture).
        final image = picture.toImageSync(
          frame.width.toInt(),
          frame.height.toInt(),
        );
        picture.dispose();
        try {
          return await bytesOf(image);
        } finally {
          image.dispose();
        }
      } finally {
        debugPictureSideLimit = wholeSide;
      }
    }

    void Function(ui.Canvas, List<ImagePiece>, ui.Rect) drawing({
      TransformPose? pose,
      LayerBlendMode blendMode = LayerBlendMode.normal,
      List<ResolvedLayerEffect> effects = const [],
    }) => (canvas, pieces, extent) => drawPosedLayerImage(
      canvas,
      pieces: pieces,
      extent: extent,
      paper: canvasSize.canvasRect,
      placement: pose == null ? null : placedBy(pose, canvasSize),
      opacity: 0.9,
      blendMode: blendMode,
      effects: effects,
      texelScale: pose == null ? 1 : null,
      filterQuality: ui.FilterQuality.low,
    );

    final turned = TransformPose.uniform(
      center: CanvasPoint(x: 66, y: 52),
      zoom: 1.3,
      rotationDegrees: 17,
    );
    // Four pixels a texel, what the frame sees standing on texels' edges
    // (60, 60)–(69, 67): an edge pixel's centre is an eighth of a texel in,
    // and filtered it reads the texel past what is seen.
    final magnified = TransformPose.uniform(
      center: CanvasPoint(x: 194, y: -24),
      zoom: 4,
    );
    final blur = ResolvedLayerEffect(kind: EffectKind.blur, values: [3, 0]);

    for (final (name, draw, posed) in [
      ('laid down texel for texel', drawing(), false),
      ('posed — turned and grown', drawing(pose: turned), true),
      (
        'magnified 400% — filtered, an edge reads past what is seen',
        drawing(pose: magnified),
        true,
      ),
      (
        'blurred — a chain that reads its neighbours',
        drawing(effects: [blur]),
        false,
      ),
      // ↩️'through an advanced blend' (multiply), until such a layer
      // painted normal over its backdrop
      // (a-blurred-folder-cut-by-the-view-moves-on-vulkan); 'through add'
      // until it did too (brush-fidelity Q3).
      ('posed and blurred', drawing(pose: turned, effects: [blur]), true),
    ]) {
      testWidgets(name, (tester) async {
        await tester.runAsync(() async {
          final surface = noise();
          final whole = await drawnAt(wholeSide, surface, draw);
          final laid = debugSeenPartsLaid;
          final inPieces = await drawnAt(side, surface, draw);

          expect(debugSeenPartsLaid, laid + 1, reason: 'one part laid');
          expectShownAsWhole(inPieces, whole, posed: posed);
        });
      });
    }

    testWidgets('a canvas that does not say what it sees has the pieces '
        'drawn apart — a texel copy the same all the same', (tester) async {
      await tester.runAsync(() async {
        final surface = noise();
        final whole = await drawnAt(wholeSide, surface, drawing());
        final apart = debugPiecesDrawnApart;
        final inPieces = await drawnAt(
          side,
          surface,
          drawing(),
          bounded: false,
        );

        expect(debugPiecesDrawnApart, apart + 1);
        expect(inPieces, whole, reason: differ(inPieces, whole));
      });
    });

    testWidgets('a draw that sees none of it lays nothing', (tester) async {
      await tester.runAsync(() async {
        final surface = noise();
        void away(ui.Canvas canvas, List<ImagePiece> pieces, ui.Rect extent) {
          canvas.translate(400, 0);
          drawing()(canvas, pieces, extent);
        }

        final whole = await drawnAt(wholeSide, surface, away);
        final laid = debugSeenPartsLaid;
        final apart = debugPiecesDrawnApart;
        final inPieces = await drawnAt(side, surface, away);

        expect((debugSeenPartsLaid, debugPiecesDrawnApart), (laid, apart));
        expect(inPieces, whole, reason: differ(inPieces, whole));
      });
    });
  });
}
