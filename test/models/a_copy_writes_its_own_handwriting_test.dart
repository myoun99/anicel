import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/conte/conte_ink_keys.dart';
import 'package:anicel/src/models/exposure_memo.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/timeline_exposure.dart';

/// 🚨A COPIED BLOCK WRITES ON THE CONTE UNDER AN ID OF ITS OWN.
///
/// 유저 2026-09-26 (cut-duplicate-sheet-ink-Q1): 「복제는 전부 복사」 — a
/// copy starts with the same handwriting, and from there on they are apart.
/// Every copy path asks this one function, linked or not.
void main() {
  TimelineExposure block(String inkId, {String action = ''}) =>
      TimelineExposure.drawing(
        const FrameId('f'),
        length: 2,
        memo: ExposureMemo(inkId: inkId, actionMemo: action),
      );

  test('a block written on takes a new id and remembers whose handwriting '
      'it starts as; a block never written on is copied as it is', () {
    var minted = 0;
    final unwritten = block('', action: 'jump');
    final copy = conteHandwritingOfACopy({
      0: block('ink-a', action: 'run'),
      2: unwritten,
    }, () => 'new-${minted += 1}');

    expect(
      copy.exposures[0]!.memo,
      const ExposureMemo(actionMemo: 'run', inkId: 'new-1'),
    );
    expect(copy.exposures[2], same(unwritten));
    expect(copy.copies, {'new-1': 'ink-a'});
  });

  test('two blocks that wrote under ONE id come out as two — each block of '
      'the copy is its own', () {
    var minted = 0;
    final copy = conteHandwritingOfACopy({
      0: block('shared'),
      2: block('shared'),
    }, () => 'new-${minted += 1}');

    expect(copy.exposures[0]!.memo!.inkId, 'new-1');
    expect(copy.exposures[2]!.memo!.inkId, 'new-2');
    expect(copy.copies, {'new-1': 'shared', 'new-2': 'shared'});
  });

  test('nothing written, nothing minted', () {
    final copy = conteHandwritingOfACopy({
      0: const TimelineExposure.drawing(FrameId('f'), length: 2),
    }, () => fail('nothing to mint'));

    expect(copy.copies, isEmpty);
    expect(copy.exposures[0]!.memo, isNull);
  });
}
