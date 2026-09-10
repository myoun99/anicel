import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/reorder_target.dart';

/// 유저 2026-09-10: 「규칙 다른거있으면 다 통일해서 법 하나로 만들어서 다른부분도
/// 문제없나 감사한번해줘」. The audit found three implementations of this
/// arithmetic — the track rail's (correct, with the sentence in a comment),
/// the brush grid's (correct, spelled out inline) and the brush group rail's
/// (wrong). This file is the law they all read now.
void main() {
  group('a slot becomes a target', () {
    test('landing BELOW yourself loses the place you vacated', () {
      // [A, B, C], A dragged to the gap after C: slot 3, and once A is
      // lifted out that gap is index 2 of [B, C].
      expect(reorderTargetForSlot(slot: 3, movedIndex: 0), 2);
    });

    test('landing ABOVE yourself does not', () {
      // [A, B, C], C dragged to the gap before A: slot 0, and [A, B] still
      // has A and B below it — nothing was vacated above.
      expect(reorderTargetForSlot(slot: 0, movedIndex: 2), 0);
    });

    test('the gap you are already in is your own place', () {
      expect(reorderTargetForSlot(slot: 1, movedIndex: 1), 1);
    });
  });

  group('a target becomes an anchor', () {
    final abc = <String>['a', 'b', 'c'];

    test('🐛the LAST target is an append, which is the move 유저 could not '
        'make', () {
      // [a, b, c] without a = [b, c]; target 2 is past its end.
      expect(reorderAnchorAt(abc, movedIndex: 0, target: 2), isNull);
    });

    test('a target below the moved entry skips the hole it left', () {
      // ⛔THE DEFECT, EXACTLY: read against [a, b, c] target 1 is 'b', and
      // inserting a before b puts it back where it started. Read against
      // [b, c] it is 'c', which is the slot the pointer was over.
      expect(reorderAnchorAt(abc, movedIndex: 0, target: 1), 'c');
    });

    test('a target above the moved entry needs no adjustment', () {
      expect(reorderAnchorAt(abc, movedIndex: 2, target: 0), 'a');
      expect(reorderAnchorAt(abc, movedIndex: 2, target: 1), 'b');
    });

    test('the first target is the head', () {
      expect(reorderAnchorAt(abc, movedIndex: 1, target: 0), 'a');
    });

    test('a target off either end clamps to that end', () {
      // A pointer can leave the list, and the ends are where it means to be.
      expect(reorderAnchorAt(abc, movedIndex: 1, target: -5), 'a');
      expect(reorderAnchorAt(abc, movedIndex: 1, target: 99), isNull);
    });

    test('a moved index that is not in the list anchors nothing', () {
      expect(reorderAnchorAt(abc, movedIndex: 9, target: 0), isNull);
      expect(reorderAnchorAt(<String>[], movedIndex: 0, target: 0), isNull);
    });

    test('⛔the list is not mutated — it is the caller\'s', () {
      final original = <String>['a', 'b', 'c'];
      reorderAnchorAt(original, movedIndex: 0, target: 2);
      expect(original, <String>['a', 'b', 'c']);
    });

    test('🚨every target lands somewhere different — the law is a bijection',
        () {
      // The property the off-by-one broke: with N entries there are N
      // landings, and two targets that produce the same anchor mean one
      // position is unreachable. That is what 「맨 밑」 was.
      final anchors = [
        for (var target = 0; target < abc.length; target += 1)
          reorderAnchorAt(abc, movedIndex: 0, target: target),
      ];
      expect(anchors, <String?>['b', 'c', null]);
      expect(anchors.toSet().length, anchors.length);
    });
  });
}
