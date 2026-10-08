import 'dart:ui';

import 'package:anicel/src/ui/dashed_path.dart';
import 'package:flutter_test/flutter_test.dart';

/// THE ONE WALK every dashed line in the app is drawn by ([dashesAlong]) —
/// the selection's ants, the timeline's repeat span and drop silhouette,
/// the text tool's resting boxes. Where a dash is, is measured here once;
/// what each painter does with its dashes is its own test's.
void main() {
  /// Five of line, four of none — the ants' own.
  const fiveFour = DashPattern(on: 5, off: 4);

  Path line(double from, double to, {double y = 0}) => Path()
    ..moveTo(from, y)
    ..lineTo(to, y);

  /// To the thousandth: a path keeps its points in single precision.
  double near(double value) => (value * 1000).roundToDouble() / 1000;

  /// Where each dash runs along a level line: its two ends.
  List<(double, double)> spans(Iterable<Path> dashes) => [
    for (final dash in dashes)
      (near(dash.getBounds().left), near(dash.getBounds().right)),
  ];

  test('a line is walked on and off from its start, and its last dash '
      'stops where the line does', () {
    expect(spans(dashesAlong(line(0, 20), fiveFour)), [
      (0, 5),
      (9, 14),
      (18, 20),
    ]);
  });

  test('a line that ends in a gap has no dash there', () {
    expect(spans(dashesAlong(line(0, 8), fiveFour)), [(0, 5)]);
  });

  test('🚨a phase slides the pattern BACK along the line — and what that '
      'leaves of a dash before the start is not drawn', () {
    // Three back: the dash that stood at 9 stands at 6, and the one that
    // stood at 0 would run from -3 to 2 — the line opens on a gap instead.
    expect(spans(dashesAlong(line(0, 20), fiveFour.marchedBy(3))), [
      (6, 11),
      (15, 20),
    ]);
  });

  test('a phase of one whole pattern is no phase', () {
    expect(
      spans(dashesAlong(line(0, 20), fiveFour.marchedBy(9))),
      spans(dashesAlong(line(0, 20), fiveFour)),
    );
  });

  test('every contour is walked from its OWN start', () {
    final two = Path()
      ..addPath(line(0, 7), Offset.zero)
      ..addPath(line(100, 112), Offset.zero);

    expect(spans(dashesAlong(two, fiveFour)), [
      (0, 5),
      (100, 105),
      (109, 112),
    ]);
  });

  test('a dash follows the line round a corner', () {
    final corner = Path()
      ..moveTo(0, 0)
      ..lineTo(3, 0)
      ..lineTo(3, 10);

    final first = dashesAlong(corner, fiveFour).first;

    expect(first.getBounds(), const Rect.fromLTRB(0, 0, 3, 2));
  });

  group('a dashed outline that reads on any artwork', () {
    /// The paths a painting strokes, in the order it strokes them: how long
    /// each contour of each is, and the paint it is stroked in.
    List<({List<double> lengths, Paint paint})> strokedBy(
      void Function(Canvas canvas) painting,
    ) {
      final calls = <({List<double> lengths, Paint paint})>[];
      bool record(Symbol method, List<dynamic> arguments) {
        calls.add((
          lengths: [
            for (final metric in (arguments.first as Path).computeMetrics())
              near(metric.length),
          ],
          paint: arguments.last as Paint,
        ));
        return method == #drawPath;
      }

      expect(
        painting,
        paints
          ..something(record)
          ..something(record),
      );
      expect(painting, paintsExactlyCountTimes(#drawPath, 2));
      return calls;
    }

    test('🚨is WHITE along the whole line first, and the dashes in its '
        'colour over that — each a hairline', () {
      const ink = Color(0xFF123456);

      final [under, over] = strokedBy(
        (canvas) => paintDashedOutline(
          canvas,
          line(0, 20),
          color: ink,
          dashes: fiveFour,
        ),
      );

      // ⚠️By their 32 bits: a paint keeps its colour in single precision,
      // and read back it is not, bit for bit, the colour it was handed.
      expect(under.lengths, [20]);
      expect(under.paint.color.toARGB32(), 0xFFFFFFFF);
      expect(over.lengths, [5, 5, 2]);
      expect(over.paint.color.toARGB32(), ink.toARGB32());
      for (final paint in [under.paint, over.paint]) {
        expect(paint.style, PaintingStyle.stroke);
        expect(paint.strokeWidth, 1);
      }
    });

    test('marches by its phase', () {
      final [_, over] = strokedBy(
        (canvas) => paintDashedOutline(
          canvas,
          line(0, 20),
          color: const Color(0xFF000000),
          dashes: fiveFour.marchedBy(3),
        ),
      );

      // From 6 and from 15 — the whole dashes a phase of three leaves.
      expect(over.lengths, [5, 5]);
    });
  });
}
