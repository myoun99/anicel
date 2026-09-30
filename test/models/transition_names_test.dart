import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/camera_instruction.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/storyboard_timeline_layout.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/models/transition_names.dart';

/// 🗣️F-229 (유저 2026-09-29): 「OL의 경우 시작이름은 대상인 이전컷, 끝이름은
/// 대상의 다음컷임. 다만 301 이렇게 표기하면 컷인지 모르니 컷이름앞에 c를
/// 붙여서 c301 이렇게되도록. 이름부분은 그냥 컷O.L.」.
void main() {
  Cut cut(String name, {int gap = 0}) => Cut(
    id: CutId(name),
    name: name,
    duration: 24,
    leadingGapFrames: gap,
    canvasSize: const CanvasSize(width: 64, height: 36),
    layers: const [],
  );

  /// Two 24-frame cuts 301 and 302 (a [gap] before 302), and the spans.
  Layer named(Map<int, InstructionEvent> spans, {int gap = 0}) {
    final track = Track(
      id: const TrackId('t'),
      name: 'T',
      cuts: [cut('301'), cut('302', gap: gap)],
    );
    return transitionRowNamedByItsCuts(
      row: track.transitionLayer.copyWith(instructions: spans),
      cuts: cutSpansOf(track),
      defById: CameraInstructionSet.standard.defById,
      olWord: '컷O.L.',
    );
  }

  test('an O.L starts at the cut it leaves and ends at the cut it enters — '
      'each a c before its name — and is named 컷O.L.', () {
    final event = named({
      18: const InstructionEvent(instructionId: 'ol', length: 12),
    }).instructions[18]!;
    expect(event.valueA, 'c301');
    expect(event.valueB, 'c302');
    expect(event.text, '컷O.L.');
  });

  test('an O.L into a gap has no cut to end at; one out of a gap none to '
      'start at', () {
    final into = named(
      {18: const InstructionEvent(instructionId: 'ol', length: 12)},
      gap: 20,
    ).instructions[18]!;
    expect(into.valueA, 'c301');
    expect(into.valueB, isNull, reason: 'the gap is its partner');

    final outOf = named(
      {38: const InstructionEvent(instructionId: 'ol', length: 12)},
      gap: 20,
    ).instructions[38]!;
    expect(outOf.valueA, isNull);
    expect(outOf.valueB, 'c302');
  });

  test('what was typed into a transition is not its writing: a fade keeps '
      'its memo and goes by its term', () {
    final event = named({
      2: const InstructionEvent(
        instructionId: 'fo',
        length: 4,
        text: 'typed',
        valueA: 'A',
        valueB: 'B',
        memo: 'slow',
      ),
    }).instructions[2]!;
    expect(event.text, isNull);
    expect(event.valueA, isNull);
    expect(event.valueB, isNull);
    expect(event.memo, 'slow');
    expect(
      event.displayLabel(CameraInstructionSet.standard.defById('fo')),
      'FO',
    );
  });

  test('a row already written this way comes back as itself', () {
    final once = named({
      18: const InstructionEvent(instructionId: 'ol', length: 12),
    });
    final track = Track(
      id: const TrackId('t'),
      name: 'T',
      cuts: [cut('301'), cut('302')],
    );
    expect(
      identical(
        transitionRowNamedByItsCuts(
          row: once,
          cuts: cutSpansOf(track),
          defById: CameraInstructionSet.standard.defById,
          olWord: '컷O.L.',
        ),
        once,
      ),
      isTrue,
    );
  });
}
