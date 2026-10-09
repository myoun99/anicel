import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/media_asset.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';

/// The pool registers a file only as the kind its name says — a file no
/// kind names is no media, and is not taken. ↩️It registered as a PICTURE:
/// an entry the viewer could not open and nothing could place (flagged on
/// 08-14; the one door, F-282, names such a file before it gets here).
void main() {
  test('a file no kind names is not registered — the ones that are named '
      'beside it still are, as their kind', () async {
    final s = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(s.dispose);

    await s.mediaPool.importMediaFiles([
      'C:/work/notes.txt',
      'C:/work/A1.png',
      'C:/work/take.mov',
    ], copyIntoProject: false);

    expect({
      for (final asset in s.mediaPool.mediaAssets) asset.path: asset.kind,
    }, {
      'C:/work/A1.png': MediaAssetKind.image,
      'C:/work/take.mov': MediaAssetKind.video,
    });
  });
}
