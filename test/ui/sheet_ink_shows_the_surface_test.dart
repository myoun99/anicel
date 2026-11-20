import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/brush_frame_key.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/models/conte/conte_sheet_layout.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/envelope/cut_envelope_ink_keys.dart';
import 'package:anicel/src/models/rgba_color.dart';
import 'package:anicel/src/models/sheet_marks.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/models/conte/conte_ink_keys.dart';
import 'package:anicel/src/services/bitmap_tile_rgba.dart';
import 'package:anicel/src/services/brush_frame_store.dart';
import 'package:anicel/src/ui/conte/conte_ink.dart';
import 'package:anicel/src/ui/envelope/cut_envelope_ink.dart';
import 'package:anicel/src/ui/sheet/sheet_ink_controller.dart';
import 'package:anicel/src/ui/sheet/sheet_ink_layer.dart';

import '../helpers/a_canvas_standing_on_a_frame.dart';

/// 🚨★★★A SHEET SHOWS ITS INK'S SURFACE THE MOMENT IT IS THE SURFACE (유저
/// 절대규칙 2026-09-17: 「보이는 중이랑 결과랑 절대로 다르면 안 되」). The
/// controller hands the panel the baked surface itself (`surfaceFor`), and
/// the engine shows it on the window's screen ([SheetInkScreens], F-215) —
/// laid from its tiles, no picture of one made — so a stroke's pen-up, an
/// undo and a redo each show on the frame they happen.
///
/// ↩️THE FILE WAS `sheet_ink_display_image_test` (09-17 → 10-01): the
/// controller composed the surface into one raster, `displayImageFor`, and
/// the panel drew that `medium`-filtered in paper space — the soft, slid
/// ink of F-215. Then (10-01 → 11-18) the panel's print drew it as the
/// brush's live window did (`printSheetInkAsLive`), a picture made of each
/// tile in the draw. The law it held is unchanged; the seam moved.
///
/// 🪦WHAT IT WAS BEFORE THAT (`sheet_ink_controller_dispose_test`, until
/// 2026-09-17): 「closing a sheet panel mid-compose must not throw」. A
/// surface with an unpictured tile was composed ASYNCHRONOUSLY — 「the stale
/// image holds meanwhile」 — and notified when the image landed; if the
/// panel closed first, that notify hit a disposed `ChangeNotifier` and the
/// image leaked into a map `dispose` had already cleared. The envelope's
/// controller guarded the callback with `_disposed`; the conte's, written
/// first, had no such field — THE BUG A COPY HID, found on 08-28 by diffing
/// the two (유저: 「사본은 특히 위험한대상이야」), and fixed by MERGING them
/// into `SheetInkController`. With nothing in flight there is nothing to
/// guard; what stays is the merge, and the last test holds it.
///
/// ⚠️THE FIRST VERSION OF THAT FILE PROVED NOTHING, and the lesson outlives
/// it: it asked a controller with no ink, so the method returned on its
/// first line and deleting the guard left every test green. These seed a
/// REAL baked surface whose tiles were never pictured — exactly the state
/// that used to take the asynchronous road.
void main() {
  opensTheEnginesScreens();
  const canvasSize = CanvasSize(width: 16, height: 16);
  final screen = GlobalKey();

  /// A surface with one painted tile that has never been pictured.
  BitmapSurface freshSurface(RgbaColor color) {
    var tile = BitmapTile.blank(size: 128);
    tile = writeRgbaColorToBitmapTile(tile: tile, x: 1, y: 1, color: color);
    return BitmapSurface(
      canvasSize: canvasSize,
      tileSize: 128,
      tiles: {TileCoord(x: 0, y: 0): tile},
    );
  }

  final red = RgbaColor(r: 255, g: 0, b: 0, a: 255);
  final blue = RgbaColor(r: 0, g: 0, b: 255, a: 255);

  /// [ink]'s surface under [key] shown through a window at the paper's
  /// corner, one surface pixel to a screen pixel — what a panel at 100%
  /// shows of it — and the pixel at (1, 1), the panel built anew at each
  /// ask, as a host rebuilds it.
  Future<List<int>> Function() shownBy(
    WidgetTester tester,
    SheetInkController<Null> ink,
    BrushFrameKey key,
  ) {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    final strokes = SheetInkStrokes();
    addTearDown(strokes.dispose);
    Widget view() => onAScreen(
      screen,
      size: const Size(16, 16),
      under: const Color(0xFF000000),
      view: SheetInkScreens(
        windows: [
          SheetInkWindow(
            id: 'window',
            key: key,
            placement: const SheetInkPlacement(
              window: Rect.fromLTWH(0, 0, 16, 16),
              scale: 1,
            ),
          ),
        ],
        keyPrefix: 'sheet',
        viewport: CanvasViewport(),
        surfaceOf: (window) => ink.surfaceFor(null, window.key),
        strokes: strokes,
        inkChanges: ink,
      ),
    );
    return () async {
      await tester.pumpWidget(view());
      await tester.pump();
      final shot = await shotOf(tester, screen);
      final at = (1 * shot.width + 1) * 4;
      return shot.rgba.sublist(at, at + 4);
    };
  }

  testWidgets('a conte window shows a surface nobody has pictured, at the '
      'paint — and the NEXT surface at the next, never the stale one', (
    tester,
  ) async {
    final rowStore = BrushFrameStore();
    final controller = ConteInkController(rowStore: rowStore);
    addTearDown(controller.dispose);
    controller.syncGeometry(
      const ConteSheetMetrics(pageWidth: 200, pageHeight: 280),
    );
    final key = conteInkRowKey(const CutId('c1'), 'ink-1');
    rowStore.storeBakedSurface(key, freshSurface(red));
    final shown = shownBy(tester, controller, key);

    expect(await shown(), [255, 0, 0, 255], reason: 'nothing to wait for');

    // An undo, a redo, another stroke: a new surface of new tiles.
    rowStore.storeBakedSurface(key, freshSurface(blue));
    expect(
      await shown(),
      [0, 0, 255, 255],
      reason: 'the stale image used to hold here until an asynchronous '
          'compose landed — the undone stroke stayed on the sheet',
    );
  });

  testWidgets('an envelope window does the same', (tester) async {
    final store = BrushFrameStore();
    final controller = CutEnvelopeInkController(store: store);
    addTearDown(controller.dispose);
    controller.syncGeometry(aspectRatio: 1.4);
    final key = envelopeInkBoxKey(const CutId('c'), 'box');
    store.storeBakedSurface(key, freshSurface(red));

    expect(
      await shownBy(tester, controller, key)(),
      [255, 0, 0, 255],
      reason: 'nothing to wait for',
    );
  });

  test('the ink a sheet shows is handed out in ONE place, and nothing there '
      'waits', () {
    // ⛔SOURCE SCAN. Behaviour cannot see the defect the merge was for: two
    // copies that agree pass, and so do two that do not — until the day the
    // wrong one runs. The invariant worth holding is that there is nothing
    // to keep in sync.
    final shared = File(
      'lib/src/ui/sheet/sheet_ink_controller.dart',
    ).readAsStringSync();
    expect(
      shared.contains('surfaceFor('),
      isTrue,
      reason: 'the shared controller hands out the surface',
    );
    for (final path in const [
      'lib/src/ui/conte/conte_ink.dart',
      'lib/src/ui/envelope/cut_envelope_ink.dart',
      'lib/src/ui/timesheet/timesheet_ink_controller.dart',
    ]) {
      final file = File(path);
      if (!file.existsSync()) {
        fail('$path moved: point this scan at the sheet\'s ink controller');
      }
      expect(
        file.readAsStringSync().contains('surfaceFor('),
        isFalse,
        reason: '$path must inherit the surface, not carry a copy',
      );
    }
  });
}
