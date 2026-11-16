import 'dart:ui' show PictureRecorder;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gpu_engine/gpu_engine.dart';

import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/native/app_gpu_engine.dart';
import 'package:anicel/src/ui/timeline/axis_turn.dart';
import 'package:anicel/src/ui/timeline/timeline_cell_exposure_state.dart';
import 'package:anicel/src/ui/timeline/timeline_grid_tile_picture.dart';
import 'package:anicel/src/ui/timeline/timeline_grid_tile_store.dart';
import 'package:anicel/src/ui/timeline/timeline_row_cells_painter.dart';

import 'dart:async';

import '../../helpers/a_shown_surface.dart';
import '../../helpers/poll_until.dart';
import '../../helpers/tiles_laid.dart';
import 'timeline_frame_geometry_probe.dart';

/// 🚨A BLOCK IS WHOLE ACROSS A TILE'S SEAM (서피스 검증 2026-11-09, card
/// the-grid-screen-lets-a-frame-line-through-a-white-block): S5 at 312 %, a
/// cell 29.9328 across at a ratio of 1.5, so a span of 18 cells ends on the
/// whole point 539 and at 808.5 device pixels — on a pixel's centre, which
/// is the next tile's. A tile 809 wide is stretched over those, and R1's
/// fixed point landed that pixel a hair before the next tile: read as
/// nothing, the sheet's frame line stood in the block.
void main() {
  const ratio = 1.5;
  const cell = 29.9328;

  // A drain reads the engine's faces from the asset bundle (`EngineFaces`).
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(openAppGpuEngine);
  // The zoom's stop is what bakes a tile here.
  setUpAll(() => TimelineGridTileStore.instance.debugZoomTimer = Timer.new);
  setUp(TimelineGridTileStore.instance.clear);
  tearDown(TimelineGridTileStore.instance.clear);

  TimelineRowCellsPainter aBlockRow(Axis axis, {double at = ratio}) =>
      TimelineRowCellsPainter(
        axis: axis,
        layer: Layer(
          id: const LayerId('block'),
          name: 'block',
          frames: const [],
          timeline: {
            0: const TimelineExposure.drawing(FrameId('f1'), length: 60),
          },
        ),
        geometry: testFrameGeometry(
          frameCellExtent: cell,
          frameEndIndexExclusive: 60,
        ),
        crossAxisExtent: 28,
        exposureStateForLayer: (_, frame) => frame == 0
            ? TimelineCellExposureState.drawingStart
            : TimelineCellExposureState.held,
        colorScheme: const ColorScheme.dark(),
        baseTextStyle: const TextStyle(fontSize: 11),
        tileStore: TimelineGridTileStore.instance,
        devicePixelRatio: at,
      );

  Future<GpuGridPicture> tile(
    TimelineRowCellsPainter row,
    int from,
    int to,
  ) async {
    TimelineGridTilePicture? asked() => TimelineGridTileStore.instance.tileFor(
      painter: row,
      spanStartIndex: from,
      spanEndIndexExclusive: to,
      devicePixelRatio: row.devicePixelRatio,
    );
    expect(await pollUntil(() => asked() != null), isTrue, reason: 'never landed');
    // Held: asking a tile over the same cells lets the others go.
    final held = asked()!..hold();
    addTearDown(held.letGo);
    return held.picture;
  }

  for (final axis in Axis.values) {
    test('along ${axis.name}, as if there were no seam', () async {
      final row = aBlockRow(axis);
      final first = await tile(row, 0, 18);
      final second = await tile(row, 18, 36);
      final whole = await tile(row, 0, 36);

      final seam = endAlong(axis, row.cellRectFor(17)) * ratio;
      final end = endAlong(axis, row.cellRectFor(35)) * ratio;
      expect(seam, 808.5, reason: 'the seam this pin is about');

      const thick = 42.0;
      Rect across(double from, double to) => rectAlong(
        axis,
        along: (from: from, to: to),
        across: (from: 0, to: thick),
      );
      (double, double, double, double) box(double from, double to) {
        final rect = across(from, to);
        return (rect.left, rect.top, rect.right, rect.bottom);
      }

      (double, double, double, double) all(GpuGridPicture picture) => (
        0,
        0,
        picture.width.toDouble(),
        picture.height.toDouble(),
      );

      // Around the seam alone: what stands at a block's ends is no seam's.
      final near = across(seam.floorToDouble() - 40, seam.floorToDouble() + 40);
      final around = (
        near.left.toInt(),
        near.top.toInt(),
        near.right.toInt(),
        near.bottom.toInt(),
      );
      final size = sizeAlong(axis, along: end.ceilToDouble(), across: thick);
      final surface = shownSurfaceOf(size.width.toInt(), size.height.toInt());
      addTearDown(surface.free);
      final lay = GpuGridLay(appGpuEngine);
      addTearDown(lay.free);

      lay.lay(surface, around, [
        (picture: first, from: all(first), onto: box(0, seam)),
        (picture: second, from: all(second), onto: box(seam, end)),
      ]);
      final seamed = surface.fingerprint();

      lay.lay(surface, around, [
        (picture: whole, from: all(whole), onto: box(0, end)),
      ]);
      expect(seamed, surface.fingerprint());
    });
  }

  // What the row itself says of its tiles: the same `from` and `onto`.
  //
  // 🔬F-604 (유저 2026-11-16 「엣지랑 블록이랑 안맞는 문제는 행 off로하면
  // 또 이번엔 왼쪽아래 엣지가 밖으로 나간다거나」): one of the tile's pixels to
  // a device pixel, what its cells were drawn on and not the whole pixels
  // around them. ↩️The whole of its picture was laid over the cells: a row
  // 28 across at 0.9 is 25.2 device pixels and its tile 26, so the paper's
  // foot rose ¾ of a pixel above its grip's, which stands where it is drawn.
  for (final (at, across) in const [(ratio, 42.0), (0.9, 25.2)]) {
    test('at $at, a row lays a tile over its cells one of its pixels to a '
        'device pixel', () async {
      final row = aBlockRow(Axis.horizontal, at: at);
      await tile(row, 0, 18);
      await tile(row, 18, 36);
      final laid = tilesLaidBy(
        () => row.paint(_noCanvas(), const Size(60 * cell, 28)),
      );
      final first = laid.first;

      expect(
        first.from.width,
        moreOrLessEquals(first.onto.width * at, epsilon: 1e-9),
      );
      expect(first.from.height, moreOrLessEquals(across, epsilon: 1e-9));
      expect(first.onto.height * at, moreOrLessEquals(across, epsilon: 1e-9));
      expect(
        first.picture.height,
        across.ceil(),
        reason: '⛔premise: the tile is whole pixels around its cells',
      );
    });
  }
}

Canvas _noCanvas() => Canvas(PictureRecorder());
