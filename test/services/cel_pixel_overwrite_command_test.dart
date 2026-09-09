import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/brush_frame_key.dart';
import 'package:anicel/src/models/brush_history_policy.dart';
import 'package:anicel/src/models/canvas_point.dart';
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
import 'package:anicel/src/services/canvas_selection.dart'
    show CanvasSelectionShape;
import 'package:anicel/src/services/canvas_selection_region.dart';
import 'package:anicel/src/services/commands/cel_pixel_overwrite_command.dart';

void main() {
  const canvasSize = CanvasSize(width: 8, height: 8);
  const tileSize = 4;

  BrushFrameKey key(String frameId) => BrushFrameKey(
    projectId: const ProjectId('project'),
    trackId: const TrackId('track'),
    cutId: const CutId('cut'),
    layerId: const LayerId('layer'),
    frameId: FrameId(frameId),
  );

  BrushFrameEditingCoordinator coordinator() => BrushFrameEditingCoordinator(
    initialFrameKey: key('frame-a'),
    frameStore: BrushFrameStore(),
    sessionStore: BrushFrameEditSessionStore(
      canvasSize: canvasSize,
      tileSize: tileSize,
    ),
    historyPolicy: const BrushHistoryPolicy(
      userUndoLimit: 8,
      deferredBakeRatio: 0,
      retainedSessionLimit: 4,
    ),
  );

  /// Paints [rgba] over every pixel of the cel's top-left tile.
  void seed(
    BrushFrameEditingCoordinator target,
    BrushFrameKey frameKey,
    List<int> rgba,
  ) {
    final bytes = Uint8List(tileSize * tileSize * 4);
    for (var pixel = 0; pixel < tileSize * tileSize; pixel += 1) {
      bytes.setRange(pixel * 4, pixel * 4 + 4, rgba);
    }
    target.restoreSurfaceSnapshot(
      frameKey,
      BitmapSurface(
        canvasSize: canvasSize,
        tileSize: tileSize,
        tiles: {
          TileCoord(x: 0, y: 0): BitmapTile(
            size: tileSize,
            pixels: bytes,
          ),
        },
      ),
    );
  }

  List<int> pixelAt(
    BrushFrameEditingCoordinator target,
    BrushFrameKey frameKey,
    int x,
    int y,
  ) {
    final surface = target.currentSurfaceOf(frameKey);
    final tile = surface.tileAt(TileCoord(x: x ~/ tileSize, y: y ~/ tileSize));
    if (tile == null) {
      return const [0, 0, 0, 0];
    }
    final offset = ((y % tileSize) * tileSize + (x % tileSize)) * 4;
    return tile.readPixels(
      (_, view) => List<int>.from(view.sublist(offset, offset + 4)),
    );
  }

  CanvasSelectionRegion rect(double l, double t, double r, double b) =>
      CanvasSelectionRegion.shape(
        CanvasSelectionShape([
          CanvasPoint(x: l, y: t),
          CanvasPoint(x: r, y: t),
          CanvasPoint(x: r, y: b),
          CanvasPoint(x: l, y: b),
        ]),
      );

  test('one step recolours every named cel and one undo brings them back', () {
    final target = coordinator();
    final cels = [key('frame-a'), key('frame-b'), key('frame-c')];
    for (final cel in cels) {
      seed(target, cel, [0, 0, 0, 255]);
    }

    final command = CelPixelOverwriteCommand.replaceColour(
      coordinator: target,
      targets: [for (final cel in cels) CelPixelTarget(key: cel)],
      argb: 0xFFCC2200,
    );

    command.execute();
    for (final cel in cels) {
      expect(pixelAt(target, cel, 1, 1), [0xCC, 0x22, 0x00, 255]);
    }

    command.undo();
    for (final cel in cels) {
      expect(pixelAt(target, cel, 1, 1), [0, 0, 0, 255]);
    }
  });

  test('flat cels make the whole step cost a few bytes', () {
    final target = coordinator();
    final cels = [key('frame-a'), key('frame-b'), key('frame-c')];
    for (final cel in cels) {
      seed(target, cel, [0, 0, 0, 255]);
    }

    final command = CelPixelOverwriteCommand.replaceColour(
      coordinator: target,
      targets: [for (final cel in cels) CelPixelTarget(key: cel)],
      argb: 0xFFCC2200,
    );
    command.execute();

    // Three bytes per cel — the point of the recipe. A surface-snapshot
    // undo would have retained three whole tiles, twice over.
    expect(command.estimatedRetainedBytes(undone: false), 9);
  });

  test('a cel with nothing under the region is left alone', () {
    final target = coordinator();
    final drawn = key('frame-a');
    final empty = key('frame-b');
    seed(target, drawn, [0, 0, 0, 255]);

    final command = CelPixelOverwriteCommand.replaceColour(
      coordinator: target,
      targets: [CelPixelTarget(key: drawn), CelPixelTarget(key: empty)],
      argb: 0xFF00FF00,
    );
    command.execute();

    expect(pixelAt(target, drawn, 0, 0), [0, 255, 0, 255]);
    // Only the drawn cel is in the payload.
    expect(command.estimatedRetainedBytes(undone: false), 3);
    expect(target.currentSurfaceOf(empty).tiles, isEmpty);
  });

  test('a region confines the pass to the pixels it covers', () {
    final target = coordinator();
    final cel = key('frame-a');
    seed(target, cel, [0, 0, 0, 255]);

    CelPixelOverwriteCommand.replaceColour(
      coordinator: target,
      targets: [CelPixelTarget(key: cel, region: rect(0, 0, 2, 2))],
      argb: 0xFFFF0000,
    ).execute();

    expect(pixelAt(target, cel, 0, 0), [255, 0, 0, 255]);
    expect(pixelAt(target, cel, 1, 1), [255, 0, 0, 255]);
    expect(pixelAt(target, cel, 3, 3), [0, 0, 0, 255]);
  });

  test('redo re-runs the pass instead of restoring a stored surface', () {
    final target = coordinator();
    final cel = key('frame-a');
    seed(target, cel, [10, 20, 30, 255]);

    final command = CelPixelOverwriteCommand.replaceColour(
      coordinator: target,
      targets: [CelPixelTarget(key: cel)],
      argb: 0xFF010203,
    );

    command.execute();
    command.undo();
    command.execute();
    expect(pixelAt(target, cel, 2, 2), [1, 2, 3, 255]);

    command.undo();
    expect(pixelAt(target, cel, 2, 2), [10, 20, 30, 255]);
  });

  test('undo uses the region the pass ran with, not the live selection', () {
    final target = coordinator();
    final cel = key('frame-a');
    seed(target, cel, [0, 0, 0, 255]);

    final command = CelPixelOverwriteCommand.replaceColour(
      coordinator: target,
      targets: [CelPixelTarget(key: cel, region: rect(0, 0, 2, 2))],
      argb: 0xFFFF0000,
    );
    command.execute();
    command.undo();

    // The frozen region is why this holds: the command carries its own
    // copy, so nothing the user selects afterwards can move it.
    expect(pixelAt(target, cel, 0, 0), [0, 0, 0, 255]);
    expect(pixelAt(target, cel, 3, 3), [0, 0, 0, 255]);
  });

  test('clearing pixels keeps the colour bytes and undoes exactly', () {
    final target = coordinator();
    final cel = key('frame-a');
    seed(target, cel, [10, 20, 30, 200]);

    final command = CelPixelOverwriteCommand.clearPixels(
      coordinator: target,
      targets: [CelPixelTarget(key: cel)],
    );

    command.execute();
    expect(pixelAt(target, cel, 1, 1), [10, 20, 30, 0]);

    command.undo();
    expect(pixelAt(target, cel, 1, 1), [10, 20, 30, 200]);
  });

  test('the same physical cel named twice is acted on once', () {
    final target = coordinator();
    final cel = key('frame-a');
    seed(target, cel, [0, 0, 0, 255]);

    final command = CelPixelOverwriteCommand.replaceColour(
      coordinator: target,
      targets: [CelPixelTarget(key: cel), CelPixelTarget(key: cel)],
      argb: 0xFF112233,
    );
    command.execute();
    command.undo();

    // A second pass would have recorded 0x112233 as "the original" and
    // undo would have stopped there.
    expect(pixelAt(target, cel, 1, 1), [0, 0, 0, 255]);
    expect(command.estimatedRetainedBytes(undone: false), 3);
  });
}
