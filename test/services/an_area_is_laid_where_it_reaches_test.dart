import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/core/floor_math.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/brush_blend_mode.dart';
import 'package:anicel/src/models/brush_dab.dart';
import 'package:anicel/src/models/brush_dab_sequence.dart';
import 'package:anicel/src/models/brush_stamp_image.dart';
import 'package:anicel/src/models/brush_tip_shape.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/shape_tool_options.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/native/qa_engine_abi.dart';
import 'package:anicel/src/native/qa_native_engine.dart';
import 'package:anicel/src/services/bitmap_surface_brush_commit.dart';
import 'package:anicel/src/services/brush_commit_builder.dart';
import 'package:anicel/src/services/brush_fill_promotion.dart';
import 'package:anicel/src/services/brush_stroke_commit_data.dart';
import 'package:anicel/src/services/canvas_flood_fill.dart';
import 'package:anicel/src/services/canvas_selection_paint_clip.dart';
import 'package:anicel/src/services/canvas_selection_region.dart';
import 'package:anicel/src/services/canvas_selection_shape.dart';
import 'package:anicel/src/services/mask_morphology.dart';
import 'package:anicel/src/services/mask_soft_edge.dart';
import 'package:anicel/src/services/plain_line_region.dart';

import '../helpers/fill_pieces.dart';
import '../helpers/native_engine_path.dart';

