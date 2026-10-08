import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/models/timesheet_ink_keys.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/session/project_file_door.dart' show SaveAsked;

import '../../helpers/opened_session.dart';
import '../../helpers/project_scratch_folder.dart';

/// The timesheet's handwriting rides the .anicel archive like the conte's
/// and the envelope's (유저 2026-09-26: 「다 통일해줘. 기능은 어차피
/// 생길수있어」) — until then it was the one sheet's ink no save carried. It
/// is keyed to the CUT the sheet describes, so load prunes a sheet whose
/// cut is gone, the envelope's unit.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  BitmapSurface inkSurface({int seed = 1}) {
    final pixels = Uint8List(8 * 8 * 4);
    for (var i = 0; i < pixels.length; i += 1) {
      pixels[i] = (i * seed * 13 + seed) & 0xFF;
    }
    return BitmapSurface(
      canvasSize: const CanvasSize(width: 16, height: 16),
      tileSize: 8,
      tiles: {
        TileCoord(x: 0, y: 0): BitmapTile(size: 8, pixels: pixels),
      },
    );
  }

  test(
    'timesheet ink round-trips through save/open, every page of it; a '
    'sheet whose CUT is gone prunes at LOAD; the main cel store never sees '
    'the namespace',
    () async {
      final dir = Directory.systemTemp.createTempSync('anicel-timesheet-ink');
      deleteAfterSessionEnds(dir);
      final path = '${dir.path}/timesheet.anicel';

      final session = EditorSessionManager(
        initialProject: createDefaultProject(),
      );
      addTearDown(session.dispose);
      final cut = session.requireActiveCut;
      final caches = session.renderCaches;

      final first = timesheetInkPageKey(cut.id, 0);
      final page = timesheetInkPageKey(cut.id, 1);
      final gone = timesheetInkPageKey(const CutId('deleted-cut'), 0);
      caches.timesheetInkStore.storeBakedSurface(first, inkSurface());
      caches.timesheetInkStore.storeBakedSurface(page, inkSurface(seed: 2));
      caches.timesheetInkStore.storeBakedSurface(gone, inkSurface(seed: 3));
      await session.projectDoor.saveProjectToFile(
        path,
        asked: SaveAsked.byAPerson,
      );

      final loaded = await openedSession(path);
      addTearDown(loaded.dispose);
      final opened = loaded.renderCaches;

      expect(
        opened.timesheetInkStore.celHasRenderableContent(first),
        isTrue,
        reason: 'what was written on the paper reopens with the project',
      );
      expect(
        opened.timesheetInkStore.celHasRenderableContent(page),
        isTrue,
        reason: 'every page of it',
      );
      expect(
        opened.timesheetInkStore.celHasRenderableContent(gone),
        isFalse,
        reason: 'a deleted cut takes its sheet\'s ink with it',
      );
      expect(
        opened.brushFrameStore.fileCelKeys.where(isTimesheetInkKey),
        isEmpty,
        reason: 'sheet ink can never leak into a cel',
      );
    },
  );
}
