import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/timeline/frame_window_semantics.dart';

/// The one "window → one semantics node per labelled frame" walk behind
/// the frame ruler and the X-sheet rail (the audit's clone scan,
/// 2026-09-06), and the one sentence a painted row says its window in
/// (I-57-Q3 c).
void main() {
  Rect rectFor(int frameIndex) => Rect.fromLTWH(frameIndex * 10.0, 0, 10, 20);

  group('🚨a row says its window in ONE node', () {
    /// Cells 1–3 a block of drawing 1, 4 a block of drawing 1 again, 5–6
    /// empty, 7 a block of drawing 2 with a mark at 8 and held to 9, and 11
    /// and 12 two blocks of drawing 3, a frame each.
    ({String label, bool runsOn})? cellAt(int frameIndex) =>
        switch (frameIndex) {
          1 || 4 => (label: 'drawing start 1', runsOn: false),
          2 || 3 || 9 => (label: 'held exposure', runsOn: true),
          7 => (label: 'drawing start 2', runsOn: false),
          8 => (label: 'inbetween mark', runsOn: true),
          11 || 12 => (label: 'drawing start 3', runsOn: false),
          _ => null,
        };

    test('what each cell says, in frame order — a run said once with its '
        'frames, a block\'s first cell beginning its own', () {
      final nodes = frameWindowSentence(
        window: (startIndex: 0, endIndexExclusive: 14),
        rectFor: rectFor,
        cellAt: cellAt,
      );
      expect(nodes, hasLength(1));
      expect(
        nodes.single.properties.label,
        'drawing start 1, frame 2; held exposure, frames 3 to 4; '
        'drawing start 1, frame 5; drawing start 2, frame 8; '
        'inbetween mark, frame 9; held exposure, frame 10; '
        'drawing start 3, frame 12; drawing start 3, frame 13',
      );
      expect(nodes.single.properties.textDirection, TextDirection.ltr);
    });

    test('a window that opens inside a run says the run from the window\'s '
        'first frame', () {
      final nodes = frameWindowSentence(
        window: (startIndex: 3, endIndexExclusive: 5),
        rectFor: rectFor,
        cellAt: cellAt,
      );
      expect(
        nodes.single.properties.label,
        'held exposure, frame 4; drawing start 1, frame 5',
      );
    });

    test('the node stands over the whole window', () {
      final nodes = frameWindowSentence(
        window: (startIndex: 2, endIndexExclusive: 6),
        rectFor: rectFor,
        cellAt: cellAt,
      );
      expect(nodes.single.rect, const Rect.fromLTWH(20, 0, 40, 20));
    });

    test('each cell is asked once', () {
      final asked = <int>[];
      frameWindowSentence(
        window: (startIndex: 0, endIndexExclusive: 14),
        rectFor: rectFor,
        cellAt: (frameIndex) {
          asked.add(frameIndex);
          return cellAt(frameIndex);
        },
      );
      expect(asked, [for (var frame = 0; frame < 14; frame += 1) frame]);
    });

    test('a window where no cell says anything says nothing — an empty one '
        'too', () {
      expect(
        frameWindowSentence(
          window: (startIndex: 5, endIndexExclusive: 7),
          rectFor: rectFor,
          cellAt: cellAt,
        ),
        isEmpty,
      );
      expect(
        frameWindowSentence(
          window: (startIndex: 5, endIndexExclusive: 5),
          rectFor: rectFor,
          cellAt: cellAt,
        ),
        isEmpty,
      );
    });
  });

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

  test('a step walks only the frames on it, from the first one on it', () {
    final asked = <int>[];
    frameWindowSemantics(
      window: (startIndex: 7, endIndexExclusive: 30),
      step: 6,
      rectFor: rectFor,
      labelFor: (frameIndex) {
        asked.add(frameIndex);
        return 'f$frameIndex';
      },
    );
    expect(asked, [12, 18, 24]);
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
