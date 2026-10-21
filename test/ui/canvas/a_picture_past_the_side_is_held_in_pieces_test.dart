import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/brush_frame_key.dart';
import 'package:anicel/src/models/camera_pose.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/models/composite_tree.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer_blend_mode.dart';
import 'package:anicel/src/models/layer_effect.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/playback_quality.dart';
import 'package:anicel/src/models/project_background.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/models/transform_pose.dart';
import 'package:anicel/src/services/brush_frame_store.dart';
import 'package:anicel/src/services/camera_frame_corners.dart';
import 'package:anicel/src/services/cut_frame_composite_plan.dart';
import 'package:anicel/src/services/import/cel_picture.dart';
import 'package:anicel/src/ui/camera/camera_frame_render_service.dart';
import 'package:anicel/src/ui/canvas/bitmap_tile_image_cache.dart';
import 'package:anicel/src/ui/canvas/canvas_layer_stack_view.dart';
import 'package:anicel/src/ui/canvas/display_resample.dart';
import 'package:anicel/src/ui/canvas/image_pieces.dart';
import 'package:anicel/src/ui/canvas/layer_image_draw.dart';
import 'package:anicel/src/ui/canvas/tiled_surface_compose.dart';
import 'package:anicel/src/ui/playback/layer_frame_image_cache.dart';

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
  /// A pose resamples, and the sampler reads where it is in the part laid,
  /// not in the whole — a smaller texture rounds its coordinates
  /// differently, the reason a posed crop gets its whole laid back
  /// ([inkCropDrawsTheSame]). A picture past the side has no whole to lay
  /// back on the device, so the rounding stays.
  void expectShownAsWhole(
    Uint8List shown,
    Uint8List whole, {
    required bool posed,
  }) {
    if (!posed) {
      expect(shown, whole, reason: differ(shown, whole));
      return;
    }
    final (:count, :most) = differences(shown, whole);
    expect(
      (most <= 1, count <= shown.length ~/ 1000),
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
      expect(
        piecesOver(over, side: 16384, texelsPerUnit: 0.5),
        [over],
        reason: 'halved, it is half as many texels',
      );
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
      // Halved, a texel is two canvas pixels: the cut is twice as far apart.
      expect(
        piecesOver(
          const ui.Rect.fromLTWH(0, 0, 40000, 100),
          side: 16384,
          texelsPerUnit: 0.5,
        ),
        const [
          ui.Rect.fromLTRB(0, 0, 32768, 100),
          ui.Rect.fromLTRB(32768, 0, 40000, 100),
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
    testWidgets('asynchronously, at full size and halved', (tester) async {
      await tester.runAsync(() async {
        final surface = noise();
        final content = surfaceContentWorldRect(surface);
        expect(content, const ui.Rect.fromLTWH(0, 0, 192, 96), reason: '전제');

        final whole = (await composePositionedSurfaceImage(surface))!;
        final halvedWhole = (await composeHalvedSurfaceImage(
          surface,
          over: content,
        ))!;
        debugPictureSideLimit = side;
        final pieces = (await composePositionedSurfaceImage(surface))!;
        final halved = (await composeHalvedSurfaceImage(
          surface,
          over: content,
        ))!;
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

        expect(
          [for (final piece in halved.pieces) piece.worldRect],
          const [
            ui.Rect.fromLTRB(0, 0, 128, 96),
            ui.Rect.fromLTRB(128, 0, 192, 96),
          ],
          reason: 'halved, 96×48 texels: past 64 across only',
        );
        expect(
          await together(halved.pieces),
          await together(halvedWhole.pieces),
        );
        for (final made in [whole, halvedWhole, pieces, halved]) {
          made.pieces.disposeAll();
        }
      });
    });

    testWidgets('made now, deferred and its snapshot alike', (tester) async {
      await tester.runAsync(() async {
        final surface = noise();
        final content = surfaceContentWorldRect(surface);
        final want = await together(
          (await composePositionedSurfaceImage(surface))!.pieces,
        );
        final wantHalved = await together(
          (await composeHalvedSurfaceImage(surface, over: content))!.pieces,
        );
        debugPictureSideLimit = side;
        final now = composePositionedSurfaceImageSync(
          surface,
          reuse: BitmapTileImageCache(),
          makePictures: true,
          snapshot: true,
        )!;
        final halvedNow = composeHalvedSurfaceImageSync(
          surface,
          makePictures: true,
          snapshot: true,
          over: content,
        )!;
        debugPictureSideLimit = wholeSide;

        expect(now.deferred.pieces, hasLength(6));
        expect(await together(now.deferred.pieces), want);
        final kept = await now.real!;
        expect(
          await together([
            for (var index = 0; index < kept.length; index += 1)
              (
                image: kept[index],
                worldRect: now.deferred.pieces[index].worldRect,
              ),
          ]),
          want,
          reason: 'the snapshot kept is the same picture, piece for piece',
        );
        expect(halvedNow.deferred.pieces, hasLength(2));
        expect(await together(halvedNow.deferred.pieces), wantHalved);
        final keptHalved = await halvedNow.real!;
        expect(keptHalved, hasLength(2));
        now.deferred.pieces.disposeAll();
        halvedNow.deferred.pieces.disposeAll();
        for (final image in [...kept, ...keptHalved]) {
          image.dispose();
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
    final blur = ResolvedLayerEffect(kind: EffectKind.blur, values: [3, 3]);

    for (final (name, draw, posed) in [
      ('laid down texel for texel', drawing(), false),
      ('posed — turned and grown', drawing(pose: turned), true),
      (
        'blurred — a chain that reads its neighbours',
        drawing(effects: [blur]),
        false,
      ),
      (
        'through an advanced blend',
        drawing(blendMode: LayerBlendMode.multiply),
        false,
      ),
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

  BrushFrameKey key(String id) => BrushFrameKey(
    projectId: const ProjectId('p'),
    trackId: const TrackId('t'),
    cutId: const CutId('c'),
    layerId: LayerId(id),
    frameId: FrameId('$id-f'),
  );

  /// The noise everywhere ([noise]), and two cels of part of it: `sparse`,
  /// tiles (3..8, 1..5), ink 96×80 that reaches the pasteboard below and is
  /// past the side across and down from its own corner; `inside`, tiles
  /// (3..6, 1..4), ink inside the canvas and the side, whole the canvas.
  Map<String, BitmapSurface> cels() {
    final everywhere = noise();
    BitmapSurface tiles(int right, int bottom) =>
        BitmapSurface(canvasSize: canvasSize, tileSize: tileSize).putTiles([
          for (final MapEntry(key: coord, value: tile)
              in everywhere.tiles.entries)
            if (coord.x >= 3 &&
                coord.x <= right &&
                coord.y >= 1 &&
                coord.y <= bottom)
              (coord: coord, tile: tile),
        ]);
    return {'noise': everywhere, 'sparse': tiles(8, 5), 'inside': tiles(6, 4)};
  }

  BrushFrameStore store() {
    final store = BrushFrameStore();
    for (final MapEntry(key: id, value: surface) in cels().entries) {
      store.storeBakedSurface(key(id), surface);
    }
    return store;
  }

  group('held by the playback cache, drawn the same as whole', () {
    const frame = ui.Size(36, 28);
    // Where the frame stands on each cel, in canvas pixels: across the cuts
    // at every level that has one — the ink's own at (112, 80).
    const at = {
      'noise': ui.Offset(96, 40),
      'sparse': ui.Offset(96, 60),
      'inside': ui.Offset(96, 40),
    };

    /// [stored] drawn texel for texel at [level]'s raster onto a frame.
    Future<Uint8List> shown(LayerFrameImage stored, String cel, int level) {
      final scale = 1 / (1 << level);
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder, ui.Offset.zero & frame)
        ..drawColor(const ui.Color(0xFF808890), ui.BlendMode.src)
        ..translate(-at[cel]!.dx * scale, -at[cel]!.dy * scale);
      drawPosedLayerImage(
        canvas,
        pieces: stored.pieces,
        extent: stored.extent,
        placement: null,
        opacity: 0.9,
        blendMode: LayerBlendMode.normal,
        rasterScale: scale,
        texelScale: scale,
        filterQuality: ui.FilterQuality.low,
      );
      final picture = recorder.endRecording();
      final image = picture.toImageSync(
        frame.width.toInt(),
        frame.height.toInt(),
      );
      picture.dispose();
      return bytesOf(image).whenComplete(image.dispose);
    }

    // How many pieces each picture is held in at a side of 64. Every cel's
    // whole is at least the canvas, 192×88 — six pieces, and two at half
    // (96 texels across) — and at a quarter the half's two each halved
    // again, a level being made from the one above it. An ink is cut from
    // its own corner: the sparse cel's, 48..144 × 16..96, four pieces and
    // one at half, and at a quarter cut out of the half's two; the inside
    // cel's, 64×64, one.
    const held = {
      ('noise', 0, false): 6,
      ('noise', 0, true): 6,
      ('noise', 1, false): 2,
      ('noise', 1, true): 2,
      ('noise', 2, false): 2,
      ('noise', 2, true): 2,
      ('sparse', 0, false): 6,
      ('sparse', 0, true): 4,
      ('sparse', 1, false): 2,
      ('sparse', 1, true): 1,
      ('sparse', 2, false): 2,
      ('sparse', 2, true): 2,
      ('inside', 0, false): 6,
      ('inside', 0, true): 1,
      ('inside', 1, false): 2,
      ('inside', 1, true): 1,
      ('inside', 2, false): 2,
      ('inside', 2, true): 1,
    };

    for (final cel in ['noise', 'sparse', 'inside']) {
      for (final level in [0, 1, 2]) {
        for (final ink in [false, true]) {
          final kept = ink ? ', its ink alone' : '';
          testWidgets('$cel at level $level$kept: made later, made now and '
              'settled', (tester) async {
            await tester.runAsync(() async {
              final quality = PlaybackQuality.forLevel(level);
              LayerFrameImageCache cache() {
                final images = LayerFrameImageCache(frameStore: store());
                addTearDown(images.dispose);
                return images;
              }

              Future<LayerFrameImage> later(LayerFrameImageCache images) =>
                  images
                      .prepare(
                        key: key(cel),
                        canvasSize: canvasSize,
                        quality: quality,
                        sourceEffects: const [],
                        inkSuffices: ink,
                      )
                      .then((made) => made!);

              final want = await shown(await later(cache()), cel, level);
              debugPictureSideLimit = side;
              final heldLater = await later(cache());
              final images = cache();
              final heldNow = images.prepareSyncOrNull(
                key: key(cel),
                canvasSize: canvasSize,
                quality: quality,
                sourceEffects: const [],
                makePictures: true,
                inkSuffices: ink,
              )!;
              final shownNow = await shown(heldNow, cel, level);
              final settled = await later(images);

              expect(
                heldLater.pieces,
                hasLength(held[(cel, level, ink)]),
                reason: '전제',
              );
              expect(heldNow.pieces, hasLength(heldLater.pieces.length));
              expect(
                identical(settled.pieces.first.image, heldNow.pieces.first.image),
                isFalse,
                reason: '전제: settled to its snapshots',
              );
              final shownLater = await shown(heldLater, cel, level);
              expect(shownLater, want, reason: differ(shownLater, want));
              expect(shownNow, want, reason: differ(shownNow, want));
              final shownSettled = await shown(settled, cel, level);
              expect(shownSettled, want, reason: differ(shownSettled, want));
            });
          });
        }
      }
    }
  });

  group('on the editing stack, the same screen as whole', () {
    const view = Size(48, 40);
    final screenKey = GlobalKey();

    CompositeNode<CanvasStackRow> row(
      String id, {
      double opacity = 1,
      LayerBlendMode blendMode = LayerBlendMode.normal,
      TransformPose? pose,
      List<ResolvedLayerEffect> effects = const [],
    }) => CompositeLeaf<CanvasStackRow>(
      CanvasLayerImageRequest(
        frameKey: key(id),
        opacity: opacity,
        blendMode: blendMode,
        placement: pose == null ? null : placedBy(pose, canvasSize),
        tint: null,
        effects: effects,
      ),
    );

    final turned = TransformPose.uniform(
      center: CanvasPoint(x: 66, y: 52),
      zoom: 1.3,
      rotationDegrees: 17,
    );
    final blurred = [
      ResolvedLayerEffect(kind: EffectKind.blur, values: [3, 3]),
    ];
    // One row a scene, so no row's pixels hide another's under them — and
    // the three over each other once.
    final scenes = <String, List<CompositeNode<CanvasStackRow>>>{
      for (final cel in ['noise', 'sparse', 'inside']) ...{
        '$cel kept as ink': [row(cel, opacity: 0.8)],
        '$cel through multiply': [
          row(cel, blendMode: LayerBlendMode.multiply),
        ],
        '$cel posed': [row(cel, pose: turned)],
        '$cel blurred': [row(cel, effects: blurred)],
      },
      'the three over each other': [
        row('noise', opacity: 0.8),
        row('sparse', blendMode: LayerBlendMode.multiply),
        row('inside', effects: blurred),
      ],
      // A folder that blends and blurs is rastered apart (its sub-tree's
      // own image), and draws its rows into that.
      'a folder through multiply, blurred': [
        CompositeGroup<CanvasStackRow>(
          children: [row('noise'), row('sparse', opacity: 0.7)],
          opacity: 0.9,
          blendMode: LayerBlendMode.multiply,
          effects: [
            ResolvedLayerEffect(kind: EffectKind.blur, values: [2, 2]),
          ],
        ),
      ],
    };

    // The view sees across a cut at each level that has one, and less of
    // the cel than the side holds.
    final viewports = <String, CanvasViewport>{
      'level 0': CanvasViewport(zoom: 1, panX: -40, panY: -40),
      'level 1': CanvasViewport(zoom: 0.5, panX: -40, panY: -10),
      'level 2': CanvasViewport(zoom: 0.25, panX: 0, panY: 0),
      'rotated 20° at 150%': CanvasViewport(
        zoom: 1.5,
        panX: -90,
        panY: -80,
        rotationDegrees: 20,
      ),
      // ⚠️At a zoom that puts no pixel's centre on a texel's edge. At 230%
      // one lies ON one (172.5 / 2.3 = 75; the pan is put on whole pixels),
      // magnified a texel is drawn unfiltered, and which texel it then
      // takes is the float rounding of the whole matrix — the part laid,
      // standing at another origin, rounded to the other side: inside a
      // folder's raster three lines of pixels took the texel beside
      // (🔬2026-10-21). Either is that pixel; neither is what these pins
      // hold. At 2.2 a centre, a half, is never k × 2.2.
      'magnified 220%': CanvasViewport(zoom: 2.2, panX: -134, panY: -125),
    };

    Iterable<CanvasLayerImageRequest> requestsIn(
      List<CompositeNode<CanvasStackRow>> nodes,
    ) sync* {
      for (final node in nodes) {
        switch (node) {
          case CompositeLeaf(payload: final CanvasLayerImageRequest request):
            yield request;
          case CompositeLeaf():
            break;
          case CompositeGroup(:final children):
          case CompositeAdjustment(:final children):
            yield* requestsIn(children);
        }
      }
    }

    /// The stack's screen for [nodes], every row warmed first the way the
    /// view asks for it, captured the way `a_cropped_cel_draws_the_same_
    /// bytes_test.dart` says why — and whether any row's picture was held in
    /// pieces.
    Future<({Uint8List bytes, bool inPieces})> screen(
      WidgetTester tester, {
      required List<CompositeNode<CanvasStackRow>> nodes,
      required CanvasViewport viewport,
      required bool walk,
    }) async {
      final images = LayerFrameImageCache(frameStore: store());
      addTearDown(images.dispose);
      var inPieces = false;
      final quality = PlaybackQuality.forLevel(
        displayLevelOf(displayScaleOf(viewport.zoom, 1)),
      );
      for (final request in requestsIn(nodes)) {
        final warmed = await tester.runAsync(
          () => images.prepare(
            key: request.frameKey,
            canvasSize: canvasSize,
            quality: quality,
            sourceEffects: request.sourceEffects,
            inkSuffices: request.inkSuffices,
          ),
        );
        expect(warmed, isNotNull, reason: 'fixture: ${request.frameKey}');
        inPieces |= warmed!.pieces.length > 1;
      }
      await tester.pumpWidget(
        MaterialApp(
          key: UniqueKey(),
          home: Scaffold(
            body: Center(
              child: RepaintBoundary(
                key: screenKey,
                child: ClipRect(
                  child: SizedBox(
                    width: view.width,
                    height: view.height,
                    child: CanvasLayerStackView(
                      nodes: nodes,
                      imageCache: images,
                      canvasSize: canvasSize,
                      viewport: viewport,
                      paintPaper: true,
                      paperBackground: const ProjectBackground.color(
                        0xFFF4EEE0,
                      ),
                      debugDisableSingleBuffer: walk,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      final render =
          screenKey.currentContext!.findRenderObject()!
              as RenderRepaintBoundary;
      final bytes = await tester.runAsync(() async {
        final image = render.toImageSync();
        try {
          return await bytesOf(image);
        } finally {
          image.dispose();
        }
      });
      return (bytes: bytes!, inPieces: inPieces);
    }

    for (final scene in scenes.entries) {
      for (final viewport in viewports.entries) {
        for (final walk in [false, true]) {
          final route = walk ? 'the direct walk' : 'the display buffer';
          testWidgets('${scene.key} · ${viewport.key} · $route', (
            tester,
          ) async {
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.resetDevicePixelRatio);
            final whole = await screen(
              tester,
              nodes: scene.value,
              viewport: viewport.value,
              walk: walk,
            );
            final laid = debugSeenPartsLaid;
            final apart = debugPiecesDrawnApart;
            debugPictureSideLimit = side;
            final inPieces = await screen(
              tester,
              nodes: scene.value,
              viewport: viewport.value,
              walk: walk,
            );
            debugPictureSideLimit = wholeSide;

            expect(debugPiecesDrawnApart, apart, reason: 'every part laid');
            expect(
              debugSeenPartsLaid > laid,
              inPieces.inPieces,
              reason: 'a part laid for every picture in pieces, and only so',
            );
            expectShownAsWhole(
              inPieces.bytes,
              whole.bytes,
              posed: scene.key.contains('posed'),
            );
          });
        }
      }
    }
  });

  group('rendered through the camera, the same film frame as whole', () {
    const service = CameraFrameRenderService();
    final turned = TransformPose.uniform(
      center: CanvasPoint(x: 66, y: 52),
      zoom: 1.3,
      rotationDegrees: 17,
    );
    final blurred = [
      ResolvedLayerEffect(kind: EffectKind.blur, values: [3, 3]),
    ];

    CompositeNode<CutFrameCompositeLayer> row(
      BitmapSurface surface, {
      double opacity = 1,
      LayerBlendMode blendMode = LayerBlendMode.normal,
      TransformPose? pose,
      List<ResolvedLayerEffect> effects = const [],
    }) => CompositeLeaf(
      CutFrameCompositeLayer(
        surface: surface,
        opacity: opacity,
        blendMode: blendMode,
        placement: pose == null ? null : placedBy(pose, canvasSize),
        effects: effects,
      ),
    );

    // One row a scene, as on the stack, and the three over each other.
    final scenes =
        <String, List<CompositeNode<CutFrameCompositeLayer>> Function()>{
          'noise kept as ink': () => [row(cels()['noise']!, opacity: 0.8)],
          'sparse through multiply': () => [
            row(cels()['sparse']!, blendMode: LayerBlendMode.multiply),
          ],
          'inside blurred': () => [row(cels()['inside']!, effects: blurred)],
          'noise posed': () => [row(cels()['noise']!, pose: turned)],
          'the three over each other': () {
            final all = cels();
            return [
              row(all['noise']!, opacity: 0.8),
              row(all['sparse']!, blendMode: LayerBlendMode.multiply),
              row(all['inside']!, effects: blurred),
            ];
          },
          'a folder through multiply, blurred': () {
            final all = cels();
            return [
              CompositeGroup(
                children: [
                  row(all['noise']!),
                  row(all['sparse']!, opacity: 0.7),
                ],
                opacity: 0.9,
                blendMode: LayerBlendMode.multiply,
                effects: [
                  ResolvedLayerEffect(kind: EffectKind.blur, values: [2, 2]),
                ],
              ),
            ];
          },
        };

    // Each sees across a cut, and less of the cel than the side holds: at
    // the camera's own size, at half (its pieces halved one by one), and
    // turned.
    final cameras =
        <String, ({CameraView view, CanvasSize? output, bool turns})>{
          'square over a part': (
            view: cameraViewOver(const ui.Rect.fromLTWH(44, 34, 40, 36)),
            output: null,
            turns: false,
          ),
          'square at half': (
            view: cameraViewOver(const ui.Rect.fromLTWH(32, 16, 112, 64)),
            output: const CanvasSize(width: 56, height: 32),
            turns: false,
          ),
          'turned': (
            view: (
              pose: CameraPose(
                center: CanvasPoint(x: 70, y: 56),
                rotationDegrees: 9,
              ),
              frameSize: const CanvasSize(width: 48, height: 40),
            ),
            output: null,
            turns: true,
          ),
        };

    for (final MapEntry(key: scene, value: nodes) in scenes.entries) {
      for (final MapEntry(key: camera, value: through) in cameras.entries) {
        testWidgets('$scene, through a camera $camera', (tester) async {
          await tester.runAsync(() async {
            Future<Uint8List> render() async {
              final rows = _Deferred(laidTexelForTexel: !through.turns);
              final frame = await service.renderThroughCamera(
                nodes: nodes(),
                pose: through.view.pose,
                cameraFrameSize: through.view.frameSize,
                outputSize: through.output,
                rows: rows,
              );
              rows.dispose();
              return bytesOf(frame).whenComplete(frame.dispose);
            }

            final whole = await render();
            final laid = debugSeenPartsLaid;
            final apart = debugPiecesDrawnApart;
            debugPictureSideLimit = side;
            final inPieces = await render();
            debugPictureSideLimit = wholeSide;

            expect(
              (debugSeenPartsLaid > laid, debugPiecesDrawnApart),
              (true, apart),
              reason: '전제: every row in pieces, every part laid',
            );
            expectShownAsWhole(
              inPieces,
              whole,
              posed: scene.contains('posed') || through.turns,
            );
          });
        });
      }
    }
  });
}

/// The rows a render draws, each piece handed to it as a deferred image —
/// the kind the part a draw lays of a picture in pieces is. ⚠️This runner
/// blends a snapshot onto the film's snapshot target through a legacy
/// blitter, ±1 from every other image through every other path
/// (`a_cropped_cel_draws_the_same_bytes_test.dart` says why; on Impeller
/// they are the same texture): handed snapshots, the whole and the laid
/// part would be held apart by the blitter and not by the pieces.
final class _Deferred implements RowPictures {
  _Deferred({required this.laidTexelForTexel});

  @override
  final bool laidTexelForTexel;

  final _made = <ImagePiece>[];

  @override
  Future<PositionedSurfaceImage> of(
    BitmapSurface surface,
    int level,
    Future<PositionedSurfaceImage> Function() compose,
  ) async {
    final made = await compose();
    final pieces = [
      for (final piece in made.pieces)
        (image: _deferred(piece.image), worldRect: piece.worldRect),
    ];
    made.pieces.disposeAll();
    _made.addAll(pieces);
    return PositionedSurfaceImage(pieces: pieces, worldRect: made.worldRect);
  }

  static ui.Image _deferred(ui.Image image) {
    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder).drawImage(
      image,
      ui.Offset.zero,
      ui.Paint()
        ..blendMode = ui.BlendMode.src
        ..filterQuality = ui.FilterQuality.none,
    );
    final picture = recorder.endRecording();
    try {
      return picture.toImageSync(image.width, image.height);
    } finally {
      picture.dispose();
    }
  }

  void dispose() => _made.disposeAll();
}
