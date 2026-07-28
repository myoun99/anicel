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

    test('start edge moves the start, end fixed, clamped by neighbors', () {
      final map = _map({2: pan, 12: fade});

      final moved = instructionMapWithEdgeShifted(
        map,
        spanStartIndex: 12,
        startEdge: true,
        delta: -6,
      )!;
      // Clamped at the previous span's end (2 + 6 = 8); end stays 16.
      expect(moved.containsKey(12), isFalse);
      expect(moved[8]!.length, 8);

      final shrunk = instructionMapWithEdgeShifted(
        map,
        spanStartIndex: 2,
        startEdge: true,
        delta: 99,
      )!;
      // Start cannot pass the last covered frame; length bottoms at 1.
      expect(shrunk[7]!.length, 1);

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
