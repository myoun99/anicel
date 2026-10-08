import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/timeline/timeline_lane_rows.dart';

/// 🗣️유저 2026-10-08 (I-73): 「ol쪽 만나면 선을 뭔가 꺾어서 위로 향하게 해서
/// 직선 잇는다던가?」 — the ONE line between a row's keys
/// ([TimelineLaneKeysLine]) steps across where its row draws the keys at
/// another height: a slope over the step's cell edge, half a cell wide each
/// side and never wider than [timelineKeysLineBendReach].
///
/// A box ten cells of 24px long and 30px across.
void main() {
  List<({double along, double across})> course({
    List<TimelineKeysLineStep> steps = const [],
    double crossFraction = 0.5,
    bool startsAtKey = true,
    bool endsAtKey = true,
    double along = 240,
    int cells = 10,
  }) => timelineKeysLineCourse(
    along: along,
    across: 30,
    cells: cells,
    startsAtKey: startsAtKey,
    endsAtKey: endsAtKey,
    crossFraction: crossFraction,
    steps: steps,
  );

  void expectCourse(
    List<({double along, double across})> actual,
    List<(double, double)> expected,
  ) {
    expect(actual.length, expected.length, reason: '$actual');
    for (var index = 0; index < expected.length; index += 1) {
      expect(actual[index].along, closeTo(expected[index].$1, 1e-9));
      expect(actual[index].across, closeTo(expected[index].$2, 1e-9));
    }
  }

  test('with no step it is the straight line between the first key\'s cell '
      'middle and the last\'s', () {
    expectCourse(course(), [(12, 15), (228, 15)]);
  });

  test('a box that stops short of a key runs the line to its edge', () {
    expectCourse(course(startsAtKey: false, endsAtKey: false), [
      (0, 15),
      (240, 15),
    ]);
  });

  test('a step slopes across its edge, six pixels either side', () {
    // The lower line (73%) up to the middle (50%) at cell 4's edge — an
    // arriving cut leaving its O.L.
    expectCourse(
      course(crossFraction: 0.73, steps: const [(edge: 4, to: 0.5)]),
      [(12, 21.9), (90, 21.9), (102, 15), (228, 15)],
    );
  });

  test('in a narrow cell the slope reaches half a cell, not six pixels', () {
    // Ten cells of 8px: half a cell is 4.
    final steps = course(along: 80, steps: const [(edge: 5, to: 0.27)]);
    expect(steps[1].along, closeTo(36, 1e-9));
    expect(steps[2].along, closeTo(44, 1e-9));
  });

  test('a slope never runs past the line\'s own ends', () {
    // A box that does not start at a key, stepping at its very first edge:
    // the slope's leading half would start before the line does.
    final steps = course(
      startsAtKey: false,
      steps: const [(edge: 0, to: 0.27)],
    );
    expect(steps[0].along, closeTo(0, 1e-9));
    expect(steps[1].along, closeTo(0, 1e-9), reason: 'held to its start');
    expect(steps[2].along, closeTo(6, 1e-9));
    expect(steps[2].across, closeTo(8.1, 1e-9));
    // …and at its far end the same.
    final last = course(endsAtKey: false, steps: const [(edge: 10, to: 0.27)]);
    expect(last[2].along, closeTo(240, 1e-9), reason: 'held to its end');
  });

  test('two steps in a row — a cut both arriving and leaving', () {
    final steps = course(
      crossFraction: 0.73,
      steps: const [(edge: 2, to: 0.5), (edge: 7, to: 0.27)],
    );
    final across = [for (final point in steps) point.across];
    expect(across.length, 6);
    for (final (index, want) in [21.9, 21.9, 15.0, 15.0, 8.1, 8.1].indexed) {
      expect(across[index], closeTo(want, 1e-9));
    }
  });

  test('a box too short to hold a line holds none', () {
    expect(course(along: 24, cells: 1), isEmpty);
  });
}
