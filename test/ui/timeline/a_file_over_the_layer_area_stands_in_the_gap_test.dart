import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/media_asset.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/timeline/layer_drop_policy.dart';
import 'package:anicel/src/ui/timeline/property_lane_model.dart';
import 'package:anicel/src/ui/timeline/timeline_drag_preview.dart';

/// 🚨A FILE OVER THE LAYER AREA STANDS IN THE GAP IT WOULD TAKE (유저
/// 2026-09-12, Q2: 「목업대로 — 실루엣 행을 끼운다」).
///
/// 🚨★★★And it is **DRAWN, NEVER COUNTED**: the gap under the pointer is
/// counted on the rows WITHOUT it, so inserting it cannot move the gap it
/// came from. That is the jitter the decision named as this option's cost
/// (「포인터를 조금만 움직여도 선이 한 줄 건너뛰는 떨림」), and these are the
/// tests that hold it off.
void main() {
  Layer row(String id) => Layer(
    id: LayerId(id),
    name: id,
    frames: const [],
    timeline: const {},
  );

  List<TimelineDisplayRow> displayed(List<Layer> layers) => [
    for (var i = 0; i < layers.length; i += 1)
      TimelineDisplayRow.layer(layers[i], layerIndex: i),
  ];

  MediaPlacementPreview standing(int slot) => MediaPlacementPreview(
    silhouetteSlot: slot,
    silhouetteRow: row('silhouette'),
  );

  group('drawn, never counted', () {
    final rows = displayed([row('A'), row('B'), row('C')]);

    test('the gap a slot names is the row it stands above', () {
      expect(displayIndexForGap(rows, 0), 0);
      expect(displayIndexForGap(rows, 1), 1);
      expect(
        displayIndexForGap(rows, 3),
        3,
        reason: 'the gap after the last row is the end of the list',
      );
    });

    test('the silhouette stands in its gap, and everything below moves down',
        () {
      final drawn = rowsWithSilhouette(rows, standing(1));

      expect(drawn, hasLength(4));
      expect(
        [for (final r in drawn) r.layer.id.value],
        ['A', 'silhouette', 'B', 'C'],
      );
    });

    test('THE COUNTING LIST IS UNTOUCHED — the same slot still names the '
        'same gap', () {
      final drawn = rowsWithSilhouette(rows, standing(1));

      expect(
        displayIndexForGap(rows, 1),
        1,
        reason: 'the list the pointer is measured against never grew',
      );
      expect(
        drawn.length - rows.length,
        1,
        reason: 'the growth is the DRAWN list\'s alone',
      );
    });

    test('no drag, no row — and a drag that is not a placement is not this '
        'one\'s business', () {
      expect(rowsWithSilhouette(rows, null), same(rows));
      expect(
        rowsWithSilhouette(
          rows,
          BlockMoveDragPreview(previewLayers: {const LayerId('A'): row('A')}),
        ),
        same(rows),
      );
      expect(
        rowsWithSilhouette(rows, const MediaPlacementPreview()),
        same(rows),
        reason: 'a file over a ROW publishes no silhouette row',
      );
    });
  });

  group('the session raises the caret and the row together', () {
    const drawing = LayerId('layer-area-A');
    const picture = '/pool/bg_street.png';
    const sound = '/pool/door.mp3';

    EditorSessionManager session() {
      final manager = EditorSessionManager(
        initialProject: Project(
          id: const ProjectId('gap-project'),
          name: 'Gap',
          createdAt: DateTime.utc(2026, 9, 12),
          mediaAssets: const [
            MediaAsset(
              path: picture,
              // Not the file's own name: the silhouette must read the POOL.
              name: '거리',
              kind: MediaAssetKind.image,
            ),
            MediaAsset(path: sound, name: 'door', kind: MediaAssetKind.audio),
          ],
          tracks: [
            Track(
              id: const TrackId('gap-track'),
              name: 'Video',
              cuts: [
                Cut(
                  id: const CutId('gap-cut'),
                  name: 'Cut',
                  duration: 12,
                  canvasSize: const CanvasSize(width: 640, height: 360),
                  layers: [
                    Layer(
                      id: drawing,
                      name: 'A',
                      frames: const [],
                      timeline: const {},
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      );
      addTearDown(manager.dispose);
      return manager;
    }

    test('a picture in a legal gap: the caret AND the row it would make', () {
      final s = session();
      final rows = s.requireActiveCut.layers;

      s.showLayerPlacement(rows, 0, picture);

      final preview = s.dragPreview.value as MediaPlacementPreview?;
      expect(preview?.silhouetteSlot, 0);
      expect(
        preview?.silhouetteRow?.kind,
        LayerKind.image,
        reason: 'one picture becomes an image row — the landing\'s own '
            'branch, asked while it hovers',
      );
      expect(
        preview?.silhouetteRow?.name,
        '거리',
        reason: 'the name the drop would give it — the pool entry\'s',
      );
      expect(
        s.layerRowDragVerbs.inFlight.value?.caretSlot,
        0,
        reason: 'the line and the row mark ONE gap',
      );
    });

    test('a SOUND raises neither: it goes to the SE rows whichever way it '
        'came in', () {
      final s = session();

      s.showLayerPlacement(s.requireActiveCut.layers, 0, sound);

      expect(s.dragPreview.value, isNull);
      expect(s.layerRowDragVerbs.inFlight.value, isNull);
    });

    test('leaving takes both away', () {
      final s = session();
      s.showLayerPlacement(s.requireActiveCut.layers, 0, picture);
      expect(s.dragPreview.value, isNotNull, reason: 'the premise');

      s.clearLayerPlacement();

      expect(s.dragPreview.value, isNull);
      expect(s.layerRowDragVerbs.inFlight.value, isNull);
    });
  });
}
