import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/ui/canvas/flip_hud_model.dart';
import 'package:anicel/src/ui/timeline/collapsed_row_overlay.dart';

/// I-22: at the ten-minute floor the folded row's fallback strip holds
/// ~10,000 frames, and it asked its row about every one of them for the
/// `x` markers and the selection cell. An empty stretch starts only at
/// frame 0 or where a run ends — so those are all it asks, and it still
/// marks exactly the cells it marked.
void main() {
  // Runs over 2-4 and 9; the cursor stands on the empty frame 7.
  Future<({int asks, _Laid laid})> foldedStrip(
    WidgetTester tester, {
    required double pixelsPerFrame,
  }) async {
    await tester.binding.setSurfaceSize(const Size(1800, 400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var asks = 0;
    final row = _CountingRow(() => asks += 1);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 1600,
            child: CollapsedRowOverlay(
              snapshot: FlipHudSnapshot(
                rows: [row],
                rowIndex: 0,
                frameIndex: 7,
                frameCount: 40,
              ),
              rail: null,
              naturalRailWidth: 100,
              pixelsPerFrame: pixelsPerFrame,
              framesPerSecond: 24,
            ),
          ),
        ),
      ),
    );
    final strip = find.byKey(const ValueKey<String>('collapsed-strip'));
    final laid = _Laid()..size = tester.getSize(strip);
    asks = 0;
    tester.widget<CustomPaint>(strip).painter!.paint(laid, laid.size!);
    return (asks: asks, laid: laid);
  }

  testWidgets('ten minutes of strip ask the row about its runs, not its '
      'frames', (tester) async {
    final strip = await foldedStrip(tester, pixelsPerFrame: 1 / 8);
    final frames = (strip.laid.size!.width * 8).floor();
    expect(frames, greaterThan(10000), reason: 'the premise: ten minutes');
    expect(strip.asks, lessThan(40));
  });

  testWidgets('and marks what it marked: an `x` where each empty stretch '
      'starts, the names at the heads, the cursor\'s empty cell', (
    tester,
  ) async {
    const cell = 12.0;
    final strip = await foldedStrip(tester, pixelsPerFrame: cell);
    int frameOf(double x) => (x / cell).floor();

    expect(
      [for (final word in strip.laid.paragraphs) frameOf(word.left)],
      unorderedEquals([0, 2, 5, 9, 10]),
      reason: 'x at 0, 5 and 10; the names 1 and 2 at 2 and 9',
    );
    expect(
      [for (final box in strip.laid.boxes) frameOf(box.left)],
      unorderedEquals([2, 2, 9, 9, 7, 7]),
      reason: 'each block and the cursor\'s empty cell, filled and outlined',
    );
  });
}

/// A row over 2-4 and 9 that says whenever it is asked where a run is.
class _CountingRow extends FlipHudRow {
  const _CountingRow(this.onAsk)
    : super(
        name: 'A',
        kind: LayerKind.animation,
        runs: const [
          FlipHudRun(startIndex: 2, length: 3, label: '1'),
          FlipHudRun(startIndex: 9, length: 1, label: '2'),
        ],
      );

  final void Function() onAsk;

  @override
  FlipHudRun? runAt(int frameIndex) {
    onAsk();
    return super.runAt(frameIndex);
  }
}

/// What the strip lays down: its words, and its rounded boxes.
class _Laid implements Canvas {
  final paragraphs = <Rect>[];
  final boxes = <Rect>[];
  Size? size;
  final _saved = <Matrix4>[];
  var _transform = Matrix4.identity();

  @override
  void save() => _saved.add(_transform.clone());

  @override
  void saveLayer(Rect? bounds, Paint paint) => save();

  @override
  void restore() => _transform = _saved.removeLast();

  @override
  void translate(double dx, double dy) =>
      _transform = _transform.multiplied(Matrix4.translationValues(dx, dy, 0));

  @override
  void scale(double sx, [double? sy]) => _transform = _transform.multiplied(
    Matrix4.diagonal3Values(sx, sy ?? sx, 1),
  );

  @override
  void drawRRect(RRect rrect, Paint paint) =>
      boxes.add(MatrixUtils.transformRect(_transform, rrect.outerRect));

  @override
  void drawParagraph(ui.Paragraph paragraph, Offset offset) => paragraphs.add(
    MatrixUtils.transformRect(
      _transform,
      offset & Size(paragraph.maxIntrinsicWidth, paragraph.height),
    ),
  );

  @override
  int getSaveCount() => _saved.length + 1;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
