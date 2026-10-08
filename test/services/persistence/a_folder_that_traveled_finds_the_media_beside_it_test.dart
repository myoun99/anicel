import 'dart:io';

import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/media_asset.dart';
import 'package:anicel/src/services/brush_frame_store.dart';
import 'package:anicel/src/services/persistence/anicel_file_service.dart';
import 'package:flutter_test/flutter_test.dart';
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
