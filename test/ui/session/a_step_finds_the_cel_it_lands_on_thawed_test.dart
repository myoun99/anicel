import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/brush_frame_key.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import '../../helpers/cels_kept_in_a_file.dart';

/// 🚨A STEP FINDS THE CEL IT LANDS ON THAWED
/// (stepping-into-another-cut-stalls-the-ui-a-third-of-a-second-Q1, 유저
/// 2026-11-16: 「이웃 컷을 미리 녹여 둔다」). Standing on a cut, the cel a
/// step off either end would stand the canvas on — the row a switch there
/// lands on, at the frame the step lands on — is thawed ahead, so the step
/// does not thaw it on the UI thread as the canvas seeds its session (🔬the
/// Surface Pro 11: 17–19 ms of a 53 ms step).
///
/// The cut BEFORE is the witness: the warm of the cut after already reads
/// that cut's cels, making its pictures, where it makes any.
void main() {
  const size = CanvasSize(width: 128, height: 128);
  const rows = ['a', 'b'];

  Layer rowOf(String cut, String row) => Layer(
    id: LayerId('$cut-$row'),
    name: row.toUpperCase(),
    frames: [
      for (final at in ['1', '2'])
        Frame(id: FrameId('$cut-$row$at'), duration: 1, strokes: const []),
    ],
    timeline: {
      0: TimelineExposure.drawing(FrameId('$cut-${row}1'), length: 1),
      1: TimelineExposure.drawing(FrameId('$cut-${row}2'), length: 1),
    },
  );

  Project threeCuts() => Project(
    id: const ProjectId('project'),
    name: 'Project',
    cameraSize: size,
    createdAt: DateTime.utc(2026),
    tracks: [
      Track(
        id: const TrackId('track'),
        name: 'Track',
        cuts: [
          for (final cut in ['c1', 'c2', 'c3'])
            Cut(
              id: CutId(cut),
              name: cut.toUpperCase(),
              duration: 2,
              canvasSize: size,
              layers: [for (final row in rows) rowOf(cut, row)],
            ),
        ],
      ),
    ],
  );

  BitmapSurface inked() => BitmapSurface(
    canvasSize: size,
    tileSize: 128,
    tiles: {
      TileCoord(x: 0, y: 0): BitmapTile(
        size: 128,
        pixels: Uint8List.fromList([
          for (var at = 0; at < 128 * 128; at += 1)
            ...const [0x30, 0x60, 0x90, 0xFF],
        ]),
      ),
    },
  );

  /// The session, a cel of the first cut by row and frame, and [keep]: every
  /// cel of the first cut kept in a file as an opened project keeps it, cold
  /// until read — asked once the hand has left that cut, so nothing done
  /// while standing on it read them first.
  ({
    EditorSessionManager session,
    BrushFrameKey Function(String, String) cel,
    void Function() keep,
  })
  opened() {
    final session = EditorSessionManager(initialProject: threeCuts());
    addTearDown(session.dispose);
    BrushFrameKey cel(String row, String frame) {
      final cut = session.cutById(const CutId('c1'))!;
      return session.brushFrameKeyForCut(
        cut,
        LayerId('c1-$row'),
        FrameId('c1-$row$frame'),
      );
    }

    void keep() => keepInAFile(session.renderCaches.brushFrameStore, {
      for (final row in rows)
        for (final frame in ['1', '2']) cel(row, frame): inked(),
    });
    return (session: session, cel: cel, keep: keep);
  }

  Future<bool> hotOnceSettled(
    EditorSessionManager session,
    BrushFrameKey key,
  ) async {
    final store = session.renderCaches.brushFrameStore;
    for (var turn = 0; turn < 200; turn += 1) {
      if (store.hotBakedSurfaceOrNull(key) != null) {
        return true;
      }
      await Future<void>.delayed(const Duration(milliseconds: 25));
    }
    return false;
  }

  test('🚨on the cut after, the cel a step back lands on — the row it was '
      'left on, at its last frame — is thawed ahead, and no other', () async {
    final (:session, :cel, :keep) = opened();
    session.selectCut(const CutId('c1'));
    session.selectLayer(const LayerId('c1-a'));
    session.selectCut(const CutId('c2'));
    keep();

    expect(
      await hotOnceSettled(session, cel('a', '2')),
      isTrue,
      reason: 'the cel a step back from C2 seeds is thawed ahead',
    );
    final store = session.renderCaches.brushFrameStore;
    expect(
      store.hotBakedSurfaceOrNull(cel('a', '1')),
      isNull,
      reason: 'C1\'s first frame is no step\'s landing',
    );
    expect(
      store.hotBakedSurfaceOrNull(cel('b', '2')),
      isNull,
      reason: 'the row C1 was left on is A',
    );
  });

  test('🚨the row is the one a switch there lands on: left on B, the cut '
      'before is thawed on B', () async {
    final (:session, :cel, :keep) = opened();
    session.selectCut(const CutId('c1'));
    session.selectLayer(const LayerId('c1-b'));
    session.selectCut(const CutId('c2'));
    keep();

    expect(
      await hotOnceSettled(session, cel('b', '2')),
      isTrue,
      reason: 'the row C1 was left on, at the frame a step back lands on',
    );
    expect(
      session.renderCaches.brushFrameStore.hotBakedSurfaceOrNull(
        cel('a', '2'),
      ),
      isNull,
      reason: 'not the row a switch to C1 does not land on',
    );
  });
}
