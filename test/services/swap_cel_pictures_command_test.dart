import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/brush_frame_key.dart';
import 'package:anicel/src/models/brush_history_policy.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/brush_frame_edit_session_store.dart';
import 'package:anicel/src/services/brush_frame_editing_coordinator.dart';
import 'package:anicel/src/services/brush_frame_store.dart';
import 'package:anicel/src/services/commands/swap_cel_pictures_command.dart';

/// F-330 · I-98: a swap trades two cels' PICTURES and leaves the cels.
void main() {
  const canvasSize = CanvasSize(width: 8, height: 8);
  const tileSize = 4;

  BrushFrameKey key(String layer, String frame) => BrushFrameKey(
    projectId: const ProjectId('project'),
    trackId: const TrackId('track'),
    cutId: const CutId('cut'),
    layerId: LayerId(layer),
    frameId: FrameId(frame),
  );

  final a = key('base', 'b1');
  final b = key('rider', 'mirror-b1');
  final c = key('rider', 'mirror-b2');
  final d = key('base', 'b2');

  BrushFrameEditingCoordinator coordinator() => BrushFrameEditingCoordinator(
    initialFrameKey: a,
    frameStore: BrushFrameStore(),
    sessionStore: BrushFrameEditSessionStore(
      canvasSize: canvasSize,
      tileSize: tileSize,
    ),
    historyPolicy: const BrushHistoryPolicy(retainedSessionLimit: 8),
  );

  /// Paints [red] over the cel's top-left tile.
  void seed(BrushFrameEditingCoordinator target, BrushFrameKey cel, int red) {
    final bytes = Uint8List(tileSize * tileSize * 4);
    for (var pixel = 0; pixel < tileSize * tileSize; pixel += 1) {
      bytes.setRange(pixel * 4, pixel * 4 + 4, [red, 0, 0, 255]);
    }
    target.restoreSurfaceSnapshot(
      cel,
      BitmapSurface(
        canvasSize: canvasSize,
        tileSize: tileSize,
        tiles: {
          TileCoord(x: 0, y: 0): BitmapTile(size: tileSize, pixels: bytes),
        },
      ),
    );
  }

  /// The red of the cel's first pixel — 0 for an empty cel.
  int redOf(BrushFrameEditingCoordinator target, BrushFrameKey cel) {
    final tile = target.currentSurfaceOf(cel).tileAt(TileCoord(x: 0, y: 0));
    return tile == null ? 0 : tile.readPixels((_, view) => view[0]);
  }

  test('each cel of a pair takes the other\'s picture, and undo trades '
      'them back', () {
    final target = coordinator();
    seed(target, a, 10);
    seed(target, b, 20);
    seed(target, c, 30);
    seed(target, d, 40);
    final command = SwapCelPicturesCommand(
      coordinator: target,
      pairs: [(a, b), (c, d)],
    );

    command.execute();
    expect([for (final cel in [a, b, c, d]) redOf(target, cel)], [
      20,
      10,
      40,
      30,
    ]);

    command.undo();
    expect([for (final cel in [a, b, c, d]) redOf(target, cel)], [
      10,
      20,
      30,
      40,
    ]);
  });

  test('an empty cel trades too: the drawn one empties, the empty one is '
      'drawn', () {
    final target = coordinator();
    seed(target, a, 10);

    SwapCelPicturesCommand(coordinator: target, pairs: [(a, b)]).execute();

    expect(redOf(target, a), 0);
    expect(redOf(target, b), 10);
  });

  test('a cel named twice is swapped once — the second pair would trade it '
      'back', () {
    final target = coordinator();
    seed(target, a, 10);
    seed(target, b, 20);

    SwapCelPicturesCommand(
      coordinator: target,
      pairs: [(a, b), (b, a), (a, a)],
    ).execute();

    expect(redOf(target, a), 20);
    expect(redOf(target, b), 10);
  });
}
