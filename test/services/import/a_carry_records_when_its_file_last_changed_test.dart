import 'dart:io';

import 'package:anicel/src/models/media_asset.dart';
import 'package:anicel/src/services/import/media_import_planner.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/temp_dir.dart';

/// 🗣️F-589-Q1 (유저 2026-11-14: 「품을 때의 날짜를 적어 두고 그것을
/// 띄운다」): an import's carry records, as it is made, when the file its
/// bytes come from had last changed — the file a piece was cut from, not the
/// piece written a moment ago.
void main() {
  late Directory root;
  setUp(() => root = Directory.systemTemp.createTempSync('anicel_carried'));
  tearDown(() => deleteTempQuietly(root));

  File fileAt(String name, DateTime modified) =>
      File('${root.path}${Platform.pathSeparator}$name')
        ..writeAsBytesSync(const [1, 2, 3])
        ..setLastModifiedSync(modified);

  test('🎯a carried file\'s carry says when the file had last changed', () {
    final when = DateTime(2026, 11, 13, 19, 41);
    final file = fileAt('take.wav', when);

    final asset = importedMediaAsset(
      path: file.path,
      kind: MediaAssetKind.audio,
      carried: true,
    );

    expect(asset.carriedAs!.modified, when);
  });

  test('🎯a piece has the date of the file it was cut from', () {
    final original = fileAt('reel.mp4', DateTime(2026, 9, 2, 8, 15));
    final piece = fileAt('reel-piece.mp4', DateTime(2026, 11, 14, 4, 30));

    final asset = importedMediaAsset(
      path: piece.path,
      kind: MediaAssetKind.video,
      sourcePath: original.path,
      carried: true,
    );

    expect(asset.carriedAs!.modified, DateTime(2026, 9, 2, 8, 15));
  });

  test('a link records no carry, and a file that is not there no date', () {
    final file = fileAt('take.wav', DateTime(2026, 11, 13, 19, 41));

    expect(
      importedMediaAsset(path: file.path, kind: MediaAssetKind.audio).carriedAs,
      isNull,
    );
    final gone = importedMediaAsset(
      path: '${root.path}${Platform.pathSeparator}gone.wav',
      kind: MediaAssetKind.audio,
      carried: true,
    );
    expect(gone.carriedAs, isNotNull);
    expect(gone.carriedAs!.modified, isNull);
  });
}
