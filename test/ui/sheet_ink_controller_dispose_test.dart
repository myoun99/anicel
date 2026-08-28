import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/conte/conte_sheet_layout.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/envelope/cut_envelope_ink_keys.dart';
import 'package:anicel/src/models/rgba_color.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/services/bitmap_tile_rgba.dart';
import 'package:anicel/src/services/brush_frame_store.dart';
import 'package:anicel/src/ui/conte/conte_ink.dart';
import 'package:anicel/src/ui/envelope/cut_envelope_ink.dart';

/// 🚨★★★CLOSING A SHEET PANEL MID-COMPOSE MUST NOT THROW.
///
/// `displayImageFor` composes a baked surface's tiles asynchronously when
/// they are not GPU-resident yet, and notifies when the image lands. If
/// the panel closes first, that notify hits a disposed `ChangeNotifier` —
/// Flutter throws — and the composed image is stored into a map that
/// `dispose` already cleared.
///
/// 🚨THIS IS THE BUG A COPY HID. The envelope's controller guarded that
/// callback with `_disposed`; the conte's, written first, had no such
/// field. The fix arrived with the envelope (f7b4fd28) and had no reason
/// to touch the conte. The 08-28 audit (유저: 「사본은 특히
/// 위험한대상이야」) found it by diffing the two, not by anything failing.
///
/// ⚠️THE FIRST VERSION OF THIS FILE PROVED NOTHING. It called
/// `displayImageFor` on a controller with no ink, so `bakedSurfaceOrNull`
/// returned null and the method returned on its first line — the async
/// path never ran, and deleting the guard left every test green. A test
/// has to reach the code it claims to hold: these seed a REAL baked
/// surface whose tiles were never uploaded, which is exactly the
/// condition that takes the async branch.
void main() {
  const canvasSize = CanvasSize(width: 16, height: 16);

  /// A surface with one painted tile that has never been uploaded, so the
  /// synchronous compose gives up and the async branch runs.
  BitmapSurface freshSurface() {
    var tile = BitmapTile.blank(coord: TileCoord(x: 0, y: 0), size: 8);
    tile = writeRgbaColorToBitmapTile(
      tile: tile,
      x: 1,
      y: 1,
      color: RgbaColor(r: 255, g: 0, b: 0, a: 255),
    );
    return BitmapSurface(
      canvasSize: canvasSize,
      tileSize: 8,
      tiles: {tile.coord: tile},
    );
  }

  testWidgets('a conte panel closing mid-compose does not throw', (
    tester,
  ) async {
    final pageStore = BrushFrameStore();
    final controller = ConteInkController(pageStore: pageStore);
    controller.syncGeometry(
      const ConteSheetMetrics(pageWidth: 200, pageHeight: 280),
    );
    final key = ConteInkController.pageKey(0);
    pageStore.storeBakedSurface(key, freshSurface());

    await tester.runAsync(() async {
      // Starts the async compose: the tiles are not GPU-resident, so the
      // synchronous path returns null and the future is in flight.
      expect(
        controller.displayImageFor(ConteInkPlane.page, key),
        isNull,
        reason: 'fixture: the async branch is the one under test',
      );
      controller.dispose();
      // Let the compose land on a controller that is already gone.
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
  });

  testWidgets('an envelope panel closing mid-compose does not throw', (
    tester,
  ) async {
    final store = BrushFrameStore();
    final controller = CutEnvelopeInkController(store: store);
    controller.syncGeometry(aspectRatio: 1.4);
    final key = envelopeInkBoxKey(const CutId('c'), 'box');
    store.storeBakedSurface(key, freshSurface());

    await tester.runAsync(() async {
      expect(
        controller.displayImageFor(null, key),
        isNull,
        reason: 'fixture: the async branch is the one under test',
      );
      controller.dispose();
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
  });

  test('the guard lives in ONE place', () {
    // ⛔SOURCE SCAN. Behaviour cannot see the defect this file exists for:
    // two copies that both carry the guard pass, and so do two copies
    // where only one does — until the day the wrong one runs. The
    // invariant worth holding is that there is nothing to keep in sync.
    expect(
      File(
        'lib/src/ui/sheet/sheet_ink_controller.dart',
      ).readAsStringSync().contains('_disposed'),
      isTrue,
      reason: 'the shared controller is where the guard belongs',
    );
    for (final path in const [
      'lib/src/ui/conte/conte_ink.dart',
      'lib/src/ui/envelope/cut_envelope_ink.dart',
    ]) {
      expect(
        File(path).readAsStringSync().contains('_disposed'),
        isFalse,
        reason: '$path must inherit the guard, not carry its own copy',
      );
    }
  });
}
