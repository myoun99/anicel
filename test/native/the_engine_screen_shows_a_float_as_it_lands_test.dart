import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/brush_dab.dart';
import 'package:anicel/src/models/brush_dab_sequence.dart';
import 'package:anicel/src/models/brush_frame_key.dart';
import 'package:anicel/src/models/brush_stamp_image.dart';
import 'package:anicel/src/models/brush_tip_shape.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/models/composite_tree.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/dirty_region.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer_effect.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/pasteboard_bounds.dart';
import 'package:anicel/src/models/project_background.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/bitmap_surface_brush_commit.dart'
    show materializeBrushDabSequenceOnBitmapSurface;
import 'package:anicel/src/services/brush_stroke_blend.dart'
    show bitmapSurfaceRegionPixels;
import 'package:anicel/src/services/guide_geometry.dart';
import 'package:anicel/src/ui/canvas/bitmap_surface_painter.dart';
import 'package:anicel/src/ui/canvas/canvas_layer_stack_view.dart';
import 'package:anicel/src/ui/canvas/float_warp.dart' show FloatResampleShown;
import 'package:anicel/src/ui/canvas/landing_preview.dart';
import 'package:anicel/src/ui/canvas/selection_float_overlay.dart';
import 'package:anicel/src/ui/canvas/text/cel_text_float.dart';
import 'package:anicel/src/ui/playback/stacked_frame_picture.dart';

import '../helpers/an_effect_sampled.dart';
import '../helpers/engine_screen_pins.dart';

