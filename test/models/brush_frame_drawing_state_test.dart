import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/brush_frame_drawing_state.dart';
import 'package:anicel/src/models/brush_frame_key.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/dirty_tile_set.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/models/track_id.dart';

/// R19 P3b: the drawing state is a pure mutation ledger (revision +
/// cache-dirty bookkeeping) — command lists retired with the raster
/// truth model.
void main() {
  final key = BrushFrameKey(
    projectId: ProjectId('p'),
    trackId: TrackId('t'),
    cutId: CutId('c'),
    layerId: LayerId('l'),
    frameId: FrameId('f'),
  );

  test('copyWith updates the ledger fields and keeps the rest', () {
    final state = BrushFrameDrawingState(key: key, sourceRevision: 3);
    final dirty = DirtyTileSet.empty().add(TileCoord(x: 1, y: 0));

    final next = state.copyWith(
      sourceRevision: 4,
      inactivePreviewDirty: true,
      cacheDirtyTiles: dirty,
    );

    expect(next.key, key);
    expect(next.sourceRevision, 4);
    expect(next.inactivePreviewDirty, isTrue);
    expect(next.cacheDirtyTiles.contains(TileCoord(x: 1, y: 0)), isTrue);
    expect(state.sourceRevision, 3, reason: 'immutable value semantics');
  });

  test('copyWithKey re-homes the cel with bookkeeping unchanged', () {
    final state = BrushFrameDrawingState(
      key: key,
      sourceRevision: 7,
      inactivePreviewDirty: true,
    );
    final moved = state.copyWithKey(
      BrushFrameKey(
        projectId: ProjectId('p'),
        trackId: TrackId('t'),
        cutId: CutId('c'),
        layerId: LayerId('other-layer'),
        frameId: FrameId('f'),
      ),
    );

    expect(moved.key.layerId, LayerId('other-layer'));
    expect(moved.sourceRevision, 7);
    expect(moved.inactivePreviewDirty, isTrue);
  });
}
