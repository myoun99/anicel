import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_link_registry.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/commands/folder_mirror.dart';

/// folderMirrorCuts decides where a new folder must be mirrored over
/// linked cuts. Its "stand down on a partial match" branch (a cut only
/// qualifies when EVERY member has a counterpart there) only fires when a
/// group has diverged — a state the command tests do not guarantee to
/// build. Pin both branches directly.
const _track = TrackId('track');
const _cut1 = CutId('cut-1');
const _cut2 = CutId('cut-2');
const _a = LayerId('a');
const _b = LayerId('b');
const _a2 = LayerId('a2');
const _b2 = LayerId('b2');

Project _project(List<LayerLinkGroup> groups) => Project(
  id: const ProjectId('project'),
  name: 'Project',
  tracks: const [],
  createdAt: DateTime(2020),
  linkRegistry: LayerLinkRegistry(groups: groups),
);

LayerLinkGroup _group(String id, List<(CutId, LayerId)> members) =>
    LayerLinkGroup(
      id: id,
      members: [
        for (final (cutId, layerId) in members)
          LayerLinkMember(trackId: _track, cutId: cutId, layerId: layerId),
      ],
    );

void main() {
  test('empty member list mirrors nowhere', () {
    final project = _project([
      _group('g', [(_cut1, _a), (_cut2, _a2)]),
    ]);
    expect(
      folderMirrorCuts(project, cutId: _cut1, memberLayerIds: const []),
      isEmpty,
    );
  });

  test('a cut where EVERY member has a counterpart is mirrored', () {
    final project = _project([
      _group('ga', [(_cut1, _a), (_cut2, _a2)]),
      _group('gb', [(_cut1, _b), (_cut2, _b2)]),
    ]);

    final mirrors = folderMirrorCuts(
      project,
      cutId: _cut1,
      memberLayerIds: const [_a, _b],
    );

    expect(mirrors, hasLength(1));
    expect(mirrors.single.cutId, _cut2);
    expect(mirrors.single.counterpartOf, {_a: _a2, _b: _b2});
  });

  test('a cut with only SOME members linked stands down (partial match)', () {
    // _a links into cut-2, but _b has no group at all — cut-2 covers only
    // one of the two members, so the folder must not be guessed there.
    final project = _project([
      _group('ga', [(_cut1, _a), (_cut2, _a2)]),
    ]);

    expect(
      folderMirrorCuts(
        project,
        cutId: _cut1,
        memberLayerIds: const [_a, _b],
      ),
      isEmpty,
    );
  });
}
