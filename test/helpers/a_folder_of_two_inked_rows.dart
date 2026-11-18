import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_folder.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/home_page.dart';

/// The folder [pumpAFolderOfTwoInkedRows] stands the canvas on.
const liftedFolder = LayerId('lifted-folder');

/// The two drawing rows inside [liftedFolder], each with two cels.
const liftedRowA = LayerId('row-a');
const liftedRowB = LayerId('row-b');

/// Two drawing rows inside [liftedFolder], each with two cels.
Project _folderProject() {
  final base = createDefaultProject();
  final track = base.tracks.first;
  final cut = track.cuts.first;
  final row = cut.layers.firstWhere(layerAcceptsBrushInput);
  Layer member(LayerId id) => row.copyWith(
    id: id,
    folderId: liftedFolder,
    frames: [
      for (var i = 0; i < 2; i += 1)
        Frame(id: FrameId('${id.value}-$i'), duration: 1, strokes: const []),
    ],
    timeline: {
      for (var i = 0; i < 2; i += 1)
        i: TimelineExposure.drawing(FrameId('${id.value}-$i'), length: 1),
    },
  );
  return base.copyWith(
    tracks: [
      track.copyWith(
        cuts: [
          cut.copyWith(
            layers: [
              member(liftedRowA),
              member(liftedRowB),
              createFolderLayer(id: liftedFolder, name: 'F'),
              for (final layer in cut.layers)
                if (layer.id != row.id) layer,
            ],
          ),
        ],
      ),
    ],
  );
}

/// An opaque block over [left]..[right] × [top]..[bottom], in the first
/// tile of a cel of [session]'s cut.
BitmapSurface _blockOn(
  EditorSessionManager session, {
  required int left,
  required int top,
  required int right,
  required int bottom,
}) {
  final cut = session.requireActiveCut;
  const size = defaultCelTileSize;
  final pixels = Uint8List(size * size * 4);
  for (var y = top; y < bottom; y += 1) {
    for (var x = left; x < right; x += 1) {
      final o = (y * size + x) * 4;
      pixels[o + 2] = 0x80;
      pixels[o + 3] = 0xFF;
    }
  }
  return BitmapSurface(
    canvasSize: cut.canvasSize,
    tiles: {TileCoord(x: 0, y: 0): BitmapTile(size: size, pixels: pixels)},
  );
}

/// The app on a cut whose [liftedFolder] holds [liftedRowA] and
/// [liftedRowB] — A's ink at (20..60, 20..40), B's at (70..110, 70..90), on
/// both of each row's cels — the canvas stood on the folder at frame 0.
Future<EditorSessionManager> pumpAFolderOfTwoInkedRows(
  WidgetTester tester,
) async {
  await tester.binding.setSurfaceSize(const Size(1700, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(home: HomePage(initialProject: _folderProject())),
  );
  await tester.pumpAndSettle();
  final session = tester
      .widget<EditorWorkspace>(find.byType(EditorWorkspace))
      .session;
  final cut = session.requireActiveCut;
  final store = session.renderCaches.brushFrameStore;
  for (final frame in ['0', '1']) {
    store.storeBakedSurface(
      session.brushFrameKeyForCut(
        cut,
        liftedRowA,
        FrameId('${liftedRowA.value}-$frame'),
      ),
      _blockOn(session, left: 20, top: 20, right: 60, bottom: 40),
    );
    store.storeBakedSurface(
      session.brushFrameKeyForCut(
        cut,
        liftedRowB,
        FrameId('${liftedRowB.value}-$frame'),
      ),
      _blockOn(session, left: 70, top: 70, right: 110, bottom: 90),
    );
  }
  // The canvas edits a drawing row first, as a user arrives at a folder.
  session.selectLayer(liftedRowA);
  session.selectFrameIndex(0);
  await tester.pumpAndSettle();
  session.selectLayer(liftedFolder);
  await tester.pumpAndSettle();
  return session;
}
