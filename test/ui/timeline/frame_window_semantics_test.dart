import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/timeline/frame_window_semantics.dart';

/// The one "window → one semantics node per labelled frame" walk behind
/// the frame ruler, the painted rows and the X-sheet rail (the audit's
/// clone scan, 2026-09-06).
void main() {
  Rect rectFor(int frameIndex) => Rect.fromLTWH(frameIndex * 10.0, 0, 10, 20);

  test('walks the half-open window and skips frames with no label', () {
    final asked = <int>[];
    final nodes = frameWindowSemantics(
      window: (startIndex: 2, endIndexExclusive: 6),
      rectFor: rectFor,
      labelFor: (frameIndex) {
        asked.add(frameIndex);
        return frameIndex == 4 ? null : 'frame ${frameIndex + 1}';
      },
    );
    expect(asked, [2, 3, 4, 5]);
    expect(nodes.map((node) => node.properties.label), [
      'frame 3',
      'frame 4',
      'frame 6',
    ]);
  });

  test('each node carries its frame\'s rect and reads left to right', () {
    final nodes = frameWindowSemantics(
      window: (startIndex: 3, endIndexExclusive: 5),
      rectFor: rectFor,
      labelFor: (frameIndex) => 'f$frameIndex',
    );
    expect(nodes.length, 2);
    expect(nodes[0].rect, const Rect.fromLTWH(30, 0, 10, 20));
    expect(nodes[1].rect, const Rect.fromLTWH(40, 0, 10, 20));
    expect(nodes[0].properties.textDirection, TextDirection.ltr);
  });

  test('an empty window emits nothing', () {
    expect(
      frameWindowSemantics(
        window: (startIndex: 5, endIndexExclusive: 5),
        rectFor: rectFor,
        labelFor: (_) => 'x',
      ),
      isEmpty,
    );
  });
}
