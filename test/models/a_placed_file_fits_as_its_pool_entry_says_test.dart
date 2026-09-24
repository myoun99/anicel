// A PLACED FILE FITS AS ITS POOL ENTRY SAYS — and a path no entry names fits
// the default. It is the one answer a reference movie's decoded frames and
// its baked cels must share (see `Project.mediaFitModeFor`), and nothing
// pinned it before the lookup moved onto the project.
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/media_asset.dart';

void main() {
  test('the pool entry\'s own fit, and contain for a path no entry names', () {
    final project = createDefaultProject().copyWith(
      mediaAssets: [
        MediaAsset(
          path: 'C:/art/take.mp4',
          name: 'take',
          kind: MediaAssetKind.video,
          fitMode: MediaFitMode.none,
        ),
      ],
    );

    expect(project.mediaFitModeFor('C:/art/take.mp4'), MediaFitMode.none);
    expect(
      project.mediaFitModeFor('C:/art/elsewhere.mp4'),
      MediaFitMode.contain,
    );
  });
}
