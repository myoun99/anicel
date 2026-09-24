// A PROJECT FINDS A MEDIA ASSET BY ITS PATH, AND ONLY BY ITS PATH.
//
// The mutation campaign (2026-09-03) turned the lookup's `==` into `!=` —
// any path then answered the first asset that was NOT it — and nothing
// noticed. These pins do.
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/media_asset.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';

void main() {
  final project = Project(
    id: const ProjectId('p'),
    name: 'P',
    createdAt: DateTime.utc(2026, 9, 3),
    tracks: const [],
    mediaAssets: [
      MediaAsset(path: 'a/one.wav', name: 'one'),
      MediaAsset(path: 'a/two.wav', name: 'two'),
    ],
  );

  test('the asset at that path, by name', () {
    expect(project.mediaAssetByPath('a/two.wav')?.name, 'two');
    expect(project.mediaAssetByPath('a/one.wav')?.name, 'one');
  });

  test('a path the project does not hold answers null', () {
    expect(project.mediaAssetByPath('a/three.wav'), isNull);
  });
}
