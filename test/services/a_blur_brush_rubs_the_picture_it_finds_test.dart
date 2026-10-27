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
import 'package:anicel/src/native/qa_engine_abi.dart';
import 'package:anicel/src/native/qa_native_engine.dart';
import 'package:anicel/src/services/brush_blur_stroke_landing.dart';
import 'package:anicel/src/services/brush_commit_builder.dart';
import 'package:anicel/src/services/brush_dab_dirty_region.dart';
import 'package:anicel/src/services/brush_ground_color_mixing.dart';
import 'package:anicel/src/services/brush_live_stroke_rasterizer.dart';
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
    });
  });

  test('a blur stroke with nothing to land lands nothing', () {
    final base = celOf((x, y) => 0x00000000);
    expect(blurStrokeLandedOn(base, rub(), opacity: 1), isEmpty);
  });
}
