import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_link_registry.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/commands/link_mirror.dart';

/// linkMirrorTargets is the mirror core four commands (name, mark, kind,
/// delete) fan out through, but no test named it directly — its two
/// branches were only reached, if at all, through those commands. Pin them.
Project _project(LayerLinkRegistry registry) => Project(
  id: const ProjectId('project'),
  name: 'Project',
  tracks: const [],
  createdAt: DateTime(2020),
  linkRegistry: registry,
);

const _track = TrackId('track');
const _cut1 = CutId('cut-1');
const _cut2 = CutId('cut-2');
const _layerA = LayerId('layer-a');
const _layerB = LayerId('layer-b');

void main() {
  test('an UNLINKED layer mirrors to itself only', () {
    final project = _project(LayerLinkRegistry.empty);

    final targets = linkMirrorTargets(
      project,
      cutId: _cut1,
      layerId: _layerA,
    );

    expect(targets, [(cutId: _cut1, layerId: _layerA)]);
  });

  test('a LINKED layer fans out to every member of its group', () {
    final project = _project(
      LayerLinkRegistry(
        groups: [
          LayerLinkGroup(
            id: 'group-1',
            members: const [
              LayerLinkMember(trackId: _track, cutId: _cut1, layerId: _layerA),
              LayerLinkMember(trackId: _track, cutId: _cut2, layerId: _layerB),
            ],
          ),
        ],
      ),
    );

    // Asked from either member, the fan-out is the whole group.
    expect(linkMirrorTargets(project, cutId: _cut1, layerId: _layerA), [
      (cutId: _cut1, layerId: _layerA),
      (cutId: _cut2, layerId: _layerB),
    ]);
    expect(linkMirrorTargets(project, cutId: _cut2, layerId: _layerB), [
      (cutId: _cut1, layerId: _layerA),
      (cutId: _cut2, layerId: _layerB),
    ]);
  });

  test('a layer outside any group stands alone even when groups exist', () {
    final project = _project(
      LayerLinkRegistry(
        groups: [
          LayerLinkGroup(
            id: 'group-1',
            members: const [
              LayerLinkMember(trackId: _track, cutId: _cut1, layerId: _layerA),
              LayerLinkMember(trackId: _track, cutId: _cut2, layerId: _layerB),
            ],
          ),
        ],
      ),
    );

    expect(
      linkMirrorTargets(project, cutId: _cut1, layerId: const LayerId('solo')),
      [(cutId: _cut1, layerId: LayerId('solo'))],
    );
  });
}
