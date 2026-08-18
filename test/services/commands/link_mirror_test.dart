import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_link_registry.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/track.dart';
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

  test('linkedCutSiblings: a sibling holding TWO members of ONE group is '
      'still a full match — link-duplicating inside a linked cut must '
      'not silently drop the 겸용 lockstep (a resize then split the '
      'sizes and the first stroke destroyed the shared cel bank)', () {
    Layer layer(String id) => Layer(
      id: LayerId(id),
      name: id,
      frames: const [],
      timeline: const {},
    );
    Cut cut(CutId id, List<Layer> layers) => Cut(
      id: id,
      name: id.value,
      duration: 8,
      canvasSize: const CanvasSize(width: 640, height: 360),
      layers: layers,
    );
    final project = Project(
      id: const ProjectId('project'),
      name: 'Project',
      createdAt: DateTime(2020),
      tracks: [
        Track(
          id: _track,
          name: 'T',
          cuts: [
            cut(_cut1, [layer('layer-a')]),
            cut(_cut2, [layer('layer-b'), layer('layer-b2')]),
          ],
        ),
      ],
      linkRegistry: LayerLinkRegistry(
        groups: [
          LayerLinkGroup(
            id: 'group-1',
            members: const [
              LayerLinkMember(trackId: _track, cutId: _cut1, layerId: _layerA),
              LayerLinkMember(trackId: _track, cutId: _cut2, layerId: _layerB),
              LayerLinkMember(
                trackId: _track,
                cutId: _cut2,
                layerId: LayerId('layer-b2'),
              ),
            ],
          ),
        ],
      ),
    );

    expect(
      linkedCutSiblings(project, cutId: _cut1),
      [_cut2],
      reason: 'counting MEMBERS instead of per-layer coverage read 2 '
          'against 1 and excluded the genuine sibling — asymmetrically',
    );
    expect(linkedCutSiblings(project, cutId: _cut2), [_cut1]);
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
