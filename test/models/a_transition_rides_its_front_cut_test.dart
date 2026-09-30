import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/camera_instruction.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/models/track_transitions.dart';

/// 🗣️유저 2026-08-10: 「그냥 글로벌로 두고 행동은 해당 범위의 양 컷을
/// ol시키는거. 움직일때만 앵커로서 앞 컷에 앵커. 앞 컷이 없으면 현재 컷에
/// 앵커.」
///
/// Three 24-frame cuts z, a, b — frames 0..23, 24..47, 48..71 — and an
/// O.L over 42..53: six frames before the a|b boundary, six after.
void main() {
  Cut cut(String id, {int duration = 24, int gap = 0}) => Cut(
    id: CutId(id),
    name: id,
    duration: duration,
    leadingGapFrames: gap,
    canvasSize: const CanvasSize(width: 64, height: 36),
    layers: const [],
  );

  Track track(List<Cut> cuts, {Map<int, InstructionEvent>? spans}) {
    final bare = Track(id: const TrackId('t'), name: 'T', cuts: cuts);
    return bare.copyWith(
      transitionLayer: bare.transitionLayer.copyWith(
        instructions:
            spans ??
            {42: const InstructionEvent(instructionId: 'ol', length: 12)},
      ),
    );
  }

  /// Where the O.L starts once the cuts go from [before] to [after].
  int olStartAfter(Track before, List<Cut> after) {
    final carried = transitionRowFollowingItsCuts(
      before: before,
      after: before.copyWith(cuts: after),
    );
    return carried.instructions.keys.single;
  }

  test('a cut before it shortened: the cut it starts in moves back, and the '
      'O.L with it', () {
    final before = track([cut('z'), cut('a'), cut('b')]);
    expect(olStartAfter(before, [cut('z', duration: 20), cut('a'), cut('b')]), 38);
  });

  test('its front cut moved to the end: the O.L goes with it', () {
    final before = track([cut('z'), cut('a'), cut('b')]);
    expect(olStartAfter(before, [cut('z'), cut('b'), cut('a')]), 42 + 24);
  });

  test('its front cut\'s own end trimmed: the cut did not move, so neither '
      'does the O.L (F-227-ol-trim-Q1 asks whether it should)', () {
    final before = track([cut('z'), cut('a'), cut('b')]);
    expect(olStartAfter(before, [cut('z'), cut('a', duration: 20), cut('b')]), 42);
  });

  test('its front cut gone: the next cut it reaches takes it', () {
    final before = track([cut('z'), cut('a'), cut('b')]);
    // b closed up onto z: it moved back 24, and so does the O.L.
    expect(olStartAfter(before, [cut('z'), cut('b')]), 42 - 24);
  });

  test('a span that starts in a gap rides the cut it reaches', () {
    final before = track(
      [cut('z'), cut('a', gap: 10)],
      spans: {30: const InstructionEvent(instructionId: 'ol', length: 10)},
    );
    expect(olStartAfter(before, [cut('z'), cut('a', gap: 15)]), 35);
  });

  test('a span carried before frame 0 keeps its end and starts at 0', () {
    final before = track(
      [cut('a', gap: 10)],
      spans: {4: const InstructionEvent(instructionId: 'ol', length: 10)},
    );
    final carried = transitionRowFollowingItsCuts(
      before: before,
      after: before.copyWith(cuts: [cut('a')]),
    );
    expect(carried.instructions.keys.single, 0);
    expect(carried.instructions[0]!.length, 4, reason: '14 - 10');
  });

  test('nothing moved: the row is the same instance', () {
    final before = track([cut('z'), cut('a'), cut('b')]);
    final after = before.copyWith(
      cuts: [cut('z'), cut('a'), cut('b', duration: 30)],
    );
    expect(
      identical(
        transitionRowFollowingItsCuts(before: before, after: after),
        after.transitionLayer,
      ),
      isTrue,
    );
  });
}
