// The first stroke on the engine compiles the executor and the stroke's
// kernels: 40 s on a machine this busy.
@Timeout(Duration(minutes: 3))
library;

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:gpu_engine/gpu_engine.dart' show gpuTileSide;

import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/brush_blend_mode.dart';
import 'package:anicel/src/models/brush_dab.dart';
import 'package:anicel/src/models/brush_dab_sequence.dart';
import 'package:anicel/src/models/brush_stamp_image.dart';
import 'package:anicel/src/models/brush_tip_shape.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/dirty_region.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/pasteboard_bounds.dart';
import 'package:anicel/src/models/placed_tile.dart';
import 'package:anicel/src/native/engine_selection_masks.dart';
import 'package:anicel/src/native/engine_stamp_pictures.dart';
import 'package:anicel/src/services/bitmap_surface_brush_commit.dart';
import 'package:anicel/src/services/brush_commit_builder.dart';
import 'package:anicel/src/services/brush_fill_promotion.dart';
import 'package:anicel/src/services/brush_live_stroke_rasterizer.dart';
import 'package:anicel/src/services/brush_stroke_commit_data.dart';
import 'package:anicel/src/services/canvas_selection.dart';
import 'package:anicel/src/services/canvas_selection_paint_clip.dart';
import 'package:anicel/src/services/canvas_selection_region.dart';
import 'package:anicel/src/services/selection_clip.dart';
import '../helpers/surface_rgba_in_place.dart';

