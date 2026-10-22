import 'dart:io';

import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/envelope/cut_envelope_ink_keys.dart';
import 'package:anicel/src/models/media_asset.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/services/brush_frame_store.dart';
import 'package:anicel/src/services/persistence/anicel_file_service.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../helpers/cel_photo_fixture.dart';
import '../../helpers/cel_text_fixture.dart';
import '../../helpers/opened_session.dart';
import '../../helpers/temp_dir.dart';

/// A project whose folder moved whole — to another disk, another machine, a
/// synced drive — keeps the media beside it: the save records those paths
/// relative to the folder the file stands in, and the open puts them back
/// inside the folder it is opened from.
///
/// Both ask the one folder of a path (`folderOfPath`) and the one join
/// (`pathInFolder`). The save asked a folder of its own until 2026-10-08,
/// which answered `.` for a project at the top of a disk (board
/// `the-save-keeps-its-own-folder-of-a-path`).
void main() {
  late Directory directory;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('anicel-traveled');
  });

  tearDown(() => deleteTempQuietly(directory));

  test('a folder that traveled whole finds the media beside it', () async {
    const service = AnicelFileService();
    final from = Directory('${directory.path}/from')..createSync();
    final sound = File('${from.path}/snd/boom.wav')
      ..createSync(recursive: true)
      ..writeAsBytesSync([1, 2, 3]);
    await service.save(
      project: createDefaultProject().copyWith(
        mediaAssets: [MediaAsset(path: sound.path, name: 'boom')],
      ),
      brushFrameStore: BrushFrameStore(),
      filePath: '${from.path}/scene.anicel',
    );

    // Copied whole, as to another machine — and the first folder stays, so
    // a sound read back from its old path would be found too.
    final to = Directory('${directory.path}/to');
    for (final name in ['scene.anicel', 'snd/boom.wav']) {
      File('${to.path}/$name').createSync(recursive: true);
      File('${from.path}/$name').copySync('${to.path}/$name');
    }
    final opened = await service.open(filePath: '${to.path}/scene.anicel');

    expect(
      opened.project.mediaAssets.single.path,
      '${to.path}/snd/boom.wav'.replaceAll(r'\', '/'),
      reason: 'the sound is the one beside the file it was opened from',
    );
  });

  test('🚨the sheets\' photos travel with it (I-97) — each stands on the '
      'file beside the file it was opened from, which the file itself does '
      'not say yet', () async {
    const service = AnicelFileService();
    final from = Directory('${directory.path}/from')..createSync();
    final picture = File('${from.path}/pics/sky.png')
      ..createSync(recursive: true)
      ..writeAsBytesSync([1, 2, 3]);
    final project = createDefaultProject().copyWith(
      mediaAssets: [MediaAsset(path: picture.path, name: 'sky')],
    );
    final key = envelopeInkBoxKey(project.tracks.first.cuts.first.id, 'memo');
    await service.save(
      project: project,
      brushFrameStore: BrushFrameStore(),
      auxCelStores: [
        BrushFrameStore()..storeBakedSurface(
          key,
          drawingOf({
            TileCoord(x: 0, y: 0): tileOf({
              (1, 1): [9, 9, 9, 255],
            }),
          }).withPhotos([
            photoOf(1, path: normalizedMediaPath(picture.path)),
          ]),
        ),
      ],
      filePath: '${from.path}/scene.anicel',
    );
    final to = Directory('${directory.path}/to');
    for (final name in ['scene.anicel', 'pics/sky.png']) {
      File('${to.path}/$name').createSync(recursive: true);
      File('${from.path}/$name').copySync('${to.path}/$name');
    }

    final session = await openedSession('${to.path}/scene.anicel');
    addTearDown(session.dispose);

    final beside = normalizedMediaPath('${to.path}/pics/sky.png');
    expect(
      session.mediaPool.mediaAssets.single.path,
      beside,
      reason: 'the CONTROL — the pool followed',
    );
    final ink = session.renderCaches.envelopeInkStore;
    expect(ink.celPhotoPathsByKey, {
      key: [beside],
    });
    expect([
      for (final photo in ink.bakedSurfaceOrNull(key)!.photos)
        photo.reference.assetPath,
    ], [beside]);
    expect(
      session.projectFile.hasUnsavedChanges,
      isTrue,
      reason: 'the cel in hand is not the cel in the file, as a healed '
          'one is not',
    );
  });

  // A project at the top of a disk is the one place the join's root slash
  // shows, and no test can write there — so the open's join is read where
  // it is written: the folder the save and the open stand in, and the one
  // join that puts a recorded path back inside it.
  test('the save and the open ask the one folder and the one join', () {
    final source = File(
      'lib/src/services/persistence/anicel_file_service.dart',
    ).readAsStringSync();

    expect('folderOfPath(filePath)'.allMatches(source), hasLength(2));
    expect(source, contains('pathInFolder(directory, entry.value)'));
  });
}
