import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/services/brush_frame_editing_coordinator.dart';
import 'package:anicel/src/ui/brush/brush_canvas_panel.dart';
import 'package:anicel/src/ui/brush/brush_edit_cache_invalidation_sink.dart';
import 'package:anicel/src/ui/canvas/active_stroke_overlay.dart';
import 'package:anicel/src/ui/canvas/bitmap_surface_painter.dart';

import '../../helpers/brush_canvas_fixture.dart';

/// 유저 2026-08-27, 실기: 「여전히 해당 프레임에서 픽셀삭제누르면 반영안됨.
/// 캔버스 여전히 그림 남아있음. **다만 타임라인 재 굽기 들어가는거보면 역시
/// 데이터적으로는 삭제 잘 한거 맞음**」 — and 「인덱스 이동하거나 액티브레이어
/// 바꾸거나 툴 바꾸거나」 made it appear, because all three rebuild the panel.
///
/// A stroke commit never had this problem, and not for any reason of its own:
/// the panel MAKES a stroke commit, so it calls `setState` itself, its build
/// re-evaluates the active surface painter, the memo token no longer matches
/// the store's surface, and a new painter goes down. 색 변환 and 픽셀 비우기
/// are pressed on the TIMELINE — same coordinator, same write, same
/// invalidation — and nothing rebuilt the widget that draws.
void main() {
  BitmapSurface surfaceOf(BrushFrameEditingCoordinator coordinator, int alpha) {
    final size = coordinator.currentSurfaceOf(coordinator.activeFrameKey);
    final pixels = Uint8List(16 * 16 * 4);
    for (var i = 3; i < pixels.length; i += 4) {
      pixels[i] = alpha;
    }
    return BitmapSurface(
      canvasSize: size.canvasSize,
      tileSize: 16,
      tiles: {
        TileCoord(x: 0, y: 0): BitmapTile(
          coord: TileCoord(x: 0, y: 0),
          size: 16,
          pixels: pixels,
        ),
      },
    );
  }

  testWidgets(
    'a cel edit made from OUTSIDE the panel reaches the canvas — 유저: '
    '「픽셀삭제누르면 반영안됨. 캔버스 여전히 그림 남아있음」',
    (tester) async {
      final frameKeys = BrushCanvasFixture.createFrameKeys();
      final coordinator = BrushCanvasFixture.createCoordinator(
        frameKeys: frameKeys,
      );
      final overlay = ActiveStrokeOverlayModel();
      addTearDown(overlay.dispose);
      // What the panel HANDS the canvas to draw the active layer with — the
      // composite tree is built by the editor, not reachable from a fixture,
      // and this is the value that travels into it.
      //
      // ⛔Not the store's surface: the store was right the whole time
      // (유저: 「데이터적으로는 삭제 잘 한거 맞음」). What was wrong is what
      // the canvas had in hand.
      BitmapSurfacePainter? handed;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BrushCanvasPanel(
              coordinator: coordinator,
              availableFrameKeys: frameKeys,
              cacheInvalidationSink: BrushEditCacheInvalidationSink(),
              // MERGED mode. The active layer only gets a painter of its own
              // here, and that painter is the thing under test.
              activeStrokeOverlayModel: overlay,
              viewportUnderlayBuilder: (context, viewport, painter, float) {
                handed = painter;
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Seed a drawing the way the store holds one, and let the panel adopt
      // it — this is the picture the user is looking at.
      final drawn = surfaceOf(coordinator, 0xFF);
      coordinator.restoreSurfaceSnapshot(coordinator.activeFrameKey, drawn);
      await tester.pumpAndSettle();
      expect(
        handed?.surface,
        same(drawn),
        reason: 'the fixture has to be drawing the seeded surface, or the '
            'assertion below is measuring an empty canvas',
      );

      // 🚨THE PRESS, exactly as the timeline makes it: the same coordinator,
      // a new surface, ⛔and no setState on the panel — nobody outside it can
      // call one.
      final cleared = surfaceOf(coordinator, 0x00);
      coordinator.restoreSurfaceSnapshot(coordinator.activeFrameKey, cleared);
      await tester.pumpAndSettle();

      expect(
        handed?.surface,
        same(cleared),
        reason: 'the canvas draws what the store holds, whoever wrote it — '
            'a memo bound to the pre-edit surface is the drawing the user '
            'already deleted',
      );
    },
  );
}
