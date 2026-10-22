import 'dart:io';
import 'dart:typed_data';

import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/brush_frame_key.dart';
import 'package:anicel/src/models/cel_photo.dart';
import 'package:anicel/src/models/envelope/cut_envelope_ink_keys.dart';
import 'package:anicel/src/models/media_asset.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/services/brush_frame_store.dart';
import 'package:anicel/src/services/history_manager.dart';
import 'package:anicel/src/services/media/media_moves.dart'
    show projectWithMediaMoved;
import 'package:anicel/src/services/media/sheet_photo_edits.dart';
import 'package:anicel/src/services/persistence/anicel_file_service.dart';
import 'package:anicel/src/services/persistence/anicel_incremental_writer.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/cel_photo_fixture.dart';
import '../../helpers/cel_text_fixture.dart';
import '../../helpers/temp_dir.dart';

/// I-97 E — what the 저장 session asked of the photo index (2026-10-15):
/// a saved cel's head names the files its photos show
/// (`AnicelCelBlob.photoPaths`), the open reads that and nothing more, and
/// it must still say what the cel's photos say after every road a save
/// takes — the file rewritten whole, or appended to.
///
/// 🧪Which road a save took is read off an entry of no kind the save
/// knows: an append keeps it, a whole rewrite leaves it behind.
void main() {
  late Directory directory;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('anicel-photo-index');
  });

  tearDown(() => deleteTempQuietly(directory));

  const service = AnicelFileService();
  const sky = 'C:/media/sky.png';
  const stranger = 'somebody-elses/row.bin';

  Project pooled() => createDefaultProject().copyWith(
    mediaAssets: [MediaAsset(path: sky, name: 'sky.png')],
  );

  BrushFrameKey boxOf(Project project, String box) =>
      envelopeInkBoxKey(project.tracks.first.cuts.first.id, box);

  BitmapSurface inked(List<CelPhoto> photos) => drawingOf({
    TileCoord(x: 0, y: 0): tileOf({
      (1, 1): [9, 9, 9, 255],
    }),
  }).withPhotos(photos);

  void plantStranger(String path) => appendAnicelEntries(
    path: path,
    newEntries: {stranger: Uint8List.fromList([1, 2, 3])},
  );

  /// The files [key]'s photos show, off the file at [path]: its head's
  /// index and its picture.
  Future<({List<String> index, List<String> photos})> readBack(
    String path,
    BrushFrameKey key,
  ) async {
    final opened = await service.open(filePath: path);
    final store = BrushFrameStore()..restoreFromFile(opened.cels);
    return (
      index: opened.cels[key]!.photoPaths,
      photos: [
        for (final photo in store.bakedSurfaceOrNull(key)!.photos)
          photo.reference.assetPath,
      ],
    );
  }

  for (final whole in [true, false]) {
    final road = whole ? 'rewritten whole' : 'appended to';

    test('🚨a file relinked after a save, saved again ($road), opens with '
        'its photo on the new file — the head and the picture alike', () async {
      final path = '${directory.path}/relink.anicel';
      final project = pooled();
      final key = boxOf(project, 'memo');
      final cels = BrushFrameStore();
      final ink = BrushFrameStore()
        ..storeBakedSurface(key, inked([photoOf(1, path: sky)]));
      await service.save(
        project: project,
        brushFrameStore: cels,
        auxCelStores: [ink],
        filePath: path,
      );
      plantStranger(path);

      const found = 'D:/found/sky.png';
      SheetPhotoEdits(() => [ink]).follow({sky: found}, HistoryManager());
      await service.save(
        project: projectWithMediaMoved(project, {sky: found}),
        brushFrameStore: cels,
        auxCelStores: [ink],
        filePath: path,
        rewriteWhole: whole,
      );

      expect(
        parseAnicelZipLayoutFile(path).entryNamed(stranger) == null,
        whole,
        reason: '⛔fixture: the save was $road',
      );
      final read = await readBack(path, key);
      expect(read.index, [found]);
      expect(read.photos, [found]);
    });

    test('🚨a cel whose key moved after a save, saved again ($road), opens '
        'under its new key with its index whole', () async {
      final path = '${directory.path}/rekey.anicel';
      final project = pooled();
      final key = boxOf(project, 'memo');
      await service.save(
        project: project,
        brushFrameStore: BrushFrameStore(),
        auxCelStores: [
          BrushFrameStore()
            ..storeBakedSurface(key, inked([photoOf(1, path: sky)])),
        ],
        filePath: path,
      );
      // Read back as the open leaves it: its bytes in the file, nothing
      // decoded — the re-key splices the head it reads there.
      final ink = BrushFrameStore()
        ..restoreFromFile((await service.open(filePath: path)).cels);
      expect(ink.isCelFileBacked(key), isTrue, reason: '⛔fixture');
      plantStranger(path);

      final moved = boxOf(project, 'other');
      ink.rekeyFrames([(key, moved)]);
      await service.save(
        project: project,
        brushFrameStore: BrushFrameStore(),
        auxCelStores: [ink],
        filePath: path,
        rewriteWhole: whole,
      );

      expect(
        parseAnicelZipLayoutFile(path).entryNamed(stranger) == null,
        whole,
        reason: '⛔fixture: the save was $road',
      );
      final read = await readBack(path, moved);
      expect(read.index, [sky]);
      expect(read.photos, [sky]);
      expect(
        (await service.open(filePath: path)).cels.containsKey(key),
        isFalse,
        reason: 'the CONTROL — it moved',
      );
    });

    test('🚨a cel saved ($road) names its files off the ref the save hands '
        'back — once it cools, without a decode', () async {
      final path = '${directory.path}/cooled.anicel';
      final project = pooled();
      final key = boxOf(project, 'memo');
      final ink = BrushFrameStore();
      await service.save(
        project: project,
        brushFrameStore: BrushFrameStore(),
        auxCelStores: [ink],
        filePath: path,
      );
      plantStranger(path);

      ink.storeBakedSurface(key, inked([photoOf(1, path: sky)]));
      await service.save(
        project: project,
        brushFrameStore: BrushFrameStore(),
        auxCelStores: [ink],
        filePath: path,
        rewriteWhole: whole,
      );
      ink
        ..hotCelByteBudget = 0
        ..storeBakedSurface(boxOf(project, 'other'), inked(const []));
      await ink.drainCooling();

      expect(
        parseAnicelZipLayoutFile(path).entryNamed(stranger) == null,
        whole,
        reason: '⛔fixture: the save was $road',
      );
      expect(
        ink.hotBakedSurfaceOrNull(key),
        isNull,
        reason: '⛔fixture: it cooled onto its ref',
      );
      expect(ink.celPhotoPathsByKey, {
        key: [sky],
      });
    });
  }

  test('🚨a head longer than the open\'s first read is read again, and '
      'names every file', () async {
    final path = '${directory.path}/long.anicel';
    final project = pooled();
    final key = boxOf(project, 'memo');
    final paths = [
      for (var index = 0; index < 60; index += 1)
        'C:/pool/${'a folder deep down/' * 6}photo $index.png',
    ];
    expect(
      paths.join().length,
      greaterThan(4096),
      reason: '⛔fixture: the index alone outgrows a first read',
    );
    await service.save(
      project: project,
      brushFrameStore: BrushFrameStore(),
      auxCelStores: [
        BrushFrameStore()
          ..storeBakedSurface(key, inked([
            for (final (index, file) in paths.indexed)
              photoOf(index + 1, path: file),
          ])),
      ],
      filePath: path,
    );

    final opened = await service.open(filePath: path);

    expect(opened.cels[key]!.photoPaths, paths);
  });
}
