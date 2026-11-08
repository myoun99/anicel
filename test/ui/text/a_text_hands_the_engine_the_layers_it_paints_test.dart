import 'dart:ui' as ui;

import 'package:anicel/src/models/app_language.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/text_cel_style.dart';
import 'package:anicel/src/ui/text/canvas_letter_shapes.dart';
import 'package:anicel/src/ui/text/canvas_letter_style.dart';
import 'package:anicel/src/ui/text/text_cel_render.dart';
import 'package:anicel/src/ui/theme/app_theme.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/app_faces.dart';

/// 🚨A TEXT HANDS THE GPU ENGINE THE LAYERS IT PAINTS
/// (cel-number-on-the-engine-letters): `TextCelLayout.shapes` is the
/// layout's own `paint` as data — the box behind, then the letters' layers
/// in `CanvasLetterPasses.layers`' order, each in the one paint it covers
/// in, the lines its letters wear in it, each cluster where the layout set
/// it — so the engine rasters what the walk draws, and no copy of where.
void main() {
  setUpAll(loadTheAppFaces);

  TextCelLayout laid(String text, TextCelStyle style) {
    final layout = layoutTextCel(
      content: TextCelContent(
        text: text,
        style: style,
        position: ui.Offset.zero,
      ),
      canvas: const CanvasSize(width: 0, height: 0),
    );
    addTearDown(layout.dispose);
    return layout;
  }

  List<CanvasLetterClusters> runsOf(CanvasLetterShapes layer) =>
      layer.shapes.whereType<CanvasLetterClusters>().toList();

  List<ui.Rect> rectsOf(CanvasLetterShapes layer) => [
    for (final shape in layer.shapes.whereType<CanvasLetterRect>()) shape.rect,
  ];

  test('smooth letters are one fill in their colour, each cluster at the '
      'left of its box on its line\'s baseline', () {
    const style = TextCelStyle(color: 0x802050C0, letterSpacing: 3);
    final layout = laid('Aé셀', style);
    final [layer] = layout.shapes;
    expect(
      (layer.argb, layer.hard, layer.outline),
      (0x802050C0, false, 0.0),
    );
    final [run] = runsOf(layer);
    expect(run.size, style.fontSize);
    expect(run.letters, style);
    expect([for (final cluster in run.clusters) cluster.text], [
      'A',
      'é',
      '셀',
    ]);

    final painter = TextPainter(
      text: TextSpan(
        text: 'Aé셀',
        style: canvasLetterTextStyle(style, lineHeight: 1.25),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    addTearDown(painter.dispose);
    final baseline = painter.computeLineMetrics().single.baseline;
    for (final (index, cluster) in run.clusters.indexed) {
      final box = painter
          .getBoxesForSelection(
            TextSelection(baseOffset: index, extentOffset: index + 1),
          )
          .single;
      expect(
        cluster.left,
        moreOrLessEquals(layout.topLeft.dx + box.left),
        reason: cluster.text,
      );
      expect(
        cluster.baseline,
        moreOrLessEquals(layout.topLeft.dy + baseline),
        reason: cluster.text,
      );
    }
  });

  test('a box, an outline and a line: the box behind, the outlines under '
      'the fills, the line in each', () {
    const style = TextCelStyle(
      color: 0xFF202020,
      outlineColor: 0xFFFFFFFF,
      outlineWidth: 6,
      underline: true,
      backgroundColor: 0xFFE02020,
    );
    final [box, outline, fill] = laid('SE', style).shapes;
    expect((box.argb, box.hard, box.outline), (0xFFE02020, false, 0.0));
    expect(box.shapes, [isA<CanvasLetterRect>()]);
    expect(
      (outline.argb, outline.hard, outline.outline),
      (0xFFFFFFFF, false, 6.0),
    );
    expect((fill.argb, fill.hard, fill.outline), (0xFF202020, false, 0.0));
    for (final layer in [outline, fill]) {
      expect(runsOf(layer), hasLength(1));
      expect(rectsOf(layer), hasLength(1), reason: 'the underline');
    }
    expect(rectsOf(outline), rectsOf(fill));
  });

  test('hard letters are cut in their colour, alpha and all — and so is '
      'the box of a text none of whose letters is smooth', () {
    const style = TextCelStyle(
      color: 0x80102030,
      outlineColor: 0xC0405060,
      outlineWidth: 4,
      antialias: false,
      backgroundColor: 0xFF00FF00,
    );
    final [box, outline, fill] = laid('H', style).shapes;
    expect((box.argb, box.hard), (0xFF00FF00, true));
    expect(
      (outline.argb, outline.hard, outline.outline),
      (0xC0405060, true, 4.0),
    );
    expect((fill.argb, fill.hard, fill.outline), (0x80102030, true, 0.0));
  });

  test('lines are runs of their own, a line lower down, and a break is no '
      'cluster', () {
    final [layer] = laid('AB\nC', const TextCelStyle()).shapes;
    final [first, second] = runsOf(layer);
    expect([for (final cluster in first.clusters) cluster.text], ['A', 'B']);
    expect([for (final cluster in second.clusters) cluster.text], ['C']);
    expect(
      second.clusters.single.baseline,
      greaterThan(first.clusters.first.baseline),
    );
  });

  test('the canvas letters fall down the faces the engine is handed, in '
      'its order — Noto Sans SC last (engine-canvas-letters-Q2)', () {
    final families = [
      for (final face in AppTypography.canvasLetterFaces) face.family,
    ];
    expect(
      canvasLetterTextStyle(
        const TextLetterStyle(),
        lineHeight: 1,
      ).fontFamilyFallback,
      families,
    );
    expect(families.last, AppTypography.familyFor(AppLanguage.zhHans));
  });
}
