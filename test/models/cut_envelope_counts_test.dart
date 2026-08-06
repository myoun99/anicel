import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/envelope/cut_envelope_counts.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/timeline_exposure.dart';

/// The cut envelope's 担当 rows. 原画 counts drawings that exist; 動画 adds
/// one per in-between dot, and says so on the form because the real number
/// has nowhere to come from yet.
Layer _layer(
  String name, {
  LayerKind kind = LayerKind.animation,
  bool onTimesheet = true,
  int frames = 0,
  Map<int, TimelineExposure>? timeline,
}) {
  return Layer(
    id: LayerId(name),
    name: name,
    kind: kind,
    onTimesheet: onTimesheet,
    frames: [
      for (var index = 1; index <= frames; index += 1)
        Frame(
          id: FrameId('$name$index'),
          duration: 1,
          strokes: const [],
          name: '$index',
        ),
    ],
    timeline: timeline ?? const {},
  );
}

Cut _cut(List<Layer> layers) => Cut(
  id: const CutId('cut-1'),
  name: '20',
  layers: layers,
  duration: 48,
  canvasSize: const CanvasSize(width: 1280, height: 720),
);

void main() {
  test('rows are the timesheet\'s animation rows, in stack order', () {
    final rows = cutEnvelopeCelCounts(
      _cut([
        _layer('A', frames: 3),
        _layer('B', frames: 2),
      ]),
    );

    expect(rows.map((row) => row.name), ['A', 'B']);
    expect(rows.map((row) => row.genga), [3, 2]);
  });

  test('a BG picture row is not a cel', () {
    final rows = cutEnvelopeCelCounts(
      _cut([
        _layer('A', frames: 3),
        _layer('BG', kind: LayerKind.image, frames: 1),
      ]),
    );

    expect(
      rows.map((row) => row.name),
      ['A'],
      reason: 'the sheet gate already excludes picture rows — BG/BOOK are '
          'not cels (user, 2026-08-06)',
    );
  });

  test('a row kept OFF the timesheet is off the envelope too', () {
    final rows = cutEnvelopeCelCounts(
      _cut([
        _layer('A', frames: 3),
        _layer('memo', frames: 5, onTimesheet: false),
      ]),
    );

    expect(rows.map((row) => row.name), ['A']);
  });

  test('動画 adds the in-between dots; 原画 does not', () {
    final rows = cutEnvelopeCelCounts(
      _cut([
        _layer(
          'A',
          frames: 2,
          timeline: {
            0: const TimelineExposure.drawing(
              FrameId('A1'),
              length: 6,
              breakdownOffsets: [2, 4],
            ),
            6: const TimelineExposure.drawing(
              FrameId('A2'),
              length: 6,
              breakdownOffsets: [3],
            ),
          },
        ),
      ]),
    );

    expect(rows.single.genga, 2, reason: 'dots are not drawings');
    expect(rows.single.dougaEstimate, 5, reason: '2 drawings + 3 dots');
  });

  test('a repeat GHOST bills nothing — it re-exposes drawings that exist', () {
    final rows = cutEnvelopeCelCounts(
      _cut([
        _layer(
          'A',
          frames: 2,
          timeline: {
            0: const TimelineExposure.drawing(
              FrameId('A1'),
              length: 4,
              breakdownOffsets: [2],
            ),
            4: const TimelineExposure.drawing(
              FrameId('A1'),
              length: 4,
              ghost: true,
              ghostOwnerId: 'run-1',
              breakdownOffsets: [2],
            ),
          },
        ),
      ]),
    );

    expect(rows.single.genga, 2);
    expect(
      rows.single.dougaEstimate,
      3,
      reason: 'the ghost chain would have billed its dots twice',
    );
  });

  test('the 計 row adds every cel up', () {
    final rows = cutEnvelopeCelCounts(
      _cut([
        _layer(
          'A',
          frames: 3,
          timeline: {
            0: const TimelineExposure.drawing(
              FrameId('A1'),
              length: 4,
              breakdownOffsets: [2],
            ),
          },
        ),
        _layer('B', frames: 2),
      ]),
    );

    final total = cutEnvelopeCelTotal(rows);

    expect(total.name, '計');
    expect(total.genga, 5);
    expect(total.dougaEstimate, 6);
  });

  test('a cut with no cels totals to zero rather than throwing', () {
    final rows = cutEnvelopeCelCounts(_cut(const []));

    expect(rows, isEmpty);
    expect(cutEnvelopeCelTotal(rows).genga, 0);
  });
}
