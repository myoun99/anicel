import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/brush_blend_mode.dart';
import 'package:anicel/src/models/brush_dab.dart';
import 'package:anicel/src/models/brush_dab_sequence.dart';
import 'package:anicel/src/models/brush_edit_canvas_input_settings.dart';
import 'package:anicel/src/models/brush_mixing_method.dart';
import 'package:anicel/src/models/brush_settings.dart';
import 'package:anicel/src/models/brush_shape.dart';
import 'package:anicel/src/models/brush_tip_shape.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/pasteboard_bounds.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/native/qa_blur_kernel.dart';
import 'package:anicel/src/native/qa_engine_abi.dart';
import 'package:anicel/src/native/qa_native_engine.dart';
import 'package:anicel/src/services/brush_blur_stroke_landing.dart';
import 'package:anicel/src/services/brush_commit_builder.dart';
import 'package:anicel/src/services/brush_dab_dirty_region.dart';
import 'package:anicel/src/services/brush_dab_kernel.dart';
import 'package:anicel/src/services/brush_ground_color_mixing.dart';
import 'package:anicel/src/services/brush_live_stroke_rasterizer.dart';
import 'package:anicel/src/services/brush_preset_defaults.dart';
import 'package:anicel/src/services/brush_stroke_commit_data.dart';
import 'package:anicel/src/services/canvas_selection_paint_clip.dart';
import 'package:anicel/src/services/canvas_selection_region.dart';
import 'package:anicel/src/services/canvas_selection_shape.dart';

import '../helpers/native_engine_path.dart';