/// 🚨★★★THE ENGINE'S SCREEN SHOWS A FLOAT AS IT LANDS (flip lane ⓐ-2, 유저
/// 절대규칙 2026-09-17: 「보이는 중이랑 결과랑 절대로 다르면 안 되」 · F-240 ·
/// TS1): what a hand carries over a row is laid in the row's own picture,
/// at its depth, before its chain and its pose — so the screen while it is
/// carried is, byte for byte, the screen once it has landed: a float moved,
/// one through the row's blur, one cut at the wall, one on a row that keys
/// its colours, a landing in place of a region on a posed row, a warp's
/// resample, a row a lift holds beside the pen's.
///
/// ⚠️Its pixels are clear or opaque: a partly clear one over ink lands by
/// the stamp blend's arithmetic and lies by the engine's, one apart at most
/// till the stroke is the engine's too (flip lane ⓒ,
/// `a_carried_text_shows_what_it_lands_as_test`).
void main() {
  // The letters read their faces from the bundle.
  TestWidgetsFlutterBinding.ensureInitialized();
  const canvas = CanvasSize(width: 256, height: 128);
  const side = 128;
  final left = TileCoord(x: 0, y: 0);
  final right = TileCoord(x: 1, y: 0);
  final engine = EngineScreenPins('the engine screen shows a float as it lands');

  /// A tile of [seed]'s pixels, alphas of every kind.
  BitmapTile tileOf(int seed) {
    final pixels = Uint8List(side * side * 4);
    for (var y = 0; y < side; y++) {
      for (var x = 0; x < side; x++) {
        final n = x * 7 + y * 13 + seed * 101;
        final alpha = switch ((x ~/ 16 + y ~/ 32 + seed) % 4) {
          0 => 0,
          1 => 255,
          2 => 96 + (n & 63),
          _ => 200 + (n & 31),
        };
        if (alpha > 0) {
          pixels.setAll((y * side + x) * 4, [
            (n * 37) & 255,
            (n * 23 + 91) & 255,
            (n * 11) & 255,
            alpha,
          ]);
        }
      }
    }
    return BitmapTile(size: side, pixels: pixels);
  }

  /// The cel a float is carried over: ink on both tiles.
  BitmapSurface cel({PasteboardReach reach = PasteboardReach.whole}) =>
      BitmapSurface(
        canvasSize: canvas,
        pasteboardReach: reach,
        tileSize: side,
        tiles: {left: tileOf(1), right: tileOf(2)},
      );

  /// Nothing, on [like]'s grid — what a lift's picture is laid on.
  BitmapSurface nothingLike(BitmapSurface like) => BitmapSurface(
    canvasSize: like.canvasSize,
    pasteboardReach: like.pasteboardReach,
    tileSize: side,
  );

  /// A lift's picture centred [at]: clear at its rim, a pattern of colours
  /// inside at [alpha] — some of them grey, which a key takes away.
  BrushDab liftAt(
    CanvasPoint at, {
    int width = 60,
    int height = 40,
    int alpha = 255,
  }) {
    final rgba = Uint8List(width * height * 4);
    for (var y = 3; y < height - 3; y++) {
      for (var x = 3; x < width - 3; x++) {
        final n = x * 29 + y * 17;
        final grey = (x ~/ 6 + y ~/ 5).isEven;
        rgba.setAll((y * width + x) * 4, [
          if (grey) ...[128 + n % 9, 128, 128 - n % 7] else ...[
            (n * 37) & 255,
            (n * 23 + 91) & 255,
            (n * 11) & 255,
          ],
          alpha,
        ]);
      }
    }
    return BrushDab(
      center: at,
      color: 0xFFFFFFFF,
      size: (width > height ? width : height).toDouble(),
      opacity: 1,
      flow: 1,
      hardness: 1,
      tipShape: BrushTipShape.square,
      pressure: 1,
      sequence: 0,
      stamp: BrushStampImage(
        id: 'a-lift',
        width: width,
        height: height,
        rgba: rgba,
      ),
    );
  }

  /// [on] with [dab] stamped on it by the landing's own code.
  BitmapSurface stamped(BitmapSurface on, BrushDab dab) =>
      materializeBrushDabSequenceOnBitmapSurface(
        surface: on,
        sequence: BrushDabSequence([dab]),
      ).surface;

  /// [lift] carried by ([dx], [dy]), as the selection layer floats a move:
  /// its picture laid on nothing, at an offset.
  SelectionFloatOverlay carried(
    BrushDab lift,
    BitmapSurface over, {
    required int dx,
    required int dy,
    FloatLanding? lands,
  }) {
    final overlay = SelectionFloatOverlay(
      SelectionFloatPaint(
        surface: floatPainter(stamped(nothingLike(over), lift)),
        surfaceOffset: CanvasPoint(x: dx.toDouble(), y: dy.toDouble()),
        clip: over.pasteboard.rect,
        lands: lands,
      ),
    );
    addTearDown(overlay.dispose);
    return overlay;
  }

  BrushDab movedBy(BrushDab dab, int dx, int dy) => dab.copyWith(
    center: CanvasPoint(x: dab.center.x + dx, y: dab.center.y + dy),
  );

  FramePage pageOf(PasteboardReach reach) => (
    canvasSize: canvas,
    pasteboardReach: reach,
    paintPaper: true,
    paperBackground: const ProjectBackground.color(0xFF30A060),
  );

  /// The frame of one row, the pen's — [row] — drawn by [live], [float]
  /// over it.
  StackedFrame frameOf(
    BitmapSurfacePainter live, {
    SelectionFloatOverlay? float,
    CanvasActiveLayerRow row = const CanvasActiveLayerRow(opacity: 1),
    PasteboardReach reach = PasteboardReach.whole,
  }) => stackedFrameOf(
    [CompositeLeaf(row)],
    page: pageOf(reach),
    surfaceOf: (_) => null,
    live: (
      rows: (
        activeSurfacePainter: live,
        floatOverlay: float,
        liftedRows: const {},
      ),
      painters: LiftedRowPainters(),
    ),
  );

  /// What the engine's screen shows of [frame] through [viewport], [size]
  /// texels — its fingerprint.
  int shown(
    StackedFrame frame, {
    CanvasViewport? viewport,
    (int, int) size = (256, 128),
  }) => engine.shown(frame, size: size, viewport: viewport);

  for (final (dx, dy) in [(0, 0), (37, -11), (-70, 25)]) {
    test('🚨a float carried by ($dx, $dy) shows on the engine\'s screen as '
        'it lands', () {
      final base = cel();
      final lift = liftAt(CanvasPoint(x: 120, y: 60));
      final drawing = shown(
        frameOf(
          BitmapSurfacePainter(surface: base),
          float: carried(lift, base, dx: dx, dy: dy),
        ),
      );

      expect(
        drawing,
        shown(
          frameOf(
            BitmapSurfacePainter(surface: stamped(base, movedBy(lift, dx, dy))),
          ),
        ),
      );
      expect(
        drawing,
        isNot(shown(frameOf(BitmapSurfacePainter(surface: base)))),
        reason: 'the float shows while it is carried',
      );
    });
  }

  test('🚨a float carried over a row of no ink shows on the engine\'s '
      'screen as it lands', () {
    final base = nothingLike(cel());
    final lift = liftAt(CanvasPoint(x: 120, y: 60));
    final drawing = shown(
      frameOf(
        BitmapSurfacePainter(surface: base),
        float: carried(lift, base, dx: 37, dy: -11),
      ),
    );

    expect(
      drawing,
      shown(
        frameOf(
          BitmapSurfacePainter(surface: stamped(base, movedBy(lift, 37, -11))),
        ),
      ),
    );
    expect(
      drawing,
      isNot(shown(frameOf(BitmapSurfacePainter(surface: base)))),
      reason: 'the float shows while it is carried',
    );
  });

  /// What the screen shows of [frame] over the canvas and past it: 64 to
  /// its left, above and below it, 192 to its right.
  int shownPast(StackedFrame frame) => shown(
    frame,
    viewport: CanvasViewport(panX: 64, panY: 64),
    size: (canvas.width + 256, canvas.height + 128),
  );

  /// The pen's row through a blur.
  CanvasActiveLayerRow blurred() => CanvasActiveLayerRow(
    opacity: 1,
    effects: [fx(EffectKind.blur, {'blurriness': 6, 'blurDimensions': 0})],
  );

  for (final (name, at, dx, dy, seen) in [
    // The pasteboard as well: the screen's world holds the row as far as
    // its blur spreads, held or landed (`rowExtentWithItsReach`). ↩️It was
    // over the canvas alone while the world reached as far as the float's
    // tiles, at its offset, where the landed cel's reached its own tiles —
    // one tile apart on the pasteboard (pasteboard-blur-cut-at-row-extent,
    // 2026-11-08).
    ('on the canvas', CanvasPoint(x: 120, y: 60), 30, 9, shownPast),
    // Past every tile the cel holds and past the float's own tiles where
    // it was taken up: the chain's picture holds it where it is carried —
    // a whole tile on, so its tiles there are the landed cel's.
    ('past the canvas', CanvasPoint(x: 230, y: 60), 128, 0, shownPast),
  ]) {
    test('🚨a float $name shows through its row\'s blur as it lands '
        '(F-240)', () {
      final base = cel();
      final lift = liftAt(at);
      final row = blurred();
      final drawing = seen(
        frameOf(
          BitmapSurfacePainter(surface: base),
          float: carried(lift, base, dx: dx, dy: dy),
          row: row,
        ),
      );

      expect(
        drawing,
        seen(
          frameOf(
            BitmapSurfacePainter(
              surface: stamped(base, movedBy(lift, dx, dy)),
            ),
            row: row,
          ),
        ),
      );
    });
  }

  test('🚨a float carried past the wall shows cut there, as it lands — '
      'through a blur, which spreads what lies past it back inside', () {
    const reach = PasteboardReach.none;
    final base = cel(reach: reach);
    final lift = liftAt(CanvasPoint(x: 200, y: 64));
    // The canvas is the wall: what is past it is past the wall.
    final drawing = shownPast(
      frameOf(
        BitmapSurfacePainter(surface: base),
        float: carried(lift, base, dx: 40, dy: 50),
        row: blurred(),
        reach: reach,
      ),
    );

    expect(
      drawing,
      shownPast(
        frameOf(
          BitmapSurfacePainter(surface: stamped(base, movedBy(lift, 40, 50))),
          row: blurred(),
          reach: reach,
        ),
      ),
    );
  });

  // Half there as well: what a float lays over the cel it is held on is
  // what it leaves there landed, under the row's keys.
  for (final alpha in [255, 128]) {
    test('🚨on a row that keys its colours, a float at alpha $alpha shows '
        'keyed with the cel, as it lands', () {
      final keys = [
        fx(EffectKind.colorKey, {
          'keyOperation': 0,
          'keyColor': 0xFF808080,
          'tolerance': 40,
          'amount': 100,
        }),
      ];
      final row = CanvasActiveLayerRow(opacity: 1, effects: keys);
      final base = cel();
      final lift = liftAt(CanvasPoint(x: 120, y: 60), alpha: alpha);
      final landing = movedBy(lift, 21, 13);
      final drawing = shown(
        frameOf(
          BitmapSurfacePainter(surface: base),
          float: carried(
            lift,
            base,
            dx: 21,
            dy: 13,
            lands: (stamp: landing, on: _Cel(base, onCanvasGrid: true)),
          ),
          row: row,
        ),
      );

      expect(
        drawing,
        shown(
          frameOf(
            BitmapSurfacePainter(surface: stamped(base, landing)),
            row: row,
          ),
        ),
      );
    });
  }

  test('🚨on a posed row, a float shows as its landing, in place of what '
      'the cel shows there', () {
    const row = CanvasActiveLayerRow(
      opacity: 1,
      placement: GuideTransform(0, 1, -1, 0, 192, -64),
    );
    final base = cel();
    final lift = liftAt(CanvasPoint(x: 120, y: 60));
    final landed = stamped(base, movedBy(lift, 17, 5));
    final whole = DirtyRegion.wholePixelsOf(base.storableRect);
    final landing = CelTextLanding.of(
      whole,
      bitmapSurfaceRegionPixels(landed, whole),
    );
    addTearDown(landing.letGo);
    final drawing = shown(
      frameOf(
        BitmapSurfacePainter(surface: base),
        float: carried(
          lift,
          base,
          dx: 17,
          dy: 5,
          lands: (
            stamp: movedBy(lift, 17, 5),
            on: _Cel(base, onCanvasGrid: false, landing: landing),
          ),
        ),
        row: row,
      ),
    );

    expect(
      drawing,
      shown(frameOf(BitmapSurfacePainter(surface: landed), row: row)),
    );
    expect(
      drawing,
      isNot(shown(frameOf(BitmapSurfacePainter(surface: base), row: row))),
      reason: 'the landing shows while it is carried',
    );
  });

  test('🚨on a row posed by whole pixels, a float no lift holds a hole for '
      'shows itself, carried into the row\'s space, as it lands', () {
    const row = CanvasActiveLayerRow(
      opacity: 1,
      placement: GuideTransform(1, 0, 0, 1, 7, -3),
    );
    final base = cel();
    final lift = liftAt(CanvasPoint(x: 120, y: 60));
    final drawing = shown(
      frameOf(
        BitmapSurfacePainter(surface: base),
        float: carried(lift, base, dx: 25, dy: 14),
        row: row,
      ),
    );

    // Where it lies on the canvas, in the row's pixels: the pose undone.
    expect(
      drawing,
      shown(
        frameOf(
          BitmapSurfacePainter(
            surface: stamped(base, movedBy(lift, 25 - 7, 14 + 3)),
          ),
          row: row,
        ),
      ),
    );
  });

  test('🚨a warp\'s resample shows on the engine\'s screen as it lands',
      () async {
    final base = cel();
    // A centre between pixels: the landing rounds it, and so does the rect
    // its tiles stand on.
    final warped = liftAt(
      CanvasPoint(x: 140.5, y: 70.25),
      width: 75,
      height: 33,
    );
    final overlay = SelectionFloatOverlay(
      SelectionFloatPaint(
        resampled: FloatResampleShown.of(warped),
        clip: base.pasteboard.rect,
      ),
    );
    addTearDown(overlay.dispose);

    expect(
      shown(frameOf(BitmapSurfacePainter(surface: base), float: overlay)),
      shown(frameOf(BitmapSurfacePainter(surface: stamped(base, warped)))),
    );
  });

  // 🗣️pasteboard-blur-cut-at-row-extent-Q1 (유저 2026-11-08 「행 범위에 그
  // 행의 번짐을 넣는다」): the screen's world holds each row as far as its
  // chain spreads (`rowExtentWithItsReach`), a row beside the pen's too —
  // clear tiles stored round it are nothing to it.
  test('🚨a cel row\'s blur spreads on the pasteboard as far as it reaches',
      () {
    const key = BrushFrameKey(
      projectId: ProjectId('p'),
      trackId: TrackId('t'),
      cutId: CutId('c'),
      layerId: LayerId('blurred'),
      frameId: FrameId('f'),
    );
    final blur = [
      fx(EffectKind.blur, {'blurriness': 6, 'blurDimensions': 0}),
    ];
    final own = cel();
    final clearTile = BitmapTile(size: side, pixels: Uint8List(side * side * 4));
    final rounded = BitmapSurface(
      canvasSize: own.canvasSize,
      pasteboardReach: own.pasteboardReach,
      tileSize: side,
      tiles: {
        for (var y = -1; y <= 1; y += 1)
          for (var x = -1; x <= 2; x += 1)
            if (own.containsTileCoord(TileCoord(x: x, y: y)))
              TileCoord(x: x, y: y):
                  own.tiles[TileCoord(x: x, y: y)] ?? clearTile,
      },
    );
    int seen(BitmapSurface surface) => shownPast(
      stackedFrameOf(
        [
          CompositeLeaf<CanvasStackRow>(
            CanvasLayerImageRequest(frameKey: key, opacity: 1, effects: blur),
          ),
        ],
        page: pageOf(PasteboardReach.whole),
        surfaceOf: (_) => surface,
      ),
    );

    expect(seen(own), seen(rounded));
  });

  test('🚨a row a lift holds beside the pen\'s shows its float as it lands',
      () {
    const key = BrushFrameKey(
      projectId: ProjectId('p'),
      trackId: TrackId('t'),
      cutId: CutId('c'),
      layerId: LayerId('lifted'),
      frameId: FrameId('f'),
    );
    final base = cel();
    final lift = liftAt(CanvasPoint(x: 120, y: 60));
    const nodes = [
      CompositeLeaf<CanvasStackRow>(
        CanvasLayerImageRequest(frameKey: key, opacity: 1),
      ),
    ];
    final drawing = shown(
      stackedFrameOf(
        nodes,
        page: pageOf(PasteboardReach.whole),
        surfaceOf: (_) => null,
        live: (
          rows: (
            activeSurfacePainter: null,
            floatOverlay: null,
            liftedRows: {
              key: (surface: base, float: carried(lift, base, dx: 9, dy: 31)),
            },
          ),
          painters: LiftedRowPainters(),
        ),
      ),
    );

    expect(
      drawing,
      shown(
        stackedFrameOf(
          nodes,
          page: pageOf(PasteboardReach.whole),
          surfaceOf: (_) => stamped(base, movedBy(lift, 9, 31)),
        ),
      ),
    );
  });
}


/// A cel a float was taken up from: [holed] under it, on the canvas's grid
/// or not, and its landing where it is asked for one.
class _Cel implements FloatLandsOn {
  _Cel(this.holed, {required this.onCanvasGrid, this.landing});

  @override
  final BitmapSurface holed;

  @override
  final bool onCanvasGrid;

  final LandingPreview? landing;

  @override
  LandingPreview? landingShown(BrushDab stamp) => landing;
}