/// 🚨★★★WHATEVER DRAWS IN A SELECTION IS CUT BY ONE EDGE
/// (brush-fidelity-Q11 · Q12, 유저 2026-10-18).
///
/// The clip reads the selection a window at a time (what a flood keeps of
/// its fill), and the bytes must be the ones the whole box reads
/// ([selectionMaskOnPasteboard], what a lift and a held picture go by):
/// a window that softens against its own edge is a seam on the tile grid.
/// On the engine the clip's mask is made once over its whole box, and a
/// stroke, a stamp and a stroke's buffer land under it (2026-11-14) — off
/// the engine's grid none lands under a selection at all.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final engineTile = gpuTileSide;
  const canvas = CanvasSize(width: 300, height: 200);
  final wall = canvas.pasteboardAt(PasteboardReach.none);
  const layerId = LayerId('row');
  const frameId = FrameId('cel');

  CanvasSelectionRegion rect(
    double left,
    double top,
    double right,
    double bottom,
  ) => CanvasSelectionRegion.shape(
    CanvasSelectionShape.rect(
      left: left,
      top: top,
      right: right,
      bottom: bottom,
    ),
  );

  final outlines = <String, CanvasSelectionRegion>{
    'a rectangle': rect(60, 40, 200, 150),
    'an ellipse': CanvasSelectionRegion.shape(
      CanvasSelectionShape.ellipse(left: 70, top: 30, right: 230, bottom: 170),
    ),
    'a hole': rect(40, 30, 260, 170).combinedWith(
      CanvasSelectionShape.ellipse(left: 120, top: 70, right: 180, bottom: 130),
      SelectionCombineMode.subtract,
    )!,
    // A selection folded in as ONE operand, as 선택반전 makes it (I-23).
    'a hole that is a selection of its own': CanvasSelectionRegion([
      CanvasSelectionStep(
        CanvasSelectionShape.rect(left: 20, top: 15, right: 280, bottom: 185),
        SelectionCombineMode.replace,
      ),
      CanvasSelectionStep.region(
        rect(90, 60, 210, 140).combinedWith(
          CanvasSelectionShape.ellipse(
            left: 150,
            top: 40,
            right: 250,
            bottom: 120,
          ),
          SelectionCombineMode.add,
        )!,
        SelectionCombineMode.subtract,
      ),
    ]),
    'a strip the wall cuts': rect(-40, 60, 120, 110),
    'a sliver thinner than the softness': rect(100, 20, 103, 180),
    'the whole picture': rect(0, 0, 300, 200),
  };

  const softnesses = [
    SelectionMaskOptions(featherPx: 6),
    SelectionMaskOptions(featherPx: 2.5),
    SelectionMaskOptions(antiAlias: true),
    SelectionMaskOptions(growPx: 5),
    SelectionMaskOptions(growPx: -4),
    SelectionMaskOptions(growPx: 3, featherPx: 5, antiAlias: true),
    SelectionMaskOptions(growPx: -3, featherPx: 5, antiAlias: true),
  ];

  /// [read] at the pixel `(x, y)`, unselected past its box.
  int readAt(SelectionMaskReading? read, int x, int y) {
    if (read == null) {
      return 0;
    }
    final (:mask, :box) = read;
    final inside =
        x >= box.left &&
        x < box.left + box.width &&
        y >= box.top &&
        y < box.top + box.height;
    return inside ? mask[(y - box.top) * box.width + x - box.left] : 0;
  }

  for (final MapEntry(key: name, value: region) in outlines.entries) {
    for (final options in softnesses) {
      final label =
          '$name, grow ${options.growPx} feather ${options.featherPx} '
          'aa ${options.antiAlias}';

      test('window for window it reads what the whole box reads: $label', () {
        final whole = selectionMaskOnPasteboard(
          region,
          wall: wall,
          options: options,
        );
        final clip = SelectionClip.of(region, wall: wall, options: options);
        const sizes = [(w: 16, h: 16), (w: 41, h: 7), (w: 3, h: 60)];
        for (final (:w, :h) in sizes) {
          for (var top = -20; top < 215; top += 13) {
            for (var left = -20; left < 315; left += 17) {
              final window = clip.maskFor(
                left: left,
                top: top,
                width: w,
                height: h,
              );
              var selected = false;
              for (var y = 0; y < h; y += 1) {
                for (var x = 0; x < w; x += 1) {
                  final byte = window[y * w + x];
                  selected = selected || byte != 0;
                  if (byte != readAt(whole, left + x, top + y)) {
                    fail(
                      '${left + x},${top + y} read $byte in a window at '
                      '$left,$top ${w}x$h, '
                      '${readAt(whole, left + x, top + y)} in the whole box',
                    );
                  }
                }
              }
              if (selected) {
                expect(
                  clip.mayCover(
                    DirtyRegion.fromXYWH(x: left, y: top, width: w, height: h),
                  ),
                  isTrue,
                  reason: 'a window at $left,$top holds selected pixels',
                );
              }
            }
          }
        }
      });
    }
  }

  test('a grown selection reaches past its outline, and no further', () {
    final region = rect(100, 100, 120, 120);
    final clip = SelectionClip.of(
      region,
      wall: wall,
      options: const SelectionMaskOptions(growPx: 4),
    );
    DirtyRegion columnAt(int x) =>
        DirtyRegion.fromXYWH(x: x, y: 100, width: 1, height: 20);
    expect(region.mayCover(columnAt(97)), isFalse, reason: 'fixture premise');
    expect(clip.mayCover(columnAt(97)), isTrue, reason: 'grown four pixels');
    expect(clip.mayCover(columnAt(90)), isFalse, reason: 'past the growth');
    expect(clip.mayCover(columnAt(122)), isTrue, reason: 'on the right too');
    expect(clip.mayCover(columnAt(130)), isFalse);
    DirtyRegion rowAt(int y) =>
        DirtyRegion.fromXYWH(x: 100, y: y, width: 20, height: 1);
    expect(clip.mayCover(rowAt(97)), isTrue, reason: 'above');
    expect(clip.mayCover(rowAt(90)), isFalse);
    expect(clip.mayCover(rowAt(122)), isTrue, reason: 'and below');
    expect(clip.mayCover(rowAt(130)), isFalse);
  });

  test('a selection the wall leaves nothing of covers nothing', () {
    final clip = SelectionClip.of(
      rect(500, 500, 520, 520),
      wall: wall,
      options: const SelectionMaskOptions(featherPx: 4),
    );
    final everywhere = DirtyRegion.fromXYWH(
      x: 0,
      y: 0,
      width: 300,
      height: 200,
    );
    expect(clip.mayCover(everywhere), isFalse);
    expect(
      clip.maskFor(left: 0, top: 0, width: 300, height: 200),
      everyElement(0),
    );
  });

  test('a selection with no softness asked of it is its own outline', () {
    final region = outlines['an ellipse']!;
    expect(
      SelectionClip.of(
        region,
        wall: wall,
        options: SelectionMaskOptions.none,
      ).maskFor(left: 60, top: 20, width: 200, height: 160),
      region.maskFor(left: 60, top: 20, width: 200, height: 160),
    );
  });

  test('🚨a window reads around itself, not the selection: the first dab '
      'of a stroke does not wait on how much is selected', () {
    final asked = <int>[];
    final spied = _ReadsSpied(rect(-4000, -4000, 8000, 8000), asked);
    const options = SelectionMaskOptions(growPx: 2, featherPx: 8);
    final clip = SelectionClip.of(
      spied,
      wall: const CanvasSize(
        width: 8000,
        height: 8000,
      ).pasteboardAt(PasteboardReach.none),
      options: options,
    );
    clip.maskFor(left: 4000, top: 4000, width: 64, height: 64);
    final side = 64 + 2 * options.neighbourReach;
    expect(asked, [side * side]);
  });

  BrushDab paintDab(double x, double y) => BrushDab(
    center: CanvasPoint(x: x, y: y),
    color: 0xFFFF0000,
    size: 40,
    opacity: 1,
    flow: 1,
    hardness: 1,
    tipShape: BrushTipShape.square,
    pressure: 1,
    sequence: 0,
  );

  BrushDab opaqueStamp() {
    final rgba = Uint8List(300 * 200 * 4);
    for (var alpha = 3; alpha < rgba.length; alpha += 4) {
      rgba[alpha] = 255;
    }
    return BrushDab(
      center: CanvasPoint(x: 150, y: 100),
      color: 0xFFFF0000,
      size: 300,
      opacity: 1,
      flow: 1,
      hardness: 1,
      tipShape: BrushTipShape.square,
      pressure: 1,
      sequence: 0,
      stamp: BrushStampImage(id: 'all', width: 300, height: 200, rgba: rgba),
    );
  }

  /// The alpha of [surface] along the row at [y].
  List<int> alphas(BitmapSurface surface, int y) => [
    for (var x = 0; x < 300; x += 1) (surfaceRgbaInPlace(surface, x, y) ?? 0) & 255,
  ];

  BitmapSurface blank() =>
      BitmapSurface(canvasSize: canvas, tileSize: engineTile);

  final soft = SelectionClip.of(
    rect(60, 20, 240, 180),
    wall: wall,
    options: const SelectionMaskOptions(featherPx: 8),
  );
  final row = soft.maskFor(left: 0, top: 100, width: 300, height: 1);

  test('a stamp the selection cannot reach reads nothing of it, and is not '
      'committed at all', () {
    final asked = <int>[];
    final rgba = Uint8List(10 * 10 * 4)..fillRange(0, 10 * 10 * 4, 255);
    final dab = paintDab(20, 190).copyWith(
      stamp: BrushStampImage(id: 'off', width: 10, height: 10, rgba: rgba),
    );
    final clip = SelectionClip.outline(
      _ReadsSpied(rect(60, 20, 240, 180), asked),
    );
    expect(
      clipStrokeCommitToSelection(
        BrushStrokeCommitData(sourceDabs: [dab]),
        clip: clip,
        surface: blank(),
      ),
      isNull,
    );
    expect(asked, isEmpty);
  });

  test('fixture premise: the row reads a ramp', () {
    expect(row[60], greaterThan(0));
    expect(row[60], lessThan(255));
    expect(row[100], 255);
    expect(row[59], 0);
  });

  test('a stroke shows the ramp, and the commit that re-derives it from its '
      'dabs lands the same one — the selection\'s edge, taken once', () {
    final dabs = [
      for (var x = 0.0; x <= 300; x += 8) paintDab(x, 100),
    ];
    final base = blank();
    final rasterizer =
        BrushLiveStrokeRasterizer(pasteboard: wall, tileSize: engineTile)
          ..selectionClip = soft;
    rasterizer.blendFrom(dabs, from: 0);
    final shown = base.putMaterializedTiles([
      for (final tile in rasterizer.promoteStrokeTiles(
        base: base,
        mode: BrushBlendMode.color,
        erase: false,
      ))
        (coord: tile.coord, tile: tile.tile),
    ]);
    rasterizer.clear();
    expect(alphas(shown, 100), row);

    final funneled = clipStrokeCommitToSelection(
      BrushStrokeCommitData(sourceDabs: dabs),
      clip: soft,
      surface: base,
    )!;
    final landed = brushCommitResultForBrushDabSequenceOnBitmapSurface(
      surface: base,
      sequence: BrushDabSequence(funneled.sourceDabs),
      layerId: layerId,
      frameId: frameId,
      prerasterizedStrokePixels: funneled.strokePixels,
      prerasterizedStrokeBounds: funneled.strokeBounds,
      selection: funneled.selection,
    ).afterSurface;
    expect(alphas(landed, 100), row);
  });

  test('a fill shows the ramp, and on a cel that moved under it the commit '
      'lands the same one — cut from the whole dab, once', () {
    final dab = opaqueStamp();
    final base = blank();
    final promoted = promoteFillDabs(
      surface: base,
      dabs: [dab],
      blendMode: BrushBlendMode.color,
      selection: soft,
      layerId: layerId,
      frameId: frameId,
    );
    final shown = base.putMaterializedTiles([
      for (final tile in promoted) (coord: tile.coord, tile: tile.tile),
    ]);
    expect(alphas(shown, 100), row);

    final moved = blank();
    final funneled = clipStrokeCommitToSelection(
      BrushStrokeCommitData(
        sourceDabs: [dab],
        promotedBase: base,
        promotedTiles: [
          for (final tile in promoted) (coord: tile.coord, tile: tile.tile),
        ],
      ),
      clip: soft,
      surface: moved,
    )!;
    final landed = brushCommitResultForBrushDabSequenceOnBitmapSurface(
      surface: moved,
      sequence: BrushDabSequence(funneled.sourceDabs),
      layerId: layerId,
      frameId: frameId,
      promotedBase: funneled.promotedBase,
      promotedTiles: funneled.promotedTiles,
      selection: funneled.selection,
    ).afterSurface;
    expect(alphas(landed, 100), row);
  });

  // 🚨관제 2026-11-14 (board `a-selection-mask-is-built-on-the-cpu-at-every-
  // move`, L1b-1b): the funnel no longer cuts — it names the selection, and
  // the commit cuts where it lands. A cel that moved between the preview and
  // the commit is where the two could part: the promoted tiles answer for
  // the cel they were blended on, and the commit lays the stroke again.
  test('🚨a fill on a cel that moved under it lands what its preview on '
      'that cel shows, byte for byte', () {
    final picture = Uint8List(300 * 200 * 4);
    for (var at = 0; at < picture.length; at += 4) {
      picture
        ..[at] = 230
        ..[at + 1] = 40
        ..[at + 2] = 60
        ..[at + 3] = 60 + (at ~/ 4 % 300) % 150;
    }
    final dab = opaqueStamp().copyWith(
      opacity: 0.6,
      stamp: BrushStampImage(id: 'fill', width: 300, height: 200, rgba: picture),
    );
    List<PlacedTile> fillOn(BitmapSurface cel) => [
      for (final tile in promoteFillDabs(
        surface: cel,
        dabs: [dab],
        blendMode: BrushBlendMode.color,
        selection: soft,
        layerId: layerId,
        frameId: frameId,
      ))
        (coord: tile.coord, tile: tile.tile),
    ];
    final base = blank();
    final promoted = fillOn(base);

    final under = Uint8List(300 * 200 * 4);
    for (var at = 0; at < under.length; at += 4) {
      under
        ..[at + 1] = 90
        ..[at + 2] = 200
        ..[at + 3] = 140;
    }
    final moved = materializeBrushDabSequenceOnBitmapSurface(
      surface: blank(),
      sequence: BrushDabSequence([
        opaqueStamp().copyWith(
          stamp: BrushStampImage(
            id: 'under',
            width: 300,
            height: 200,
            rgba: under,
          ),
        ),
      ]),
    ).surface;
    final preview = moved.putMaterializedTiles(fillOn(moved));

    final funneled = clipStrokeCommitToSelection(
      BrushStrokeCommitData(
        sourceDabs: [dab],
        promotedBase: base,
        promotedTiles: promoted,
      ),
      clip: soft,
      surface: moved,
    )!;
    final landed = brushCommitResultForBrushDabSequenceOnBitmapSurface(
      surface: moved,
      sequence: BrushDabSequence(funneled.sourceDabs),
      layerId: layerId,
      frameId: frameId,
      promotedBase: funneled.promotedBase,
      promotedTiles: funneled.promotedTiles,
      selection: funneled.selection,
    ).afterSurface;

    final atTheEdge = surfaceRgbaInPlace(preview, 62, 100);
    expect(
      atTheEdge,
      isNot(surfaceRgbaInPlace(moved, 62, 100)),
      reason: 'fixture premise: the fill lands at the edge',
    );
    expect(
      atTheEdge,
      isNot(surfaceRgbaInPlace(preview, 150, 100)),
      reason: 'fixture premise: the edge is soft there',
    );
    for (var y = 0; y < 200; y += 1) {
      for (var x = 0; x < 300; x += 1) {
        final want = surfaceRgbaInPlace(preview, x, y);
        final got = surfaceRgbaInPlace(landed, x, y);
        if (got != want) {
          fail(
            '$x,$y landed ${got?.toRadixString(16)}, the preview on the '
            'cel shows ${want?.toRadixString(16)}',
          );
        }
      }
    }
  });

  test('off the engine\'s grid a selection is turned away — by the commit, '
      'a stamp\'s landing and the live stroke alike', () {
    final small = BitmapSurface(canvasSize: canvas, tileSize: 64);
    expect(
      () => brushCommitResultForBrushDabSequenceOnBitmapSurface(
        surface: small,
        sequence: BrushDabSequence([paintDab(150, 100)]),
        layerId: layerId,
        frameId: frameId,
        selection: soft,
      ),
      throwsStateError,
    );
    expect(
      () => materializeBrushDabSequenceOnBitmapSurface(
        surface: small,
        sequence: BrushDabSequence([opaqueStamp()]),
        selection: soft,
      ),
      throwsStateError,
    );
    expect(
      () => BrushLiveStrokeRasterizer(pasteboard: wall, tileSize: 64)
        ..selectionClip = soft
        ..blendFrom([paintDab(150, 100)], from: 0),
      throwsStateError,
    );
  });

  test('a blur handed to the commit with its selection rubs nothing the '
      'selection does not take', () {
    final rgba = Uint8List(300 * 200 * 4);
    for (var at = 0; at < rgba.length; at += 4) {
      if ((at ~/ 4 % 300 ~/ 4).isEven) {
        rgba
          ..[at] = 255
          ..[at + 3] = 255;
      }
    }
    final striped = materializeBrushDabSequenceOnBitmapSurface(
      surface: blank(),
      sequence: BrushDabSequence([
        opaqueStamp().copyWith(
          stamp: BrushStampImage(
            id: 'stripes',
            width: 300,
            height: 200,
            rgba: rgba,
          ),
        ),
      ]),
    ).surface;
    final rubbed = brushCommitResultForBrushDabSequenceOnBitmapSurface(
      surface: striped,
      sequence: BrushDabSequence([
        for (var i = 0; i < 27; i += 1)
          paintDab(20.0 + i * 10, 100).copyWith(
            size: 30,
            blurs: true,
            sequence: i,
          ),
      ]),
      layerId: layerId,
      frameId: frameId,
      selection: SelectionClip.outline(rect(100, 0, 200, 200)),
    ).afterSurface;

    var rubbedInside = false;
    for (var y = 85; y < 115; y += 1) {
      for (var x = 0; x < 300; x += 1) {
        final before = surfaceRgbaInPlace(striped, x, y);
        final after = surfaceRgbaInPlace(rubbed, x, y);
        if (x < 100 || x >= 200) {
          expect(after, before, reason: '$x,$y lies outside the selection');
        } else {
          rubbedInside = rubbedInside || after != before;
        }
      }
    }
    expect(rubbedInside, isTrue, reason: 'fixture premise: it rubs inside');
  });

  group('on the engine', () {
    // 🔬The CPU audit (2026-11-13): a stroke under a selection had the CPU
    // make the mask's bytes over the tiles of each landing, at every move,
    // and hand them up. The engine makes the selection's mask once for the
    // stroke, by the same law.

    /// A stroke of one opaque square over the whole picture, under [clip],
    /// on the engine's grid; the rasterizer is handed back unclear.
    (BitmapSurface, BrushLiveStrokeRasterizer) strokedUnder(
      SelectionClip clip,
    ) {
      final base = BitmapSurface(canvasSize: canvas, tileSize: engineTile);
      final rasterizer =
          BrushLiveStrokeRasterizer(pasteboard: wall, tileSize: engineTile)
            ..selectionClip = clip;
      rasterizer.blendFrom([
        paintDab(150, 100).copyWith(size: 400),
      ], from: 0);
      final shown = base.putMaterializedTiles([
        for (final tile in rasterizer.promoteStrokeTiles(
          base: base,
          mode: BrushBlendMode.color,
          erase: false,
        ))
          (coord: tile.coord, tile: tile.tile),
      ]);
      return (shown, rasterizer);
    }

    for (final MapEntry(key: name, value: region) in outlines.entries) {
      for (final options in softnesses) {
        final label =
            '$name, grow ${options.growPx} feather ${options.featherPx} '
            'aa ${options.antiAlias}';

        test('a stroke is cut by the bytes the whole box reads: $label', () {
          final whole = selectionMaskOnPasteboard(
            region,
            wall: wall,
            options: options,
          );
          final (shown, rasterizer) = strokedUnder(
            SelectionClip.of(region, wall: wall, options: options),
          );
          rasterizer.clear();

          for (var y = 0; y < 200; y += 1) {
            for (var x = 0; x < 300; x += 1) {
              final alpha = (surfaceRgbaInPlace(shown, x, y) ?? 0) & 255;
              if (alpha != readAt(whole, x, y)) {
                fail(
                  '$x,$y took $alpha of the stroke, the selection reads '
                  '${readAt(whole, x, y)}',
                );
              }
            }
          }
        });
      }
    }

    /// Fails at the first pixel of [landed] whose alpha is not what
    /// [whole] reads there.
    void cutBy(SelectionMaskReading? whole, BitmapSurface landed) {
      for (var y = 0; y < 200; y += 1) {
        for (var x = 0; x < 300; x += 1) {
          final alpha = (surfaceRgbaInPlace(landed, x, y) ?? 0) & 255;
          if (alpha != readAt(whole, x, y)) {
            fail(
              '$x,$y took $alpha of it, the selection reads '
              '${readAt(whole, x, y)}',
            );
          }
        }
      }
    }

    for (final MapEntry(key: name, value: region) in outlines.entries) {
      for (final options in softnesses) {
        final label =
            '$name, grow ${options.growPx} feather ${options.featherPx} '
            'aa ${options.antiAlias}';

        test('a stamp is cut by the bytes a stroke is: $label', () {
          final landed = materializeBrushDabSequenceOnBitmapSurface(
            surface: BitmapSurface(canvasSize: canvas, tileSize: engineTile),
            sequence: BrushDabSequence([opaqueStamp()]),
            selection: SelectionClip.of(region, wall: wall, options: options),
          ).surface;

          cutBy(
            selectionMaskOnPasteboard(region, wall: wall, options: options),
            landed,
          );
        });
      }
    }

    test('a stroke\'s buffer is cut by the bytes a stroke is', () {
      final region = outlines['an ellipse']!;
      const options = SelectionMaskOptions(growPx: 3, featherPx: 5);
      final landed = brushCommitResultForBrushDabSequenceOnBitmapSurface(
        surface: BitmapSurface(canvasSize: canvas, tileSize: engineTile),
        sequence: BrushDabSequence([paintDab(150, 100).copyWith(size: 400)]),
        layerId: layerId,
        frameId: frameId,
        selection: SelectionClip.of(region, wall: wall, options: options),
      ).afterSurface;

      cutBy(
        selectionMaskOnPasteboard(region, wall: wall, options: options),
        landed,
      );
    });

    test('where the selection takes all of a stamp, it lands what it lands '
        'with none', () {
      final rgba = Uint8List(300 * 200 * 4);
      for (var at = 0; at < rgba.length; at += 4) {
        rgba
          ..[at] = 200
          ..[at + 1] = 90
          ..[at + 2] = 30
          ..[at + 3] = 101;
      }
      final stamp = opaqueStamp().copyWith(
        opacity: 0.6,
        stamp: BrushStampImage(id: 'half', width: 300, height: 200, rgba: rgba),
      );
      final under = BitmapSurface(canvasSize: canvas, tileSize: engineTile);
      BitmapSurface landed(SelectionClip? selection) =>
          materializeBrushDabSequenceOnBitmapSurface(
            surface: under,
            sequence: BrushDabSequence([stamp]),
            selection: selection,
          ).surface;
      final inside = landed(soft);
      final whole = landed(null);
      final reads = selectionMaskOnPasteboard(
        rect(60, 20, 240, 180),
        wall: wall,
        options: const SelectionMaskOptions(featherPx: 8),
      );
      expect(readAt(reads, 150, 100), 255, reason: 'fixture premise');
      expect(readAt(reads, 20, 100), 0, reason: 'fixture premise');

      for (var y = 0; y < 200; y += 1) {
        for (var x = 0; x < 300; x += 1) {
          final read = readAt(reads, x, y);
          final at = surfaceRgbaInPlace(inside, x, y) ?? 0;
          if (read == 255 && at != (surfaceRgbaInPlace(whole, x, y) ?? 0)) {
            fail('$x,$y is wholly selected and landed otherwise');
          }
          if (read == 0 && at != 0) {
            fail('$x,$y is not selected and took something');
          }
        }
      }
    });

    test('a stamp the selection cannot reach is neither handed up nor cut',
        () {
      final clip = SelectionClip.of(
        rect(60, 20, 240, 180),
        wall: wall,
        options: const SelectionMaskOptions(featherPx: 2),
      );
      final rgba = Uint8List(10 * 10 * 4)..fillRange(0, 10 * 10 * 4, 255);
      final dab = paintDab(20, 190).copyWith(
        stamp: BrushStampImage(id: 'away', width: 10, height: 10, rgba: rgba),
      );
      final made = EngineSelectionMasks.debugMade;
      final handed = EngineStampPictures.debugHandedUp;
      final landed = materializeBrushDabSequenceOnBitmapSurface(
        surface: BitmapSurface(canvasSize: canvas, tileSize: engineTile),
        sequence: BrushDabSequence([dab]),
        selection: clip,
      );

      expect(landed.hasChanges, isFalse);
      expect(EngineSelectionMasks.debugMade, made);
      expect(EngineStampPictures.debugHandedUp, handed);
    });

    test('a brush dab handed in with a selection is turned away', () {
      expect(
        () => materializeBrushDabSequenceOnBitmapSurface(
          surface: BitmapSurface(canvasSize: canvas, tileSize: engineTile),
          sequence: BrushDabSequence([opaqueStamp(), paintDab(40, 40)]),
          selection: soft,
        ),
        throwsArgumentError,
      );
    });

    test('a region asked for its clip again, at its softness inside its wall, '
        'is the clip it was — its mask made once for every verb under it', () {
      final region = rect(60, 20, 240, 180);
      SelectionClip clipAt(double feather, {PasteboardWall? within}) =>
          SelectionClip.of(
            region,
            wall: within ?? wall,
            options: SelectionMaskOptions(featherPx: feather),
          );
      final first = clipAt(3);

      expect(identical(clipAt(3), first), isTrue);
      expect(
        identical(clipAt(4), first),
        isFalse,
        reason: 'another softness is another clip',
      );
      expect(
        identical(
          clipAt(
            3,
            within: const CanvasSize(
              width: 400,
              height: 300,
            ).pasteboardAt(PasteboardReach.none),
          ),
          first,
        ),
        isFalse,
        reason: 'another wall is another clip',
      );
      final made = EngineSelectionMasks.debugMade;
      clipAt(3).maskOnEngine();
      clipAt(3).maskOnEngine();
      expect(EngineSelectionMasks.debugMade, made + 1);
    });

    test('a clip has its mask made once, for a fill\'s every piece and the '
        'strokes after it', () {
      final clip = SelectionClip.of(
        rect(60, 20, 240, 180),
        wall: wall,
        options: const SelectionMaskOptions(featherPx: 8),
      );
      final made = EngineSelectionMasks.debugMade;
      final pieces = [
        for (final (x, y) in [(70.0, 40.0), (150.0, 100.0), (230.0, 160.0)])
          opaqueStamp().copyWith(
            center: CanvasPoint(x: x, y: y),
            stamp: BrushStampImage(
              id: 'piece $x',
              width: 20,
              height: 20,
              rgba: Uint8List(20 * 20 * 4)..fillRange(0, 20 * 20 * 4, 255),
            ),
          ),
      ];
      final fill = promoteFillDabs(
        surface: BitmapSurface(canvasSize: canvas, tileSize: engineTile),
        dabs: pieces,
        blendMode: BrushBlendMode.color,
        selection: clip,
        layerId: layerId,
        frameId: frameId,
      );
      expect(fill, isNotEmpty, reason: 'fixture premise');
      for (var stroke = 0; stroke < 2; stroke += 1) {
        final (shown, rasterizer) = strokedUnder(clip);
        rasterizer
          ..blendFrom([paintDab(40, 40), paintDab(260, 160)], from: 0)
          ..preBlendedOverlayTiles(
            coords: [for (final tile in shown.tiles.keys) tile],
            base: shown,
            mode: BrushBlendMode.color,
            erase: false,
          )
          ..clear();
      }

      expect(EngineSelectionMasks.debugMade, made + 1);
    });
  });
}

/// [CanvasSelectionRegion] saying how many pixels each read of it asked for.
class _ReadsSpied extends CanvasSelectionRegion {
  _ReadsSpied(CanvasSelectionRegion region, this.asked) : super(region.steps);

  final List<int> asked;

  @override
  Uint8List maskFor({
    required int left,
    required int top,
    required int width,
    required int height,
  }) {
    asked.add(width * height);
    return super.maskFor(left: left, top: top, width: width, height: height);
  }
}
