import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/a_canvas_standing_on_a_frame.dart';
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
import 'package:anicel/src/services/canvas_flood_fill.dart';
import 'package:anicel/src/services/canvas_selection_region.dart';
import 'package:anicel/src/services/canvas_selection_shape.dart';
import 'package:anicel/src/services/selection_clip.dart';
import 'package:anicel/src/ui/canvas/active_stroke_overlay.dart';
import 'package:anicel/src/ui/canvas/bitmap_surface_painter.dart';
import 'package:anicel/src/ui/canvas/canvas_layer_stack_view.dart';
import 'package:anicel/src/ui/canvas/fill_range_mark.dart';
import 'package:anicel/src/ui/playback/stacked_frame_picture.dart';

/// 🚨★★★A FILL HELD DOWN MARKS ITS RANGE (I-160-Q1 a, 유저 2026-11-04
/// 「TVPaint 처럼 체크 격자」 — 「체크격자가 그림 위에 오는것임. 즉 현재 행
/// 위. 그 위에 레이어있으면 체크격자 가려져서 사라지는거 인지하고있음 …
/// 흰색/검정을 불투명도 50%정도로」): a checker of white and black at half
/// strength over the row the fill lands on, under every row above it,
/// outside the row's own opacity — and a mark that moves is patched where
/// it was and where it is, as a landing preview is.
void main() {
  opensTheEnginesScreens();
  const side = 32;
  const canvasSize = CanvasSize(width: side, height: side);

  BrushFrameKey keyOf(String layer) => BrushFrameKey(
    projectId: const ProjectId('p'),
    trackId: const TrackId('t'),
    cutId: const CutId('c'),
    layerId: LayerId(layer),
    frameId: const FrameId('f'),
  );

  BitmapSurface surfaceOf(Map<TileCoord, BitmapTile> tiles) =>
      onTheEnginesTiles(
        BitmapSurface(canvasSize: canvasSize, tileSize: 16, tiles: tiles),
      );

  /// The mark of a closed, hard range [width]×[height] at ([left], [top]).
  FillRangeMark markOf(int left, int top, int width, int height) =>
      FillRangeMark(
        FillRange.over(
          FloodFillRegion(
            left: left,
            top: top,
            width: width,
            height: height,
            mask: Uint8List(width * height)..fillRange(0, width * height, 255),
          ),
        ).coveredWithin(null)!,
      );

  /// The frame [nodes] stack, the live row drawn by [live].
  StackedFrame frameOf(
    List<CompositeNode<CanvasStackRow>> nodes, {
    required BitmapSurfacePainter live,
    Map<BrushFrameKey, BitmapSurface> cels = const {},
  }) => stackedFrameOf(
    nodes,
    page: (
      canvasSize: canvasSize,
      pasteboardReach: PasteboardReach.whole,
      paintPaper: false,
      paperBackground: ProjectBackground.defaultBackground,
    ),
    surfaceOf: (cel) => cels[cel],
    live: (
      rows: (
        activeSurfacePainter: live,
        floatOverlay: null,
        liftedRows: const {},
      ),
      painters: LiftedRowPainters(),
    ),
  );

  /// [frame] as its picture is laid, its premultiplied bytes.
  Future<Uint8List> bytesOf(WidgetTester tester, StackedFrame frame) async =>
      pixelsOfFrame(frame, const Rect.fromLTWH(0, 0, side * 1.0, side * 1.0));

  List<int> pixelAt(Uint8List bytes, int x, int y) {
    final at = (y * side + x) * 4;
    return bytes.sublist(at, at + 4);
  }

  group('the mark in the stack', () {
    late ActiveStrokeOverlayModel overlay;
    setUp(() => overlay = ActiveStrokeOverlayModel(tileSize: defaultCelTileSize));
    tearDown(() => overlay.dispose());

    BitmapSurfacePainter liveOn(BitmapSurface surface) => BitmapSurfacePainter(
      surface: surface,
      overlayModel: overlay,
      showTransparentBackground: false,
    );

    /// Opaque red over the left half of the canvas — the row above.
    BitmapSurface leftHalfRed() {
      BitmapTile red() {
        final pixels = Uint8List(16 * 16 * 4);
        for (var i = 0; i < pixels.length; i += 4) {
          pixels[i] = 0xFF;
          pixels[i + 3] = 0xFF;
        }
        return BitmapTile(size: 16, pixels: pixels);
      }

      return surfaceOf({
        TileCoord(x: 0, y: 0): red(),
        TileCoord(x: 0, y: 1): red(),
      });
    }

    testWidgets('🚨over the row it lands on, at half strength, UNDER the '
        'row above', (tester) async {
      final above = keyOf('above');
      final nodes = [
        CompositeLeaf<CanvasStackRow>(
          CanvasActiveLayerRow(opacity: 1, frameKey: keyOf('live')),
        ),
        CompositeLeaf<CanvasStackRow>(
          CanvasLayerImageRequest(frameKey: above, opacity: 1),
        ),
      ];
      final live = liveOn(surfaceOf(const {}));
      overlay.showFillRange(markOf(0, 0, side, side));

      final bytes = await bytesOf(
        tester,
        frameOf(nodes, live: live, cels: {above: leftHalfRed()}),
      );

      // Cells of eight from the row's origin: white where the cell's row and
      // column add up even, black where odd — each at half strength.
      expect(
        pixelAt(bytes, 20, 4),
        [0x80, 0x80, 0x80, 0x80],
        reason: 'a white cell at 50% (premultiplied) where nothing is above',
      );
      expect(
        pixelAt(bytes, 28, 4),
        [0, 0, 0, 0x80],
        reason: 'a black cell at 50% beside it',
      );
      expect(
        pixelAt(bytes, 4, 4),
        [0xFF, 0, 0, 0xFF],
        reason: '유저: 「그 위에 레이어있으면 체크격자 가려져서 사라지는거」 — the '
            'row above hides the mark',
      );
    });

    testWidgets('outside the row\'s own opacity — a row at half strength '
        'marks at the same half', (tester) async {
      final nodes = [
        CompositeLeaf<CanvasStackRow>(
          CanvasActiveLayerRow(opacity: 0.5, frameKey: keyOf('live')),
        ),
      ];
      final live = liveOn(surfaceOf(const {}));
      overlay.showFillRange(markOf(0, 0, side, side));

      final bytes = await bytesOf(tester, frameOf(nodes, live: live));

      expect(pixelAt(bytes, 20, 4), [0x80, 0x80, 0x80, 0x80]);
    });

    testWidgets('only over its range, and gone with the lift\'s reset', (
      tester,
    ) async {
      final nodes = [
        CompositeLeaf<CanvasStackRow>(
          CanvasActiveLayerRow(opacity: 1, frameKey: keyOf('live')),
        ),
      ];
      final live = liveOn(surfaceOf(const {}));
      overlay.showFillRange(markOf(8, 8, 8, 8));

      final marked = await bytesOf(tester, frameOf(nodes, live: live));
      expect(pixelAt(marked, 12, 12)[3], 0x80, reason: 'inside the range');
      expect(pixelAt(marked, 20, 20)[3], 0, reason: 'past it');

      overlay.reset();
      expect(overlay.fillRange, isNull, reason: 'the reset clears the mark');
      final reset = await bytesOf(tester, frameOf(nodes, live: live));
      expect(pixelAt(reset, 12, 12)[3], 0, reason: 'nothing marked');
    });

    testWidgets('🚨not in a hole of its range — the checker keeps to the '
        'outline, not to the box around it', (tester) async {
      final nodes = [
        CompositeLeaf<CanvasStackRow>(
          CanvasActiveLayerRow(opacity: 1, frameKey: keyOf('live')),
        ),
      ];
      final live = liveOn(surfaceOf(const {}));
      final mask = Uint8List(16 * 16)..fillRange(0, 256, 255);
      for (var y = 6; y < 10; y += 1) {
        mask.fillRange(y * 16 + 6, y * 16 + 10, 0);
      }
      overlay.showFillRange(
        FillRangeMark(
          FillRange.over(
            FloodFillRegion(left: 8, top: 8, width: 16, height: 16, mask: mask),
          ).coveredWithin(null)!,
        ),
      );

      final bytes = await bytesOf(tester, frameOf(nodes, live: live));
      expect(pixelAt(bytes, 10, 10)[3], 0x80, reason: 'the range');
      expect(pixelAt(bytes, 16, 16)[3], 0, reason: 'its hole');
    });

    testWidgets('🚨its checker pushed as far as the press moved, and the same '
        'way — the outline where it was (F-568-Q1 a, 유저 2026-11-05 「커서가 '
        '움직인 만큼 무늬가 같이 밀린다」)', (tester) async {
      final nodes = [
        CompositeLeaf<CanvasStackRow>(
          CanvasActiveLayerRow(opacity: 1, frameKey: keyOf('live')),
        ),
      ];
      final live = liveOn(surfaceOf(const {}));
      final mark = markOf(0, 0, 16, side);
      Future<Uint8List> pushedBy(Offset shift) {
        overlay.showFillRange(mark.shifted(shift));
        return bytesOf(tester, frameOf(nodes, live: live));
      }

      const white = [0x80, 0x80, 0x80, 0x80];
      const black = [0, 0, 0, 0x80];
      final still = await pushedBy(Offset.zero);
      expect(pixelAt(still, 2, 4), white, reason: 'premise: a white cell');
      expect(pixelAt(still, 10, 4), black, reason: 'premise: a black one');

      final across = await pushedBy(const Offset(3, 0));
      expect(
        pixelAt(across, 2, 4),
        black,
        reason: 'three pixels on, the black cell before it reaches here',
      );
      expect(pixelAt(across, 10, 4), white);

      final down = await pushedBy(const Offset(0, 8));
      expect(pixelAt(down, 2, 4), black, reason: 'a cell down, the rows trade');

      final period = await pushedBy(const Offset(16, 16));
      expect(pixelAt(period, 2, 4), white, reason: 'a whole period: as still');

      expect(
        pixelAt(across, 20, 4),
        [0, 0, 0, 0],
        reason: 'the outline does not go with it: nothing past the range',
      );
    });

    test('🚨a mark that moves is patched where it was and where it is', () {
      final nodes = [
        CompositeLeaf<CanvasStackRow>(
          CanvasActiveLayerRow(opacity: 1, frameKey: keyOf('live')),
        ),
      ];
      final frame = frameOf(nodes, live: liveOn(surfaceOf(const {})));
      final was = markOf(0, 0, 8, 8);

      // It comes: where it is.
      var before = frame.tokens;
      overlay.showFillRange(was);
      var moved = frame.movedSince(before);
      expect(moved.located, isTrue, reason: 'it is a patch');
      expect(moved.dirty, was.bounds.inflate(1));

      // Its checker is pushed (F-568): where it is, the outline unmoved.
      before = frame.tokens;
      overlay.showFillRange(was.shifted(const Offset(3, 0)));
      moved = frame.movedSince(before);
      expect(moved.located, isTrue);
      expect(moved.dirty, was.bounds.inflate(1));

      // It moves to another region: where it was and where it is.
      before = frame.tokens;
      final now = markOf(16, 16, 8, 8);
      overlay.showFillRange(now);
      moved = frame.movedSince(before);
      expect(moved.located, isTrue);
      expect(moved.dirty, was.bounds.expandToInclude(now.bounds).inflate(1));

      // It goes: where it was.
      before = frame.tokens;
      overlay.showFillRange(null);
      moved = frame.movedSince(before);
      expect(moved.located, isTrue);
      expect(moved.dirty, now.bounds.inflate(1));
    });

    testWidgets('a canvas that paints its own row marks it the same', (
      tester,
    ) async {
      final live = liveOn(surfaceOf(const {}));
      overlay.showFillRange(markOf(0, 0, side, side));
      final recorder = ui.PictureRecorder();
      live.paint(Canvas(recorder), const Size(side * 1.0, side * 1.0));
      final picture = recorder.endRecording();
      final image = picture.toImageSync(side, side);
      picture.dispose();
      final data = await tester.runAsync(image.toByteData);
      image.dispose();
      expect(pixelAt(data!.buffer.asUint8List(), 20, 4), [
        0x80,
        0x80,
        0x80,
        0x80,
      ]);
    });

    test('the live row reaches as far as its mark', () {
      final live = liveOn(surfaceOf(const {}));
      expect(live.drawnWorldRect, Rect.zero, reason: 'premise: nothing drawn');
      final mark = markOf(4, 4, 8, 8);
      overlay.showFillRange(mark);
      expect(
        live.drawnWorldRect,
        mark.bounds,
        reason: 'a folder\'s buffer and the frame\'s extent reach it',
      );
    });
  });

  group('the range', () {
    FloodFillRegion square(int left, int top, int side) => FloodFillRegion(
      left: left,
      top: top,
      width: side,
      height: side,
      mask: Uint8List(side * side)..fillRange(0, side * side, 255),
    );

    test('covers what its flood covered, and nothing past it', () {
      final range = FillRange.over(square(10, 20, 4));
      expect(range.covers(CanvasPoint(x: 10, y: 20)), isTrue);
      expect(range.covers(CanvasPoint(x: 13.9, y: 23.9)), isTrue);
      expect(range.covers(CanvasPoint(x: 14, y: 20)), isFalse);
      expect(range.covers(CanvasPoint(x: 9.9, y: 20)), isFalse);
    });

    test('its outline is its pixels\' edge, holes carved', () {
      final mask = Uint8List(6 * 6)..fillRange(0, 36, 255);
      for (final at in [14, 15, 20, 21]) {
        mask[at] = 0;
      }
      final covered = FillRange.over(
        FloodFillRegion(left: 0, top: 0, width: 6, height: 6, mask: mask),
      ).coveredWithin(null)!;
      expect(covered.outline, hasLength(2), reason: 'the square and its hole');
      final path = FillRangeMark(covered).outline;
      expect(path.contains(const Offset(0.5, 0.5)), isTrue);
      expect(path.contains(const Offset(2.5, 2.5)), isFalse, reason: 'hole');
    });

    test('a hole the row scan could step over four pixels at a time is '
        'carved to the pixel', () {
      // Four uncovered pixels on a four-aligned column: a whole word of the
      // mask, which the scan reads at once wherever a row is solid.
      final mask = Uint8List(16 * 3)..fillRange(0, 48, 255);
      mask.fillRange(16 + 8, 16 + 12, 0);
      final contours = FillRange.over(
        FloodFillRegion(left: 0, top: 0, width: 16, height: 3, mask: mask),
      ).coveredWithin(null)!.outline;
      expect(
        [
          for (final contour in contours)
            [for (final point in contour) (point.x, point.y)],
        ],
        [
          [(0.0, 0.0), (16.0, 0.0), (16.0, 3.0), (0.0, 3.0)],
          [(8.0, 1.0), (8.0, 2.0), (12.0, 2.0), (12.0, 1.0)],
        ],
      );
    });

    test('cut by the selection, as the fill is', () {
      final clip = SelectionClip.outline(
        CanvasSelectionRegion.shape(
          CanvasSelectionShape.rect(left: 0, top: 0, right: 3, bottom: 6),
        ),
      );
      final path = FillRangeMark(
        FillRange.over(square(0, 0, 6)).coveredWithin(clip)!,
      ).outline;
      expect(path.contains(const Offset(1.5, 1.5)), isTrue);
      expect(
        path.contains(const Offset(4.5, 1.5)),
        isFalse,
        reason: 'past the selection nothing fills, so nothing is marked',
      );
    });

    test('🚨its cover — what the engine lays its checker under — is 255 on '
        'every pixel its outline holds and 0 elsewhere: a soft edge whole, '
        'words read at once among them (flip lane ⓐ-3)', () {
      // A row covered across three words, a row whose first word is empty,
      // and a row of every coverage there is.
      const width = 12;
      final mask = Uint8List(width * 3)
        ..fillRange(0, width, 255)
        ..fillRange(width + 4, 2 * width, 255);
      for (var x = 0; x < width; x += 1) {
        mask[2 * width + x] = const [0, 1, 128, 255][x % 4];
      }
      final covered = FillRange.over(
        FloodFillRegion(left: 5, top: 7, width: width, height: 3, mask: mask),
      ).coveredWithin(null)!;
      final cover = covered.cover;
      expect(
        (cover.left, cover.top, cover.width, cover.height),
        (5, 7, width, 3),
      );
      expect(cover.mask, [
        for (final byte in mask)
          if (byte > 0) 255 else 0,
      ]);
      final path = FillRangeMark(covered).outline;
      for (var at = 0; at < mask.length; at += 1) {
        final centre = Offset(5 + at % width + 0.5, 7 + at ~/ width + 0.5);
        expect(
          path.contains(centre),
          cover.mask[at] == 255,
          reason: 'pixel $at',
        );
      }
    });

    test('its cover is cut by the selection, as its outline is', () {
      final clip = SelectionClip.outline(
        CanvasSelectionRegion.shape(
          CanvasSelectionShape.rect(left: 0, top: 0, right: 3, bottom: 6),
        ),
      );
      final cover = FillRange.over(
        square(0, 0, 6),
      ).coveredWithin(clip)!.cover;
      expect(cover.mask, [
        for (var at = 0; at < 36; at += 1)
          if (at % 6 < 3) 255 else 0,
      ]);
    });
  });
}
