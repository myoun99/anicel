import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/canvas_size.dart';
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
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/canvas/stroke_in_flight.dart';
import 'package:anicel/src/ui/session/layer_stack.dart';
import 'package:anicel/src/ui/timeline/timeline_cel_content_source.dart';
import 'package:anicel/src/ui/timeline/timeline_cell_exposure_state.dart';
import 'package:anicel/src/ui/timeline/timeline_drag_preview.dart'
    show ExposureEdgeDragPreview;
import 'package:anicel/src/ui/timeline/timeline_row_cells_painter.dart';

import 'timeline_frame_geometry_probe.dart';

/// one-cel-turning-white-repaints-every-row (2026-10-24): the unworked-block
/// tint's revision was ONE number every row heard, so one block going grey →
/// white re-recorded every row's painter. A bump names the rows it can have
/// changed, and a row painter hears its own row's.
///
/// The collaborator the naming lives in, named so `tool/mutation_run.dart`
/// runs this file for it.
LayerStack stackOf(EditorSessionManager s) => s.layerStack;

const _cutId = CutId('tint-cut');
const _canvas = CanvasSize(width: 16, height: 16);

Layer _row(String id, Map<int, int> blocks, {String? inside}) => Layer(
  id: LayerId(id),
  name: id,
  kind: LayerKind.animation,
  folderId: inside == null ? null : LayerId(inside),
  frames: [
    for (final start in blocks.keys)
      Frame(id: FrameId('$id$start'), duration: 1, strokes: const []),
  ],
  timeline: {
    for (final MapEntry(key: start, value: length) in blocks.entries)
      start: TimelineExposure.drawing(FrameId('$id$start'), length: length),
  },
);

Layer _folderRow(String id, {String? inside}) => Layer(
  id: LayerId(id),
  name: id,
  kind: LayerKind.folder,
  folderId: inside == null ? null : LayerId(inside),
  frames: const [],
  timeline: const {},
);

/// Bottom → top:
///
///     over            [over0]
///     F ─┬─ G ── b    ·  ·  [b2]
///        └─ a         [a0]
///     under           [under0]
const _rows = ['under', 'a', 'b', 'G', 'F', 'over'];

EditorSessionManager _session() {
  final session = EditorSessionManager(
    initialProject: Project(
      id: const ProjectId('tint'),
      name: 'tint',
      createdAt: DateTime.utc(2026, 10, 24),
      tracks: [
        Track(
          id: const TrackId('tint-track'),
          name: 'Video',
          cuts: [
            Cut(
              id: _cutId,
              name: 'c1',
              duration: 24,
              canvasSize: _canvas,
              layers: [
                _row('under', const {0: 2}),
                _row('a', const {0: 2}, inside: 'F'),
                _row('b', const {2: 2}, inside: 'G'),
                _folderRow('G', inside: 'F'),
                _folderRow('F'),
                _row('over', const {0: 2}),
              ],
            ),
          ],
        ),
      ],
    ),
  );
  addTearDown(session.dispose);
  return session;
}

BitmapSurface _ink() => BitmapSurface(
  canvasSize: _canvas,
  tileSize: 4,
  tiles: {
    TileCoord(x: 0, y: 0): BitmapTile(
      size: 4,
      pixels: Uint8List(4 * 4 * 4)..fillRange(0, 4 * 4 * 4, 0xFF),
    ),
  },
);

/// Puts a picture in the cel [frame] of [layer] — the store crosses it.
void _draw(EditorSessionManager s, String layer, String frame) =>
    s.renderCaches.brushFrameStore.storeBakedSurface(
      s.brushFrameKeyForCut(s.requireActiveCut, LayerId(layer), FrameId(frame)),
      _ink(),
    );

/// Whether the block at frame 0 of [layer] reads as drawn.
bool _drawn(EditorSessionManager s, String layer) =>
    stackOf(s).celHasContentForLayer(s.layerById(LayerId(layer))!, 0);

/// The rows of [rows] that heard the tint since the last read — each
/// listening as its painter does ([CelContentRevision.forRow]).
Set<String> Function() _hearing(EditorSessionManager s, List<String> rows) {
  final heard = <String>{};
  for (final row in rows) {
    void hears() => heard.add(row);
    final signal = stackOf(s).celTintRevision.forRow(LayerId(row));
    signal.addListener(hears);
    addTearDown(() => signal.removeListener(hears));
  }
  return () {
    final read = {...heard};
    heard.clear();
    return read;
  };
}

