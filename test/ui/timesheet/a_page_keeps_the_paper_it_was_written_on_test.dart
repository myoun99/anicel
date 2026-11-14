// 🗣️F-252 (유저 2026-10-01): 「잉크는 용지에 귀속됨 … 내용물이 뭐가
// 바뀌던 독립적」 — and since 11-05 each cut prints on a paper of its own
// (its sheet kind; an XDTS sheet as wide as its columns).
//
// A PAGE KEEPS THE PAPER IT WAS WRITTEN ON until a brush comes to it: a
// plane moving to another cut's paper rewrites no cel
// (`BrushFrameEditingCoordinator._laysCelsOnItsCanvas`), and the cel a
// window does seed is laid on the paper with every tile behind the wall
// kept. ↩️Every cel of every cut was laid on the paper last shown, as the
// panel built — a kept one unpacked, laid and packed again on the UI
// thread, and its export cropped to that paper (card a-sheet-ink-resized-
// as-its-panel-builds-rewrites-kept-cels-on-the-ui-thread, 2026-11-14).
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/brush_dab.dart';
import 'package:anicel/src/models/brush_tip_shape.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/cut_metadata.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/models/timesheet_document.dart';
import 'package:anicel/src/models/timesheet_ink_keys.dart';
import 'package:anicel/src/models/timesheet_sheet_kind.dart';
import 'package:anicel/src/services/brush_frame_store.dart';
import 'package:anicel/src/services/brush_stroke_commit_data.dart';
import 'package:anicel/src/services/history_manager.dart';
import 'package:anicel/src/ui/export/sheet_ink_picture.dart';
import 'package:anicel/src/ui/timesheet/timesheet_document_painter.dart';
import 'package:anicel/src/ui/timesheet/timesheet_ink_controller.dart';

import '../../helpers/cels_kept_in_a_file.dart';

const _wideCut = CutId('wide');
const _narrowCut = CutId('narrow');

TimesheetDocumentLayout _layout(CutId cut, TimesheetSheetKind kind) =>
    TimesheetDocumentLayout(
      document: TimesheetDocument.fromCut(
        cut: Cut(
          id: cut,
          name: '1',
          duration: 24,
          canvasSize: const CanvasSize(width: 1920, height: 1080),
          metadata: CutMetadata(sheetKind: kind),
          layers: const [],
        ),
        projectName: 'P',
        fps: 24,
      ),
    );

/// Our A3 sheet, and a B4 viewer's — narrower AND shorter.
const _wideKind = TimesheetSheetKind.sixSeconds;
const _narrowKind = TimesheetSheetKind.xdtsB4SixSeconds;

BrushStrokeCommitData _dabAt(double x, double y) => BrushStrokeCommitData(
  sourceDabs: [
    BrushDab(
      center: CanvasPoint(x: x, y: y),
      color: 0xFF000000,
      size: 6,
      opacity: 1,
      flow: 1,
      hardness: 1,
      tipShape: BrushTipShape.round,
      pressure: 1,
      sequence: 0,
    ),
  ],
);

/// The tile [size]'s last pixel stands in.
TileCoord _cornerTileOf(CanvasSize size) => TileCoord(
  x: (size.width - 1) ~/ defaultCelTileSize,
  y: (size.height - 1) ~/ defaultCelTileSize,
);

/// A page inked solid in the tile [size]'s last pixel stands in.
BitmapSurface _inkedToTheCorner(CanvasSize size) => BitmapSurface(
  canvasSize: size,
  tileSize: defaultCelTileSize,
  tiles: {
    _cornerTileOf(size): BitmapTile(
      size: defaultCelTileSize,
      pixels: Uint8List(defaultCelTileSize * defaultCelTileSize * 4)
        ..fillRange(0, defaultCelTileSize * defaultCelTileSize * 4, 255),
    ),
  },
);