/// 🗣️I-75 흐리기 (유저 2026-10-27): a brush in the mixing group that blurs
/// what is already drawn — no slider of its own (Q3: its size is how far it
/// smears, its flow and the pen's pressure how hard) — and blurs further
/// the more it is rubbed (Q4).
///
/// The law is `BrushBlurPicture`'s; these pin what it promises and that the
/// screen, the pen-up landing and a stroke re-derived from its dabs all
/// land the same bytes.
void main() {
  const canvasSize = CanvasSize(width: 192, height: 128);
  const tileSize = 64;
  const layerId = LayerId('l');
  const frameId = FrameId('f');
  final wall = canvasSize.pasteboardAt(PasteboardReach.whole);
  final dllPath = nativeEngineLibraryPathOrNull();

  tearDown(() {
    QaNativeEngine.debugResetForTests();
    debugQaEngineLibraryPathOverride = null;
    QaNativeEngine.debugForceDartFallback = false;
  });

  /// A cel whose pixel at (x, y) is [argbAt]'s.
  BitmapSurface celOf(int Function(int x, int y) argbAt) {
    final tiles = [
      for (var tileY = 0; tileY < canvasSize.height ~/ tileSize; tileY += 1)
        for (var tileX = 0; tileX < canvasSize.width ~/ tileSize; tileX += 1)
          (
            coord: TileCoord(x: tileX, y: tileY),
            tile: BitmapTile(
              size: tileSize,
              pixels: Uint8List(tileSize * tileSize * 4)
                ..setAll(0, [
                  for (var y = 0; y < tileSize; y += 1)
                    for (var x = 0; x < tileSize; x += 1)
                      ...() {
                        final argb = argbAt(
                          tileX * tileSize + x,
                          tileY * tileSize + y,
                        );
                        return [
                          (argb >> 16) & 0xFF,
                          (argb >> 8) & 0xFF,
                          argb & 0xFF,
                          (argb >> 24) & 0xFF,
                        ];
                      }(),
                ]),
            ),
          ),
    ];
    return BitmapSurface(
      canvasSize: canvasSize,
      tileSize: tileSize,
    ).putTiles(tiles);
  }

  /// Opaque blue on the left, half-transparent orange on the right — an
  /// edge to smear, colour on both sides of it.
  BitmapSurface edgeCel() =>
      celOf((x, y) => x < 96 ? 0xFF2244CC : 0x80EE8811);

  BrushDab blurDab(double x, double y, int sequence, {double flow = 0.6}) =>
      BrushDab(
        center: CanvasPoint(x: x, y: y),
        color: 0xFF000000,
        size: 24,
        opacity: 1,
        flow: flow,
        hardness: 0.5,
        tipShape: BrushTipShape.round,
        pressure: 1,
        sequence: sequence,
        blurs: true,
      );

  /// Across the edge and back, two rows apart: every pixel near the edge is
  /// rubbed by many dabs, each reading what the ones before it left.
  List<BrushDab> rub({int passes = 1}) => [
    for (var pass = 0; pass < passes; pass += 1) ...[
      for (var i = 0; i < 24; i += 1)
        blurDab(60.0 + i * 3, 60.5, pass * 48 + i),
      for (var i = 0; i < 24; i += 1)
        blurDab(132.0 - i * 3, 66.5, pass * 48 + 24 + i),
    ],
  ];

  /// What the user watched: the live rasterizer fed a pointer-move at a
  /// time, the screen asking for its tiles between moves, promoted at
  /// pen-up.
  BitmapSurface live(
    List<BrushDab> dabs,
    BitmapSurface base, {
    double opacity = 1,
    CanvasSelectionRegion? selection,
  }) {
    final rasterizer =
        BrushLiveStrokeRasterizer(pasteboard: wall, tileSize: tileSize)
          ..selectionRegion = selection
          ..strokeOpacity = opacity
          ..blurOver(base);
    for (var from = 0; from < dabs.length; from += 5) {
      final region = rasterizer.blendFrom(
        dabs.sublist(0, (from + 5).clamp(0, dabs.length)),
        from: from,
      );
      if (region != null) {
        final range = region.tileRange(tileSize: tileSize);
        rasterizer.preBlendedOverlayTiles(
          coords: [
            for (var y = range.firstY; y <= range.lastY; y += 1)
              for (var x = range.firstX; x <= range.lastX; x += 1)
                TileCoord(x: x, y: y),
          ],
          base: base,
          mode: BrushBlendMode.color,
          erase: false,
        );
      }
    }
    final promoted = rasterizer.promoteStrokeTiles(
      base: base,
      mode: BrushBlendMode.color,
      erase: false,
    );
    rasterizer.clear();
    return base.putTiles([
      for (final entry in promoted) (coord: entry.coord, tile: entry.tile),
    ]);
  }

  /// The same stroke with nothing but its dabs — a commit after the cel
  /// moved, 확정 on another cel.
  BitmapSurface rederived(
    List<BrushDab> dabs,
    BitmapSurface base, {
    double opacity = 1,
  }) => brushCommitResultForBrushDabSequenceOnBitmapSurface(
    surface: base,
    sequence: BrushDabSequence(dabs, opacity),
    layerId: layerId,
    frameId: frameId,
  ).afterSurface;

  /// Each surface read once, as ARGB per canvas pixel — surfaces are
  /// immutable, so the reading stands.
  final canvases = Expando<Uint32List>();
  Uint32List canvasOf(BitmapSurface surface) =>
      canvases[surface] ??= () {
        final argb = Uint32List(canvasSize.width * canvasSize.height);
        for (final MapEntry(key: coord, value: tile)
            in surface.tiles.entries) {
          final pixels = tile.pixels;
          for (var y = 0; y < tileSize; y += 1) {
            for (var x = 0; x < tileSize; x += 1) {
              final canvasX = coord.x * tileSize + x;
              final canvasY = coord.y * tileSize + y;
              if (canvasX < 0 ||
                  canvasY < 0 ||
                  canvasX >= canvasSize.width ||
                  canvasY >= canvasSize.height) {
                continue;
              }
              final i = (y * tileSize + x) * 4;
              argb[canvasY * canvasSize.width + canvasX] =
                  (pixels[i + 3] << 24) |
                  (pixels[i] << 16) |
                  (pixels[i + 1] << 8) |
                  pixels[i + 2];
            }
          }
        }
        return argb;
      }();

  int pixelAt(BitmapSurface surface, int x, int y) =>
      canvasOf(surface)[y * canvasSize.width + x];

  void expectSameArtwork(
    BitmapSurface actual,
    BitmapSurface expected,
    String reason,
  ) {
    for (var y = 0; y < canvasSize.height; y += 1) {
      for (var x = 0; x < canvasSize.width; x += 1) {
        final a = pixelAt(actual, x, y);
        final b = pixelAt(expected, x, y);
        if (a != b) {
          fail(
            '$reason: ($x, $y) is ${a.toRadixString(16)}, '
            'expected ${b.toRadixString(16)}',
          );
        }
      }
    }
  }

  int movedPixels(BitmapSurface after, BitmapSurface before) {
    var moved = 0;
    for (var y = 0; y < canvasSize.height; y += 1) {
      for (var x = 0; x < canvasSize.width; x += 1) {
        if (pixelAt(after, x, y) != pixelAt(before, x, y)) {
          moved += 1;
        }
      }
    }
    return moved;
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
      expect(
        QaBlurKernel.instance,
        isNotNull,
        reason: 'the engine is loaded, so its blur runs in the C',
      );
      body();
    });
  }

  onEachEngine('what the screen showed is what lands — promoted at pen-up, '
      're-derived from the dabs, and cut by a selection that covers it', () {
    final base = edgeCel();
    final dabs = rub();
    final watched = live(dabs, base);
    expect(
      movedPixels(watched, base),
      greaterThan(500),
      reason: 'premise: the stroke smeared the edge',
    );
    expectSameArtwork(rederived(dabs, base), watched, 're-derived');

    final clipped = clipStrokeCommitToSelection(
      BrushStrokeCommitData(sourceDabs: dabs),
      region: CanvasSelectionRegion.shape(
        CanvasSelectionShape.rect(left: 0, top: 0, right: 192, bottom: 128),
      ),
      surface: base,
    )!;
    expectSameArtwork(
      brushCommitResultForBrushDabSequenceOnBitmapSurface(
        surface: base,
        sequence: BrushDabSequence(dabs),
        layerId: layerId,
        frameId: frameId,
        promotedBase: clipped.promotedBase,
        promotedTiles: clipped.promotedTiles,
      ).afterSurface,
      watched,
      'through a selection that covers it',
    );
  });

  onEachEngine('the screen shows, tile for tile, what pen-up lands', () {
    final base = edgeCel();
    final rasterizer =
        BrushLiveStrokeRasterizer(pasteboard: wall, tileSize: tileSize)
          ..blurOver(base);
    rasterizer.blendFrom(rub(), from: 0);
    final coords = [
      for (var y = 0; y < canvasSize.height ~/ tileSize; y += 1)
        for (var x = 0; x < canvasSize.width ~/ tileSize; x += 1)
          TileCoord(x: x, y: y),
    ];
    final shown = rasterizer.preBlendedOverlayTiles(
      coords: coords,
      base: base,
      mode: BrushBlendMode.color,
      erase: false,
    );
    final screen = {
      for (var i = 0; i < coords.length; i += 1)
        if (shown[i] case final tile?)
          coords[i]: tile.readStraight(Uint8List.fromList),
    };
    final landed = rasterizer.promoteStrokeTiles(
      base: base,
      mode: BrushBlendMode.color,
      erase: false,
    );
    rasterizer.clear();
    expect(screen, isNotEmpty, reason: 'the screen showed the stroke');
    expect(
      {for (final entry in landed) entry.coord: entry.tile.pixels},
      screen,
    );
  });

  /// The plain reading of the law (`BrushBlurPicture`), dab by dab, on a
  /// premultiplied 16-bit plane padded with nothing: what each dab lays
  /// onto an empty plane, measured afresh by the dab kernel; the whole
  /// plane blurred — three box passes along the rows, then three along the
  /// columns, each a sixth of the dab's size, means rounded half up; each
  /// pixel moved toward its blur by that share, rounded half away from
  /// zero. Straight ARGB per canvas pixel.
  Uint32List byTheLaw(BitmapSurface base, List<BrushDab> dabs) {
    const pad = 40;
    const width = 192 + pad * 2;
    const height = 128 + pad * 2;
    var plane = List<int>.filled(width * height * 4, 0);
    for (var y = 0; y < 128; y += 1) {
      for (var x = 0; x < 192; x += 1) {
        final argb = pixelAt(base, x, y);
        final alpha = argb >> 24;
        final o = ((y + pad) * width + x + pad) * 4;
        for (final (c, shift) in [(0, 16), (1, 8), (2, 0)]) {
          final channel = (argb >> shift) & 0xFF;
          plane[o + c] = (channel * alpha * 514 + 255) ~/ 510;
        }
        plane[o + 3] = alpha * 257;
      }
    }

    List<int> pass(List<int> from, int radius, {required bool alongRows}) {
      final count = radius * 2 + 1;
      final to = List<int>.filled(from.length, 0);
      for (var y = 0; y < height; y += 1) {
        for (var x = 0; x < width; x += 1) {
          for (var c = 0; c < 4; c += 1) {
            var sum = 0;
            for (var k = -radius; k <= radius; k += 1) {
              final sx = alongRows ? x + k : x;
              final sy = alongRows ? y : y + k;
              if (sx >= 0 && sx < width && sy >= 0 && sy < height) {
                sum += from[(sy * width + sx) * 4 + c];
              }
            }
            to[(y * width + x) * 4 + c] = (sum * 2 + count) ~/ (count * 2);
          }
        }
      }
      return to;
    }

    int scaled(int difference, int factor, int whole) => difference >= 0
        ? (difference * factor * 2 + whole) ~/ (whole * 2)
        : -((-difference * factor * 2 + whole) ~/ (whole * 2));

    for (final dab in dabs) {
      const scratch = 64;
      final planes = <(int, int), BrushDabTileBuffers>{};
      blendDabTilesDart(
        BrushDabPlan.of(
          dab.copyWith(color: 0xFFFFFFFF),
          wall: wall,
          tileSize: scratch,
          erase: false,
        )!,
        tileSize: scratch,
        bufferFor: (tileX, tileY) => planes.putIfAbsent(
          (tileX, tileY),
          () => (
            bytes: Uint8List(scratch * scratch * 4),
            wide: Uint16List(scratch * scratch * 4),
            second: null,
          ),
        ),
      );
      final radius = (dab.size / 6).round().clamp(1, 1 << 30);
      var blurred = plane;
      for (var i = 0; i < 3; i += 1) {
        blurred = pass(blurred, radius, alongRows: true);
      }
      for (var i = 0; i < 3; i += 1) {
        blurred = pass(blurred, radius, alongRows: false);
      }
      final next = List<int>.of(plane);
      for (final MapEntry(key: (tileX, tileY), value: planesOfTile)
          in planes.entries) {
        for (var i = 0; i < scratch * scratch; i += 1) {
          final share = planesOfTile.wide[i * 4 + 3];
          if (share == 0) {
            continue;
          }
          final x = tileX * scratch + i % scratch + pad;
          final y = tileY * scratch + i ~/ scratch + pad;
          final o = (y * width + x) * 4;
          final alpha =
              plane[o + 3] + scaled(blurred[o + 3] - plane[o + 3], share, 65535);
          next[o + 3] = alpha;
          for (var c = 0; c < 3; c += 1) {
            next[o + c] =
                plane[o + c] + scaled(blurred[o + c] - plane[o + c], share, 65535);
            // Held by nothing in the law: the order the blur and the move
            // keep (M9).
            expect(next[o + c], lessThanOrEqualTo(alpha), reason: 'a channel '
                'passed its alpha at ($x, $y)');
          }
        }
      }
      plane = next;
    }

    final argb = Uint32List(192 * 128);
    for (var y = 0; y < 128; y += 1) {
      for (var x = 0; x < 192; x += 1) {
        final o = ((y + pad) * width + x + pad) * 4;
        final alpha = plane[o + 3];
        final outAlpha = (alpha * 2 + 257) ~/ 514;
        int straight(int channel) =>
            outAlpha == 0 ? 0 : (channel * 510 + alpha) ~/ (alpha * 2);
        argb[y * 192 + x] =
            (outAlpha << 24) |
            (straight(plane[o]) << 16) |
            (straight(plane[o + 1]) << 8) |
            straight(plane[o + 2]);
      }
    }
    return argb;
  }

  void expectByTheLaw(List<BrushDab> dabs, {BitmapSurface? over}) {
    final base = over ?? edgeCel();
    final landed = live(dabs, base);
    final expected = byTheLaw(base, dabs);
    var moved = 0;
    for (var y = 0; y < 128; y += 1) {
      for (var x = 0; x < 192; x += 1) {
        final got = pixelAt(landed, x, y);
        expect(
          got,
          expected[y * 192 + x],
          reason: '($x, $y)',
        );
        if (got != pixelAt(base, x, y)) {
          moved += 1;
        }
      }
    }
    expect(moved, greaterThan(100), reason: 'premise: the edge was smeared');
  }

  BrushDab dabAt(
    double x, {
    required double flow,
    required double hardness,
    int sequence = 0,
    double? pathStep,
    double size = 24,
  }) => BrushDab(
    center: CanvasPoint(x: x, y: 64),
    color: 0xFF000000,
    size: size,
    opacity: 1,
    flow: flow,
    hardness: hardness,
    tipShape: BrushTipShape.round,
    pressure: 1,
    sequence: sequence,
    blurs: true,
    pathStep: pathStep,
  );

  onEachEngine('one hard dab leaves exactly the picture blurred under it, '
      'by the law written beside it', () {
    expectByTheLaw([dabAt(96, flow: 1, hardness: 1)]);
  });

  onEachEngine('a dab wide enough to share its passes out among threads '
      'lays the law too', () {
    // 84px: a window of 168² pixels, past the C's 128² floor for the pool.
    expectByTheLaw([dabAt(96, flow: 0.7, hardness: 0.6, size: 84)]);
  });

  onEachEngine('soft dabs rubbed over each other each read what the ones '
      'before them left, by the law written beside it', () {
    expectByTheLaw([
      for (var i = 0; i < 4; i += 1)
        dabAt(
          90.0 + i * 3,
          flow: 0.35,
          hardness: 0.4,
          sequence: i,
          pathStep: i == 0 ? null : 3,
        ),
    ]);
  });

  onEachEngine('a dab whose blur reaches tiles it does not touch reads them '
      'as the cel has them, by the law written beside it', () {
    // A hard square in the corner of tile (0, 0): its window runs a reach
    // into the three tiles beside it, which it never rewrites — so the
    // corner it moves is mostly what it reads from them.
    final dab = BrushDab(
      center: CanvasPoint(x: 52, y: 52),
      color: 0xFF000000,
      size: 24,
      opacity: 1,
      flow: 1,
      hardness: 1,
      tipShape: BrushTipShape.square,
      pressure: 1,
      sequence: 0,
      blurs: true,
    );
    final plan = BrushDabPlan.of(
      dab,
      wall: wall,
      tileSize: tileSize,
      erase: false,
    )!;
    final range = plan.clip.tileRange(tileSize: tileSize);
    expect(
      (range.firstX, range.lastX, range.firstY, range.lastY),
      (0, 0, 0, 0),
      reason: 'premise: the dab touches one tile',
    );
    expect(
      plan.rightExclusive + (24 / 6).round() * 3,
      greaterThan(tileSize),
      reason: 'premise: its window reaches past it',
    );
    expectByTheLaw(
      [dab],
      over: celOf(
        (x, y) => (x ~/ 6 + y ~/ 6).isEven ? 0xFF2244CC : 0xFFEE8811,
      ),
    );
  });

  onEachEngine('over a cel with tiles missing, the blur reads nothing there '
      '— also in memory a stroke before it let go', () {
    // The stroke before leaves its rewritten tiles' blocks to be handed out
    // again, its picture still in them.
    live(rub(), edgeCel());
    final whole = edgeCel();
    expectByTheLaw(
      rub(),
      over: BitmapSurface(canvasSize: canvasSize, tileSize: tileSize).putTiles([
        for (final coord in [TileCoord(x: 0, y: 0), TileCoord(x: 2, y: 1)])
          (coord: coord, tile: whole.tileAt(coord)!),
      ]),
    );
  });

  test('under the engine a blur stroke gives its memory back — a '
      'coordinate\'s finished tile made again in its own buffer, and the '
      'rewritten tiles and the scratch let go at the stroke\'s end', () {
    if (dllPath == null) {
      markTestSkipped(nativeEngineMissingSkipReason);
      return;
    }
    QaNativeEngine.debugResetForTests();
    debugQaEngineLibraryPathOverride = dllPath;
    QaNativeEngine.debugForceDartFallback = false;
    final kernel = QaBlurKernel.instance!;
    final base = edgeCel();
    final rasterizer =
        BrushLiveStrokeRasterizer(pasteboard: wall, tileSize: tileSize)
          ..blurOver(base);
    Uint8List shown() => rasterizer
        .preBlendedOverlayTile(
          tileX: 1,
          tileY: 0,
          base: base,
          mode: BrushBlendMode.color,
          erase: false,
        )!
        .readStraight((straight) => straight);

    final dabs = rub();
    rasterizer.blendFrom(dabs.sublist(0, 24), from: 0);
    final first = shown();
    rasterizer.blendFrom(dabs, from: 24);
    expect(
      identical(shown(), first),
      isTrue,
      reason: 'the next result is made in the buffer of the one before',
    );
    expect(kernel.debugScratchBytes, greaterThan(0), reason: 'premise');

    final before = QaNativeEngine.debugReleasedTileBuffers;
    rasterizer.clear();
    expect(
      QaNativeEngine.debugReleasedTileBuffers - before,
      7,
      reason: 'the six tiles the rub rewrote and the one finished tile shown',
    );
    expect(kernel.debugScratchBytes, 0);
  });

  onEachEngine('a rasterizer let go after a blur paints the next stroke', () {
    final base = edgeCel();
    final rasterizer =
        BrushLiveStrokeRasterizer(pasteboard: wall, tileSize: tileSize)
          ..blurOver(base);
    rasterizer.blendFrom(rub(), from: 0);
    rasterizer.clear();

    final paint = [
      for (final dab in rub()) dab.copyWith(blurs: false, color: 0xFFFF0000),
    ];
    rasterizer.blendFrom(paint, from: 0);
    final promoted = rasterizer.promoteStrokeTiles(
      base: base,
      mode: BrushBlendMode.color,
      erase: false,
    );
    rasterizer.clear();
    expectSameArtwork(
      base.putTiles([
        for (final entry in promoted) (coord: entry.coord, tile: entry.tile),
      ]),
      rederived(paint, base),
      'paint after a blur',
    );
  });


  onEachEngine('rubbing again blurs further (Q4)', () {
    final base = edgeCel();
    final once = live(rub(), base);
    final twice = live(rub(passes: 2), base);
    // Along the rubbed row, the blue's alpha-weighted reach into the orange:
    // a second pass carries it further.
    int blueAcross(BitmapSurface surface) {
      var total = 0;
      for (var x = 96; x < 130; x += 1) {
        total += pixelAt(surface, x, 63) & 0xFF;
      }
      return total;
    }

    expect(blueAcross(once), greaterThan(blueAcross(base)));
    expect(blueAcross(twice), greaterThan(blueAcross(once)));
  });

  onEachEngine('a flat field stays exactly as it was — nothing to blur, '
      'and no rounding creeps in', () {
    final base = celOf((x, y) => 0xB0337788);
    expectSameArtwork(live(rub(passes: 2), base), base, 'flat');
  });

  onEachEngine('a colour behind no alpha the blur never reached is kept, '
      'though its tile was rewritten', () {
    // Rows 0-3 carry a colour under no alpha; the dabs smear an edge
    // across rows 32-48 of the same 64px tiles.
    final base = celOf(
      (x, y) => y < 4 ? 0x00EE8811 : (x < 32 ? 0xFF2244CC : 0xFFCC4422),
    );
    final landed = live([
      for (var i = 0; i < 6; i += 1)
        BrushDab(
          center: CanvasPoint(x: 20.0 + i * 4, y: 40),
          color: 0xFF000000,
          size: 16,
          opacity: 1,
          flow: 1,
          hardness: 1,
          tipShape: BrushTipShape.round,
          pressure: 1,
          sequence: i,
          blurs: true,
        ),
    ], base);
    expect(pixelAt(landed, 30, 1), 0x00EE8811);
    expect(
      pixelAt(landed, 32, 40),
      isNot(pixelAt(base, 32, 40)),
      reason: 'premise: the dabs smeared their own rows',
    );
  });

  onEachEngine('over nothing a line fades, it does not darken', () {
    final base = celOf(
      (x, y) => (x - 96).abs() <= 1 ? 0xFFFF0000 : 0x00000000,
    );
    final blurred = live(rub(), base);
    var faded = 0;
    for (var y = 0; y < canvasSize.height; y += 1) {
      for (var x = 0; x < canvasSize.width; x += 1) {
        final argb = pixelAt(blurred, x, y);
        final alpha = argb >> 24;
        if (alpha == 0) {
          continue;
        }
        expect(
          argb & 0xFFFFFF,
          0xFF0000,
          reason: '($x, $y) at alpha $alpha took on a colour',
        );
        if (alpha < 255) {
          faded += 1;
        }
      }
    }
    expect(faded, greaterThan(50), reason: 'premise: the line was smeared');
  });

  onEachEngine('only what the brush reaches moves', () {
    final base = edgeCel();
    final dabs = rub();
    final reached = [for (final dab in dabs) dirtyRegionForBrushDab(dab)!];
    final blurred = live(dabs, base);
    for (var y = 0; y < canvasSize.height; y += 1) {
      for (var x = 0; x < canvasSize.width; x += 1) {
        final inside = reached.any(
          (r) =>
              x >= r.left &&
              x < r.rightExclusive &&
              y >= r.top &&
              y < r.bottomExclusive,
        );
        if (!inside) {
          expect(pixelAt(blurred, x, y), pixelAt(base, x, y));
        }
      }
    }
  });

  onEachEngine('the selection keeps what lies outside it', () {
    final base = edgeCel();
    final selection = CanvasSelectionRegion.shape(
      CanvasSelectionShape.rect(left: 0, top: 0, right: 100, bottom: 128),
    );
    final blurred = live(rub(), base, selection: selection);
    var movedInside = 0;
    for (var y = 0; y < canvasSize.height; y += 1) {
      for (var x = 0; x < canvasSize.width; x += 1) {
        final moved = pixelAt(blurred, x, y) != pixelAt(base, x, y);
        if (x >= 100) {
          expect(moved, isFalse, reason: '($x, $y) lies outside');
        } else if (moved) {
          movedInside += 1;
        }
      }
    }
    expect(movedInside, greaterThan(100));
    expectSameArtwork(
      clipStrokeCommitToSelection(
            BrushStrokeCommitData(sourceDabs: rub()),
            region: selection,
            surface: base,
          )!.promotedTiles!.fold(
            base,
            (surface, placed) => surface.putTiles([placed]),
          ),
      blurred,
      'the selection cut re-derived',
    );
  });

  onEachEngine('the tool\'s opacity caps how far the picture moves', () {
    final base = edgeCel();
    final full = live(rub(), base);
    final half = live(rub(), base, opacity: 0.5);
    var between = 0;
    for (var y = 0; y < canvasSize.height; y += 1) {
      for (var x = 0; x < canvasSize.width; x += 1) {
        final from = pixelAt(base, x, y) >> 24;
        final most = (pixelAt(full, x, y) >> 24) - from;
        final capped = (pixelAt(half, x, y) >> 24) - from;
        expect(capped.abs(), lessThanOrEqualTo(most.abs()));
        if (capped != 0 && capped.abs() < most.abs()) {
          between += 1;
        }
      }
    }
    expect(between, greaterThan(100));
    expectSameArtwork(
      rederived(rub(), base, opacity: 0.5),
      half,
      're-derived at half opacity',
    );
  });

  group('the setting', () {
    const blur = BrushShape(
      mixesGroundColor: true,
      mixingMethod: BrushMixingMethod.blur,
    );

    test('blurs only with mixing on, and the eraser\'s law wins', () {
      expect(blur.blurs, isTrue);
      expect(blur.picksUpGround, isFalse);
      expect(blur, isNot(blur.copyWith(mixingMethod: BrushMixingMethod.mix)));
      expect(blur.copyWith(mixesGroundColor: false).blurs, isFalse);
      expect(
        BrushEditCanvasInputSettings.fromShape(blur).blurs,
        isTrue,
      );
      expect(
        BrushEditCanvasInputSettings.fromShape(blur, erase: true).blurs,
        isFalse,
      );
      expect(BrushGroundColorMixer(shape: blur).isActive, isFalse);
      expect(
        BrushGroundColorMixer(
          shape: blur.copyWith(mixingMethod: BrushMixingMethod.mix),
        ).isActive,
        isTrue,
      );
    });

    test('rides a preset and a dab through JSON', () {
      final settings = BrushSettings.fromShape(blur);
      expect(settings.toJson()['mixingMethod'], 'blur');
      expect(BrushSettings.fromJson(settings.toJson()), settings);
      expect(
        BrushSettings.fromShape(
          blur.copyWith(mixingMethod: BrushMixingMethod.mix),
        ).toJson().containsKey('mixingMethod'),
        isFalse,
        reason: 'the default writes nothing',
      );
      final dab = blurDab(10, 10, 0);
      expect(dab.toJson()['blurs'], isTrue);
      expect(BrushDab.fromJson(dab.toJson()), dab);
      expect(BrushDab.fromJson(dab.copyWith(blurs: false).toJson()).blurs, isFalse);
      expect(dab, isNot(dab.copyWith(blurs: false)));
    });

    test('the mixing group carries a blur (Q1)', () {
      final preset = defaultBrushPresets.singleWhere(
        (preset) => preset.id.value == 'builtin-blur',
      );
      expect(preset.groupId?.value, 'builtin-blend-group');
      expect(preset.settings.shape.blurs, isTrue);
    });
  });

  test('a blur stroke with nothing to land lands nothing', () {
    final base = celOf((x, y) => 0x00000000);
    expect(blurStrokeLandedOn(base, rub(), opacity: 1), isEmpty);
  });
}