void main() {
  group('a bump names the rows it can have changed', () {
    test('a cel crossing names its row and the folders that hold it — '
        'every one up the tree, and no other row', () {
      final s = _session();
      final heard = _hearing(s, _rows);

      _draw(s, 'a', 'a0');
      expect(_drawn(s, 'a'), isTrue, reason: 'premise: the block went white');
      expect(heard(), {'a', 'F'});

      _draw(s, 'b', 'b2');
      expect(heard(), {'b', 'G', 'F'}, reason: 'G is in F: both show b');
    });

    test('the pen going down on an empty cel names the row it stands on, '
        'and its folders', () {
      final s = _session();
      s.selectLayer(const LayerId('a'));
      s.selectFrameIndex(0);
      final heard = _hearing(s, _rows);

      s.setCanvasStroke(StrokeInFlight.paints);
      expect(
        _drawn(s, 'a'),
        isTrue,
        reason: 'premise: the live stroke turned the block white',
      );
      expect(heard(), {'a', 'F'});

      s.setCanvasStroke(StrokeInFlight.none);
      expect(heard(), {'a', 'F'}, reason: 'and back to grey');
    });

    test('🚨a linked row is named by the bank it windows — the store names '
        'the group\'s key, not the row the stroke was on', () {
      final s = EditorSessionManager(initialProject: createDefaultProject());
      addTearDown(s.dispose);
      s.cutVerbs.createLinkedCutFromActiveCut();
      s.createDrawingAtCurrentFrame();
      final layer = s.activeLayer!;
      final key = s.brushFrameKeyForCut(
        s.activeCutOrNull!,
        layer.id,
        layer.frames.single.id,
      );
      final store = s.renderCaches.brushFrameStore;
      expect(
        store.canonicalKeyOf(key).layerId,
        isNot(layer.id),
        reason: 'premise: the row windows another row\'s bank',
      );
      final heard = _hearing(s, [layer.id.value]);

      store.storeBakedSurface(key, _ink());

      expect(store.celsLastCrossed, {store.canonicalKeyOf(key)});
      expect(stackOf(s).celHasContentForLayer(layer, 0), isTrue);
      expect(heard(), {layer.id.value});
    });

    test('an announcement that names no cel names every row', () {
      final s = _session();
      final heard = _hearing(s, _rows);

      s.renderCaches.brushFrameStore.celContentRevision.value += 1;

      expect(heard(), _rows.toSet());
    });

    test('🚨a drag in flight names every row — it hangs cels where they '
        'are not', () {
      final s = _session();
      s.dragPreview.value = ExposureEdgeDragPreview(
        previewLayer: s.layerById(const LayerId('under'))!,
      );
      final heard = _hearing(s, _rows);

      _draw(s, 'a', 'a0');

      expect(heard(), _rows.toSet());
    });

    test('a cel noted unreadable names every row', () {
      final s = _session();
      final heard = _hearing(s, _rows);

      s.renderCaches.layerFrameImageCache.unreadable.note(
        s.brushFrameKeyForCut(
          s.requireActiveCut,
          const LayerId('a'),
          const FrameId('a0'),
        ),
      );

      expect(heard(), _rows.toSet());
    });

    test('every move reaches what listens to the whole number — the shared '
        'pill', () {
      final s = _session();
      var bumps = 0;
      stackOf(s).celTintRevision.addListener(() => bumps += 1);
      final before = stackOf(s).celTintRevision.value;

      _draw(s, 'a', 'a0');

      expect(bumps, 1);
      expect(stackOf(s).celTintRevision.value, before + 1);
    });
  });

  group('a row painter hears its own row', () {
    TimelineRowCellsPainter painterOver(
      Layer layer,
      CelContentRevision revision,
    ) => TimelineRowCellsPainter(
      layer: layer,
      geometry: testFrameGeometry(
        frameCellExtent: 24,
        frameEndIndexExclusive: 8,
      ),
      crossAxisExtent: 28,
      exposureStateForLayer: (_, _) => TimelineCellExposureState.uncovered,
      celContent: TimelineCelContentSource(
        hasContent: (_, _) => true,
        cannotRead: (_, _) => false,
        revision: revision,
      ),
      colorScheme: const ColorScheme.dark(),
      baseTextStyle: const TextStyle(fontSize: 11),
    );

    test('a bump naming one row repaints that row\'s painter only; a bump '
        'naming none repaints both', () {
      final revision = RowNamingRevision();
      addTearDown(revision.dispose);
      final a = painterOver(_row('a', const {0: 2}), revision);
      final b = painterOver(_row('b', const {0: 2}), revision);
      final repainted = <String>[];
      void onA() => repainted.add('a');
      void onB() => repainted.add('b');
      a.addListener(onA);
      b.addListener(onB);
      addTearDown(() {
        a.removeListener(onA);
        b.removeListener(onB);
      });

      revision.bump(rows: {const LayerId('a')});
      expect(repainted, ['a']);

      repainted.clear();
      revision.bump();
      expect(repainted, unorderedEquals(['a', 'b']));
    });

    test('a detached painter hears no more of its row', () {
      final revision = RowNamingRevision();
      addTearDown(revision.dispose);
      final a = painterOver(_row('a', const {0: 2}), revision);
      var repaints = 0;
      void onA() => repaints += 1;
      a.addListener(onA);
      a.removeListener(onA);

      revision.bump(rows: {const LayerId('a')});
      revision.bump();

      expect(repaints, 0);
    });

    test('a row over every row\'s cels hears every move — the conte row', () {
      final number = ValueNotifier<int>(0);
      addTearDown(number.dispose);
      final revision = CelContentRevision.everyRow(number);
      final conte = painterOver(_row('conte', const {0: 2}), revision);
      var repaints = 0;
      void onConte() => repaints += 1;
      conte.addListener(onConte);
      addTearDown(() => conte.removeListener(onConte));

      number.value += 1;

      expect(repaints, 1);
      expect(revision.value, 1);
    });
  });
}