void main() {
  final wide = _layout(_wideCut, _wideKind).paperPixelSize;
  final narrow = _layout(_narrowCut, _narrowKind).paperPixelSize;

  test('⛔premise: the second paper is narrower and shorter, and the first '
      'one\'s corner tile lies past it', () {
    expect(narrow.width, lessThan(wide.width));
    expect(narrow.height, lessThan(wide.height));
    final corner = _cornerTileOf(wide);
    expect(corner.x * defaultCelTileSize, greaterThanOrEqualTo(narrow.width));
    expect(corner.y * defaultCelTileSize, greaterThanOrEqualTo(narrow.height));
  });

  group('another cut\'s page, kept in its file at its own paper', () {
    final page = timesheetInkPageKey(_wideCut, 0);

    /// [page] kept in a file, and the plane gone over to the narrow cut
    /// with its window seeded — the store the export then reads.
    BrushFrameStore shownTheNarrowCut() {
      final store = BrushFrameStore();
      keepInAFile(store, {page: _inkedToTheCorner(wide)});
      final controller = TimesheetInkController(store: store);
      addTearDown(controller.dispose);
      controller.syncGeometry(_layout(_wideCut, _wideKind));
      controller.syncGeometry(_layout(_narrowCut, _narrowKind));
      controller.sessionStateFor(null, timesheetInkPageKey(_narrowCut, 0));
      return store;
    }

    test('is not rewritten when the plane goes over to a cut on another '
        'paper', () {
      final store = shownTheNarrowCut();
      expect(store.isCelFileBacked(page), isTrue, reason: 'still its file');
      expect(store.isCelCold(page), isFalse, reason: 'not parked anew');
      expect(
        store.dirtyCelKeysSinceSave,
        isNot(contains(page)),
        reason: 'nothing written',
      );
    });

    testWidgets('exports to its own paper\'s corner, as the export reads it '
        '(a look, pictured)', (tester) async {
      await tester.runAsync(() async {
        final store = shownTheNarrowCut();
        final surface = store.bakedSurfaceOrNull(page, read: CelRead.look)!;
        final picture = await sheetInkPictureOf(surface);
        try {
          expect((picture.width, picture.height), (wide.width, wide.height));
          final data = await picture.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          );
          final corner = ((wide.height - 1) * wide.width + wide.width - 1) * 4;
          expect(
            data!.getUint8(corner + 3),
            255,
            reason: 'the ink in the far corner is printed',
          );
        } finally {
          picture.dispose();
        }
      });
    });
  });

  group('a page written on from another paper keeps every tile it was not '
      'written on, byte for byte', () {
    final page = timesheetInkPageKey(_wideCut, 0);

    /// [page] inked at [first]'s far corner, written on at its top-left
    /// from [second], then seeded on [first] again: what it was, and what
    /// it is.
    (BitmapSurface, BitmapSurface) writtenOnFrom(
      TimesheetSheetKind first,
      TimesheetSheetKind second,
    ) {
      final controller = TimesheetInkController();
      addTearDown(controller.dispose);
      final history = HistoryManager();
      final firstLayout = _layout(_wideCut, first);
      final paper = firstLayout.paperPixelSize;
      controller.syncGeometry(firstLayout);
      controller.commitStroke(
        plane: null,
        key: page,
        strokeData: _dabAt(paper.width - 8, paper.height - 8),
        historyManager: history,
      );
      final before = controller.surfaceFor(null, page)!;
      controller.syncGeometry(_layout(_wideCut, second));
      controller.commitStroke(
        plane: null,
        key: page,
        strokeData: _dabAt(40, 40),
        historyManager: history,
      );
      controller.syncGeometry(firstLayout);
      controller.sessionStateFor(null, page);
      return (before, controller.surfaceFor(null, page)!);
    }

    void expectKeptBesides(BitmapSurface before, BitmapSurface after) {
      final stroke = TileCoord(x: 0, y: 0);
      expect(before.tiles.containsKey(stroke), isFalse, reason: '⛔fixture');
      expect(after.tiles.keys.toSet(), {...before.tiles.keys, stroke});
      for (final MapEntry(:key, value: tile) in before.tiles.entries) {
        expect(after.tiles[key]!.pixels, tile.pixels, reason: '$key');
      }
    }

    test('the wide paper\'s far corner, written on from the narrow one', () {
      final (before, after) = writtenOnFrom(_wideKind, _narrowKind);
      expect(after.canvasSize, wide);
      expect(
        before.tiles.keys.any(
          (tile) => tile.x * defaultCelTileSize >= narrow.width,
        ),
        isTrue,
        reason: '⛔fixture: ink past the narrow paper',
      );
      expectKeptBesides(before, after);
    });

    test('the narrow paper\'s far corner, written on from the wide one', () {
      final (before, after) = writtenOnFrom(_narrowKind, _wideKind);
      expect(after.canvasSize, narrow);
      expectKeptBesides(before, after);
    });
  });

  group('the page a window seeds stands on the paper it shows', () {
    final page = timesheetInkPageKey(_narrowCut, 0);

    test('a cut\'s page written on its old paper is laid on its new one, '
        'every tile kept', () {
      final store = BrushFrameStore();
      final before = _inkedToTheCorner(wide);
      store.storeBakedSurface(page, before);
      final controller = TimesheetInkController(store: store);
      addTearDown(controller.dispose);
      controller.syncGeometry(_layout(_narrowCut, _narrowKind));
      controller.sessionStateFor(null, page);
      final laid = controller.surfaceFor(null, page)!;
      expect(laid.canvasSize, narrow);
      expect(laid.tiles.keys.toSet(), before.tiles.keys.toSet());
      for (final MapEntry(:key, value: tile) in before.tiles.entries) {
        expect(laid.tiles[key]!.pixels, tile.pixels, reason: '$key');
      }
    });

    test('🚨what another coordinator over the store wrote at another paper '
        'is what this one stands on next', () {
      final store = BrushFrameStore();
      final here = TimesheetInkController(store: store);
      final there = TimesheetInkController(store: store);
      addTearDown(here.dispose);
      addTearDown(there.dispose);
      here.syncGeometry(_layout(_narrowCut, _narrowKind));
      here.sessionStateFor(null, page);
      there.syncGeometry(_layout(_narrowCut, _wideKind));
      there.commitStroke(
        plane: null,
        key: page,
        strokeData: _dabAt(40, 40),
        historyManager: HistoryManager(),
      );
      final shown = here.sessionStateFor(null, page).canvasState;
      expect(
        shown.currentSurface.tiles.containsKey(TileCoord(x: 0, y: 0)),
        isTrue,
        reason: 'a session left on the old pixels paints over the stroke',
      );
    });
  });
}
