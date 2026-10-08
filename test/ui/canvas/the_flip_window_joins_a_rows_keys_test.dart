import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/ui/canvas/flip_hud_controller.dart';
import 'package:anicel/src/ui/canvas/flip_hud_model.dart';
import 'package:anicel/src/ui/canvas/flip_hud_overlay.dart';
import 'package:anicel/src/ui/timeline/timeline_cell_style.dart'
    show timelineJoiningLineWidth;

/// 🗣️I-73-lines-Q1 (유저 2026-10-09: 「플립 창에도 긋는다」) — the line the
/// panels draw between a row's first key and its last (「사이만 존재하도록」)
/// is in the flip window's key row too: one line, from the middle of the
/// first key's slot to the middle of the last's, none beside a key alone.
void main() {
  final scheme = ColorScheme.fromSeed(seedColor: Colors.blue);

  FlipHudRun key(int frame) =>
      FlipHudRun(startIndex: frame, length: 1, isKey: true);

  /// The joining lines the frame window paints for one row of [runs] —
  /// each from its start to its end, as thick as the panels' line.
  List<(Offset, Offset)> joins(List<FlipHudRun> runs, {bool frameStep = true}) {
    final canvas = TestRecordingCanvas();
    FlipHudPainter(
      snapshot: FlipHudSnapshot(
        rows: [
          FlipHudRow(
            name: 'Position',
            kind: LayerKind.camera,
            isLane: true,
            holdsDrawings: false,
            runs: runs,
          ),
        ],
        rowIndex: 0,
        frameIndex: 3,
        frameCount: 12,
      ),
      axis: FlipHudAxis.frame,
      frameStep: frameStep,
      colorScheme: scheme,
      baseTextStyle: const TextStyle(fontSize: 11),
    ).paint(canvas, FlipHudMetrics.sizeFor(FlipHudAxis.frame));
    // A paint keeps its stroke as a 32-bit float: 1.4 reads back a hair
    // under.
    bool joining(Paint paint) =>
        (paint.strokeWidth - timelineJoiningLineWidth).abs() < 1e-6;
    return [
      for (final call in canvas.invocations)
        if (call.invocation.memberName == #drawLine &&
            joining(call.invocation.positionalArguments[2] as Paint))
          (
            call.invocation.positionalArguments[0] as Offset,
            call.invocation.positionalArguments[1] as Offset,
          ),
    ];
  }

  test('a row of keys draws one line from its first key to its last', () {
    final lines = joins([key(1), key(3), key(5)]);

    expect(lines, hasLength(1));
    final (from, to) = lines.single;
    expect(from.dy, to.dy, reason: 'along the strip');
    expect(
      to.dx - from.dx,
      closeTo(4 * FlipHudMetrics.frameCellWidth, 1e-6),
      reason: 'the middle of key 1\'s slot to the middle of key 5\'s',
    );
  });

  test('stepping a block at a time, it runs between the keys\' slots too', () {
    final lines = joins([key(1), key(5)], frameStep: false);

    expect(lines, hasLength(1));
    final (from, to) = lines.single;
    expect(to.dx, greaterThan(from.dx));
  });

  test('a key alone draws none', () {
    expect(joins([key(2)]), isEmpty);
  });

  test('a row of blocks draws none', () {
    expect(
      joins([
        const FlipHudRun(startIndex: 0, length: 2, label: '1'),
        const FlipHudRun(startIndex: 4, length: 2, label: '2'),
      ]),
      isEmpty,
    );
  });
}
