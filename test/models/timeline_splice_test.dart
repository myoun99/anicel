import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/timeline_splice.dart';

/// 🚨T2·T3 — the ONE splice, at the model level.
///
/// The row is written as a string so the assertions read like the timeline
/// does: `AAA.BB` is a 3-frame A, an empty cell, then a 2-frame B. What the
/// user asked for is stated in those terms too — 「A A A B B에서 A블록 복사
/// → B 첫 칸에 붙여넣기 → A A A P P P B B」 — so the test says the same
/// sentence the decision did.
void main() {
  group('splitTimelineAt', () {
    test('a hold becomes two entries over the same cel', () {
      final row = splitTimelineAt(_row('AAAA'), 2);

      expect(_render(row, 4), 'AAAA', reason: 'the cells do not move');
      expect(row.keys, [0, 2]);
      expect(row[0]!.length, 2);
      expect(row[2]!.length, 2);
      expect(row[2]!.frameId, const FrameId('A'));
    });

    test('a block start, an empty cell and an index past the end are '
        'already boundaries', () {
      expect(splitTimelineAt(_row('AAA'), 0).keys, [0]);
      expect(splitTimelineAt(_row('AAA.'), 3).keys, [0]);
      expect(splitTimelineAt(_row('AAA'), 9).keys, [0]);
    });

    test('the dots divide themselves, and the head keeps the memo', () {
      final timeline = {
        0: const TimelineExposure.drawing(
          FrameId('A'),
          length: 6,
          breakdownOffsets: [1, 3, 5],
        ),
      };

      final row = splitTimelineAt(timeline, 3);

      expect(row[0]!.breakdownOffsets, [1], reason: 'offset 3 became a start');
      expect(row[3]!.breakdownOffsets, [2], reason: '5 - 3');
    });
  });

  group('captureTimelineRun', () {
    test('a range that cuts a hold carries the PIECE it selected', () {
      final clip = captureTimelineRun(
        timeline: _row('AAAAA'),
        index: 1,
        count: 2,
      );

      expect(clip.length, 2);
      expect(clip.exposures.keys, [0]);
      expect(clip.exposures[0]!.length, 2);
    });

    test('an empty cell inside the run comes back as an empty cell', () {
      final clip = captureTimelineRun(
        timeline: _row('AA.B'),
        index: 0,
        count: 4,
      );

      expect(clip.length, 4);
      expect(clip.exposures.keys, [0, 3]);
    });

    test('trailing blanks are part of what was selected', () {
      final clip = captureTimelineRun(
        timeline: _row('AA'),
        index: 0,
        count: 5,
      );

      expect(clip.length, 5, reason: 'the run is what the range said');
      expect(clip.exposures.keys, [0]);
    });
  });

  group('spliceTimeline', () {
    test('유저 예시: A A A B B에 A블록을 B의 첫 칸에 붙여넣으면 '
        'A A A P P P B B', () {
      final clip = captureTimelineRun(
        timeline: _row('AAABB'),
        index: 0,
        count: 3,
      );

      final row = spliceTimeline(timeline: _row('AAABB'), index: 3, clip: clip);

      expect(_render(row, 8), 'AAAAAABB');
      expect(row.keys, [0, 3, 6], reason: 'the pasted block is its own entry');
    });

    test('no lift means nothing is overwritten — the tail moves right', () {
      final clip = captureTimelineRun(
        timeline: _row('PP'),
        index: 0,
        count: 2,
      );

      final row = spliceTimeline(timeline: _row('AABB'), index: 2, clip: clip);

      expect(_render(row, 6), 'AAPPBB');
    });

    test('inserting inside a hold splits it rather than landing headless', () {
      final clip = captureTimelineRun(
        timeline: _row('P'),
        index: 0,
        count: 1,
      );

      final row = spliceTimeline(timeline: _row('AAAA'), index: 2, clip: clip);

      expect(_render(row, 5), 'AAPAA');
    });

    test('a LONGER clip pushes the tail', () {
      final clip = captureTimelineRun(
        timeline: _row('PPPP'),
        index: 0,
        count: 4,
      );

      final row = spliceTimeline(
        timeline: _row('AABBBCC'),
        index: 2,
        liftCount: 3,
        clip: clip,
      );

      expect(_render(row, 8), 'AAPPPPCC', reason: 'C survived, one to the right');
    });

    test('a SHORTER clip pulls the tail — ⛔the surplus is not overwritten', () {
      final clip = captureTimelineRun(
        timeline: _row('P'),
        index: 0,
        count: 1,
      );

      final row = spliceTimeline(
        timeline: _row('AABBBCC'),
        index: 2,
        liftCount: 3,
        clip: clip,
      );

      expect(_render(row, 5), 'AAPCC', reason: 'the gap closed, C is intact');
    });

    test('잘라내기 = a lift with no clip', () {
      final row = spliceTimeline(
        timeline: _row('AABBBCC'),
        index: 2,
        liftCount: 3,
      );

      expect(_render(row, 4), 'AACC');
    });

    test('the cut length is never asked — a push past the end line stays '
        'past the end line', () {
      final clip = captureTimelineRun(
        timeline: _row('PPPPPPPP'),
        index: 0,
        count: 8,
      );

      final row = spliceTimeline(timeline: _row('AB'), index: 1, clip: clip);

      expect(_render(row, 10), 'APPPPPPPPB');
      expect(row.keys.last, 9, reason: 'B is at 9 and nothing clamped it');
    });
  });
}

/// `AAB.C` → a 2-frame A, a 1-frame B, an empty cell, a 1-frame C.
Map<int, TimelineExposure> _row(String cells) {
  final timeline = <int, TimelineExposure>{};
  var index = 0;
  while (index < cells.length) {
    final symbol = cells[index];
    if (symbol == '.') {
      index += 1;
      continue;
    }
    var length = 1;
    while (index + length < cells.length && cells[index + length] == symbol) {
      length += 1;
    }
    timeline[index] = TimelineExposure.drawing(
      FrameId(symbol),
      length: length,
    );
    index += length;
  }
  return timeline;
}

/// The inverse, so a failure prints the row instead of a map.
String _render(Map<int, TimelineExposure> timeline, int cells) {
  final out = List<String>.filled(cells, '.');
  for (final entry in timeline.entries) {
    final symbol = entry.value.frameId?.value ?? '?';
    for (var at = entry.key; at < entry.key + (entry.value.length ?? 1); at += 1) {
      if (at >= 0 && at < cells) {
        out[at] = symbol;
      }
    }
  }
  return out.join();
}
