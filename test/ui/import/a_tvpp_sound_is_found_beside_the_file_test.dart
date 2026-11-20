import 'dart:io';

import 'package:anicel/src/models/media_asset.dart' show normalizedMediaPath;
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/ui/session/tvpp_import_door.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/opened_session.dart';
import '../../helpers/temp_dir.dart';
import '../../models/import/tvpp_test_builder.dart';

/// 🗣️F-621 ① (유저 2026-11-19: 「사운드파일 해당 위치에 있었는데 인식안됨」):
/// a .tvpp records each sound by the absolute path it was made at, and the
/// user's Google Drive names its root differently on another machine —
/// the sounds stood beside the file, under a root that was not there. Where
/// a sound is not at its recorded place, it is looked for under the .tvpp's
/// folder by the relink's own rule ([readTvppProject]).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory temp;
  setUp(() => temp = Directory.systemTemp.createTempSync('tvpp-sound'));
  tearDown(() => deleteTempQuietly(temp));

  String at(List<String> parts) =>
      [temp.path, ...parts].join(Platform.pathSeparator);

  /// A file of a few bytes at [parts] under the test's folder.
  String place(List<String> parts) {
    final file = File(at(parts))..parent.createSync(recursive: true);
    file.writeAsBytesSync(const [0, 1, 2, 3]);
    return file.path;
  }

  /// A .tvpp at [parts] whose one clip plays [recorded].
  String writeTvpp(List<String> parts, List<String> recorded) {
    final b = TvppBuilder()
      ..clipProperties('c')
      ..clipHeader(width: 64, height: 48)
      ..layerHead('A', end: 0, count: 1)
      ..layerExt(const {})
      ..zchkSlot(srawRecord(List.filled(64 * 48, 0), 64, 48))
      ..clipConfig(
        audio: [for (final path in recorded) (path, 0.0, 1.0, false)],
      );
    final file = File(at(parts))..parent.createSync(recursive: true);
    file.writeAsBytesSync(b.bytes);
    return file.path;
  }

  /// Where the root the file was made under is not: the user's 「マイドライブ」
  /// on a machine that calls it 「My Drive」.
  String recorded(List<String> parts) =>
      normalizedMediaPath(at(['マイドライブ', ...parts]));

  List<String> soundsOf(Project project) => [
    for (final track in project.tracks)
      for (final layer in track.seLayers)
        for (final clip in layer.audioClips) clip.filePath,
  ];

  test('🎯a sound not where the file says is found under the file\'s '
      'folder — the clip plays it', () async {
    final tvpp = writeTvpp(
      ['My Drive', 'ER', '作業', 'ER.tvpp'],
      [recorded(['ER', '作業', 'movie', '187.mov'])],
    );
    final beside = place(['My Drive', 'ER', '作業', 'movie', '187.mov']);

    final read = await readTvppProject(tvppPath: tvpp);

    expect(soundsOf(read!.project), [normalizedMediaPath(beside)]);
  });

  test('🚨the pool holds it where it was found, and nothing says it is '
      'missing', () async {
    final tvpp = writeTvpp(
      ['My Drive', 'ER', '作業', 'ER.tvpp'],
      [recorded(['ER', '作業', 'lo', '196', '196_lo.mov'])],
    );
    final beside = place(['My Drive', 'ER', '作業', 'lo', '196', '196_lo.mov']);

    final opened = await openedTvpp(tvpp);
    final session = opened!.session;
    addTearDown(session.dispose);

    expect(
      [for (final asset in session.mediaPool.mediaAssets) asset.path],
      [normalizedMediaPath(beside)],
    );
    expect(
      opened.warnings.where((warning) => warning.key == 'soundMissing'),
      isEmpty,
    );
  });

  test('🚨two files the folder holds under its name, and no folder of its '
      'path to tell them apart: neither is taken — the relink does not '
      'guess', () async {
    final missing = recorded(['ER', '作業', 'movie', '187.mov']);
    final tvpp = writeTvpp(['My Drive', 'ER', '作業', 'ER.tvpp'], [missing]);
    place(['My Drive', 'ER', '作業', 'a', '187.mov']);
    place(['My Drive', 'ER', '作業', 'b', '187.mov']);

    final read = await readTvppProject(tvppPath: tvpp);

    expect(soundsOf(read!.project), [missing]);
  });

  test('a sound where the file says stays there, whatever the folder holds '
      'under its name', () async {
    final there = place(['elsewhere', 'movie', '187.mov']);
    final tvpp = writeTvpp(
      ['My Drive', 'ER', '作業', 'ER.tvpp'],
      [normalizedMediaPath(there)],
    );
    place(['My Drive', 'ER', '作業', 'movie', '187.mov']);

    final read = await readTvppProject(tvppPath: tvpp);

    expect(soundsOf(read!.project), [normalizedMediaPath(there)]);
  });
}
