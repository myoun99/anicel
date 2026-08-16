import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/ui/timeline/timeline_cell_exposure_state.dart';
import 'package:anicel/src/ui/timeline/timeline_glyph_cache.dart';
import 'package:anicel/src/ui/timeline/timeline_row_cells_painter.dart';
import 'package:anicel/src/ui/timeline/timeline_row_run_labels_painter.dart';

import 'timeline_frame_geometry_probe.dart';

/// The block/코마 text is SELF-INVERTING now (user 2026-08-17): one white
/// fill in [BlendMode.difference] instead of the white-outline pair — the
/// number reads dark over the light paper blocks and light over dark
/// ground, pixel-by-pixel, with no outline pass left anywhere.
///
/// The pixel tests rasterize the REAL painters into one picture (the same
/// raster the production row uses: the run labels ride the cells painter
/// as its foreground pass, so blocks and text share a canvas) and sample
/// the label's glyph rect for polarity.
void main() {
  const cellWidth = 48.0;
  const crossExtent = 52.0;
  const frameCount = 12;
  const width = 576; // cellWidth * frameCount
  const height = 52;

  Layer blockLayer() => Layer(
    id: const LayerId('a-1'),
    name: 'A',
    kind: LayerKind.animation,
    frames: const [],
    timeline: {0: const TimelineExposure.drawing(FrameId('f1'), length: 4)},
  );

  // The hand-rolled exposure read matching that timeline: a 4-frame block
  // starting at 0 (the cells painter takes the resolver, not the model).
  TimelineCellExposureState stateFor(Layer layer, int frameIndex) {
    if (frameIndex == 0) {
      return TimelineCellExposureState.drawingStart;
    }
    if (frameIndex > 0 && frameIndex < 4) {
      return TimelineCellExposureState.held;
    }
    return TimelineCellExposureState.uncovered;
  }

  TimelineRowRunLabelsPainter labelsPainter() => TimelineRowRunLabelsPainter(
    layer: blockLayer(),
    geometry: testFrameGeometry(
      frameCellExtent: cellWidth,
      frameEndIndexExclusive: frameCount,
    ),
    crossAxisExtent: crossExtent,
    showSeconds: false,
    countingBase: 24,
  );

  TimelineRowCellsPainter cellsPainter() => TimelineRowCellsPainter(
    layer: blockLayer(),
    geometry: testFrameGeometry(
      frameCellExtent: cellWidth,
      frameEndIndexExclusive: frameCount,
    ),
    crossAxisExtent: crossExtent,
    exposureStateForLayer: stateFor,
    colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
    baseTextStyle: const TextStyle(fontSize: 12, color: Color(0xFF000000)),
  );

  /// Rasterizes [ground] (a backdrop color standing in for whatever the
  /// row composites under this raster), optionally the real cell
  /// substrate, then the run labels — all into ONE picture, exactly the
  /// production layering.
  Future<ByteData> rasterize(
    WidgetTester tester, {
    required Color ground,
    required bool withBlocks,
  }) async {
    final data = await tester.runAsync(() async {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.drawRect(
        const Rect.fromLTWH(0, 0, width * 1.0, height * 1.0),
        Paint()..color = ground,
      );
      if (withBlocks) {
        cellsPainter().paint(canvas, const Size(width * 1.0, height * 1.0));
      }
      labelsPainter().paint(canvas, const Size(width * 1.0, height * 1.0));
      final image = await recorder.endRecording().toImage(width, height);
      return image.toByteData(format: ui.ImageByteFormat.rawRgba);
    });
    return data!;
  }

  /// The label's glyph rect in integer pixels, read off the painter's own
  /// probe surface (anchor + the cached glyph's measured box).
  ({int left, int top, int right, int bottom}) glyphRect() {
    final painter = labelsPainter();
    final label = painter.runLabels().single;
    final glyph = timelineGlyphPainter(label.text, painter.labelStyle);
    return (
      left: (label.anchor.dx - glyph.width / 2).floor(),
      top: (crossExtent - glyph.height - 1).floor(),
      right: (label.anchor.dx + glyph.width / 2).ceil(),
      bottom: (crossExtent - 1).floor(),
    );
  }

  int sumAt(ByteData data, int x, int y) {
    final offset = (y * width + x) * 4;
    return data.getUint8(offset) +
        data.getUint8(offset + 1) +
        data.getUint8(offset + 2);
  }

  /// Classifies the glyph rect against [groundSum] (the channel sum of the
  /// pixels the glyph landed on): how many pixels the glyph TOUCHED
  /// (presence), and how many of those are solidly dark / light.
  ({int present, int dark, int light}) sample(ByteData data, int groundSum) {
    final rect = glyphRect();
    var present = 0;
    var dark = 0;
    var light = 0;
    for (var y = rect.top; y < rect.bottom; y += 1) {
      for (var x = rect.left; x < rect.right; x += 1) {
        final sum = sumAt(data, x, y);
        if ((sum - groundSum).abs() <= 60) {
          continue; // Untouched ground (or a wash too faint to count).
        }
        present += 1;
        if (sum < 300) {
          dark += 1;
        } else if (sum > 500) {
          light += 1;
        }
      }
    }
    return (present: present, dark: dark, light: light);
  }

  testWidgets('over the LIGHT paper block the number inverts to DARK — the '
      'real substrate and the real labels pass, one raster', (tester) async {
    // The block paper under the label is timelineDrawingHeldColor
    // (0xFFE9E7E2, channel sum 690) — painted by the actual cells painter
    // over a dark lane ground, so the sampled destination is the block.
    final data = await rasterize(
      tester,
      ground: const Color(0xFF17191C),
      withBlocks: true,
    );
    final counts = sample(data, 0xE9 + 0xE7 + 0xE2);
    expect(
      counts.present,
      greaterThanOrEqualTo(4),
      reason: 'presence anchor: glyph pixels exist on the paper',
    );
    expect(
      counts.dark,
      greaterThanOrEqualTo(4),
      reason: 'white ink in BlendMode.difference lands DARK on light paper; '
          'a srcOver white fill would leave nothing dark here',
    );
    expect(
      counts.dark,
      greaterThan(counts.light),
      reason: 'the glyph body is dark on this ground — bright pixels can '
          'only be antialiased slivers, never the ink',
    );
  });

  testWidgets('over DARK ground the same number lands LIGHT', (tester) async {
    // No substrate pass: the label sits directly on the dark ground, the
    // chromeless/collapsed row's situation (a row laid over dark artwork).
    const ground = Color(0xFF202020);
    final data = await rasterize(tester, ground: ground, withBlocks: false);
    final counts = sample(data, 0x20 * 3);
    expect(
      counts.present,
      greaterThanOrEqualTo(4),
      reason: 'presence anchor: glyph pixels exist on the dark ground',
    );
    expect(
      counts.light,
      greaterThanOrEqualTo(4),
      reason: 'the SAME white difference fill reads light over dark ground '
          '— pixel-by-pixel self-inversion, no outline needed',
    );
    expect(
      counts.light,
      greaterThan(counts.dark),
      reason: 'the glyph body is light on this ground',
    );
  });

  test('the outline arm is GONE from the glyph pipeline — the inverting '
      'fill is the only arm left', () {
    final cache = File(
      'lib/src/ui/timeline/timeline_glyph_cache.dart',
    ).readAsStringSync();
    expect(
      cache,
      contains('BlendMode.difference'),
      reason: 'the self-inverting fill lives in the shared glyph cache',
    );
    expect(
      cache,
      isNot(contains('PaintingStyle.stroke')),
      reason: 'no second stroke/outline pass remains in the glyph pipeline',
    );
    expect(
      cache,
      isNot(contains('outlineColor')),
      reason: 'the outline params left with the outline',
    );
    for (final path in [
      'lib/src/ui/timeline/timeline_row_run_labels_painter.dart',
      'lib/src/ui/storyboard_cut_blocks_painter.dart',
    ]) {
      expect(
        File(path).readAsStringSync(),
        contains('paintTimelineInvertingGlyph'),
        reason: 'every block/코마 text site paints the self-inverting fill: '
            '$path',
      );
    }
  });
}
