import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/project_frame_rate.dart';
import 'package:anicel/src/ui/timeline/timeline_frame_ruler_painter.dart';

/// A RULER MARK IS A POSITION, AND NOTHING HAS ELAPSED AT THE FIRST FRAME.
///
/// 유저 2026-08-13: 「룰러 숫자, 초 표시하는곳. 1부터 시작하는데 그게아니라
/// 0부터 시작하도록」.
///
/// The mark on frame 25 (at 24fps) is where exactly one second has passed,
/// so `1` belongs there and `0` belongs at the head. It used to count the
/// seconds themselves, which put every mark one ahead of the clock.
void main() {
  group('the mark counts elapsed time', () {
    test('the head of the axis is 0, not 1', () {
      expect(
        timelineRulerSecondsLabel(frameIndex: 0, framesPerSecond: 24),
        '0',
      );
    });

    test('one second has elapsed at frame index 24 (the 25th frame)', () {
      expect(
        timelineRulerSecondsLabel(frameIndex: 24, framesPerSecond: 24),
        '1',
      );
      expect(
        timelineRulerSecondsLabel(frameIndex: 48, framesPerSecond: 24),
        '2',
      );
    });

    test('nothing is printed off a boundary', () {
      for (final index in [1, 13, 23, 25, 47]) {
        expect(
          timelineRulerSecondsLabel(frameIndex: index, framesPerSecond: 24),
          '',
          reason: 'frame $index is not a second boundary',
        );
      }
    });

    test('it follows the project rate', () {
      expect(timelineRulerSecondsLabel(frameIndex: 12, framesPerSecond: 12), '1');
      expect(timelineRulerSecondsLabel(frameIndex: 30, framesPerSecond: 30), '1');
    });

    test('a nonsense rate falls back to 24 rather than dividing by zero', () {
      expect(timelineRulerSecondsLabel(frameIndex: 24, framesPerSecond: 0), '1');
    });
  });

  group('a LENGTH is a different question and keeps counting', () {
    test('24 frames is one second long — `1+0`, not `0+…`', () {
      expect(
        secondsPlusFramesLabel(24, 24),
        '1+0',
        reason:
            'The `s+ff` notation measures a DURATION: a cut of 24 frames is '
            'one second long. It looks like the ruler mark and answers the '
            'opposite question, which is why the two are separate functions '
            'and why only one of them moved.',
      );
      expect(secondsPlusFramesLabel(0, 24), '0+0');
    });
  });

  test('the expression lives in ONE place — no surface re-derives it', () {
    final offenders = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) {
        continue;
      }
      final path = entity.path.replaceAll(r'\', '/');
      if (path.endsWith('timeline_frame_ruler_painter.dart')) {
        continue; // the implementation itself
      }
      final lines = entity.readAsLinesSync();
      for (var i = 0; i < lines.length; i += 1) {
        // The shape the two surfaces used to carry, letter for letter.
        if (lines[i].contains('~/ safeFps') || lines[i].contains('~/ fps')) {
          offenders.add('$path:${i + 1}  ${lines[i].trim()}');
        }
      }
    }
    // The duration formatter is the ONE other place allowed to divide by the
    // rate, and it answers the other question (see the group above).
    offenders.removeWhere(
      (line) => line.startsWith('lib/src/models/project_frame_rate.dart') ||
          line.startsWith('lib/src/models/timesheet_document.dart') ||
          line.startsWith('lib/src/models/envelope/cut_envelope_source.dart'),
    );
    expect(
      offenders,
      isEmpty,
      reason:
          'A surface is computing the second mark for itself again. The '
          'timeline and the x-sheet each had their own copy of this '
          'expression, so the first fix would have left the sheet counting '
          'from 1. Call `timelineRulerSecondsLabel`.\n'
          '${offenders.join('\n')}',
    );
  });
}
