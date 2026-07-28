import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/cut_metadata.dart';
import 'package:anicel/src/models/layer_section_defaults.dart';

void main() {
  group('CutMetadata', () {
    test('empty metadata defaults to blank note', () {
      const metadata = CutMetadata.empty();

      expect(metadata.note, '');
    });

    test('value equality uses note', () {
      const metadata = CutMetadata(note: 'Check expression.');
      const sameMetadata = CutMetadata(note: 'Check expression.');
      const differentMetadata = CutMetadata(note: 'FX-heavy cut.');

      expect(metadata, sameMetadata);
      expect(metadata.hashCode, sameMetadata.hashCode);
      expect(metadata, isNot(differentMetadata));
    });

    test('copyWith changes note only', () {
      const metadata = CutMetadata(note: 'Original note');

      expect(
        metadata.copyWith(note: 'Updated note'),
        const CutMetadata(note: 'Updated note'),
      );
    });

    test('toJson serializes note only', () {
      const metadata = CutMetadata(note: 'General');

      final json = metadata.toJson();

      expect(json, {'note': 'General'});
      expect(json.containsKey('actionMemo'), isFalse);
      expect(json.containsKey('dialogueMemo'), isFalse);
      expect(json.keys, unorderedEquals(['note']));
    });

    test('fromJson reads note', () {
      final metadata = CutMetadata.fromJson({'note': 'General'});

      expect(metadata, const CutMetadata(note: 'General'));
    });

    test('fromJson ignores legacy actionMemo and dialogueMemo', () {
      final metadata = CutMetadata.fromJson({
        'actionMemo': 'Old action.',
        'dialogueMemo': 'A: Wait!',
        'note': 'General',
      });

      expect(metadata, const CutMetadata(note: 'General'));
    });

    test('fromJson defaults missing note to empty metadata', () {
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
      const metadata = CutMetadata(note: 'FX-heavy cut.');

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
        metadata: const CutMetadata(note: 'FX-heavy cut.'),
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
        metadata: const CutMetadata(note: 'Camera shakes after impact.'),
      );

      expect(cutWithMetadata, isNot(cut));
      expect(
        cutWithMetadata,
        _cut().copyWith(
          metadata: const CutMetadata(note: 'Camera shakes after impact.'),
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
