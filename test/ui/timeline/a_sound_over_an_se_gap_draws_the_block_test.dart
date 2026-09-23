import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/media_asset.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/timeline/timeline_drag_preview.dart';

import '../../helpers/placed_sound_conform.dart';

/// 🚨A SOUND OVER AN SE ROW'S EMPTY CELL DRAWS THE BLOCK IT WOULD START
/// THERE (유저 2026-09-11, 목업 s-se-empty: 「떨어뜨린 칸부터 소리 길이만큼」
/// — 미디어 배치 라운드 2d 2부).
///
/// ⚠️**AN SE ROW LIVES ON THE TRACK.** The first draft looked it up among the
/// open cut's layers, found nothing, and drew nothing — and no test noticed,
/// because the only mutant aimed at it was run against a file with no SE row
/// in it. These are the tests that were missing; the bug and the hole were
/// the same hole.
void main() {
  const seId = LayerId('se-1');
  const blockCel = FrameId('se-block');
  const sound = '/pool/door_close.mp3';

  /// A track whose SE row already carries a block at frames 6..10, under a
  /// cut that starts at the project's first frame — so the cut's axis and
  /// the track's coincide and the numbers below read as they are written.
  EditorSessionManager session() {
    final manager = EditorSessionManager(
      initialProject: Project(
        id: const ProjectId('se-project'),
        name: 'SE',
        createdAt: DateTime.utc(2026, 9, 12),
        mediaAssets: [
          MediaAsset(path: sound, name: 'door_close', kind: MediaAssetKind.audio),
        ],
        tracks: [
          Track(
            id: const TrackId('se-track'),
            name: 'Video',
            seLayers: [
              Layer(
                id: seId,
                name: 'S1',
                kind: LayerKind.se,
                frames: [
                  Frame(id: blockCel, duration: 1, strokes: const []),
                ],
                timeline: {
                  6: const TimelineExposure.drawing(blockCel, length: 4),
                },
              ),
            ],
            cuts: [
              Cut(
                id: const CutId('se-cut'),
                name: 'Cut',
                duration: 24,
                canvasSize: const CanvasSize(width: 640, height: 360),
                layers: [
                  Layer(
                    id: const LayerId('drawing'),
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
      // A quarter second: 6 frames at the project's 24 — long enough to be
      // clipped by the block at 6 when it is dropped at 2.
      audioConformStore: soundConformStore(seconds: 0.25),
    );
    addTearDown(manager.dispose);
    return manager;
  }

  MediaPlacementPreview? shown(EditorSessionManager s) =>
      s.dragPreview.value as MediaPlacementPreview?;

  test('the block it would start there — from the cell, as long as the '
      'sound', () async {
    final s = session();
    await s.audioConformStore.ensurePeaksFor(sound);

    s.showMediaPlacement(seId, 0, sound);

    expect(
      shown(s)?.silhouette,
      (layerId: seId, startIndex: 0, endIndexExclusive: 6),
      reason: 'six frames of sound from the cell it stands on',
    );
  });

  test('and no longer than the gap — 「다음 블록까지」', () async {
    final s = session();
    await s.audioConformStore.ensurePeaksFor(sound);

    s.showMediaPlacement(seId, 2, sound);

    expect(
      shown(s)?.silhouette,
      (layerId: seId, startIndex: 2, endIndexExclusive: 6),
      reason: 'the sound wants six frames; the block at 6 leaves four, and '
          'the landing clips to exactly that',
    );
  });

  test('a cell the block already covers draws nothing', () async {
    final s = session();
    await s.audioConformStore.ensurePeaksFor(sound);

    s.showMediaPlacement(seId, 7, sound);

    expect(s.dragPreview.value, isNull);
  });

  test('before the conform has answered there is no length — and nothing '
      'is invented', () {
    final s = session();

    s.showMediaPlacement(seId, 0, sound);

    expect(
      s.dragPreview.value,
      isNull,
      reason: 'the hover cannot wait for the conform, so it draws nothing '
          'rather than guessing how long the sound is',
    );
  });
}
