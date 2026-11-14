import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/conte/conte_camera_room.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/cut_metadata.dart';
import 'package:anicel/src/models/sheet_memo_side.dart';
import 'package:anicel/src/models/layer_mark.dart';
import 'package:anicel/src/models/layer_process.dart';
import 'package:anicel/src/models/layer_section_defaults.dart';

void main() {
  group('CutMetadata', () {
    test('empty metadata has no memo on any page', () {
      const metadata = CutMetadata.empty();

      expect(metadata.pageNotes, isEmpty);
      expect(metadata.noteOf(0), '');
      expect(metadata.noteOf(3), '');
    });

    // 🗣️F-301 (유저 2026-10-05): 「타임시트의 메모란은 페이지별로 다름 …
    // 페이지별로 독립」.
    test('🚨a memo is its page\'s: writing one page leaves the others as they '
        'are, and a later page can be written before an earlier one', () {
      final second = const CutMetadata.empty().withPageNote(1, 'Two');
      expect(second.noteOf(0), '', reason: 'the first page is not written');
      expect(second.noteOf(1), 'Two');

      final both = second.withPageNote(0, 'One');
      expect(both.pageNotes, ['One', 'Two']);

      expect(
        both.withPageNote(1, '').pageNotes,
        ['One'],
        reason: 'a blank last page is no memo — the same value as never '
            'written',
      );
    });

    // 🗣️F-542 (유저 2026-11-02): 「타임시트 메모란, 텍스트 공간 왼쪽 오른쪽
    // 두개로 나누자」 · Q1: 「둘 다 동일한 메모」.
    test('🚨each side of a page has a memo of its own, by the one law', () {
      const right = SheetMemoSide.right;
      final written = const CutMetadata.empty()
          .withPageNote(1, 'Left')
          .withPageNote(1, 'Right', side: right);
      expect(written.noteOf(1), 'Left');
      expect(written.noteOf(1, side: SheetMemoSide.left), 'Left');
      expect(written.noteOf(1, side: right), 'Right');
      expect(written.noteOf(0, side: right), '');
      expect(written.noteOf(-1, side: right), '');
      expect(written.noteOf(2, side: right), '');
      expect(written.pageNotes, ['', 'Left']);
      expect(written.rightPageNotes, ['', 'Right']);

      expect(
        written.withPageNote(1, '', side: right).rightPageNotes,
        isEmpty,
        reason: 'a blank last page is no memo, on the right as on the left',
      );
      expect(written.withPageNote(1, '', side: right).noteOf(1), 'Left');

      final saved = written.toJson();
      expect(saved['rightPageNotes'], ['', 'Right']);
      expect(CutMetadata.fromJson(saved), written);
      expect(
        const CutMetadata.empty().toJson(),
        isNot(contains('rightPageNotes')),
      );

      const one = CutMetadata(rightPageNotes: ['a']);
      expect(one, const CutMetadata(rightPageNotes: ['a']));
      expect(one.hashCode, const CutMetadata(rightPageNotes: ['a']).hashCode);
      expect(one, isNot(const CutMetadata(rightPageNotes: ['b'])));
      expect(one, isNot(const CutMetadata(pageNotes: ['a'])));
      expect(one.copyWith(pageNotes: const ['b']).rightPageNotes, ['a']);
      expect(one.toString(), contains('rightPageNotes: [a]'));
      expect(const CutMetadata.empty().rightPageNotes, isEmpty);
    });

    test('🗣️the colour label is part of the value — metadata differing only '
        'in its label is different metadata (유저 2026-09-26: 컷별 색라벨)', () {
      const key = LayerMark(process: LayerProcess.key);
      const labelled = CutMetadata(mark: key);

      expect(labelled, isNot(const CutMetadata()));
      expect(labelled, const CutMetadata(mark: key));
      expect(labelled.hashCode, const CutMetadata(mark: key).hashCode);
    });

    test('value equality uses the page memos', () {
      const metadata = CutMetadata(pageNotes: ['Check expression.']);
      const sameMetadata = CutMetadata(pageNotes: ['Check expression.']);
      const differentMetadata = CutMetadata(pageNotes: ['FX-heavy cut.']);

      expect(metadata, sameMetadata);
      expect(metadata.hashCode, sameMetadata.hashCode);
      expect(metadata, isNot(differentMetadata));
    });

    test('withPageNote changes that page\'s memo only', () {
      const metadata = CutMetadata(pageNotes: ['Original note']);

      expect(
        metadata.withPageNote(0, 'Updated note'),
        const CutMetadata(pageNotes: ['Updated note']),
      );
    });

    test('toJson writes the page memos, and nothing when there are none', () {
      const metadata = CutMetadata(pageNotes: ['General', '', 'Third']);

      expect(metadata.toJson(), {
        'pageNotes': ['General', '', 'Third'],
      });
      expect(const CutMetadata.empty().toJson(), isEmpty);
    });

    test('fromJson reads the page memos', () {
      final metadata = CutMetadata.fromJson({
        'pageNotes': ['General', '', 'Third'],
      });

      expect(
        metadata,
        const CutMetadata(pageNotes: ['General', '', 'Third']),
      );
    });

    // The save law (유저 2026-10-06): an older shape is not read — the
    // archive refuses its format by number (v11).
    test('fromJson reads no one-per-cut note', () {
      expect(
        CutMetadata.fromJson({'note': 'General'}),
        const CutMetadata.empty(),
      );
    });

    test('fromJson defaults missing memos to empty metadata', () {
      final metadata = CutMetadata.fromJson({
        'actionMemo': 'Old action.',
        'dialogueMemo': 'A: Wait!',
      });

      expect(metadata, const CutMetadata.empty());
    });

    test('I-82: a cut takes the format\'s camera room until it keeps one of '
        'its own — written only then, and given back by null', () {
      expect(const CutMetadata.empty().conteCameraRoom, isNull);
      expect(
        const CutMetadata.empty().toJson().containsKey('conteCameraRoom'),
        isFalse,
      );
      for (final room in ConteCameraRoom.values) {
        final own = const CutMetadata.empty().copyWith(conteCameraRoom: room);
        expect(CutMetadata.fromJson(own.toJson()), own, reason: '$room');
        expect(own, isNot(const CutMetadata.empty()), reason: '$room');
        expect(
          own.copyWith(scene: 'S1').conteCameraRoom,
          room,
          reason: 'another change keeps it',
        );
        expect(
          own.copyWith(conteCameraRoom: null),
          const CutMetadata.empty(),
          reason: 'null gives it back to the format',
        );
      }
      expect(
        CutMetadata.fromJson(const {'conteCameraRoom': 'unknown'})
            .conteCameraRoom,
        isNull,
      );
    });
  });

  group('Cut metadata', () {
    test('defaults to empty metadata', () {
      final cut = _cut();

      expect(cut.metadata, const CutMetadata.empty());
    });

    test('copyWith updates metadata and preserves other fields', () {
      final cut = _cut();
      const metadata = CutMetadata(pageNotes: ['FX-heavy cut.']);

      final updatedCut = cut.copyWith(metadata: metadata);

      expect(updatedCut.metadata, metadata);
      expect(updatedCut.id, cut.id);
      expect(updatedCut.name, cut.name);
      expect(updatedCut.layers, cut.layers);
      expect(updatedCut.duration, cut.duration);
      expect(updatedCut.canvasSize, cut.canvasSize);
    });

    test('round-trips non-empty metadata through JSON', () {
      final cut = _cut().copyWith(
        metadata: const CutMetadata(pageNotes: ['FX-heavy cut.']),
      );

      final restoredCut = Cut.fromJson(cut.toJson());

      // Loading backfills the SE/instruction fixture rows.
      expect(
        restoredCut,
        cut.copyWith(layers: withEnsuredSectionLayers(cut.id, cut.layers)),
      );
      expect(restoredCut.metadata, cut.metadata);
    });

    test('fromJson defaults missing metadata to empty metadata', () {
      final json = _cut().toJson()..remove('metadata');

      final restoredCut = Cut.fromJson(json);

      expect(restoredCut.metadata, const CutMetadata.empty());
    });

    test('equality includes metadata', () {
      final cut = _cut();
      final cutWithMetadata = cut.copyWith(
        metadata: const CutMetadata(pageNotes: ['Camera shakes after impact.']),
      );

      expect(cutWithMetadata, isNot(cut));
      expect(
        cutWithMetadata,
        _cut().copyWith(
          metadata: const CutMetadata(pageNotes: ['Camera shakes after impact.']),
        ),
      );
    });
  });
}

Cut _cut() {
  return Cut(
    id: const CutId('cut-1'),
    name: 'Cut 1',
    layers: const [],
    duration: 24,
    canvasSize: const CanvasSize(width: 1920, height: 1080),
  );
}
