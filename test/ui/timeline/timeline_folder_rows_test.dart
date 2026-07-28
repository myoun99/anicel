import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_folder.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/transform_track.dart';
import 'package:anicel/src/ui/timeline/property_lane_model.dart';
import 'package:anicel/src/ui/timeline/transform_lane_policy.dart';

/// Folder rows in the timeline display list. A folder is a LAYER now, so
/// the builder synthesizes nothing: the row is already in the stack,
/// sitting directly above its members. What is left is the tree indent,
/// the collapse fold, and the aggregate band the folder row paints.
void main() {
  Layer layer(
    String id, {
    String? folder,
    Map<int, TimelineExposure> timeline = const {},
  }) => Layer(
    id: LayerId(id),
    name: id,
    frames: const [],
    timeline: timeline,
    folderId: folder == null ? null : LayerId(folder),
  );

  Layer folderRow(String id, {String? parent, bool collapsed = false}) =>
      createFolderLayer(
        id: LayerId(id),
        name: id.toUpperCase(),
        parentId: parent == null ? null : LayerId(parent),
      ).copyWith(collapsed: collapsed);

  test('folder rows carry tree depth and their members indent under them', () {
    // Display order (what the horizontal grid hands in): folder row first,
    // members below it.
    final rows = buildTimelineDisplayRows(
      layers: [
        layer('top'),
        folderRow('outer'),
        layer('a', folder: 'outer'),
        folderRow('inner', parent: 'outer'),
        layer('b', folder: 'inner'),
      ],
      expandedLayerIds: const {},
      lanesForLayer: (_) => const [],
    );

    expect(rows.map((row) => row.layer.id.value), [
      'top',
      'outer',
      'a',
      'inner',
      'b',
    ]);
    expect(rows[1].isFolder, isTrue);
    expect(rows[1].depth, 0);
    expect(rows[2].depth, 1, reason: 'outer member indents one level');
    expect(rows[3].depth, 1, reason: 'nested folder row indents');
    expect(rows[4].depth, 2, reason: 'nested member indents two levels');
  });

  test('R27 #24: a collapsed folder keeps its row and swallows EVERY '
      'member row, the active layer included', () {
    List<TimelineDisplayRow> build({LayerId? activeLayerId}) =>
        buildTimelineDisplayRows(
          layers: [
            folderRow('f', collapsed: true),
            layer('a', folder: 'f'),
            layer('b', folder: 'f'),
          ],
          expandedLayerIds: const {},
          lanesForLayer: (_) => const [],
          activeLayerId: activeLayerId,
        );

    expect(build().length, 1);
    expect(build().single.isFolder, isTrue);
    expect(
      build(activeLayerId: const LayerId('b')).map((r) => r.layer.id.value),
      ['f'],
      reason:
          'the old active-layer exemption meant a fold with a member '
          'selected did not look folded at all (R27 #24); the folder row '
          'takes the selection instead',
    );
  });

  test('a folder row has no representative member: its layer IS the folder', () {
    final rows = buildTimelineDisplayRows(
      layers: [folderRow('f'), layer('a', folder: 'f')],
      expandedLayerIds: const {},
      lanesForLayer: (_) => const [],
    );
    expect(rows.first.isFolder, isTrue);
    expect(
      rows.first.layer.id,
      const LayerId('f'),
      reason:
          'the header used to carry its first MEMBER as a stand-in, which '
          'is what let row walks land on the wrong layer (R28 #12)',
    );
  });

  test('folder FX lanes are plain layer lanes — no folder-fx address', () {
    final folder = folderRow('f').copyWith(
      transformTrack: TransformTrack.empty(),
    );
    final rows = buildTimelineDisplayRows(
      layers: [folder, layer('a', folder: 'f')],
      expandedLayerIds: {const LayerId('f')},
      lanesForLayer: (row) => transformPropertyLanes(
        row.transformTrack,
        includeAnchorAndOpacity: true,
      ),
    );
    expect(rows.first.isFolder, isTrue);
    expect(
      rows.skip(1).takeWhile((row) => row.isLane).map((row) => row.lane!.label),
      // R27 #26: the LAYER's lane grammar verbatim — and now literally the
      // layer's lanes, keyed by plain base lane ids.
      ['Transform', 'Anchor Point', 'Position', 'Scale', 'Rotation', 'Opacity'],
    );
    expect(rows[1].lane!.isGroupHeader, isTrue);
    expect(rows[3].lane!.laneId, 'position');
    expect(rows[3].layer.id, const LayerId('f'));
  });

  test('the aggregate band is the subtree exposure UNION, holds merged', () {
    final rows = buildTimelineDisplayRows(
      layers: [
        folderRow('f'),
        layer(
          'a',
          folder: 'f',
          timeline: {
            0: TimelineExposure.drawing(const FrameId('x'), length: 3),
          },
        ),
        layer(
          'b',
          folder: 'f',
          timeline: {
            2: TimelineExposure.drawing(const FrameId('y'), length: 2),
            8: TimelineExposure.drawing(const FrameId('z'), length: 1),
          },
        ),
      ],
      expandedLayerIds: const {},
      lanesForLayer: (_) => const [],
    );
    expect(rows.first.isFolder, isTrue);
    expect(rows.first.aggregateRuns, [
      (start: 0, endExclusive: 4),
      (start: 8, endExclusive: 9),
    ]);
    expect(rows.first.members.map((l) => l.id.value), ['a', 'b']);
  });
}
