import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
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
import 'package:anicel/src/models/timeline_row_address.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';

import '../../helpers/pill_row_clipboard.dart';

/// 🗣️F-615 (유저 2026-11-19): 「항상 하듯이 ui안멈추게」 — 링크 독립 of a
/// band gives each shared cel a copy of its own, its picture copied after
/// the splice; each copy announced its crossing alone, to every listener
/// of the cels' content. 🔬S5_BA cut 352, a band over 61 linked rows: 274
/// copies, their announcements 1.6 s of a 1.8 s step. A step is ONE edit
/// of the cels (`RepositoryStepScope` ⑤) — its pictures with it.
const _a = LayerId('heard-a');
const _canvas = CanvasSize(
  width: defaultCelTileSize,
  height: defaultCelTileSize,
);

EditorSessionManager _session() {
  final session = EditorSessionManager(
    initialProject: Project(
      id: const ProjectId('heard-once'),
      name: 'Heard once',
      createdAt: DateTime.utc(2026, 11, 19),
      tracks: [
        Track(
          id: const TrackId('heard-v'),
          name: 'V',
          cuts: [
            Cut(
              id: const CutId('heard-cut'),
              name: '1',
              duration: 4,
              canvasSize: _canvas,
              layers: [
                Layer(
                  id: _a,
                  name: 'A',
                  frames: [
                    for (final cel in ['a1', 'a2'])
                      Frame(
                        id: FrameId(cel),
                        duration: 2,
                        name: cel,
                        strokes: const [],
                      ),
                  ],
                  timeline: {
                    0: const TimelineExposure.drawing(FrameId('a1'), length: 2),
                    2: const TimelineExposure.drawing(FrameId('a2'), length: 2),
                  },
                ),
              ],
            ),
          ],
        ),
      ],
    ),
  );
  addTearDown(session.dispose);
  return session;
}

BitmapSurface _ink() => BitmapSurface(
  canvasSize: _canvas,
  tileSize: defaultCelTileSize,
  tiles: {
    TileCoord(x: 0, y: 0): BitmapTile(
      size: defaultCelTileSize,
      pixels: Uint8List(defaultCelTileSize * defaultCelTileSize * 4)
        ..fillRange(0, 4, 0xFF),
    ),
  },
);

void main() {
  test('🚨a 링크 독립 of a band over two shared cels is heard ONCE — the '
      'splice and the pictures it copies are one edit of the cels', () {
    final s = _session();
    final store = s.renderCaches.brushFrameStore;
    final cut = s.requireActiveCut;
    for (final cel in ['a1', 'a2']) {
      store.storeBakedSurface(
        s.brushFrameKeyForCut(cut, _a, FrameId(cel)),
        _ink(),
      );
    }
    s.selectLayer(_a);
    final before = {for (final row in s.requireActiveCut.layers) row.id};
    linkDuplicateActiveRow(s);
    final linked = s.requireActiveCut.layers
        .where((row) => !before.contains(row.id))
        .single;
    s.standOnRow(LayerRowAddress(linked.id), frameIndex: 0);
    s.updateFrameRangeSelectionDrag(
      layerId: linked.id,
      anchorIndex: 0,
      headIndex: 3,
      spanRows: [LayerRowAddress(linked.id)],
    );
    expect(s.cells.celsUnlinked, hasLength(2), reason: '⛔전제: two shared');

    var heard = 0;
    void hear() => heard += 1;
    store.celContentRevision.addListener(hear);
    addTearDown(() => store.celContentRevision.removeListener(hear));
    s.cells.unlinkCells();

    final now = s.requireActiveCut;
    final row = now.layers.firstWhere((one) => one.id == linked.id);
    expect(
      [
        for (final shown in row.timeline.values)
          store.celHasRenderableContent(
            s.brushFrameKeyForCut(now, linked.id, shown.frameId!),
          ),
      ],
      [true, true],
      reason: '⛔전제: each copy shows its picture',
    );
    expect(heard, 1);
  });
}
