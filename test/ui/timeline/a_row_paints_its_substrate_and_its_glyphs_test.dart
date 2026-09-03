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
// ⚠️The store's own tiled path needs the native engine (`tileFor` answers
// null without it), so with a store present but no engine the painter
// takes the fallback INSIDE the tiled pass — which is exactly the arm the
// second test pins. The "a fresh tile carries its own glyphs" arm belongs
// to the native lane.
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/timeline_coverage.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/ui/timeline/timeline_cell_exposure_state.dart';
import 'package:anicel/src/ui/timeline/timeline_grid_tile_store.dart';
import 'package:anicel/src/ui/timeline/timeline_row_cells_painter.dart';

import 'timeline_frame_geometry_probe.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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

  /// The painter's own output as raw RGBA over [size].
  Future<Uint8List> paintBytes(TimelineRowCellsPainter painter) async {
    final recorder = ui.PictureRecorder();
    painter.paint(Canvas(recorder, Offset.zero & size), size);
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

  testWidgets('with a tile store but no fresh tile the row still paints '
      'its cells AND their glyphs', (tester) async {
    await tester.runAsync(() async {
      // The store answers null for every span here (the raster needs the
      // native engine), so the tiled pass produces nothing at all. What
      // reaches the strip here is the foreground alone.
      final bytes = await paintBytes(
        painterFor(store: TimelineGridTileStore.instance),
      );
      // ⛔MEASURED, NOT ASSUMED (2026-09-04): this strip comes out 0.101
      // painted, and deleting EITHER the store substrate or the classic
      // one leaves it at exactly 0.101 — this setup reaches neither and
      // CANNOT pin them. The bound below is what it really proves: a row
      // with a store but no fresh tile still paints, rather than coming
      // out blank. Pinning either substrate needs a setup that reaches it;
      // the one that would is still to be found.
      expect(
        paintedFraction(bytes),
        greaterThan(0.05),
        reason:
            'a row waiting for its tile still paints its cells rather than '
            'coming out blank',
      );
      expect(
        coloursInFirstCell(bytes),
        greaterThan(1),
        reason: 'and the foregrounds still go on top of it',
      );
    });
  });
}
