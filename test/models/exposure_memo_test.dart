import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/exposure_memo.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/timeline_exposure.dart';

/// The memo belongs to the exposure BLOCK, not to the drawing. That is what
/// makes two exposures of the same cel carry two memos, and it is what lets
/// every move and copy carry the memo without any code knowing about it.
void main() {
  const memo = ExposureMemo(actionMemo: 'Girl looks up', note: 'BG reuse');

  group('ExposureMemo', () {
    test('an empty memo is what "no memo" means', () {
      expect(const ExposureMemo.empty().isEmpty, isTrue);
      expect(const ExposureMemo(note: 'x').isEmpty, isFalse);
      expect(const ExposureMemo(actionMemo: 'x').isEmpty, isFalse);
    });

    test('round-trips through JSON', () {
      expect(ExposureMemo.fromJson(memo.toJson()), memo);
    });

    test('an empty memo writes nothing', () {
      expect(const ExposureMemo.empty().toJson(), isEmpty);
    });
  });

  group('TimelineExposure.memo', () {
    final block = TimelineExposure.drawing(
      const FrameId('frame-a'),
      length: 4,
      memo: memo,
    );

    test('rides copyWith untouched, the way breakdown offsets do', () {
      expect(block.copyWith(length: 9).memo, memo);
      expect(
        block.copyWith(frameId: const FrameId('frame-b')).memo,
        memo,
      );
    });

    test('can be replaced or cleared explicitly', () {
      expect(
        block.copyWith(memo: () => const ExposureMemo(note: 'other')).memo,
        const ExposureMemo(note: 'other'),
      );
      expect(block.copyWith(memo: () => null).memo, isNull);
    });

    test('round-trips through JSON', () {
      final decoded = TimelineExposure.fromJson(block.toJson());

      expect(decoded.memo, memo);
      expect(decoded, block);
    });

    test('a block without a memo writes no memo key', () {
      final plain = TimelineExposure.drawing(
        const FrameId('frame-a'),
        length: 2,
      );

      expect(plain.toJson().containsKey('memo'), isFalse);
      expect(TimelineExposure.fromJson(plain.toJson()).memo, isNull);
    });

    test('two exposures of the SAME drawing hold their own memos', () {
      final first = TimelineExposure.drawing(
        const FrameId('shared'),
        length: 2,
        memo: const ExposureMemo(actionMemo: 'first time'),
      );
      final second = TimelineExposure.drawing(
        const FrameId('shared'),
        length: 2,
        memo: const ExposureMemo(actionMemo: 'and again, differently'),
      );

      expect(first.frameId, second.frameId);
      expect(first.memo, isNot(second.memo));
    });

    test('the memo takes part in equality', () {
      final plain = TimelineExposure.drawing(
        const FrameId('frame-a'),
        length: 4,
      );

      expect(block == plain, isFalse);
      expect(block.copyWith(memo: () => null), plain);
    });

    test('a memo survives the LAYER round trip — the exposure decoder is '
        'not the one project.json goes through', () {
      final layer = Layer(
        id: const LayerId('A'),
        name: 'A',
        frames: [
          Frame(id: const FrameId('a1'), duration: 1, strokes: const []),
        ],
        timeline: {
          0: TimelineExposure.drawing(
            const FrameId('a1'),
            length: 3,
            memo: memo,
          ),
        },
      );

      final restored = Layer.fromJson(layer.toJson());
      expect(
        restored.timeline[0]!.memo,
        memo,
        reason: 'the memo is written into project.json — a decoder that '
            'skips the key loses everything the user typed on reopen',
      );
      expect(restored, layer);
    });
  });
}
