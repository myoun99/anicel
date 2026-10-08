import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/cut_metadata.dart';
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

    test('🗣️the colour label is part of the value — metadata differing only '
        'in its label is different metadata (유저 2026-09-26: 컷별 색라벨)', () {
      const art = LayerMark(process: LayerProcess.art);
      const labelled = CutMetadata(mark: art);

      expect(labelled, isNot(const CutMetadata()));
      expect(labelled, const CutMetadata(mark: art));
      expect(labelled.hashCode, const CutMetadata(mark: art).hashCode);
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
