import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/brush_frame_key.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/timeline_row_address.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/command.dart' show WorkAhead;
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/timeline/toolbar_panel_context.dart';

import '../../helpers/cels_parked_cold.dart';

/// 🗣️F-615 (유저 2026-11-19): 「항상 하듯이 ui안멈추게 뒤에서 돌게?하고 대상
/// 프레임 수에 맞춰서 몇퍼센트인지 표시」 — a copy, or a 잘라내기, reads the
/// pictures of what it takes (`picturesShownBy`); a cel kept cold was thawed
/// by that read, on the UI thread. 🔬S5_BA: a range of 346 drawings froze a
/// copy for 1.3 s and a 잘라내기 for 1.7 s. What each board's copy reads is
/// thawed ahead of it now, off the UI thread, a share a drawing — and only
/// what it reads.
const _v = TrackId('v');
const _a = LayerId('thaw-a');
const _b = LayerId('thaw-b');
const _canvas = CanvasSize(
  width: defaultCelTileSize,
  height: defaultCelTileSize,
);

/// [id] holding [cels] one after another, two frames each.
Layer _row(LayerId id, List<String> cels) => Layer(
  id: id,
  name: id.value,
  frames: [
    for (final cel in cels)
      Frame(id: FrameId(cel), duration: 2, name: cel, strokes: const []),
  ],
  timeline: {
    for (final (index, cel) in cels.indexed)
      index * 2: TimelineExposure.drawing(FrameId(cel), length: 2),
  },
);

/// Cut 1 — row A drawing a1 then a2, row B b1 — and cut 2 after it, bare.
EditorSessionManager _session() {
  Cut cut(String id, List<Layer> layers) => Cut(
    id: CutId(id),
    name: id,
    duration: 4,
    canvasSize: _canvas,
    layers: layers,
  );
  final session = EditorSessionManager(
    initialProject: Project(
      id: const ProjectId('thaw-ahead'),
      name: 'Thaw ahead',
      createdAt: DateTime.utc(2026, 11, 19),
      tracks: [
        Track(
          id: _v,
          name: 'V',
          cuts: [
            cut('thaw-cut-1', [
              _row(_a, ['a1', 'a2']),
              _row(_b, ['b1']),
            ]),
            cut('thaw-cut-2', [_row(const LayerId('thaw-c'), const [])]),
          ],
        ),
      ],
    ),
  );
  addTearDown(session.dispose);
  return session;
}

/// A picture of one tile, its bytes salted by [seed].
BitmapSurface _ink(int seed) {
  final pixels = Uint8List(defaultCelTileSize * defaultCelTileSize * 4);
  for (var i = 0; i < pixels.length; i += 1) {
    pixels[i] = (i * 31 + seed) & 0xFF;
  }
  return BitmapSurface(
    canvasSize: _canvas,
    tileSize: defaultCelTileSize,
    tiles: {
      TileCoord(x: 0, y: 0): BitmapTile(
        size: defaultCelTileSize,
        pixels: pixels,
      ),
    },
  );
}

/// Every drawing of cut 1 parked cold, by its cel's name.
Map<String, BrushFrameKey> _parkCut1Cold(EditorSessionManager s) {
  final cut = s.repository.requireProject().tracks.single.cuts.first;
  final keys = {
    for (final (row, cel) in [(_a, 'a1'), (_a, 'a2'), (_b, 'b1')])
      cel: s.brushFrameKeyForCut(cut, row, FrameId(cel)),
  };
  parkCold(s.renderCaches.brushFrameStore, {
    for (final (index, key) in keys.values.indexed) key: _ink(index + 1),
  });
  return keys;
}

/// What [ahead] told of its share, run whole.
Future<List<double>> _told(WorkAhead? ahead) async {
  expect(ahead, isNotNull, reason: 'the copy reads pictures');
  final told = <double>[];
  await ahead!(told.add);
  return told;
}

/// The cels of [keys] still kept cold.
List<String> _cold(EditorSessionManager s, Map<String, BrushFrameKey> keys) =>
    [
      for (final MapEntry(key: cel, value: key) in keys.entries)
        if (s.renderCaches.brushFrameStore.isCelCold(key)) cel,
    ];

void main() {
  for (final lifted in [false, true]) {
    final verb = lifted ? '잘라내기' : 'copy';

    test('the frame board: a $verb of a band over row A thaws its two '
        'drawings ahead, a share each — and leaves row B\'s cold', () async {
      final s = _session();
      s.standOnRow(const LayerRowAddress(_a), frameIndex: 0);
      s.updateFrameRangeSelectionDrag(
        layerId: _a,
        anchorIndex: 0,
        headIndex: 3,
        spanRows: const [LayerRowAddress(_a)],
      );
      final keys = _parkCut1Cold(s);

      final told = await _told(
        TimelineToolbarPanelContext(s).takeAhead(lifted: lifted),
      );

      expect(told, [0.5, 1.0]);
      expect(_cold(s, keys), ['b1']);
    });

    test('the row board: a $verb of row A thaws its two drawings ahead, a '
        'share each — and leaves row B\'s cold', () async {
      final s = _session();
      s.rowSelectionVerbs.beginRowSelection(const LayerRowAddress(_a));
      final keys = _parkCut1Cold(s);

      final told = await _told(
        TimelineToolbarPanelContext(s).takeAhead(lifted: lifted),
      );

      expect(told, [0.5, 1.0]);
      expect(_cold(s, keys), ['b1']);
    });

    test('the cut board: a $verb of cut 1 thaws every drawing of its rows '
        'ahead, a share each', () async {
      final s = _session();
      s.selectGlobalFrame(1);
      s.selectTrackRow(_v);
      final keys = _parkCut1Cold(s);

      final told = await _told(
        StoryboardToolbarPanelContext(s).takeAhead(lifted: lifted),
      );

      expect(told, [
        closeTo(1 / 3, 1e-9),
        closeTo(2 / 3, 1e-9),
        closeTo(1.0, 1e-9),
      ]);
      expect(_cold(s, keys), isEmpty);
    });
  }
}
