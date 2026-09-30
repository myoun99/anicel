@TestOn('vm')
library;

import 'package:flutter_test/flutter_test.dart';
import '../helpers/dart_sources.dart';

/// 🚨EVERY PREVIEW OF A CUT LAYOUT IS SETTLED AS ITS RELEASE WILL BE.
///
/// 🗣️F-227: the のりしろ holds and the conte start an O.L asks of the cuts
/// it joins are derived by the repository's write, from the new layout. A
/// drag that re-lays the cuts and published its `CutTrimDragPreview` bare
/// showed the holds gone under the hand and the receiving cut's panels
/// where the old のりしろ put them — five verbs built one, and none of them
/// went through the write's pass until F-227-trim-preview-holds.
/// `cutTrimPreviewAsReleased` is that pass for a preview; this holds the
/// next verb to it.
void main() {
  test('a file that builds a cut-layout preview settles each one', () {
    var built = 0;
    final bare = <String>[];
    for (final entity in dartFilesUnder('lib')) {
      final path = entity.path.replaceAll(r'\', '/');
      if (path.endsWith('lib/src/ui/timeline/timeline_drag_preview.dart')) {
        // The class and the settle itself.
        continue;
      }
      final source = entity.readAsStringSync();
      final previews = _built.allMatches(source).length;
      if (previews == 0) {
        continue;
      }
      built += previews;
      if (_settled.allMatches(source).length != previews) {
        bare.add(path);
      }
    }
    expect(
      built,
      greaterThanOrEqualTo(5),
      reason: 'LIVENESS — the scan reads the verbs it is about',
    );
    expect(
      bare,
      isEmpty,
      reason:
          'a cut-layout preview is published through '
          'cutTrimPreviewAsReleased, one call per preview built',
    );
  });
}

final _built = RegExp(r'\bCutTrimDragPreview\(');
final _settled = RegExp(r'\bcutTrimPreviewAsReleased\(');
