import 'dart:typed_data';

import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/brush_frame_key.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/pasteboard_bounds.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/brush_frame_store.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/cels_kept_in_a_file.dart';

/// 🗣️F-569 — WHAT AN EDIT LEFT FOR GOOD IS NAMED WITH ITS PIXEL BUMP
/// (`BrushFrameStore.revisionsLastLeft`): every revision a cel leaves that
/// named one content and that no undo gives back — what the frames'
/// pictures let go of (`FramePictures.letGoOfLeftRevisions`). Every way a
/// cel takes a new revision, and the two that name none.
void main() {
  const canvas = CanvasSize(width: 16, height: 8);
  const tileSize = 4;

  BrushFrameKey key(String frame) => BrushFrameKey(
    projectId: const ProjectId('p'),
    trackId: const TrackId('t'),
    cutId: const CutId('c'),
    layerId: const LayerId('l'),
    frameId: FrameId(frame),
  );

  /// Ink on the tile at [coord], every byte [value].
  BitmapSurface inkAt(TileCoord coord, {int value = 10}) => BitmapSurface(
    canvasSize: canvas,
    tileSize: tileSize,
  ).putTiles([
    (
      coord: coord,
      tile: BitmapTile(
        size: tileSize,
        pixels: Uint8List(tileSize * tileSize * 4)..fillRange(0, 64, value),
      ),
    ),
  ]);

  /// Every revision [store]'s bumps name from here on.
  Set<int> namedBy(BrushFrameStore store) {
    final named = <int>{};
    void heard() => named.addAll(store.revisionsLastLeft);
    store.celPixelRevision.addListener(heard);
    addTearDown(() => store.celPixelRevision.removeListener(heard));
    return named;
  }

  final a = key('a');

  test('an edit names the revision its cel left — a cel\'s first, none', () {
    final store = BrushFrameStore();
    store.markCelEdited(a);
    expect(store.revisionsLastLeft, isEmpty, reason: 'it left none');
    final first = store.sourceRevisionOf(a);
    store.markCelEdited(a);
    expect(store.revisionsLastLeft, {first});
    store.markCelEdited(key('b'));
    expect(store.revisionsLastLeft, isEmpty, reason: 'one bump\'s alone');
  });

  test('⛔a file\'s cels are seeded at one revision, which names no one '
      'content: what one of them leaves is named by none', () {
    final store = BrushFrameStore();
    keepInAFile(store, {a: inkAt(TileCoord(x: 0, y: 0)), key('b'): inkAt(
      TileCoord(x: 1, y: 0),
    )});
    expect(store.sourceRevisionOf(a), store.sourceRevisionOf(key('b')),
        reason: '⛔premise: one revision');
    store.markCelEdited(a);
    expect(store.revisionsLastLeft, isEmpty);
  });

  test('a cel given back a revision names the one it leaves', () {
    final store = BrushFrameStore();
    store.markCelEdited(a);
    final back = store.sourceRevisionOf(a);
    store.markCelEdited(a);
    final left = store.sourceRevisionOf(a);
    store.markCelEdited(a, backTo: back);
    expect(store.sourceRevisionOf(a), back);
    expect(store.revisionsLastLeft, {left});
    store.markCelEdited(a, backTo: back);
    expect(store.revisionsLastLeft, isEmpty, reason: 'at it already');
  });

  test('⛔a cel the pasteboard\'s wall cuts names nothing: its undo lays the '
      'pixels back under the revision that named them (F-432 ④)', () {
    final store = BrushFrameStore();
    store.storeBakedSurface(a, inkAt(TileCoord(x: -2, y: 0)));
    store.markCelEdited(a);
    store.markCelEdited(a);
    expect(store.revisionsLastLeft, isNotEmpty,
        reason: '⛔premise: the bump before the cut named one');
    final before = store.sourceRevisionOf(a);
    final named = namedBy(store);
    final taken = store.adoptPasteboardReach(PasteboardReach.quarter);
    expect(taken[a]?.revision, before, reason: '⛔premise: cut and named');
    expect(store.sourceRevisionOf(a), isNot(before));
    expect(named, isEmpty);
  });

  test('a cel carried onto another key names the revision it left', () {
    final store = BrushFrameStore();
    store.storeBakedSurface(a, inkAt(TileCoord(x: 0, y: 0)));
    store.markCelEdited(a);
    final left = store.sourceRevisionOf(a);
    final named = namedBy(store);
    store.carryCels([(a, key('carried'))]);
    store.markCelEdited(key('other'));
    expect(named, {left});
  });

  test('a movie cel given another picture names the revision it left', () {
    final store = BrushFrameStore();
    store.installMovieCel(a, inkAt(TileCoord(x: 0, y: 0)));
    final left = store.sourceRevisionOf(a);
    store.installMovieCel(a, inkAt(TileCoord(x: 0, y: 0), value: 20));
    expect(store.revisionsLastLeft, {left});
  });

  test('a cut moved on its canvas names the revision each cel left', () {
    final store = BrushFrameStore();
    store.storeBakedSurface(a, inkAt(TileCoord(x: 0, y: 0)));
    store.markCelEdited(a);
    final left = store.sourceRevisionOf(a);
    store.adoptCutCanvasSize(
      cutId: const CutId('c'),
      canvasSize: canvas,
      dx: 4,
    );
    expect(store.revisionsLastLeft, {left});
  });
}