/// 🚨★★★board `an-area-dab-costs-its-box` (2026-10-09): an area — what the
/// shape tool lays without the brush, and the fill tool's shape fill — was
/// finished as ONE SHEET over its whole box, so a thin line across a big box
/// cost the box. It is finished only where it reaches now, and every fill —
/// the bucket's too — lands as stamp pieces cut on the cel's tiles.
///
/// Nothing a user sees may move for it: the pieces are pinned here against
/// the one sheet itself, restated below as the old code built it, and their
/// landing against that sheet's one stamp, on both engines, through every
/// route a stamp lands by.
void main() {
  const color = 0xFF336699;
  const layerId = LayerId('l');
  const frameId = FrameId('f');
  const grid = defaultCelTileSize;
  CanvasPoint p(double x, double y) => CanvasPoint(x: x, y: y);

  /// The area finished as ONE SHEET over its whole box — how it was laid
  /// before it was cut: the coverage box grown by all the finish reaches,
  /// the hard mask in it, then the expand's generations and the soften over
  /// all of it.
  ({int left, int top, int width, int height, Uint8List mask}) sheetOf(
    CanvasSelectionRegion region,
    FloodFillOptions options,
  ) {
    final bounds = region.coverageBounds;
    final left = bounds.left.floor();
    final top = bounds.top.floor();
    final width = bounds.right.ceil() - left;
    final height = bounds.bottom.ceil() - top;
    final grow = options.expandPx;
    // The box holds all the finish reaches: the expand, and the ramp's one
    // pixel past it (유저 답 the-fill-ramp-is-cut-at-its-box-Q1, 「상자를 한
    // 칸 넓혀 어디서나 번지게」).
    final reach = grow + (options.antiAlias ? 1 : 0);
    final hard = region.maskFor(
      left: left,
      top: top,
      width: width,
      height: height,
    );
    final sheetWidth = width + reach * 2;
    final sheetHeight = height + reach * 2;
    final mask = Uint8List(sheetWidth * sheetHeight);
    for (var y = 0; y < height; y += 1) {
      final at = (y + reach) * sheetWidth + reach;
      mask.setRange(at, at + width, hard, y * width);
    }
    dilateMask4(mask, width: sheetWidth, height: sheetHeight, passes: grow);
    if (options.antiAlias) {
      softenMaskBoundary(
        mask,
        width: sheetWidth,
        height: sheetHeight,
        insideOutlineOnly: false,
      );
    }
    return (
      left: left - reach,
      top: top - reach,
      width: sheetWidth,
      height: sheetHeight,
      mask: mask,
    );
  }

  /// That sheet as the ONE stamp dab it used to land as.
  BrushDab oneStampOf(
    ({int left, int top, int width, int height, Uint8List mask}) sheet, {
    required double opacity,
  }) {
    final rgba = Uint8List(sheet.width * sheet.height * 4);
    for (var i = 0; i < sheet.mask.length; i += 1) {
      if (sheet.mask[i] == 0) {
        continue;
      }
      rgba
        ..[i * 4] = 0x33
        ..[i * 4 + 1] = 0x66
        ..[i * 4 + 2] = 0x99
        ..[i * 4 + 3] = sheet.mask[i];
    }
    return BrushDab(
      center: p(
        sheet.left + sheet.width / 2,
        sheet.top + sheet.height / 2,
      ),
      color: color,
      size: (sheet.width > sheet.height ? sheet.width : sheet.height)
          .toDouble(),
      opacity: opacity,
      flow: 1,
      hardness: 1,
      tipShape: BrushTipShape.square,
      pressure: 1,
      sequence: 0,
      stamp: BrushStampImage(
        id: 'the-one-sheet',
        width: sheet.width,
        height: sheet.height,
        rgba: rgba,
      ),
    );
  }

  final areas = <String, CanvasSelectionRegion>{
    'a 4px diagonal across nine tiles': plainLineRegion(
      points: [p(3.3, 5.7), p(371.2, 340.9)],
      closed: false,
      width: 4,
      corners: ShapeCorners.sharp,
    )!,
    "a rectangle's outline astride the grid": plainLineRegion(
      points: [p(100.5, 120.25), p(420, 120.25), p(420, 300), p(100.5, 300)],
      closed: true,
      width: 6,
      corners: ShapeCorners.round,
    )!,
    'a filled ellipse': CanvasSelectionRegion.shape(
      CanvasSelectionShape.ellipse(left: 20, top: 30, right: 400, bottom: 290),
    ),
    'an outline out on the pasteboard, left of and above the canvas':
        plainLineRegion(
          points: [p(-300, -200), p(-20, -200), p(-20, 60), p(-300, 60)],
          closed: true,
          width: 3,
          corners: ShapeCorners.sharp,
        )!,
    'a box whose edges sit on the grid': CanvasSelectionRegion.shape(
      CanvasSelectionShape.rect(left: 128, top: 0, right: 384, bottom: 256),
    ),
    // One row of pixel centres, the last one above a tile row: what the
    // soften and the expand lay below it is in the NEXT row of tiles.
    'a hair along the bottom of a tile row': CanvasSelectionRegion.shape(
      CanvasSelectionShape.rect(left: 10, top: 127.2, right: 500, bottom: 128.4),
    ),
  };
  const optionsTried = [
    FloodFillOptions(expandPx: 0, antiAlias: false),
    FloodFillOptions(expandPx: 0, antiAlias: true),
    FloodFillOptions(expandPx: 1, antiAlias: true),
    FloodFillOptions(expandPx: 3, antiAlias: false),
    FloodFillOptions(expandPx: 3, antiAlias: true),
  ];

  /// The tiles of [grid] holding a covered byte of [sheet].
  Set<TileCoord> tilesOfTheSheet(
    ({int left, int top, int width, int height, Uint8List mask}) sheet,
  ) => {
    for (var y = 0; y < sheet.height; y += 1)
      for (var x = 0; x < sheet.width; x += 1)
        if (sheet.mask[y * sheet.width + x] != 0)
          TileCoord.fromPixel(
            pixelX: sheet.left + x,
            pixelY: sheet.top + y,
            tileSize: grid,
          ),
  };

  test('an area\'s pieces lay, byte for byte, what ONE sheet over its whole '
      'box laid — through the expand and the soften, across tile edges, out '
      'on the pasteboard', () {
    for (final MapEntry(key: name, value: region) in areas.entries) {
      for (final options in optionsTried) {
        final why = '$name, expand ${options.expandPx} AA ${options.antiAlias}';
        final sheet = sheetOf(region, options);
        final pieces = buildRegionFillDabs(
          region: region,
          color: color,
          opacity: 0.7,
          options: options,
        );
        // Every byte the pieces lay, laid out over the sheet's box — and
        // no piece outside it, and no pixel laid twice.
        final laid = Uint8List(sheet.width * sheet.height);
        final written = Uint8List(sheet.width * sheet.height);
        for (final piece in pieces) {
          final stamp = piece.stamp!;
          final landing = stamp.landingRect(piece.center);
          expect(landing.left, greaterThanOrEqualTo(sheet.left), reason: why);
          expect(landing.top, greaterThanOrEqualTo(sheet.top), reason: why);
          expect(
            landing.rightExclusive,
            lessThanOrEqualTo(sheet.left + sheet.width),
            reason: why,
          );
          expect(
            landing.bottomExclusive,
            lessThanOrEqualTo(sheet.top + sheet.height),
            reason: why,
          );
          var anything = false;
          for (var y = 0; y < stamp.height; y += 1) {
            for (var x = 0; x < stamp.width; x += 1) {
              final at =
                  (landing.top - sheet.top + y) * sheet.width +
                  (landing.left - sheet.left + x);
              expect(written[at], 0, reason: '$why: a pixel laid twice');
              written[at] = 1;
              final alpha = stamp.rgba[(y * stamp.width + x) * 4 + 3];
              laid[at] = alpha;
              if (alpha != 0) {
                anything = true;
                expect(
                  stamp.rgba.sublist(
                    (y * stamp.width + x) * 4,
                    (y * stamp.width + x) * 4 + 3,
                  ),
                  [0x33, 0x66, 0x99],
                  reason: why,
                );
              }
            }
          }
          expect(anything, isTrue, reason: '$why: a piece with nothing in it');
          expect(piece.opacity, 0.7, reason: why);
        }
        expect(laid, sheet.mask, reason: '$why: what the one sheet laid');
        // Cut on the cel's own tiles, a piece a run of one row of them.
        for (final piece in pieces) {
          final landing = piece.stamp!.landingRect(piece.center);
          expect(
            floorDiv(landing.bottomExclusive - 1, grid) -
                floorDiv(landing.top, grid),
            0,
            reason: '$why: one row of tiles',
          );
          expect(
            landing.left == sheet.left || landing.left % grid == 0,
            isTrue,
            reason: '$why: starts on a tile edge',
          );
        }
        expect(
          {for (final piece in pieces) piece.stamp!.id}.length,
          pieces.length,
          reason: '$why: a stamp is equal to another by its id — no two '
              'pieces may share one',
        );
      }
    }
  });

  test('ONLY where it reaches: a thin line across a big box carries the '
      'tiles it crosses and not one more', () {
    for (final MapEntry(key: name, value: region) in areas.entries) {
      for (final options in optionsTried) {
        final why = '$name, expand ${options.expandPx} AA ${options.antiAlias}';
        final pieces = buildRegionFillDabs(
          region: region,
          color: color,
          options: options,
        );
        final carried = <TileCoord>{};
        for (final piece in pieces) {
          final landing = piece.stamp!.landingRect(piece.center);
          for (var x = landing.left; x < landing.rightExclusive; x += 1) {
            carried.add(
              TileCoord.fromPixel(
                pixelX: x,
                pixelY: landing.top,
                tileSize: grid,
              ),
            );
          }
        }
        expect(carried, tilesOfTheSheet(sheetOf(region, options)), reason: why);
      }
    }
    // The line that made the card: a thin diagonal across a box the size
    // of a page is carried by the few tiles it crosses, not by the box.
    const options = FloodFillOptions(expandPx: 0, antiAlias: true);
    final diagonal = plainLineRegion(
      points: [p(100, 100), p(2100, 1600)],
      closed: false,
      width: 4,
      corners: ShapeCorners.sharp,
    )!;
    final sheet = sheetOf(diagonal, options);
    final boxTiles =
        (floorDiv(sheet.left + sheet.width - 1, grid) -
                floorDiv(sheet.left, grid) +
                1) *
        (floorDiv(sheet.top + sheet.height - 1, grid) -
                floorDiv(sheet.top, grid) +
                1);
    var laidPixels = 0;
    for (final piece in buildRegionFillDabs(
      region: diagonal,
      color: color,
      options: options,
    )) {
      laidPixels += piece.stamp!.width * piece.stamp!.height;
    }
    expect(tilesOfTheSheet(sheet).length * 4, lessThan(boxTiles));
    expect(laidPixels * 4, lessThan(sheet.width * sheet.height));
  });

  test('an area that covers no pixel lays no piece', () {
    expect(
      buildRegionFillDabs(
        region: CanvasSelectionRegion.shape(
          CanvasSelectionShape.rect(left: 0, top: 0.6, right: 900, bottom: 1.4),
        ),
        color: color,
      ),
      isEmpty,
    );
  });

  group('the pieces LAND what the one stamp landed', () {
    final dllPath = nativeEngineLibraryPathOrNull();
    const canvas = CanvasSize(width: 512, height: 384);

    tearDown(() {
      QaNativeEngine.debugResetForTests();
      debugQaEngineLibraryPathOverride = null;
      QaNativeEngine.debugForceDartFallback = false;
    });

    /// Paint under the area, where a blend has something to read.
    BitmapSurface painted() => materializeBrushDabSequenceOnBitmapSurface(
      surface: BitmapSurface(canvasSize: canvas),
      sequence: BrushDabSequence([
        for (var i = 0; i < 9; i += 1)
          BrushDab(
            center: p(-150.5 + i * 70.0, 60.5 + (i.isEven ? 0 : 120)),
            color: 0xD0994411,
            size: 150,
            opacity: 1,
            flow: 1,
            hardness: 0.6,
            tipShape: BrushTipShape.round,
            pressure: 1,
            sequence: i,
          ),
      ]),
    ).surface;

    BitmapSurface landed(
      List<BrushDab> dabs,
      BitmapSurface base,
      BrushBlendMode mode, {
      CanvasSelectionRegion? selection,
    }) {
      final raw = BrushStrokeCommitData(
        sourceDabs: [for (final dab in dabs) dab.underBlend(mode)],
        blendMode: mode,
      );
      final data = selection == null
          ? raw
          : clipStrokeCommitToSelection(raw, region: selection, surface: base)!;
      return brushCommitResultForBrushDabSequenceOnBitmapSurface(
        surface: base,
        sequence: BrushDabSequence(data.sourceDabs),
        layerId: layerId,
        frameId: frameId,
        prerasterizedStrokePixels: data.strokePixels,
        prerasterizedStrokeBounds: data.strokeBounds,
        blendMode: mode,
      ).afterSurface;
    }

    /// The first pixel that SHOWS differently in [a] and [b], or null.
    ///
    /// ⚠️Under alpha 0 the colour is nobody's: a soft edge leaves the colour
    /// it was painted with there, and a composite of the whole stroke (a
    /// blend, 뒤에 그리기) clears it wherever it passes — the one sheet
    /// passed over its whole box and a piece passes over itself. Every
    /// byte of every pixel that is not clear on both sides must match.
    String? firstVisibleDifference(BitmapSurface a, BitmapSurface b) {
      final coords = {...a.tiles.keys, ...b.tiles.keys};
      for (final coord in coords) {
        final ta = a.tileAt(coord)?.pixels;
        final tb = b.tileAt(coord)?.pixels;
        final length = (ta ?? tb)!.length;
        for (var i = 0; i < length; i += 4) {
          final clearA = ta == null || ta[i + 3] == 0;
          final clearB = tb == null || tb[i + 3] == 0;
          if (clearA && clearB) {
            continue;
          }
          for (var c = 0; c < 4; c += 1) {
            final va = ta == null ? 0 : ta[i + c];
            final vb = tb == null ? 0 : tb[i + c];
            if (va != vb) {
              return '$coord pixel ${i ~/ 4} channel $c: $va vs $vb';
            }
          }
        }
      }
      return null;
    }

    void onEachEngine(String name, void Function() body) {
      test('$name — Dart engine', () {
        QaNativeEngine.debugResetForTests();
        QaNativeEngine.debugForceDartFallback = true;
        expect(QaNativeEngine.instance, isNull);
        body();
      });
      test('$name — native engine', () {
        if (dllPath == null) {
          markTestSkipped(nativeEngineMissingSkipReason);
          return;
        }
        QaNativeEngine.debugResetForTests();
        debugQaEngineLibraryPathOverride = dllPath;
        QaNativeEngine.debugForceDartFallback = false;
        expect(QaNativeEngine.instance, isNotNull);
        body();
      });
    }

    onEachEngine('painting, erasing, multiplying and 뒤에 그리기, with a '
        'selection and without', () {
      final base = painted();
      final selection = CanvasSelectionRegion.shape(
        CanvasSelectionShape.ellipse(
          left: -120,
          top: 40,
          right: 330,
          bottom: 260,
        ),
      );
      for (final name in [
        'a 4px diagonal across nine tiles',
        "a rectangle's outline astride the grid",
        'an outline out on the pasteboard, left of and above the canvas',
      ]) {
        const options = FloodFillOptions(expandPx: 1, antiAlias: true);
        final region = areas[name]!;
        final pieces = buildRegionFillDabs(
          region: region,
          color: color,
          opacity: 0.6,
          options: options,
        );
        final one = [oneStampOf(sheetOf(region, options), opacity: 0.6)];
        for (final mode in [
          BrushBlendMode.color,
          BrushBlendMode.erase,
          BrushBlendMode.multiply,
          BrushBlendMode.behind,
        ]) {
          for (final within in [null, selection]) {
            expect(
              firstVisibleDifference(
                landed(pieces, base, mode, selection: within),
                landed(one, base, mode, selection: within),
              ),
              isNull,
              reason: '$name, ${mode.name}, '
                  '${within == null ? 'no selection' : 'in a selection'}',
            );
          }
        }
      }
    });

    onEachEngine('a fill shown before it commits is still its commit, cut '
        'in pieces', () {
      final base = painted();
      final region = areas["a rectangle's outline astride the grid"]!;
      final selection = CanvasSelectionRegion.shape(
        CanvasSelectionShape.rect(left: 90, top: 100, right: 300, bottom: 320),
      );
      final pieces = [
        for (final piece in buildRegionFillDabs(
          region: region,
          color: color,
          opacity: 0.5,
        ))
          piece.underBlend(BrushBlendMode.color),
      ];
      expect(pieces.length, greaterThan(1), reason: 'the premise: pieces');
      final promoted = promoteFillDabs(
        surface: base,
        dabs: pieces,
        blendMode: BrushBlendMode.color,
        selection: selection,
        layerId: layerId,
        frameId: frameId,
      );
      final classic = landed(
        pieces,
        base,
        BrushBlendMode.color,
        selection: selection,
      );
      final installed = base.putMaterializedTiles([
        for (final entry in promoted) (coord: entry.coord, tile: entry.tile),
      ]);
      expect(firstVisibleDifference(installed, classic), isNull);
    });
  });

  group('the bucket lands in pieces too', () {
    // Two outlines: a frame round the page, and a box whose inside holds
    // the whole of tile (1, 1) — so the fill between them is a ring with
    // a hole a tile wide.
    const canvas = CanvasSize(width: 320, height: 320);
    bool isInk(int x, int y) {
      bool outline(int from, int to) =>
          (x >= from && x <= to && (y == from || y == to)) ||
          (y >= from && y <= to && (x == from || x == to));
      return outline(10, 300) || outline(120, 264);
    }

    BitmapSurface inked() {
      const size = 64;
      final buffers = <TileCoord, Uint8List>{};
      for (var y = 0; y < canvas.height; y += 1) {
        for (var x = 0; x < canvas.width; x += 1) {
          if (!isInk(x, y)) {
            continue;
          }
          final buffer = buffers.putIfAbsent(
            TileCoord(x: x ~/ size, y: y ~/ size),
            () => Uint8List(size * size * 4),
          );
          buffer[((y % size) * size + x % size) * 4 + 3] = 255;
        }
      }
      return BitmapSurface(
        canvasSize: canvas,
        tileSize: size,
        tiles: {
          for (final entry in buffers.entries)
            entry.key: BitmapTile(size: size, pixels: entry.value),
        },
      );
    }

    test('a ring\'s fill is four pieces — a whole tile empty in its middle '
        'carries nothing — and lays exactly the ring', () {
      final surface = inked();
      final pieces = buildFillDabs(
        cut: Cut(
          id: const CutId('cut'),
          name: 'Cut',
          layers: [
            Layer(
              id: const LayerId('ink'),
              name: 'Ink',
              frames: [
                Frame(id: const FrameId('ink'), duration: 1, strokes: const []),
              ],
              timeline: {
                0: const TimelineExposure.drawing(FrameId('ink'), length: 1),
              },
            ),
          ],
          duration: 24,
          canvasSize: canvas,
        ),
        frameIndex: 0,
        surfaceResolver: (_, _) => surface,
        point: p(50.5, 50.5),
        color: color,
        options: const FloodFillOptions(expandPx: 0, antiAlias: false),
      );
      expect(pieces, hasLength(4), reason: 'rows 0 and 2 whole, row 1 split');
      for (var y = 0; y < canvas.height; y += 1) {
        for (var x = 0; x < canvas.width; x += 1) {
          final inRing =
              x > 10 && x < 300 && y > 10 && y < 300 &&
              !(x >= 120 && x <= 264 && y >= 120 && y <= 264);
          expect(
            piecesAlphaAt(pieces, x, y),
            inRing ? 255 : 0,
            reason: '($x, $y)',
          );
        }
      }
      for (final piece in pieces) {
        final landing = piece.stamp!.landingRect(piece.center);
        expect(
          landing.left >= 256 || landing.rightExclusive <= 128 ||
              landing.bottomExclusive <= 128 || landing.top >= 256,
          isTrue,
          reason: 'tile (1, 1) is all hole: no piece carries it',
        );
      }
    });
  });
}
