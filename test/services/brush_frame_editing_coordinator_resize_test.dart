import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/brush_dab.dart';
import 'package:anicel/src/models/brush_frame_key.dart';
import 'package:anicel/src/models/brush_history_policy.dart';
import 'package:anicel/src/models/brush_tip_shape.dart';
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

void main() {
  const canvasSize = CanvasSize(width: 8, height: 8);

  BrushFrameKey key(String frameId) => BrushFrameKey(
    projectId: const ProjectId('project'),
    trackId: const TrackId('track'),
    cutId: const CutId('cut'),
    layerId: const LayerId('layer'),
    frameId: FrameId(frameId),
  );

  BrushFrameEditingCoordinator coordinator() {
    return BrushFrameEditingCoordinator(
      initialFrameKey: key('frame-a'),
      frameStore: BrushFrameStore(),
      sessionStore: BrushFrameEditSessionStore(
        canvasSize: canvasSize,
        tileSize: 4,
      ),
      historyPolicy: const BrushHistoryPolicy(
        userUndoLimit: 8,
        deferredBakeRatio: 0,
      ),
    );
  }

  group('resizeCanvas', () {
    test('rebuilds the active session surface at the new size', () {
      final c = coordinator();
      c.commitSourceStroke(sourceDabs: [_dab(x: 1, y: 1)]);
      expect(_alphaAt(c, x: 1, y: 1), greaterThan(0));

      c.resizeCanvas(const CanvasSize(width: 12, height: 12), cutId: const CutId('cut'));

      final surface = c.activeSessionState.canvasState.currentSurface;
      expect(surface.canvasSize, const CanvasSize(width: 12, height: 12));
      expect(_alphaAt(c, x: 1, y: 1), greaterThan(0));
    });

    test('shrinking crops the raster (PS semantics) — surviving pixels '
        'stay byte-true; the resize COMMAND owns restoration via its '
        'reference snapshot', () {
      final c = coordinator();
      // One dab inside the shrunken bounds, one outside.
      c.commitSourceStroke(sourceDabs: [_dab(x: 1, y: 1)]);
      c.commitSourceStroke(sourceDabs: [_dab(x: 6, y: 6)]);

      c.resizeCanvas(const CanvasSize(width: 4, height: 4), cutId: const CutId('cut'));
      expect(_alphaAt(c, x: 1, y: 1), greaterThan(0));
      expect(
        c.activeSessionState.canvasState.currentSurface.canvasSize,
        const CanvasSize(width: 4, height: 4),
      );

      // Growing back keeps the surviving content; the cropped tile is
      // gone (raster truth — ResizeCutCanvasCommand's undo restores it).
      c.resizeCanvas(canvasSize, cutId: const CutId('cut'));
      expect(_alphaAt(c, x: 1, y: 1), greaterThan(0));
    });

    test('same size is a no-op that keeps session state', () {
      final c = coordinator();
      c.commitSourceStroke(sourceDabs: [_dab(x: 1, y: 1)]);
      final before = c.activeSessionState;

      c.resizeCanvas(canvasSize, cutId: const CutId('cut'));

      expect(identical(c.activeSessionState, before), isTrue);
    });

    test('no display cache survives a resize at the OLD size', () {
      final c = coordinator();
      final frameA = c.activeFrameKey;
      c.commitSourceStroke(sourceDabs: [_dab(x: 1, y: 1)]);
      c.selectFrame(key('frame-b'));
      c.commitSourceStroke(sourceDabs: [_dab(x: 2, y: 2)]);
      expect(c.frameStore.hasValidDisplayCache(frameA), isTrue);

      c.resizeCanvas(const CanvasSize(width: 12, height: 12), cutId: const CutId('cut'));

      // The active frame's session rebuild immediately donates a fresh
      // preview at the NEW size…
      final active = c.frameStore.displayCacheOrNull(c.activeFrameKey)!;
      expect(active.isValid, isTrue);
      expect(
        active.previewSurface.canvasSize,
        const CanvasSize(width: 12, height: 12),
      );
      // …while inactive frames' old-size caches are simply dropped (they
      // rebuild lazily on selection).
      expect(c.frameStore.displayCacheOrNull(frameA), isNull);
    });

    test('inactive frames rebuild lazily when selected after resize', () {
      final c = coordinator();
      c.commitSourceStroke(sourceDabs: [_dab(x: 1, y: 1)]);
      c.selectFrame(key('frame-b'));
      c.commitSourceStroke(sourceDabs: [_dab(x: 2, y: 2)]);

      c.resizeCanvas(const CanvasSize(width: 12, height: 12), cutId: const CutId('cut'));
      c.selectFrame(key('frame-a'));

      expect(
        c.activeSessionState.canvasState.currentSurface.canvasSize,
        const CanvasSize(width: 12, height: 12),
      );
      expect(_alphaAt(c, x: 1, y: 1), greaterThan(0));
    });
  });
}

BrushDab _dab({required int x, required int y}) => BrushDab(
  center: CanvasPoint(x: x.toDouble(), y: y.toDouble()),
  color: 0xFF000000,
  size: 2,
  opacity: 1,
  flow: 1,
  hardness: 1,
  tipShape: BrushTipShape.round,
  pressure: 1,
  sequence: 0,
);

int _alphaAt(
  BrushFrameEditingCoordinator coordinator, {
  required int x,
  required int y,
}) {
  final surface = coordinator.activeSessionState.canvasState.currentSurface;
  final tileSize = surface.tileSize;
  final tile = surface.tileAt(TileCoord(x: x ~/ tileSize, y: y ~/ tileSize));
  if (tile == null) {
    return 0;
  }
  final offset = tile.byteOffsetForPixel(x: x % tileSize, y: y % tileSize);
  return tile.pixels[offset + 3];
}
