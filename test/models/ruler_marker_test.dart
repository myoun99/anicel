import 'package:anicel/src/models/block_run_move.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/cut_metadata.dart';
import 'package:anicel/src/models/project_timeline.dart';
import 'package:anicel/src/models/ruler_marker.dart';
import 'package:anicel/src/models/timeline_id.dart';
import 'package:flutter_test/flutter_test.dart';

/// 🗣️I-169 (유저 2026-11-12): 「타임라인 룰러에 북마크? 메모 넣는기능」, and of
/// what was drawn for it (2026-11-13): 「마커로 명명할건데, 마커끼리 겹치는건
/// 불가능하고 어떻게 움직일지는 프레임블록 규칙이랑 동일하게」 (Q1) · 「컷(로컬)
/// 이랑 콘티(글로벌)이랑 마커 독립적으로」 (Q2) · 「구간도」 (Q3) · 「여러 색」
/// (Q4).
void main() {
  RulerMarker at(int start, [int length = 1, String text = '']) =>
      RulerMarker(start: start, length: length, text: text);

  List<(int, int)> placesOf(RulerMarkers markers) => [
    for (final marker in markers.inOrder) (marker.start, marker.length),
  ];

  group('a marker', () {
    test('stands on its ruler, over a frame at least', () {
      const marker = RulerMarker(start: -3, length: 0);
      expect((marker.start, marker.length), (0, 1));
      expect(marker.color, RulerMarkerColor.yellow, reason: 'a new one');
      expect(marker.text, isEmpty);
    });

    test('covers its frames and none beside them', () {
      final span = at(4, 3);
      expect([for (var frame = 3; frame < 8; frame += 1) span.covers(frame)], [
        false,
        true,
        true,
        true,
        false,
      ]);
      expect(span.endExclusive, 7);
    });

    test('says in a file only what a new one would not', () {
      expect(at(5).toJson(), {'start': 5});
      const full = RulerMarker(
        start: 5,
        length: 4,
        text: '口パク',
        color: RulerMarkerColor.sky,
      );
      expect(full.toJson(), {
        'start': 5,
        'length': 4,
        'text': '口パク',
        'color': 'sky',
      });
      expect(RulerMarker.fromJson(full.toJson()), full);
      expect(RulerMarker.fromJson(at(5).toJson()), at(5));
      expect(full, isNot(full.copyWith(color: RulerMarkerColor.pink)));
      expect(full.hashCode, full.copyWith().hashCode);
    });

    test('there are the six colours the question named, yellow first', () {
      expect([for (final color in RulerMarkerColor.values) color.name], [
        'yellow',
        'orange',
        'pink',
        'sky',
        'violet',
        'white',
      ]);
      expect(RulerMarkerColor.named('violet'), RulerMarkerColor.violet);
      expect(RulerMarkerColor.named('red'), RulerMarkerColor.yellow);
      expect(RulerMarkerColor.named(null), RulerMarkerColor.yellow);
    });
  });

  group('the markers of a ruler', () {
    test('🚨are in frame order and none stands over another — one that '
        'starts under another is laid just past it, and the next gives way '
        'in turn', () {
      final settled = RulerMarkers.settled([
        at(10, 2),
        at(2, 4, 'a'),
        at(4, 3, 'b'),
        at(7, 1, 'c'),
        at(20),
      ]);
      expect(placesOf(settled), [(2, 4), (6, 3), (9, 1), (10, 2), (20, 1)]);
      expect([for (final marker in settled.inOrder) marker.text], [
        'a',
        'b',
        'c',
        '',
        '',
      ]);
    });

    test('markers that start on one frame keep the order they came in', () {
      final settled = RulerMarkers.settled([
        at(3, 1, 'first'),
        at(3, 1, 'second'),
      ]);
      expect(
        [for (final marker in settled.inOrder) (marker.start, marker.text)],
        [(3, 'first'), (4, 'second')],
      );
    });

    test('the list it hands out cannot be written to', () {
      final markers = RulerMarkers.settled([at(1)]);
      expect(() => markers.inOrder.add(at(1)), throwsUnsupportedError);
      expect(
        () => const RulerMarkers.none().inOrder.add(at(1)),
        throwsUnsupportedError,
      );
    });

    test('says which marker stands over a frame', () {
      final markers = RulerMarkers.settled([at(2, 3), at(8)]);
      expect([for (final frame in [1, 2, 4, 5, 8, 9]) markers.indexAt(frame)], [
        null,
        0,
        0,
        null,
        1,
        null,
      ]);
      expect(const RulerMarkers.none().indexAt(0), isNull);
      expect(const RulerMarkers.none().isEmpty, isTrue);
      expect(markers.isEmpty, isFalse);
    });

    test('takes one more where it is put', () {
      final markers = RulerMarkers.settled([at(2), at(8)]).withMarker(at(5, 2));
      expect(placesOf(markers), [(2, 1), (5, 2), (8, 1)]);
    });

    test('🚨a span made longer pushes what follows, as a block made longer '
        'does — the empty frames between take the push first', () {
      final markers = RulerMarkers.settled([at(2), at(4), at(9), at(20)]);
      final longer = markers.withMarker(at(2, 6), replacing: 0);
      expect(
        placesOf(longer),
        [(2, 6), (8, 1), (9, 1), (20, 1)],
        reason: 'the second gives way, the third is not reached',
      );
      expect(
        placesOf(markers.withMarker(at(2, 8), replacing: 0)),
        [(2, 8), (10, 1), (11, 1), (20, 1)],
      );
      expect(
        placesOf(longer.withMarker(at(2, 1), replacing: 0)),
        [(2, 1), (8, 1), (9, 1), (20, 1)],
        reason: 'made short again, nothing comes back by itself',
      );
    });

    test('lets one go and leaves the rest where they stand', () {
      final markers = RulerMarkers.settled([at(2, 3), at(8), at(12)]);
      expect(placesOf(markers.without(1)), [(2, 3), (12, 1)]);
      expect(markers.without(0).without(0).without(0).isEmpty, isTrue);
    });

    test('is its markers: two sets of the same are one value', () {
      final one = RulerMarkers.settled([at(2, 3, 'x'), at(8)]);
      final same = RulerMarkers.settled([at(8), at(2, 3, 'x')]);
      expect(one, same);
      expect(one.hashCode, same.hashCode);
      expect(one, isNot(one.without(1)));
      expect(const RulerMarkers.none(), RulerMarkers.settled(const []));
    });

    test('🚨a file cannot say two over one frame either', () {
      final read = RulerMarkers.fromJson([
        {'start': 4, 'length': 3},
        {'start': 5, 'text': 'under the first'},
      ]);
      expect(placesOf(read), [(4, 3), (7, 1)]);
      expect(RulerMarkers.fromJson(read.toJson()), read);
      expect(RulerMarkers.fromJson(null), const RulerMarkers.none());
      expect(RulerMarkers.fromJson(const <Object>[]).isEmpty, isTrue);
      expect(const RulerMarkers.none().toJson(), isEmpty);
    });
  });

  group('🚨a marker dragged moves as a frame block does', () {
    final markers = RulerMarkers.settled([
      at(2, 2, 'a'),
      at(6, 3, 'b'),
      at(12, 1, 'c'),
    ]);

    test('it slides through the empty frames and stops where it touches a '
        'neighbour', () {
      expect(placesOf(markers.moved(1, -1)), [(2, 2), (5, 3), (12, 1)]);
      expect(
        placesOf(markers.moved(1, -2)),
        [(2, 2), (4, 3), (12, 1)],
        reason: 'against the first — no further, and nothing pushed',
      );
      expect(placesOf(markers.moved(1, 3)), [(2, 2), (9, 3), (12, 1)]);
    });

    test('it trades places with a neighbour once its far edge has cleared '
        'that neighbour\'s — the blocks\' seat — and with the next one past '
        'it', () {
      List<String> order(int delta) => [
        for (final marker in markers.moved(0, delta).inOrder) marker.text,
      ];
      expect(order(4), ['a', 'b', 'c'], reason: 'a frame short of the seat');
      expect(order(5), ['b', 'a', 'c']);
      expect(order(9), ['b', 'c', 'a']);
      for (final delta in [4, 5, 9]) {
        final traded = markers.moved(0, delta);
        for (final (index, marker) in traded.inOrder.indexed.skip(1)) {
          expect(
            marker.start,
            greaterThanOrEqualTo(traded.inOrder[index - 1].endExclusive),
            reason: 'none over another, whatever the drag',
          );
        }
      }
    });

    test('the ruler starts at frame 0 and has no end', () {
      expect(markers.moved(0, -50).inOrder.first.start, 0);
      expect(markers.moved(2, 500).inOrder.last.start, 512);
    });

    test('by the very plan the blocks move by, at every step of a drag', () {
      final lengths = [for (final marker in markers.inOrder) marker.length];
      final slots = [
        for (final (slot, gap) in leadingGapsOf(
          starts: [for (final marker in markers.inOrder) marker.start],
          lengths: lengths,
        ).indexed)
          (leadingGap: gap, length: lengths[slot]),
      ];
      for (var index = 0; index < 3; index += 1) {
        for (var delta = -16; delta <= 16; delta += 1) {
          final plan = planBlockRunMove(
            slots: slots,
            runStart: index,
            runEnd: index,
            frameDelta: delta,
          );
          final moved = markers.moved(index, delta);
          expect(
            [for (final marker in moved.inOrder) (marker.text, marker.start)],
            [
              for (final (position, slot) in plan.order.indexed)
                (markers.inOrder[slot].text, plan.starts[position]),
            ],
            reason: 'marker $index by $delta',
          );
        }
      }
    });

    test('a drag that goes nowhere leaves the very same set', () {
      expect(markers.moved(1, 0), markers);
    });
  });

  group('who holds them', () {
    test('a cut holds its own: written only where there is one, read back, '
        'and part of what the cut is', () {
      const none = CutMetadata.empty();
      expect(none.rulerMarkers.isEmpty, isTrue);
      expect(none.toJson().containsKey('rulerMarkers'), isFalse);
      expect(const CutMetadata().rulerMarkers.isEmpty, isTrue);

      final markers = RulerMarkers.settled([at(3, 2, 'セリフ')]);
      final held = none.copyWith(rulerMarkers: markers);
      expect(held.rulerMarkers, markers);
      expect(held, isNot(none));
      expect(held.hashCode, isNot(none.hashCode));
      expect(held.copyWith(scene: '3').rulerMarkers, markers);
      expect(CutMetadata.fromJson(held.toJson()), held);
      expect('$held', contains('rulerMarkers'));
    });

    test('a timeline holds its own — and keeps them when it is named', () {
      final timeline = ProjectTimeline(
        id: const TimelineId('t'),
        number: 1,
        tracks: const [],
      );
      expect(timeline.rulerMarkers.isEmpty, isTrue);
      expect(timeline.toJson().containsKey('rulerMarkers'), isFalse);

      final markers = RulerMarkers.settled([at(40, 12, 'A パート')]);
      final held = timeline.copyWith(rulerMarkers: markers);
      expect(held.rulerMarkers, markers);
      expect(held, isNot(timeline));
      expect(held.hashCode, isNot(timeline.hashCode));
      expect(held.named('本編').rulerMarkers, markers);
      expect(held.copyWith(trailingFrames: 5).rulerMarkers, markers);
      expect(ProjectTimeline.fromJson(held.toJson()), held);
    });

    test('a holder is a cut or the open timeline, and nothing else', () {
      const cut = RulerMarkerHolder.cut(CutId('c'));
      expect(cut, const RulerMarkerHolder.cut(CutId('c')));
      expect(cut.hashCode, const RulerMarkerHolder.cut(CutId('c')).hashCode);
      expect(cut, isNot(const RulerMarkerHolder.cut(CutId('d'))));
      expect(cut, isNot(const RulerMarkerHolder.timeline()));
      expect(
        const RulerMarkerHolder.timeline(),
        const RulerMarkerHolder.timeline(),
      );
    });
  });
}
