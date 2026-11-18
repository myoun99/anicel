import 'dart:collection';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/camera_instruction.dart';
import 'package:anicel/src/ui/timeline/instruction_span_editing.dart';

SplayTreeMap<int, InstructionEvent> _map(Map<int, InstructionEvent> entries) {
  return SplayTreeMap.of(entries);
}

void main() {
  const pan = InstructionEvent(instructionId: 'pan', length: 6);
  const fade = InstructionEvent(instructionId: 'fi', length: 4);

  group('instructionSpanCovering', () {
    test('finds the covering span, misses gaps', () {
      final map = _map({2: pan, 12: fade});
      expect(instructionSpanCovering(map, 2)!.key, 2);
      expect(instructionSpanCovering(map, 7)!.key, 2);
      expect(instructionSpanCovering(map, 8), isNull);
      expect(instructionSpanCovering(map, 12)!.key, 12);
      expect(instructionSpanCovering(map, 16), isNull);
      expect(instructionSpanCovering(map, 0), isNull);
    });
  });

  group('instructionMapWithEdgeShifted', () {
    test('end edge resizes with min 1 and clamps at the next span', () {
      final map = _map({2: pan, 12: fade});

      final longer = instructionMapWithEdgeShifted(
        map,
        spanStartIndex: 2,
        startEdge: false,
        delta: 10,
      )!;
      // 2..8 grows toward 12 only.
      expect(longer[2]!.length, 10);

      final shorter = instructionMapWithEdgeShifted(
        map,
        spanStartIndex: 2,
        startEdge: false,
        delta: -20,
      )!;
      expect(shorter[2]!.length, 1);
    });

    // The start edge is a block's front edge, by the one rule (I-21 ·
    // I-179 — 「블록을 사용하는거라면 모든것에 법 통일적용」).
    test('start edge drawn out spends the gap, then the span in front gives '
        'frames down to one — its head held, the end fixed', () {
      final map = _map({2: pan, 12: fade});

      final moved = instructionMapWithEdgeShifted(
        map,
        spanStartIndex: 12,
        startEdge: true,
        delta: -6,
      )!;
      expect(moved, {2: pan.copyWith(length: 4), 6: fade.copyWith(length: 10)});

      final asFarAsItGoes = instructionMapWithEdgeShifted(
        map,
        spanStartIndex: 12,
        startEdge: true,
        delta: -99,
      )!;
      expect(asFarAsItGoes, {
        2: pan.copyWith(length: 1),
        3: fade.copyWith(length: 13),
      });
    });

    test('start edge pulled back holds one frame, then takes the span and '
        'sweeps on, the span glued in front following', () {
      final map = _map({2: pan, 12: fade});

      expect(
        instructionMapWithEdgeShifted(
          map,
          spanStartIndex: 2,
          startEdge: true,
          delta: 5,
        ),
        {7: pan.copyWith(length: 1), 12: fade},
      );
      expect(
        instructionMapWithEdgeShifted(
          map,
          spanStartIndex: 2,
          startEdge: true,
          delta: 6,
        ),
        {12: fade},
        reason: 'past its last frame the span is gone',
      );
      expect(
        instructionMapWithEdgeShifted(
          map,
          spanStartIndex: 2,
          startEdge: true,
          delta: 99,
        ),
        isEmpty,
        reason: 'as far as the row\'s last frame, every span it passes',
      );

      final glued = _map({0: fade, 4: fade, 8: fade});
      expect(
        instructionMapWithEdgeShifted(
          glued,
          spanStartIndex: 4,
          startEdge: true,
          delta: 6,
        ),
        {0: fade.copyWith(length: 10), 10: fade.copyWith(length: 2)},
      );
    });

    test('start edge grows to frame 0 and no further', () {
      final clampedAtZero = instructionMapWithEdgeShifted(
        _map({2: pan}),
        spanStartIndex: 2,
        startEdge: true,
        delta: -5,
      )!;
      expect(clampedAtZero[0]!.length, 8);
    });

    test('returns null when nothing changes', () {
      final map = _map({2: pan});
      expect(
        instructionMapWithEdgeShifted(
          map,
          spanStartIndex: 2,
          startEdge: false,
          delta: 0,
        ),
        isNull,
      );
      expect(
        instructionMapWithEdgeShifted(
          map,
          spanStartIndex: 99,
          startEdge: false,
          delta: 1,
        ),
        isNull,
      );
    });
  });

  group('instructionMapWithEventAdded / Replaced / Removed', () {
    test('add clamps at the next span and refuses covered cells', () {
      final map = _map({6: fade});

      final added = instructionMapWithEventAdded(
        map,
        startIndex: 2,
        event: const InstructionEvent(instructionId: 'pan', length: 99),
      )!;
      expect(added[2]!.length, 4);

      expect(
        instructionMapWithEventAdded(map, startIndex: 7, event: pan),
        isNull,
      );
    });

    test('replace keeps start and length, remove deletes', () {
      final map = _map({2: pan});

      final replaced = instructionMapWithEventReplaced(
        map,
        spanStartIndex: 2,
        event: const InstructionEvent(
          instructionId: 'fo',
          length: 99,
          valueA: 'A',
        ),
      )!;
      expect(replaced[2]!.instructionId, 'fo');
      expect(replaced[2]!.length, 6, reason: 'length is grip-owned');
      expect(replaced[2]!.valueA, 'A');

      expect(instructionMapWithEventRemoved(map, spanStartIndex: 2), isEmpty);
      expect(instructionMapWithEventRemoved(map, spanStartIndex: 5), isNull);
    });
  });
}
