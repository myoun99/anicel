import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/brush_tip_mask.dart';
import 'package:anicel/src/services/brush_tip_defaults.dart';
import 'package:anicel/src/services/brush_tip_image_codec.dart';
import 'package:anicel/src/services/brush_tip_library_service.dart';
import 'package:anicel/src/ui/brush/brush_tip_library.dart';

BrushTipMask _mask(String id, {int size = 8, int value = 200}) => BrushTipMask(
  id: id,
  size: size,
  alpha: Uint8List.fromList(List<int>.filled(size * size, value)),
);

void main() {
  late Directory tempDirectory;
  late BrushTipLibraryService service;

  setUp(() async {
    tempDirectory = await Directory.systemTemp.createTemp('brush_tip_library');
    service = BrushTipLibraryService(directoryPath: tempDirectory.path);
  });

  tearDown(() async {
    for (var attempt = 0; ; attempt += 1) {
      try {
        if (await tempDirectory.exists()) {
          await tempDirectory.delete(recursive: true);
        }
        return;
      } on FileSystemException {
        if (attempt >= 20) {
          rethrow;
        }
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    }
  });

  group('BrushTipLibraryService', () {
    test('a missing library is empty, not an error', () async {
      expect(await service.loadIndex(), isEmpty);
      expect(await service.loadMask('nothing'), isNull);
    });

    test('an image written then read comes back identical', () async {
      final mask = _mask('tip-1');

      final entry = await service.writeImage(mask, name: 'Mine');
      await service.saveIndex([entry]);

      expect(File(service.imagePathFor('tip-1')).existsSync(), isTrue);
      expect((await service.loadMask('tip-1'))!.alpha, mask.alpha);
      final index = await service.loadIndex();
      expect(index.single.name, 'Mine');
      expect(index.single.size, 8);
      expect(index.single.thumbnail.length, 16 * 16);
      // The index is names and previews; the pixels live in the PNG.
      expect(index.single.mask, isNull);
    });

    test('built-ins are never written to the index', () async {
      // They are generated on every launch — a copy on disk could drift from
      // the generator, and the fingerprint tests lock the generator.
      await service.saveIndex([
        ...defaultBrushTipEntries,
        await service.writeImage(_mask('tip-1'), name: 'Mine'),
      ]);

      final index = await service.loadIndex();

      expect(index.map((entry) => entry.id), ['tip-1']);
    });

    test('a corrupt index reads as empty', () async {
      await File(service.indexPath).parent.create(recursive: true);
      await File(service.indexPath).writeAsString('{not json');

      expect(await service.loadIndex(), isEmpty);
    });

    test('deleting an image twice is not an error', () async {
      await service.writeImage(_mask('tip-1'), name: 'Mine');

      await service.deleteImage('tip-1');
      await service.deleteImage('tip-1');

      expect(File(service.imagePathFor('tip-1')).existsSync(), isFalse);
    });
  });

  group('sanitizeBrushTipId', () {
    test('keeps an already safe id', () {
      expect(sanitizeBrushTipId('abr-1234-tip'), 'abr-1234-tip');
    });

    test('folds anything that could escape the folder', () {
      // The id becomes a FILE NAME, which preset ids never were.
      expect(sanitizeBrushTipId('../../etc/passwd'), 'etc-passwd');
      expect(sanitizeBrushTipId(r'a\b/c'), 'a-b-c');
      expect(sanitizeBrushTipId('..'), 'tip');
    });

    test('folds non-latin names rather than dropping them silently', () {
      expect(sanitizeBrushTipId('불투명 수채'), 'tip');
      expect(sanitizeBrushTipId('sut-불투명-42'), 'sut-42');
    });

    test('collapses runs and trims edges', () {
      expect(sanitizeBrushTipId('  A***B  '), 'a-b');
    });
  });

  group('nextUserBrushTipId', () {
    test('two tips minted in the same millisecond differ', () {
      // Registering a folder of images at once does exactly this, and two
      // tips sharing an id would mean two brushes sharing one file.
      expect(
        nextUserBrushTipId(sequence: 1),
        isNot(nextUserBrushTipId(sequence: 2)),
      );
    });
  });

  group('BrushTipLibrary', () {
    test('starts with the built-in tips before anything loads', () {
      final library = BrushTipLibrary(service: service);
      addTearDown(library.dispose);

      expect(library.tips, defaultBrushTipEntries);
      expect(library.maskFor('builtin-chalk'), isNotNull);
    });

    test('loads names and thumbnails BEFORE the images', () async {
      final entry = await service.writeImage(_mask('tip-1'), name: 'Mine');
      await service.saveIndex([entry]);
      final library = BrushTipLibrary(service: service);
      addTearDown(library.dispose);

      final snapshots = <({int count, bool loaded})>[];
      library.addListener(() {
        final tip = library.tips.last;
        snapshots.add((count: library.tips.length, loaded: tip.isLoaded));
      });
      await library.load();

      // First pass: the tip is listed and previewable but not decoded.
      // Second: its image has landed.
      expect(snapshots.first.loaded, isFalse);
      expect(snapshots.last.loaded, isTrue);
      expect(library.maskFor('tip-1')!.alpha, _mask('tip-1').alpha);
    });

    test('a tip whose file vanished stays listed but unloaded', () async {
      final entry = await service.writeImage(_mask('tip-1'), name: 'Mine');
      await service.saveIndex([entry]);
      await service.deleteImage('tip-1');
      final library = BrushTipLibrary(service: service);
      addTearDown(library.dispose);

      await library.load();

      // Listed so the user can see what a preset is asking for; unloaded so
      // the brush falls back to the round tip instead of crashing.
      expect(library.tips.last.name, 'Mine');
      expect(library.maskFor('tip-1'), isNull);
    });

    test('registering the same id replaces rather than duplicates', () async {
      final library = BrushTipLibrary(service: service);
      addTearDown(library.dispose);

      await library.register(_mask('tip-1', value: 100), name: 'First');
      await library.register(_mask('tip-1', value: 200), name: 'Second');

      expect(library.tips.where((tip) => tip.id == 'tip-1').length, 1);
      expect(library.tips.last.name, 'Second');
      expect(library.maskFor('tip-1')!.alpha.first, 200);
    });

    test('an unreadable image is refused with a message', () async {
      final library = BrushTipLibrary(service: service);
      addTearDown(library.dispose);

      final message = await library.registerImageBytes(
        Uint8List.fromList([1, 2, 3]),
        name: 'Broken',
      );

      expect(message, isNotNull);
      expect(library.tips, defaultBrushTipEntries);
    });

    test(
      'a blank image is refused rather than silently doing nothing',
      () async {
        final library = BrushTipLibrary(service: service);
        addTearDown(library.dispose);
        final blank = await encodeBrushTipImage(_mask('blank', value: 0));

        final message = await library.registerImageBytes(blank, name: 'Blank');

        expect(message, contains('no visible shape'));
        expect(library.tips, defaultBrushTipEntries);
      },
    );

    test('registers a real image and persists it', () async {
      final library = BrushTipLibrary(service: service);
      addTearDown(library.dispose);
      final png = await encodeBrushTipImage(_mask('source'));

      final message = await library.registerImageBytes(png, name: 'Mine');

      expect(message, isNull);
      final added = library.tips.last;
      expect(added.name, 'Mine');
      expect(added.builtIn, isFalse);
      expect(File(service.imagePathFor(added.id)).existsSync(), isTrue);
    });

    test('deleting a user tip removes its file; built-ins are safe', () async {
      final library = BrushTipLibrary(service: service);
      addTearDown(library.dispose);
      await library.register(_mask('tip-1'), name: 'Mine');

      await library.delete('tip-1');
      await library.delete('builtin-chalk');

      expect(library.tips.any((tip) => tip.id == 'tip-1'), isFalse);
      expect(File(service.imagePathFor('tip-1')).existsSync(), isFalse);
      // A built-in is regenerated on every launch; there is nothing to
      // delete and pretending otherwise would just lose it until restart.
      expect(library.maskFor('builtin-chalk'), isNotNull);
    });

    test('renaming touches the name only, never the id', () async {
      final library = BrushTipLibrary(service: service);
      addTearDown(library.dispose);
      await library.register(_mask('tip-1'), name: 'Mine');

      library.rename('tip-1', 'Renamed');

      expect(library.tips.last.id, 'tip-1');
      expect(library.tips.last.name, 'Renamed');
      expect(library.maskFor('tip-1'), isNotNull);
    });
  });
}
