import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/camera_pose.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/composite_tree.dart';
import 'package:anicel/src/models/layer_blend_mode.dart';
import 'package:anicel/src/models/layer_effect.dart';
import 'package:anicel/src/models/pasteboard_bounds.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/models/transform_pose.dart';
import 'package:anicel/src/services/camera_frame_corners.dart';
import 'package:anicel/src/services/cut_frame_composite_plan.dart';
import 'package:anicel/src/services/import/cel_picture.dart';
import 'package:anicel/src/ui/camera/camera_frame_render_service.dart';
import 'package:anicel/src/ui/canvas/image_pieces.dart';
import 'package:anicel/src/ui/canvas/layer_blend_shader.dart';
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

void main() {
  setUpAll(LayerBlendShader.load);

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
  /// ⚠️A row's blur reduced by the camera stays red here, and on GLES by the
  /// same bytes: the engine's blur scales its input by a size rounded up
  /// (`gaussian_blur_filter_contents.cc`), so a smaller part blurs at
  /// another ratio (impeller-sweep-canvas-reds-Q1).
  void expectShownAsWhole(
    Uint8List shown,
    Uint8List whole, {
    required bool posed,
  }) {
    if (ui.ImageFilter.isShaderFilterSupported) {
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
      // (a-blurred-folder-cut-by-the-view-moves-on-vulkan).
      ('through add', drawing(blendMode: LayerBlendMode.add), false),
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

  group('rendered through the camera, the same film frame as whole', () {
    const service = CameraFrameRenderService();
    final turned = TransformPose.uniform(
      center: CanvasPoint(x: 66, y: 52),
      zoom: 1.3,
      rotationDegrees: 17,
    );
    final blurred = [
      ResolvedLayerEffect(kind: EffectKind.blur, values: [3, 0]),
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
                  ResolvedLayerEffect(kind: EffectKind.blur, values: [2, 0]),
                ],
              ),
            ];
          },
        };

    // Each sees across a cut, and less of the cel than the side holds: at
    // the camera's own size, at half (each piece read from its own chain),
    // and turned. ↩️At half it saw 112 × 64 of the cel, which fit the side
    // halved — its pieces halved one by one — until every row was drawn at
    // canvas resolution (one-picture-per-frame ②-5b-3).
    final cameras =
        <String, ({CameraView view, CanvasSize? output, bool turns})>{
          'square over a part': (
            view: cameraViewOver(const ui.Rect.fromLTWH(44, 34, 40, 36)),
            output: null,
            turns: false,
          ),
          'square at half': (
            view: cameraViewOver(const ui.Rect.fromLTWH(92, 48, 40, 24)),
            output: const CanvasSize(width: 20, height: 12),
            turns: false,
          ),
          // Between two levels of the chain: a sampler blends the first and
          // the second.
          'square at two fifths': (
            view: cameraViewOver(const ui.Rect.fromLTWH(92, 48, 40, 25)),
            output: const CanvasSize(width: 16, height: 10),
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

    // ↩️The folder held its rows at the side of 64 too, until a raster a
    // spreading chain reads lay on the canvas's 16-pixel cells
    // (nested-folder-buffers-read-past-the-view). 🔬Through these cameras
    // the blurred folder's raster is 64×48, 48×32 at half (96×64 of the
    // cel), 32×16 at two fifths (80×40) and, turned, 80×80; the window its
    // rows are drawn through, read 2 past each edge, went past 64, and its
    // rows were drawn apart — at two fifths 70 bytes apart from the whole,
    // by up to 20. At 112 the noise is held in the same six pieces of 64
    // (the longest power of two inside) and every part, 100 at most, is
    // laid; the sparse ink, 96×80, is held whole.
    const sidePastTheCells = 112;

    for (final MapEntry(key: scene, value: nodes) in scenes.entries) {
      for (final MapEntry(key: camera, value: through) in cameras.entries) {
        testWidgets('$scene, through a camera $camera', (tester) async {
          await tester.runAsync(() async {
            Future<Uint8List> render() async {
              final rows = _Deferred(laidTexelForTexel: !through.turns);
              final frame = await service.renderThroughCamera(
                canvasSize: canvasSize,
                // As the plan hands them over: a row in multiply composed
                // over what lies below it.
                nodes: composeOverTheirBackdrops(
                  nodes(),
                  blendOf: (layer) => layer.blendMode,
                  paintedNormal: (layer) => layer.paintedNormal(),
                ),
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
            debugPictureSideLimit = scene.startsWith('a folder')
                ? sidePastTheCells
                : side;
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
