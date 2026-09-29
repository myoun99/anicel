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

    // 🗣️F-236 (유저 2026-09-29): 「블록 중간에 붙여넣는거랑 프레임 추가랑 똑같은
    // 법 통일」, and F-236-Q1: 「선택범위로 코마정보가 있을때만 코마대로
    // 유지해서 붙여넣어서 뒤가 짧으면 당기고 부족하면 밀고」. An insert inside a
    // hold REPLACES the rest of it. ↩️It split the hold and pushed its rest on
    // behind the clip — `AAAA` + P@2 was `AAPAA`, the same drawing again.
    group('inside a hold, the insert replaces the rest of it', () {
      test('an untimed comma takes the rest — the division an added frame '
          'makes', () {
        final clip = TimelineClipRow.untimed(
          const TimelineExposure.drawing(FrameId('P'), length: 1),
        );

        final row = spliceTimeline(
          timeline: _row('AAAA.BB'),
          index: 2,
          clip: clip,
        );

        expect(_render(row, 7), 'AAPP.BB', reason: 'nothing behind moves');
        expect(row.keys, [0, 2, 5]);
      });

      test('an untimed comma keeps the dots that time those frames, as an '
          'added frame does', () {
        final row = spliceTimeline(
          timeline: {
            0: const TimelineExposure.drawing(
              FrameId('A'),
              length: 6,
              breakdownOffsets: [1, 3, 5],
            ),
          },
          index: 3,
          clip: TimelineClipRow.untimed(
            const TimelineExposure.drawing(FrameId('P'), length: 1),
          ),
        );

        expect(row[3]!.frameId, const FrameId('P'));
        expect(row[3]!.length, 3);
        expect(row[3]!.breakdownOffsets, [2], reason: '5 - 3');
        expect(row[0]!.breakdownOffsets, [1]);
      });

      test('a timed run keeps its commas: a SHORTER one pulls the tail in', () {
        final clip = captureTimelineRun(
          timeline: _row('P'),
          index: 0,
          count: 1,
        );

        final row = spliceTimeline(
          timeline: _row('AAAAAB'),
          index: 2,
          clip: clip,
        );

        expect(_render(row, 6), 'AAPB..');
      });

      test('a timed run keeps its commas: a LONGER one pushes the tail', () {
        final clip = captureTimelineRun(
          timeline: _row('PPPP'),
          index: 0,
          count: 4,
        );

        final row = spliceTimeline(
          timeline: _row('AAAB'),
          index: 2,
          clip: clip,
        );

        expect(_render(row, 7), 'AAPPPPB');
      });

      test('at a block\'s HEAD nothing is inside — the insert goes in front '
          'and the block steps back, untimed or not', () {
        for (final clip in [
          TimelineClipRow.untimed(
            const TimelineExposure.drawing(FrameId('P'), length: 1),
          ),
          captureTimelineRun(timeline: _row('P'), index: 0, count: 1),
        ]) {
          final row = spliceTimeline(
            timeline: _row('AABB'),
            index: 2,
            clip: clip,
          );
          expect(_render(row, 5), 'AAPBB', reason: 'timed: ${clip.timed}');
        }
      });
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

    /// 🚨⑳ (유저 확정 2026-08-15): 「프레임 잘라내기하면 **뒤 프레임을
    /// 앞당김. 이딴거 누가넣으랫지?** 삭제는 잘만 해당 위치 블록만 삭제하고
    /// 다른거 위치 안건드는데」.
    ///
    /// ⛔This asserted `AACC` — everything after the cut pulled forward.
    /// That was MINE: E(T2·T3) built the splice as "the length difference is
    /// absorbed behind" and then defined 잘라내기 as a splice with no clip,
    /// so cutting dragged the rest of the row. The symmetry made it look
    /// right; nobody asked for it.
    test('잘라내기 leaves a HOLE — a bare lift moves nothing else', () {
      final row = spliceTimeline(
        timeline: _row('AABBBCC'),
        index: 2,
        liftCount: 3,
      );

      expect(
        _render(row, 7),
        'AA...CC',
        reason: 'the row a DELETE would leave: three cells gone and C still '
            'on the frames it was already on',
      );
    });

    /// ⚠️The other half, and why this is a split rather than a deletion: the
    /// PUSH is user-confirmed (T3 「현재 인덱스에 블록이 있으면 … 뒤를 민다」),
    /// so a REPLACE still closes its own gap.
    test('a replace still absorbs the difference — only a bare lift does not',
        () {
      final clip = captureTimelineRun(
        timeline: _row('PP'),
        index: 0,
        count: 2,
      );

      final row = spliceTimeline(
        timeline: _row('AABBBCC'),
        index: 2,
        liftCount: 3,
        clip: clip,
      );

      expect(
        _render(row, 7),
        'AAPPCC.',
        reason: 'three out, two in — the row shortens by one and C follows',
      );
    });

    // 🗣️F-235 (유저 2026-09-29): 「블록, 빈 공간에 붙여넣는건데 대체 왜 뒤가
    // 밀려나냐니까?」 · 「겹치는 공간이 전혀 없는 붙여넣기인데도 뒤가
    // 밀려나니까 하는소리임」.
    test('🚨F-235: a paste that fits in empty space moves nothing', () {
      final clip = captureTimelineRun(
        timeline: _row('PP'),
        index: 0,
        count: 2,
      );

      final row = spliceTimeline(
        timeline: _row('AA....BB'),
        index: 3,
        clip: clip,
      );

      expect(_render(row, 8), 'AA.PP.BB', reason: '↩️was AA.PP...BB');
    });

    test('🚨F-235: a paste longer than its empty space pushes only as far as '
        'it reaches — the next empty cells take the rest', () {
      final clip = captureTimelineRun(
        timeline: _row('PPPP'),
        index: 0,
        count: 4,
      );

      final row = spliceTimeline(
        timeline: _row('AA..BB..CC'),
        index: 2,
        clip: clip,
      );

      expect(
        _render(row, 12),
        'AAPPPPBBCC..',
        reason: 'B moved the two cells the clip overlapped; the gap after it '
            'took the rest, so C stayed — ↩️AAPPPP..BB..CC',
      );
    });

    test('F-235: a push carries on through the blocks that touch, and stops '
        'at the first empty cell that can take it', () {
      final clip = captureTimelineRun(
        timeline: _row('PPP'),
        index: 0,
        count: 3,
      );

      final row = spliceTimeline(
        timeline: _row('AA.BBCC...DD'),
        index: 2,
        clip: clip,
      );

      expect(
        _render(row, 12),
        'AAPPPBBCC.DD',
        reason: 'B took the push and passed it to C, which touched it; the '
            'empty cells after C took what was left, and D never moved',
      );
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
