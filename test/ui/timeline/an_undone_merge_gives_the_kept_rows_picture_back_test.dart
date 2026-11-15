import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/attached_layer_resolve.dart'
    show attachedMirrorCelId;
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/conte_key.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/timeline_row_address.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/brush_frame_store.dart' show CelRead;
import 'package:anicel/src/services/editing/default_cut_helpers.dart';
import 'package:anicel/src/services/import/raster_cel_import.dart'
    show bakeCelSurface;
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/timeline/merge_layer_rows.dart';

import '../../helpers/cel_text_fixture.dart' show pixelOf;
import '../../helpers/wait_window.dart';

/// 🔎Card a-synced-row-added-in-one-pair-cut-shows-another-rows-picture
/// (검증/서피스 2026-11-16 07:39): after merging a conte's rows and undoing
/// it, a synced row of the conte showed the other row's picture as well as
/// its own — in a 겸용 pair, in the other cut too.
///
/// A synced row's cels are minted as its mirrors of the conte's cels
/// (`attach-mirror-<row>-<panel>`), and the merge's result, kept under the
/// topmost row's id, named its new cel by that very mirror — the kept row's
/// own cel. The picture was laid over the cel the row still held, and an
/// undo gives back rows, not pictures.
void main() {
  const tile = defaultCelTileSize;
  const canvasSize = CanvasSize(width: 4 * tile, height: 3 * tile);
  const cutId = CutId('cut');
  const red = [200, 0, 0, 255];
  const green = [0, 200, 0, 255];

  BitmapSurface inkAt(TileCoord coord, List<int> rgba) {
    final pixels = Uint8List(tile * tile * 4);
    for (var i = 0; i < pixels.length; i += 4) {
      pixels.setRange(i, i + 4, rgba);
    }
    return BitmapSurface(
      canvasSize: canvasSize,
      tileSize: tile,
      tiles: {coord: BitmapTile(size: tile, pixels: pixels)},
    );
  }

  /// [cel]'s pixel at canvas ([x], [y]).
  List<int>? at(BitmapSurface cel, int x, int y) {
    final size = cel.tileSize;
    final (column, row) = ((x / size).floor(), (y / size).floor());
    return pixelOf(
      cel,
      TileCoord(x: column, y: row),
      x - column * size,
      y - row * size,
    );
  }

  const conte = LayerId('s');
  const panel = FrameId('s-1');

  /// The conte's row [id], riding it synced as the app makes one: its cel
  /// over the panel is its mirror of it.
  Layer onIt(String id, String key) => Layer(
    id: LayerId(id),
    name: id,
    kind: LayerKind.storyboard,
    attachedToLayerId: conte,
    conteKey: ConteKey(key),
    frames: [
      Frame(
        id: attachedMirrorCelId(LayerId(id), panel),
        duration: 1,
        strokes: const [],
      ),
    ],
    baseFrameLinks: {panel: attachedMirrorCelId(LayerId(id), panel)},
    timeline: const {},
  );

  EditorSessionManager session() => EditorSessionManager(
    initialProject: Project(
      id: const ProjectId('project'),
      name: 'Project',
      cameraSize: canvasSize,
      tracks: [
        Track(
          id: const TrackId('track'),
          name: 'Track',
          cuts: [
            Cut(
              id: cutId,
              name: 'cut',
              duration: 2,
              canvasSize: canvasSize,
              layers: [
                Layer(
                  id: conte,
                  name: 'Conte',
                  kind: LayerKind.storyboard,
                  frames: [
                    Frame(id: panel, duration: 2, name: '1', strokes: []),
                  ],
                  timeline: const {
                    0: TimelineExposure.drawing(panel, length: 2),
                  },
                ),
                onIt('k1', 'K1'),
                onIt('k2', 'K2'),
                createCameraLayer(cutId: cutId),
              ],
            ),
          ],
        ),
      ],
      createdAt: DateTime.utc(2026),
    ),
  );

  testWidgets("🎯after a merge of the conte's rows is undone, each row "
      'shows its own picture again — the kept one not the two together', (
    tester,
  ) async {
    final s = session();
    addTearDown(s.dispose);
    final store = s.renderCaches.brushFrameStore;
    BitmapSurface picture(String id) => store.bakedSurfaceOrNull(
      s.brushFrameKeyForCut(
        s.requireActiveCut,
        LayerId(id),
        attachedMirrorCelId(LayerId(id), panel),
      ),
      read: CelRead.look,
    )!;
    for (final (id, coord, rgba) in [
      ('k1', TileCoord(x: 1, y: 0), red),
      ('k2', TileCoord(x: 2, y: 0), green),
    ]) {
      bakeCelSurface(
        store,
        s.brushFrameKeyForCut(
          s.requireActiveCut,
          LayerId(id),
          attachedMirrorCelId(LayerId(id), panel),
        ),
        inkAt(coord, rgba),
      );
    }
    s.rowSelection.value = const [
      LayerRowAddress(LayerId('k1')),
      LayerRowAddress(LayerId('k2')),
    ];
    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (hosted) {
            context = hosted;
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    unawaited(mergeLayerRows(context, s));
    await settleBehindTheWaitWindow(
      tester,
      () =>
          s.requireActiveCut.layers.byId(const LayerId('k1')) == null &&
          find
              .byKey(const ValueKey<String>('layer-merge-progress'))
              .evaluate()
              .isEmpty,
    );
    final merged = s.requireActiveCut.layers.byId(const LayerId('k2'))!;
    final shown = store.bakedSurfaceOrNull(
      s.brushFrameKeyForCut(
        s.requireActiveCut,
        merged.id,
        merged.baseFrameLinks[panel]!,
      ),
      read: CelRead.look,
    )!;
    expect(
      [at(shown, 160, 40), at(shown, 288, 40)],
      [red, green],
      reason: '⛔전제: the result shows the two together',
    );

    s.undo();
    expect(
      s.requireActiveCut.layers.byId(const LayerId('k1')),
      isNotNull,
      reason: '⛔전제: the rows are back',
    );
    expect(
      [at(picture('k2'), 160, 40)?[3] ?? 0, at(picture('k2'), 288, 40)],
      [0, green],
      reason: "k2 shows its own picture alone — not k1's laid with it",
    );
    expect(at(picture('k1'), 160, 40), red);
    s.playbackRig.prerenderScheduler.cancel();
  });
}
