import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/brush_frame_key.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/composite_tree.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/pasteboard_bounds.dart';
import 'package:anicel/src/models/project_background.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/guide_geometry.dart';
import 'package:anicel/src/ui/canvas/bitmap_surface_painter.dart';
import 'package:anicel/src/ui/canvas/canvas_layer_stack_view.dart';
import 'package:anicel/src/ui/canvas/selection_float_overlay.dart';
import 'package:anicel/src/ui/playback/stacked_frame_picture.dart';

/// 🚨★★★A FLOAT OR A LIFT IN HAND IS TOLD WHERE IT MOVED — the selection
/// floated in the live row's slot, and the rows a lift holds beside it — as
/// the text in hand is (F-344, `a_landing_preview_moves_by_patch_test`): by
/// value, beside where its slot draws it, so a step of the hand patches
/// where it was and where it is into the frame's picture.
///
/// ↩️Neither was told, and while either was in hand the frame was drawn as
/// it stands, whole, at every step (`_FrameRows._liveCanBeTold`). 🔬The
/// Surface Pro 11 paid 22 ms a frame's build for it, ≈19 ms of it the UI
/// thread waiting on the GPU for the whole frame composed again
/// (a-float-in-hand-draws-the-frame-as-it-stands, 2026-11-12).
///
/// What the canvas shows of it is `float_drag_is_never_cached_test`'s.
void main() {
  const tileSide = defaultCelTileSize;
  const side = 2 * tileSide;
  const canvasSize = CanvasSize(width: side, height: side);
  const page = (
    canvasSize: canvasSize,
    pasteboardReach: PasteboardReach.whole,
    paintPaper: false,
    paperBackground: ProjectBackground.defaultBackground,
  );
  const tile = Rect.fromLTWH(0, 0, tileSide * 1.0, tileSide * 1.0);

  BrushFrameKey keyOf(String layer) => BrushFrameKey(
    projectId: const ProjectId('p'),
    trackId: const TrackId('t'),
    cutId: const CutId('c'),
    layerId: LayerId(layer),
    frameId: const FrameId('f'),
  );

  /// One tile of red ink at the pixels [inked] says, clear elsewhere.
  BitmapTile tileOf(bool Function(int x, int y) inked) {
    final pixels = Uint8List(tileSide * tileSide * 4);
    for (var y = 0; y < tileSide; y += 1) {
      for (var x = 0; x < tileSide; x += 1) {
        if (inked(x, y)) {
          pixels.setRange(
            (y * tileSide + x) * 4,
            (y * tileSide + x) * 4 + 4,
            const [0xFF, 0, 0, 0xFF],
          );
        }
      }
    }
    return BitmapTile(size: tileSide, pixels: pixels);
  }

  BitmapSurface surfaceOf(Map<TileCoord, BitmapTile> tiles) =>
      BitmapSurface(canvasSize: canvasSize, tileSize: tileSide, tiles: tiles);

  // What a lift takes up: a 4×4 square at the far corner of the first
  // tile, moved by whole pixels — a selection's pure move.
  final liftedInk = tileOf((x, y) => x >= tileSide - 4 && y >= tileSide - 4);
  final carried = BitmapSurfacePainter(
    surface: surfaceOf({TileCoord(x: 0, y: 0): liftedInk}),
    showTransparentBackground: false,
  );
  SelectionFloatPaint floatAt(double x, double y) => SelectionFloatPaint(
    surface: carried,
    surfaceOffset: CanvasPoint(x: x, y: y),
  );

  // The cel the lift is taken from: that square, and ink of its own on
  // the far tile, which the lift leaves where it is — the same tile in
  // the cel as stored and in the cel as the lift holes it.
  final kept = tileOf((x, y) => x == 0 && y == 0);
  final stored = surfaceOf({
    TileCoord(x: 0, y: 0): liftedInk,
    TileCoord(x: 1, y: 1): kept,
  });
  final holed = surfaceOf({TileCoord(x: 1, y: 1): kept});

  group('the selection floated in the live row\'s slot', () {
    StackedFrame liveRowWith(SelectionFloatOverlay float) => stackedFrameOf(
      const [CompositeLeaf<CanvasStackRow>(CanvasActiveLayerRow(opacity: 1))],
      page: page,
      surfaceOf: (_) => null,
      live: (
        rows: (
          activeSurfacePainter: BitmapSurfacePainter(
            surface: holed,
            showTransparentBackground: false,
          ),
          floatOverlay: float,
          liftedRows: const {},
        ),
        painters: LiftedRowPainters(),
      ),
    );

    test('a step of the hand is where it was and where it is, one pixel of '
        'hairline', () {
      final float = SelectionFloatOverlay(floatAt(2, 2));
      addTearDown(float.dispose);
      final frame = liveRowWith(float);
      final before = frame.tokens;
      final was = float.value!.drawnWorldRect;

      float.value = floatAt(10, 8);
      final moved = frame.movedSince(before);

      expect(moved.located, isTrue, reason: 'it is a patch');
      expect(
        moved.dirty,
        was.expandToInclude(float.value!.drawnWorldRect).inflate(1),
      );
    });

    test('🚨a float handed again where it was is no change — told by its '
        'value, not by the one shown', () {
      final float = SelectionFloatOverlay(floatAt(2, 2));
      addTearDown(float.dispose);
      final frame = liveRowWith(float);
      final before = frame.tokens;

      float.value = floatAt(2, 2);
      final moved = frame.movedSince(before);

      expect(moved.located, isTrue);
      expect(moved.dirty, isNull, reason: 'nothing moved, nothing goes in');
    });

    test('🚨on a row posed off its place, a step is where it was and where it '
        'is on the canvas — the float is told in canvas space', () {
      // a-marquee-on-a-posed-row: the box moves the float on the canvas,
      // whatever the row's pose; the slot takes it in through the pose
      // undone, and the pose lays it back where the box is.
      final float = SelectionFloatOverlay(floatAt(2, 2));
      addTearDown(float.dispose);
      final frame = stackedFrameOf(
        const [
          CompositeLeaf<CanvasStackRow>(
            CanvasActiveLayerRow(
              opacity: 1,
              placement: GuideTransform(1, 0, 0, 1, 3, 0),
            ),
          ),
        ],
        page: page,
        surfaceOf: (_) => null,
        live: (
          rows: (
            activeSurfacePainter: BitmapSurfacePainter(
              surface: holed,
              showTransparentBackground: false,
            ),
            floatOverlay: float,
            liftedRows: const {},
          ),
          painters: LiftedRowPainters(),
        ),
      );
      final before = frame.tokens;
      final was = float.value!.drawnWorldRect;

      float.value = floatAt(10, 8);
      final moved = frame.movedSince(before);

      expect(moved.located, isTrue, reason: 'it is a patch');
      expect(
        moved.dirty,
        was.expandToInclude(float.value!.drawnWorldRect).inflate(1),
      );
    });

    test('🚨the live row gone from under the pen is not told — what it drew '
        'is no cel\'s', () {
      final float = SelectionFloatOverlay(floatAt(2, 2));
      addTearDown(float.dispose);
      final drawn = liveRowWith(float);
      final gone = stackedFrameOf(
        const [CompositeLeaf<CanvasStackRow>(CanvasActiveLayerRow(opacity: 1))],
        page: page,
        surfaceOf: (_) => null,
        live: (
          rows: (
            activeSurfacePainter: null,
            floatOverlay: null,
            liftedRows: const {},
          ),
          painters: LiftedRowPainters(),
        ),
      );

      expect(gone.movedSince(drawn.tokens).located, isFalse);
    });
  });

  group('the rows a lift holds beside the live one', () {
    final cel = keyOf('lifted');
    final nodes = [
      CompositeLeaf<CanvasStackRow>(
        CanvasLayerImageRequest(frameKey: cel, opacity: 1),
      ),
    ];
    final painters = LiftedRowPainters();

    StackedFrame frameWith(
      Map<BrushFrameKey, LiftedCel> lifted, {
      bool inHand = true,
    }) => stackedFrameOf(
      nodes,
      page: page,
      surfaceOf: (key) => inHand && key == cel ? stored : null,
      live: (
        rows: (
          activeSurfacePainter: null,
          floatOverlay: null,
          liftedRows: lifted,
        ),
        painters: painters,
      ),
    );

    test('a step of the hand is where it was and where it is', () {
      final float = SelectionFloatOverlay(floatAt(2, 2));
      addTearDown(float.dispose);
      final frame = frameWith({cel: (surface: holed, float: float)});
      final before = frame.tokens;
      final was = float.value!.drawnWorldRect;

      float.value = floatAt(10, 8);
      final moved = frame.movedSince(before);

      expect(moved.located, isTrue, reason: 'it is a patch');
      expect(
        moved.dirty,
        was.expandToInclude(float.value!.drawnWorldRect).inflate(1),
      );
    });

    test('🚨taken up, it is what it shows against its cel as stored — and '
        'let go, the same, from the other side', () {
      final float = SelectionFloatOverlay(floatAt(0, 0));
      addTearDown(float.dispose);
      final none = frameWith(const {});
      final lifted = frameWith({cel: (surface: holed, float: float)});
      // The tile the lift holed, and the float where it was lifted from
      // inside it; not the far tile, which the lift left as it was.
      final holedTile = tile.inflate(1);

      final takenUp = lifted.movedSince(none.tokens);
      expect(takenUp.located, isTrue, reason: 'it is a patch');
      expect(takenUp.dirty, holedTile);

      final letGo = none.movedSince(lifted.tokens);
      expect(letGo.located, isTrue, reason: 'it is a patch');
      expect(letGo.dirty, holedTile);
    });

    test('🚨let go where the hand carried it, where it was is patched too — '
        'no cel holds it there', () {
      // Carried onto the far tile, which neither the cel as stored nor the
      // lift's hole tells apart.
      final float = SelectionFloatOverlay(floatAt(8, 8));
      addTearDown(float.dispose);
      final lifted = frameWith({cel: (surface: holed, float: float)});
      final carriedTo = float.value!.drawnWorldRect;

      final letGo = frameWith(const {}).movedSince(lifted.tokens);

      expect(letGo.located, isTrue, reason: 'it is a patch');
      expect(letGo.dirty, tile.expandToInclude(carriedTo).inflate(1));
    });

    test('a cel taken up that is not in hand is not told — the frame is drawn '
        'as it stands', () {
      final float = SelectionFloatOverlay(floatAt(0, 0));
      addTearDown(float.dispose);
      final none = frameWith(const {}, inHand: false);
      final lifted = frameWith({
        cel: (surface: holed, float: float),
      }, inHand: false);

      expect(lifted.movedSince(none.tokens).located, isFalse);
    });
  });
}
