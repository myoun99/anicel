import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/layer_mark.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/ui/theme/app_theme.dart' show AppColors;
import 'package:anicel/src/ui/timeline/layer_label_controls.dart'
    show layerMarkColor;
import 'package:anicel/src/ui/timeline/timeline_cel_content_source.dart';
import 'package:anicel/src/ui/timeline/timeline_cell_exposure_state.dart';
import 'package:anicel/src/ui/timeline/timeline_cell_style.dart';
import 'package:anicel/src/ui/timeline/timeline_glyph_cache.dart';
import 'package:anicel/src/ui/timeline/timeline_row_cells_painter.dart';
import 'package:anicel/src/ui/timeline/timeline_row_run_labels_painter.dart';

import 'timeline_frame_geometry_probe.dart';

/// The block/코마 text follows the GROUND LAW now (user 2026-08-17): solid
/// black or white picked by the luminance of the KNOWN color each label
/// sits on — [timelineTextOnColor]. It replaces #1104's difference blend,
/// whose inverted ink read navy on the PURPLE blocks, and before that the
/// #15 white outline; no blend, no halo, no outline pass anywhere.
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

  Layer blockLayer({LayerMark mark = LayerMark.none}) => Layer(
    id: const LayerId('a-1'),
    name: 'A',
    kind: LayerKind.animation,
    mark: mark,
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

  /// The unworked-cel source: every block reads as "no picture yet".
  TimelineCelContentSource emptyCels() => TimelineCelContentSource(
    hasContent: (_, _) => false,
    revision: ValueNotifier<int>(0),
  );

  TimelineRowRunLabelsPainter labelsPainter({
    LayerMark mark = LayerMark.none,
    TimelineCelContentSource? celContent,
  }) => TimelineRowRunLabelsPainter(
    layer: blockLayer(mark: mark),
    geometry: testFrameGeometry(
      frameCellExtent: cellWidth,
      frameEndIndexExclusive: frameCount,
    ),
    crossAxisExtent: crossExtent,
    showSeconds: false,
    countingBase: 24,
    celContent: celContent,
  );

  TimelineRowCellsPainter cellsPainter({
    LayerMark mark = LayerMark.none,
    TimelineCelContentSource? celContent,
  }) => TimelineRowCellsPainter(
    layer: blockLayer(mark: mark),
    geometry: testFrameGeometry(
      frameCellExtent: cellWidth,
      frameEndIndexExclusive: frameCount,
    ),
    crossAxisExtent: crossExtent,
    exposureStateForLayer: stateFor,
    celContent: celContent,
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
    LayerMark mark = LayerMark.none,
    TimelineCelContentSource? celContent,
  }) async {
    final data = await tester.runAsync(() async {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.drawRect(
        const Rect.fromLTWH(0, 0, width * 1.0, height * 1.0),
        Paint()..color = ground,
      );
      if (withBlocks) {
        cellsPainter(
          mark: mark,
          celContent: celContent,
        ).paint(canvas, const Size(width * 1.0, height * 1.0));
      }
      labelsPainter(
        mark: mark,
        celContent: celContent,
      ).paint(canvas, const Size(width * 1.0, height * 1.0));
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

  int channelSum(Color color) =>
      ((color.r + color.g + color.b) * 255.0).round();

  testWidgets('over the LIGHT paper block the number is solid DARK — the '
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
      reason:
          'the ground law picks BLACK over the light paper '
          '(luminance 0.80 > 0.179); a white pick would leave nothing dark',
    );
    expect(
      counts.dark,
      greaterThan(counts.light),
      reason:
          'the glyph body is dark on this ground — bright pixels can '
          'only be antialiased slivers, never the ink',
    );
  });

  testWidgets('over the PURPLE block the number is solid DARK — THE device '
      'regression: the difference blend read navy here', (tester) async {
    // The real purple palette color (layerMarkColor(LayerMark.purple),
    // 0xFF9B6BD3, luminance ≈0.22): above the crossover, so black wins —
    // 5.4:1 against white's 3.9:1, which is the pale-blue text the user
    // reported.
    final purple = layerMarkColor(LayerMark.purple);
    final data = await rasterize(
      tester,
      ground: const Color(0xFF17191C),
      withBlocks: true,
      mark: LayerMark.purple,
    );
    final counts = sample(data, channelSum(purple));
    expect(
      counts.present,
      greaterThanOrEqualTo(4),
      reason: 'presence anchor: glyph pixels exist on the purple paper',
    );
    expect(
      counts.dark,
      greaterThanOrEqualTo(4),
      reason:
          'the ground law picks BLACK over the purple paper — the '
          'difference blend (navy) and a white pick both fail this',
    );
    expect(
      counts.dark,
      greaterThan(counts.light),
      reason: 'the glyph body is dark on the purple block',
    );
  });

  testWidgets('over an EMPTY-CEL purple block on the dark lane the same '
      'number flips to solid LIGHT — the 43%-alpha blend is the ground', (
    tester,
  ) async {
    // The substrate paints the paper at the empty-cel alpha over the dark
    // lane; the composited ground is deep (luminance ≈0.07), so the law
    // flips to white (9.0:1) where opaque purple takes black.
    final blended = Color.alphaBlend(
      timelineEmptyCelPaperColor(layerMarkColor(LayerMark.purple)),
      AppColors.surface,
    );
    final data = await rasterize(
      tester,
      ground: AppColors.surface,
      withBlocks: true,
      mark: LayerMark.purple,
      celContent: emptyCels(),
    );
    final counts = sample(data, channelSum(blended));
    expect(
      counts.present,
      greaterThanOrEqualTo(4),
      reason: 'presence anchor: glyph pixels exist on the translucent paper',
    );
    expect(
      counts.light,
      greaterThanOrEqualTo(4),
      reason:
          'the label ground is the COMPOSITED empty-cel blend, not the '
          'opaque paper — black-on-dark (2.3:1) is what skipping the blend '
          'would produce',
    );
    expect(
      counts.light,
      greaterThan(counts.dark),
      reason: 'the glyph body is light on this ground',
    );
  });

  testWidgets('on the dark lane itself the shared paint entry lands solid '
      'LIGHT — the storyboard band/plate situation', (tester) async {
    // No substrate: the glyph is painted straight onto the cut-block plate
    // color through the one entry point every site uses.
    const style = TextStyle(fontSize: 11, fontWeight: FontWeight.w700);
    final data = await tester.runAsync(() async {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.drawRect(
        const Rect.fromLTWH(0, 0, 64, 24),
        Paint()..color = AppColors.washUp,
      );
      paintTimelineGlyphOnGround(
        canvas,
        const Offset(4, 4),
        '24',
        style,
        ground: AppColors.washUp,
      );
      final image = await recorder.endRecording().toImage(64, 24);
      return image.toByteData(format: ui.ImageByteFormat.rawRgba);
    });
    final bytes = data!;
    final groundSum = channelSum(AppColors.washUp);
    var present = 0;
    var light = 0;
    for (var y = 0; y < 24; y += 1) {
      for (var x = 0; x < 64; x += 1) {
        final offset = (y * 64 + x) * 4;
        final sum =
            bytes.getUint8(offset) +
            bytes.getUint8(offset + 1) +
            bytes.getUint8(offset + 2);
        if ((sum - groundSum).abs() <= 60) {
          continue;
        }
        present += 1;
        if (sum > 500) {
          light += 1;
        }
      }
    }
    expect(present, greaterThanOrEqualTo(4), reason: 'presence anchor');
    expect(
      light,
      greaterThanOrEqualTo(4),
      reason: 'washUp is far below the crossover (luminance 0.02): white',
    );
  });

  group('the ground law over the actual palette', () {
    test('every layer-mark paper takes the DARK ink — purple included, '
        'which is the reported regression', () {
      for (final mark in LayerMark.values) {
        expect(
          timelineTextOnColor(layerMarkColor(mark)),
          timelineTextOnLightGroundColor,
          reason:
              '$mark paper (${layerMarkColor(mark)}) has luminance '
              '${layerMarkColor(mark).computeLuminance().toStringAsFixed(3)}'
              ' > 0.179, where black is the higher-contrast ink',
        );
      }
    });

    test('every dark lane takes the LIGHT ink', () {
      for (final lane in [
        AppColors.surface,
        AppColors.backdrop,
        AppColors.washUp,
        AppColors.washDown,
      ]) {
        expect(
          timelineTextOnColor(lane),
          timelineTextOnDarkGroundColor,
          reason: '$lane is far below the crossover',
        );
      }
    });

    test('every COLORED mark\'s 43%-alpha empty-cel blend over the dark '
        'lane flips to the LIGHT ink; the plain paper\'s blend sits a hair '
        'above the crossover and stays dark — where both inks tie', () {
      for (final mark in LayerMark.values) {
        final blend = Color.alphaBlend(
          timelineEmptyCelPaperColor(layerMarkColor(mark)),
          AppColors.surface,
        );
        expect(
          timelineTextOnColor(blend),
          mark == LayerMark.none
              ? timelineTextOnLightGroundColor
              : timelineTextOnDarkGroundColor,
          reason:
              '$mark empty-cel blend $blend, luminance '
              '${blend.computeLuminance().toStringAsFixed(3)}',
        );
      }
    });

    test('the crossover is the WCAG optimum: on every live ground the '
        'chosen ink has at least the contrast of the rejected one', () {
      double contrast(double a, double b) {
        final hi = a > b ? a : b;
        final lo = a > b ? b : a;
        return (hi + 0.05) / (lo + 0.05);
      }

      final grounds = <Color>[
        for (final mark in LayerMark.values) layerMarkColor(mark),
        for (final mark in LayerMark.values)
          Color.alphaBlend(
            timelineEmptyCelPaperColor(layerMarkColor(mark)),
            AppColors.surface,
          ),
        AppColors.surface,
        AppColors.backdrop,
        AppColors.washUp,
        AppColors.washDown,
      ];
      for (final ground in grounds) {
        final l = ground.computeLuminance();
        final black = contrast(l, 0.0);
        final white = contrast(l, 1.0);
        final choseBlack =
            timelineTextOnColor(ground) == timelineTextOnLightGroundColor;
        expect(
          choseBlack ? black >= white : white >= black,
          isTrue,
          reason:
              '$ground: black $black vs white $white, law chose '
              '${choseBlack ? 'black' : 'white'}',
        );
      }
    });
  });

  test('the labels painter resolves its GROUND from the block: full paper '
      'when the cel has a picture, the empty-cel blend when it does not', () {
    expect(
      labelsPainter(mark: LayerMark.purple).groundForBlockAt(0),
      layerMarkColor(LayerMark.purple),
    );
    expect(
      labelsPainter(
        mark: LayerMark.purple,
        celContent: emptyCels(),
      ).groundForBlockAt(0),
      Color.alphaBlend(
        timelineEmptyCelPaperColor(layerMarkColor(LayerMark.purple)),
        AppColors.surface,
      ),
    );
  });

  test('the inverting and outline arms are GONE from the glyph pipeline — '
      'the ground-law solid is the only arm left', () {
    final cache = File(
      'lib/src/ui/timeline/timeline_glyph_cache.dart',
    ).readAsStringSync();
    expect(
      cache,
      contains('timelineTextOnColor'),
      reason: 'the ground law resolves the ink in the shared paint entry',
    );
    expect(
      cache,
      isNot(contains('BlendMode.difference')),
      reason: 'the difference blend left with #1104\'s arm (navy on purple)',
    );
    expect(
      cache,
      isNot(contains('PaintingStyle.stroke')),
      reason: 'no second stroke/outline pass remains in the glyph pipeline',
    );
    expect(
      cache,
      isNot(contains('inverting')),
      reason:
          'the flag left with the arm; the resolved color keys the '
          'cache through the style\'s own color slot',
    );
    for (final path in [
      'lib/src/ui/timeline/timeline_row_run_labels_painter.dart',
      'lib/src/ui/storyboard_cut_blocks_painter.dart',
    ]) {
      expect(
        File(path).readAsStringSync(),
        contains('paintTimelineGlyphOnGround'),
        reason:
            'every block/코마 text site paints the ground-law solid: '
            '$path',
      );
    }
  });

  test('D29: the strip\'s WRITING reads the picture ground when thumbnails '
      'are on — the B1 grip fix, applied to the text', () {
    final painter = File(
      'lib/src/ui/storyboard_cut_blocks_painter.dart',
    ).readAsStringSync();
    expect(
      painter,
      contains('storyboardPanelPictureGroundColor'),
      reason: 'the glyphs sit on paper-white composite thumbnails — the '
          'dark plate resolved WHITE ink on white pictures',
    );
    expect(
      RegExp(r'ground: _stripWritingGround\(block\)')
          .allMatches(painter)
          .length,
      greaterThanOrEqualTo(3),
      reason: 'panel name, comma AND the D30 create + all take the '
          'picture-aware ground (a no-layer cut still paints its '
          'coverage cell\'s paper-white composite under the +)',
    );
    expect(
      painter,
      isNot(contains('ground: _stripGround(block)')),
      reason: 'no strip glyph reads the plate directly — the writing '
          'ground decides (D29)',
    );
    expect(
      painter,
      isNot(contains('timelineFittedGlyphFontSize(\n          9,')),
      reason: 'the comma wears the cut-block text grade (_labelStyle\'s '
          '11), not a cell-fitted 9 (D29)',
    );
  });
}
