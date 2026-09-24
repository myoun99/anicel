import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/media_asset.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/timeline/timeline_drag_preview.dart';

/// 🚨A FILE HELD OVER A ROW DRAWS WHAT LETTING GO WOULD MAKE — 「끄는 동안
/// 보이는 것은 놓았을 때 생길 것이다」 (미디어 배치 라운드 2d 2부).
///
/// The blocks in the way move WHILE it hovers, by the landing's own planner
/// (유저 2026-09-12, Q1: 「블록 드래그와 같게 — 밀림까지 실시간」), and the
/// cells that are not there yet are named so the row can say so.
void main() {
  const rowId = LayerId('sil-row');
  const b1 = FrameId('sil-b1');
  const b2 = FrameId('sil-b2');
  const sequencePath = '/pool/walk_0001.png';
  const stillPath = '/pool/bg_street.png';

  /// A row with B1 at 0 (two cells) and B2 at 5 (three cells), in a 24
  /// frame cut — the mockup's 「겹칠 때 ①」 shape — plus whatever the pool
  /// holds. The pool lives on the PROJECT, which is where the browser and
  /// every placement read it from.
  EditorSessionManager session({List<MediaAsset> pool = const []}) {
    final manager = EditorSessionManager(
      initialProject: Project(
        id: const ProjectId('sil-project'),
        name: 'Silhouette',
        createdAt: DateTime.utc(2026, 9, 12),
        mediaAssets: pool,
        tracks: [
          Track(
            id: const TrackId('sil-track'),
            name: 'Video',
            cuts: [
              Cut(
                id: const CutId('sil-cut'),
                name: 'Cut',
                duration: 24,
                canvasSize: const CanvasSize(width: 640, height: 360),
                layers: [
                  Layer(
                    id: rowId,
                    name: 'B',
                    frames: [
                      Frame(id: b1, duration: 1, strokes: const []),
                      Frame(id: b2, duration: 1, strokes: const []),
                    ],
                    timeline: {
                      0: const TimelineExposure.drawing(b1, length: 2),
                      5: const TimelineExposure.drawing(b2, length: 3),
                    },
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

  /// The pool entry a sequence registers: ONE path, and the count of files
  /// behind it — `planSequenceLayer` writes exactly this
  /// (`frameCount: sourceFiles.length`), so the silhouette is as long as
  /// the bake will be.
  final sequence = MediaAsset(
    path: sequencePath,
    name: 'walk',
    kind: MediaAssetKind.image,
    frameCount: 4,
  );

  MediaPlacementPreview? shown(EditorSessionManager s) =>
      s.dragPreview.value as MediaPlacementPreview?;

  test('a four-cell sequence over cell 3 names the four cells it would '
      'author', () {
    final s = session(pool: [sequence]);

    s.showMediaPlacement(rowId, 3, sequencePath);

    expect(
      shown(s)?.silhouette,
      (layerId: rowId, startIndex: 3, endIndexExclusive: 7),
      reason: 'the cells it would make, where it would make them',
    );
  });

  test('the block in the way is PUSHED while it hovers — the landing\'s own '
      'plan, not a preview of its own', () {
    final s = session(pool: [sequence]);

    s.showMediaPlacement(rowId, 3, sequencePath);

    final row = shown(s)?.previewLayers[rowId];
    expect(row, isNotNull, reason: 'the row the release would leave');
    expect(
      row!.timeline.keys,
      [0, 3, 4, 5, 6, 7],
      reason:
          'B1 stays at 0; the four files are four CELS (the fold merges '
          'consecutive DUPLICATES, and four different pictures are not '
          'duplicates — `planSequenceLayer` bakes exactly this), so they '
          'take 3·4·5·6; and B2 is pushed to 7 (the mockup: 「뒤가 겹치면 '
          '뒤 블록이 밀린다」)',
    );
    expect(
      row.timeline[7]!.length,
      3,
      reason: 'B2 moves WHOLE — it is not split by the arrival',
    );
  });

  test('a still is ONE cell — a file with no count is one picture', () {
    final s = session(
      pool: [
        MediaAsset(
          path: stillPath,
          name: 'bg_street',
          kind: MediaAssetKind.image,
        ),
      ],
    );

    s.showMediaPlacement(rowId, 3, stillPath);

    expect(
      shown(s)?.silhouette,
      (layerId: rowId, startIndex: 3, endIndexExclusive: 4),
    );
  });

  test(
    'nothing is drawn where nothing can land — the chip already says no',
    () {
      final s = session(pool: [sequence]);

      s.showMediaPlacement(const LayerId('no-such-row'), 3, sequencePath);

      expect(s.dragPreview.value, isNull);
    },
  );

  test('the file leaving takes its drawing with it', () {
    final s = session(pool: [sequence]);
    s.showMediaPlacement(rowId, 3, sequencePath);
    expect(s.dragPreview.value, isNotNull, reason: 'the premise');

    s.mediaPlacement.clear();

    expect(s.dragPreview.value, isNull);
  });

  test('a BLOCK drag\'s preview is not this drag\'s to clear', () {
    final s = session(pool: [sequence]);
    final other = BlockMoveDragPreview(
      previewLayers: {rowId: s.layerById(rowId)!},
    );
    s.dragPreview.value = other;

    s.mediaPlacement.clear();

    expect(
      s.dragPreview.value,
      same(other),
      reason: 'two drags share one channel; each clears only its own',
    );
  });
}
