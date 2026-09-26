import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/conte/conte_sheet_layout.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/envelope/cut_envelope_ink_keys.dart';
import 'package:anicel/src/models/rgba_color.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/models/conte/conte_ink_keys.dart';
import 'package:anicel/src/services/bitmap_tile_rgba.dart';
import 'package:anicel/src/services/brush_frame_store.dart';
import 'package:anicel/src/ui/conte/conte_ink.dart';
import 'package:anicel/src/ui/envelope/cut_envelope_ink.dart';

/// 🚨★★★A SHEET'S DISPLAY IMAGE IS THE SURFACE'S PICTURE THE MOMENT IT IS
/// THE SURFACE (유저 절대규칙 2026-09-17: 「보이는 중이랑 결과랑 절대로 다르면
/// 안 되」). `displayImageFor` composes the baked surface inside the call —
/// a tile that has no picture gets one made there, through the one door —
/// so a stroke's pen-up, an undo and a redo each show on the frame they
/// happen.
///
/// 🪦WHAT THIS FILE USED TO BE (`sheet_ink_controller_dispose_test`, until
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
/// it: it called `displayImageFor` on a controller with no ink, so the
/// method returned on its first line and deleting the guard left every test
/// green. These seed a REAL baked surface whose tiles were never pictured —
/// exactly the state that used to take the asynchronous road.
void main() {
  const canvasSize = CanvasSize(width: 16, height: 16);

  /// A surface with one painted tile that has never been pictured.
  BitmapSurface freshSurface(RgbaColor color) {
    var tile = BitmapTile.blank(size: 8);
    tile = writeRgbaColorToBitmapTile(tile: tile, x: 1, y: 1, color: color);
    return BitmapSurface(
      canvasSize: canvasSize,
      tileSize: 8,
      tiles: {TileCoord(x: 0, y: 0): tile},
    );
  }

  final red = RgbaColor(r: 255, g: 0, b: 0, a: 255);
  final blue = RgbaColor(r: 0, g: 0, b: 255, a: 255);

  Future<List<int>> pixelAt(ui.Image image, int x, int y) async {
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    final bytes = data!.buffer.asUint8List();
    final o = (y * image.width + x) * 4;
    return [bytes[o], bytes[o + 1], bytes[o + 2], bytes[o + 3]];
  }

  testWidgets('a conte window shows a surface nobody has pictured, in the '
      'call — and the NEXT surface on the next ask, never the stale one', (
    tester,
  ) async {
    final pageStore = BrushFrameStore();
    final controller = ConteInkController(pageStore: pageStore);
    controller.syncGeometry(
      const ConteSheetMetrics(pageWidth: 200, pageHeight: 280),
    );
    final key = conteInkPageKey(0);
    pageStore.storeBakedSurface(key, freshSurface(red));

    await tester.runAsync(() async {
      final first = controller.displayImageFor(ConteInkPlane.page, key);
      expect(first, isNotNull, reason: 'nothing to wait for');
      expect(await pixelAt(first!, 1, 1), [255, 0, 0, 255]);
      expect(
        identical(controller.displayImageFor(ConteInkPlane.page, key), first),
        isTrue,
        reason: 'kept while the surface stands',
      );

      // An undo, a redo, another stroke: a new surface of new tiles.
      pageStore.storeBakedSurface(key, freshSurface(blue));
      final second = controller.displayImageFor(ConteInkPlane.page, key);
      expect(
        await pixelAt(second!, 1, 1),
        [0, 0, 255, 255],
        reason: 'the stale image used to hold here until an asynchronous '
            'compose landed — the undone stroke stayed on the sheet',
      );

      // Closing right after: nothing is in flight to land on a controller
      // that is gone.
      controller.dispose();
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
  });

  testWidgets('an envelope window does the same', (tester) async {
    final store = BrushFrameStore();
    final controller = CutEnvelopeInkController(store: store);
    controller.syncGeometry(aspectRatio: 1.4);
    final key = envelopeInkBoxKey(const CutId('c'), 'box');
    store.storeBakedSurface(key, freshSurface(red));

    await tester.runAsync(() async {
      final image = controller.displayImageFor(null, key);
      expect(image, isNotNull, reason: 'nothing to wait for');
      expect(await pixelAt(image!, 1, 1), [255, 0, 0, 255]);
      controller.dispose();
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
  });

  test('the display image is made in ONE place, and nothing there waits', () {
    // ⛔SOURCE SCAN. Behaviour cannot see the defect the merge was for: two
    // copies that agree pass, and so do two that do not — until the day the
    // wrong one runs. The invariant worth holding is that there is nothing
    // to keep in sync.
    final shared = File(
      'lib/src/ui/sheet/sheet_ink_controller.dart',
    ).readAsStringSync();
    expect(
      shared.contains('composeTiledSurfaceImageNow('),
      isTrue,
      reason: 'the shared controller composes in the call',
    );
    expect(
      shared.contains('composeTiledSurfaceImage('),
      isFalse,
      reason: 'and has no asynchronous compose to hold a stale image for',
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
        file.readAsStringSync().contains('displayImageFor('),
        isFalse,
        reason: '$path must inherit the display image, not carry a copy',
      );
    }
  });
}
