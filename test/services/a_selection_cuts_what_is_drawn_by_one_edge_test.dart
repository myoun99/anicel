import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

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
/// The clip reads the selection a window at a time so that a stroke pays for
/// the tiles it touches, and the bytes must be the ones the whole box reads
/// ([selectionMaskOnPasteboard], what a lift and a held picture go by):
/// a window that softens against its own edge is a seam on the tile grid.
void main() {
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

  BitmapSurface blank() => BitmapSurface(canvasSize: canvas, tileSize: 64);

  final soft = SelectionClip.of(
    rect(60, 20, 240, 180),
    wall: wall,
    options: const SelectionMaskOptions(featherPx: 8),
  );
  final row = soft.maskFor(left: 0, top: 100, width: 300, height: 1);

  test('a stamp the selection cannot reach reads nothing of it', () {
    final asked = <int>[];
    final rgba = Uint8List(10 * 10 * 4)..fillRange(0, 10 * 10 * 4, 255);
    final dab = paintDab(20, 190).copyWith(
      stamp: BrushStampImage(id: 'off', width: 10, height: 10, rgba: rgba),
    );
    final clip = SelectionClip.outline(
      _ReadsSpied(rect(60, 20, 240, 180), asked),
    );
    expect(clipStampDabToSelection(dab, clip: clip), isNull);
    expect(asked, isEmpty);
  });

  test('a dab the selection cannot reach is left out before the stroke is '
      'rastered: it widens nothing that is read', () {
    final asked = <int>[];
    final clip = SelectionClip.outline(
      _ReadsSpied(rect(60, 20, 240, 180), asked),
    );
    List<int> readFor(List<BrushDab> dabs) {
      asked.clear();
      clipDabsToSelection(
        dabs: dabs,
        canvasSize: canvas,
        tileSize: 64,
        clip: clip,
      );
      return List.of(asked);
    }

    final near = readFor([paintDab(150, 100)]);
    expect(near, isNotEmpty, reason: 'fixture premise');
    expect(readFor([paintDab(150, 100), paintDab(20, 190)]), near);
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
        BrushLiveStrokeRasterizer(pasteboard: wall, tileSize: 64)
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
    ).afterSurface;
    expect(alphas(landed, 100), row);
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
