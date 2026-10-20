import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/media_asset.dart';
import 'package:anicel/src/models/viewer_ink_keys.dart';

/// 🗣️I-114 (유저 2026-10-21): 「물론 그리는게 가능한 파일만 대응 … 오디오
/// 파일처럼 못그리는건 대응불가하도록」 · I-114-Q1: 「품은 파일만」.
void main() {
  MediaAsset asset(MediaAssetKind kind, {required bool carried}) => MediaAsset(
    path: 'C:/work/file',
    name: 'file',
    kind: kind,
    carriedAs: carried ? mintMediaCarry('C:/work/file') : null,
  );

  test('a file the project carries takes ink on every kind with a picture — '
      'and a sound, a file pointed at, or none at all takes none', () {
    expect(
      {
        for (final kind in MediaAssetKind.values)
          for (final carried in [true, false])
            (kind, carried): viewerInksOn(asset(kind, carried: carried)),
      },
      {
        (MediaAssetKind.audio, true): false,
        (MediaAssetKind.audio, false): false,
        (MediaAssetKind.image, true): true,
        (MediaAssetKind.image, false): false,
        (MediaAssetKind.video, true): true,
        (MediaAssetKind.video, false): false,
        (MediaAssetKind.pdf, true): true,
        (MediaAssetKind.pdf, false): false,
      },
    );
    expect(viewerInksOn(null), isFalse);
  });

  test('a page\'s ink is the carry\'s and the page\'s — read back from the '
      'key, and told apart from every other ink', () {
    final key = viewerInkPageKey('carry-a', 3);
    expect(isViewerInkKey(key), isTrue);
    expect(viewerInkCarryOf(key), 'carry-a');
    expect(key, isNot(viewerInkPageKey('carry-a', 4)));
    expect(key, isNot(viewerInkPageKey('carry-b', 3)));
  });
}
