// A DRAWING ROW PAINTS TWO THINGS: THE SUBSTRATE UNDER ITS CELLS AND THE
// GLYPHS ON TOP — AND IT PAINTS BOTH WHETHER OR NOT A TILE STORE IS THERE.
//
// Three survivors of the mutation campaign (2026-09-04, the row cells
// painter's substrate/foreground split): the substrate pass dropped
// entirely, its cold-span fallback dropped, and the foreground pass
// dropped. All three survived because every existing row test reads the
// painter's cell MODEL (timeline_cell_probe) or its geometry — nothing
// looked at the pixels the painter actually lays down.
//
// ⚠️A row asks its store only on a grid's screen, where its tiles are laid
// (`TimelineGridScreenSlot.laying`); off one it paints its cells itself —
// the arm the second test pins. ↩️It was the native engine the store
// needed until grid-on-the-engine ④, and the second test the fallback
// INSIDE the tiled pass. A fresh tile is laid on the screen, not painted
// here (`the_grid_screen_shows_what_its_rows_lay`).
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/native/app_gpu_engine.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/timeline_coverage.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/ui/timeline/timeline_cell_exposure_state.dart';
import 'package:anicel/src/ui/timeline/timeline_grid_tile_store.dart';
import 'package:anicel/src/ui/timeline/timeline_row_cells_painter.dart';

import '../../helpers/tiles_laid.dart';
import 'timeline_frame_geometry_probe.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(openAppGpuEngine);

  const cell = 24.0;
  const crossExtent = 28.0;
  const frames = 6;
  const size = Size(cell * frames, crossExtent);

  TimelineCellExposureState stateFor(Layer layer, int frameIndex) {
    if (layer.timeline[frameIndex]?.isDrawing ?? false) {
      return TimelineCellExposureState.drawingStart;
    }
    if (coveringDrawingBlockAt(layer.timeline, frameIndex) != null) {
      return TimelineCellExposureState.held;
    }
    return TimelineCellExposureState.uncovered;
  }

  final layer = Layer(
    id: const LayerId('layer-a'),
    name: 'A',
    frames: [Frame(id: const FrameId('f1'), duration: 1, strokes: const [])],
    timeline: {0: const TimelineExposure.drawing(FrameId('f1'), length: 3)},
  );

  TimelineRowCellsPainter painterFor({TimelineGridTileStore? store}) =>
      TimelineRowCellsPainter(
        layer: layer,
        geometry: testFrameGeometry(
          frameCellExtent: cell,
          frameEndIndexExclusive: frames,
        ),
        crossAxisExtent: crossExtent,
        exposureStateForLayer: stateFor,
        // A label on the block start, so there is a glyph to look for.
        frameNameForLayer: (_, frameIndex) => frameIndex == 0 ? 'A1' : null,
        colorScheme: const ColorScheme.dark(),
        baseTextStyle: const TextStyle(fontSize: 11),
        tileStore: store,
        substrateGeneration: 'g1',
      );

  /// The painter's own output as raw RGBA over [size] — painted on a grid's
  /// screen when [onAScreen], where it asks its store.
  Future<Uint8List> paintBytes(
    TimelineRowCellsPainter painter, {
    bool onAScreen = false,
  }) async {
    final recorder = ui.PictureRecorder();
    void paint() => painter.paint(Canvas(recorder, Offset.zero & size), size);
    if (onAScreen) {
      expect(tilesLaidBy(paint), isEmpty, reason: 'premise: a cold store');
    } else {
      paint();
    }
    final picture = recorder.endRecording();
    final image = picture.toImageSync(size.width.round(), size.height.round());
    picture.dispose();
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    image.dispose();
    return data!.buffer.asUint8List();
  }

  /// How much of the strip is painted at all. The substrate FILLS its
  /// cells; the foreground only draws thin glyphs and dashes, so a strip
  /// with no substrate is nearly empty however many glyphs it carries.
  double paintedFraction(Uint8List bytes) {
    var painted = 0;
    final total = size.width.round() * size.height.round();
    for (var i = 3; i < bytes.length; i += 4) {
      if (bytes[i] > 0) painted += 1;
    }
    return painted / total;
  }

  /// How many DISTINCT colours the first cell holds. A cell with only its
  /// substrate is one flat fill (plus its border); a cell with a glyph on
  /// top holds the ink and its antialiasing too.
  int coloursInFirstCell(Uint8List bytes) {
    final seen = <int>{};
    final width = size.width.round();
    // Inside the cell, clear of its border: the glyph sits here.
    for (var y = 4; y < crossExtent - 4; y += 1) {
      for (var x = 4; x < cell - 4; x += 1) {
        final i = (y * width + x.toInt()) * 4;
        seen.add(
          bytes[i] << 24 |
              bytes[i + 1] << 16 |
              bytes[i + 2] << 8 |
              bytes[i + 3],
        );
      }
    }
    return seen.length;
  }

  setUp(TimelineGridTileStore.instance.clear);

  testWidgets('with no tile store the row paints its cells AND their '
      'glyphs', (tester) async {
    await tester.runAsync(() async {
      final bytes = await paintBytes(painterFor());
      expect(
        paintedFraction(bytes),
        greaterThan(0.5),
        reason:
            'the substrate reaches the cell edge — with the substrate '
            'pass gone the row is transparent there',
      );
      expect(
        coloursInFirstCell(bytes),
        greaterThan(1),
        reason:
            'the glyph is ON the substrate — with the foreground pass '
            'gone the cell is one flat fill',
      );
    });
  });

  testWidgets('with a tile store but no screen to lay its tiles on the row '
      'paints its cells AND their glyphs itself', (tester) async {
    await tester.runAsync(() async {
      final bytes = await paintBytes(
        painterFor(store: TimelineGridTileStore.instance),
      );
      // ↩️MEASURED (2026-09-04): with a store but no engine this strip came
      // out 0.101 painted — the foreground alone — and deleting EITHER
      // substrate left it there, so this case could not pin them; a cold
      // span on a live store (F-94, the next test) did. Off a screen the
      // row paints its cells itself now, which this pins.
      expect(
        paintedFraction(bytes),
        greaterThan(0.5),
        reason: 'the substrate is painted, not left to a screen it is not on',
      );
      expect(
        coloursInFirstCell(bytes),
        greaterThan(1),
        reason: 'and the foregrounds still go on top of it',
      );
      expect(
        TimelineGridTileStore.instance.debugBusy,
        isFalse,
        reason: 'nothing was asked of the store',
      );
    });
  });

  testWidgets('🚨with the engine on and the store COLD, a span waiting for its '
      'tile paints the same cells the classic pass paints (F-94)',
      (tester) async {
    addTearDown(TimelineGridTileStore.instance.clear);
    await tester.runAsync(() async {
      final classic = paintedFraction(await paintBytes(painterFor()));
      TimelineGridTileStore.instance.clear();
      // Nothing has rastered yet, so every span asks and gets null — the
      // tiled pass has to lay the cells down itself while the raster lands
      // off-frame. That is the zoom step across a span boundary.
      final cold = paintedFraction(
        await paintBytes(
          painterFor(store: TimelineGridTileStore.instance),
          onAScreen: true,
        ),
      );
      expect(
        classic,
        greaterThan(0.5),
        reason: 'premise: the classic pass fills its cells',
      );
      expect(
        cold,
        closeTo(classic, 0.01),
        reason: 'a cold span keeps the classic paint underneath — with the '
            'fallback gone the strip is the foreground alone (~0.10) and '
            'every zoom step flashes the blocks away for a frame',
      );
    });
  });
}
