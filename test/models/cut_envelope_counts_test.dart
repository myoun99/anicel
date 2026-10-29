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
import 'package:anicel/src/models/layer_mark.dart';
import 'package:anicel/src/models/layer_process.dart';
import 'package:anicel/src/models/timeline_exposure.dart';

/// The cut envelope's 担当 rows: one per cel name, each stage's drawings in
/// its own column — 原画 the sheet's ACTION block, 動画 and 仕上げ its CELL
/// block, by the rows' colour labels (F-498).
Layer _layer(
  String name, {
  String? id,
  LayerKind kind = LayerKind.animation,
  LayerMark mark = LayerMark.none,
  bool onTimesheet = true,
  int frames = 0,
  Map<int, TimelineExposure>? timeline,
  String? attachedTo,
}) {
  final rowId = id ?? name;
  return Layer(
    id: LayerId(rowId),
    name: name,
    kind: kind,
    mark: mark,
    onTimesheet: onTimesheet,
    attachedToLayerId: attachedTo == null ? null : LayerId(attachedTo),
    frames: [
      for (var index = 1; index <= frames; index += 1)
        Frame(
          id: FrameId('$rowId$index'),
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

const _inbetween = LayerMark(process: LayerProcess.inbetween);
const _finish = LayerMark(process: LayerProcess.finish);

void main() {
  test('rows are the timesheet\'s cel rows, in stack order', () {
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

  group('🗣️F-498: each stage counts only its own rows', () {
    test('a cel\'s 原画 and 動画 rows are one envelope row', () {
      final rows = cutEnvelopeCelCounts(
        _cut([
          _layer('A', id: 'A-key', frames: 3),
          _layer('B', frames: 2),
          _layer('A', id: 'A-douga', mark: _inbetween, frames: 7),
        ]),
      );

      expect(rows.map((row) => row.name), ['A', 'B']);
      expect(
        rows.first.genga,
        3,
        reason: 'the 動画 row is the CELL block\'s, not 原画',
      );
      expect(rows.first.douga, 7);
      expect(rows.last.douga, 0, reason: 'B has no 動画 row yet');
    });

    test('a 動画 label counts as 動画 whatever its revise', () {
      final rows = cutEnvelopeCelCounts(
        _cut([
          _layer(
            'A',
            mark: const LayerMark(
              process: LayerProcess.inbetween,
              revise: LayerRevise.inbetweenCheck,
            ),
            frames: 4,
          ),
        ]),
      );

      expect(rows.single.genga, 0);
      expect(rows.single.douga, 4);
    });

    test('a 仕上げ row counts under 仕上げ alone', () {
      final rows = cutEnvelopeCelCounts(
        _cut([
          _layer('A', id: 'A-key', frames: 3),
          _layer('A', id: 'A-finish', mark: _finish, frames: 5),
        ]),
      );

      expect(rows.single.genga, 3);
      expect(rows.single.douga, 0);
      expect(rows.single.shiage, 5);
    });

    test('in-between dots are not drawings — no column counts them', () {
      final rows = cutEnvelopeCelCounts(
        _cut([
          _layer(
            'A',
            frames: 2,
            timeline: {
              0: const TimelineExposure.drawing(
                FrameId('A1'),
                length: 6,
                breakdownMarks: {2: InbetweenMark.two, 4: InbetweenMark.two},
              ),
            },
          ),
        ]),
      );

      expect(rows.single.genga, 2);
      expect(rows.single.douga, 0, reason: '動画 is no longer estimated');
    });

    test('a row counts 原画 exactly when the sheet prints it in ACTION', () {
      for (final process in [null, ...LayerProcess.values]) {
        final layer = _layer(
          'A',
          mark: LayerMark(process: process),
          frames: 1,
        );
        final row = cutEnvelopeCelCounts(_cut([layer])).single;

        expect(row.genga + row.douga + row.shiage, 1, reason: '$process');
        expect(
          row.genga == 1,
          !layerTakesTheCelBlock(layer),
          reason: '$process: the envelope and the sheet read one law',
        );
      }
    });
  });

  test('the 計 row adds every cel up, stage by stage', () {
    final rows = cutEnvelopeCelCounts(
      _cut([
        _layer('A', frames: 3),
        _layer('B', frames: 2),
        _layer('A', id: 'A-douga', mark: _inbetween, frames: 6),
        _layer('B', id: 'B-finish', mark: _finish, frames: 4),
      ]),
    );

    final total = cutEnvelopeCelTotal(rows);

    expect(total.name, '計');
    expect(total.genga, 5);
    expect(total.douga, 6);
    expect(total.shiage, 4);
  });

  test('🚨an attach row is not a 担当 row — it rides its base, and the '
      'envelope must not bill its drawings a second time', () {
    final rows = cutEnvelopeCelCounts(
      _cut([
        _layer('A', frames: 3),
        _layer('A색', frames: 3, attachedTo: 'A'),
        _layer('B', frames: 2),
      ]),
    );

    expect(
      rows.map((row) => row.name),
      ['A', 'B'],
      reason: 'the sheet prints no attach columns — the envelope asks the '
          'one gate and nothing else',
    );
    expect(cutEnvelopeCelTotal(rows).genga, 5);
  });

  test('a cut with no cels totals to zero rather than throwing', () {
    final rows = cutEnvelopeCelCounts(_cut(const []));

    expect(rows, isEmpty);
    expect(cutEnvelopeCelTotal(rows).genga, 0);
  });
}
