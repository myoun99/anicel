import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/brush_frame_key.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/brush_frame_store.dart';
import 'package:anicel/src/services/cel_content_notes.dart';

/// Cels noted at the content they hold now — what a cel that could not be
/// read is remembered by (`LayerFrameImageCache.unreadable`), and a cel that
/// gave nothing to make (`FramePictures`).
void main() {
  BrushFrameKey key(String frame) => BrushFrameKey(
    projectId: const ProjectId('p'),
    trackId: const TrackId('t'),
    cutId: const CutId('c'),
    layerId: const LayerId('l'),
    frameId: FrameId(frame),
  );

  BitmapSurface surfaceWithInk() => BitmapSurface(
    canvasSize: const CanvasSize(width: 4, height: 4),
    tileSize: 4,
  ).putTiles([
    (
      coord: TileCoord(x: 0, y: 0),
      tile: BitmapTile(size: 4, pixels: Uint8List(64)..fillRange(0, 16, 255)),
    ),
  ]);

  /// Another cel of [store] crossing empty → drawn — what a new drawing
  /// anywhere does — after checking that it moves the store's generation.
  void anotherCelCrosses(BrushFrameStore store) {
    final generation = store.celContentRevision.value;
    store.storeBakedSurface(key('another'), surfaceWithInk());
    expect(
      store.celContentRevision.value,
      greaterThan(generation),
      reason: '⛔CONTROL: the crossing moves the store\'s generation',
    );
  }

  group('a note held at the cel\'s own content', () {
    test('holds until that content changes, and lapses by itself then', () {
      final store = BrushFrameStore();
      final notes = CelContentNotes(store);
      addTearDown(notes.dispose);
      final cel = key('cel');
      store.getOrCreateFrame(cel);

      notes.note(cel);
      expect(notes.has(cel), isTrue);

      store.markCelEdited(cel);
      expect(
        notes.has(cel),
        isFalse,
        reason: 'a new revision is other content, which nobody has tried',
      );
    });

    // 유저 2026-10-16 (frame-picture-indicator, the card the record is for):
    // 「영영실패 … 아예 해동실패했을때 얘기잖아. 디스크에 데이터가 없는상황」.
    test('🚨stands when another cel crosses empty↔drawn — ↩️every new drawing '
        'read each unreadable cel again, and the red that shows one went '
        'out until it had', () {
      final store = BrushFrameStore();
      final notes = CelContentNotes(store);
      addTearDown(notes.dispose);
      final cel = key('cel');
      store.getOrCreateFrame(cel);
      notes.note(cel);

      anotherCelCrosses(store);

      expect(notes.has(cel), isTrue);
    });

    test('a cel noted before it has any frame state stands until one '
        'appears', () {
      final store = BrushFrameStore();
      final notes = CelContentNotes(store);
      addTearDown(notes.dispose);
      final cel = key('cel');

      notes.note(cel);
      expect(notes.has(cel), isTrue);

      store.getOrCreateFrame(cel);
      expect(notes.has(cel), isFalse);
    });
  });

  test('a note that lapses with the store\'s content lapses on that crossing '
      'too — for a cel recorded at another size, which a resize heals with '
      'no revision of its own', () {
    final store = BrushFrameStore();
    final notes = CelContentNotes.orTheStoresContent(store);
    addTearDown(notes.dispose);
    final cel = key('cel');
    store.getOrCreateFrame(cel);
    notes.note(cel);
    expect(notes.has(cel), isTrue);

    anotherCelCrosses(store);

    expect(notes.has(cel), isFalse);
  });

  group('the revision', () {
    test('moves when a note is made and when it is taken back', () {
      final store = BrushFrameStore();
      final notes = CelContentNotes(store);
      addTearDown(notes.dispose);
      final cel = key('cel');

      notes.note(cel);
      expect(notes.revision.value, 1);
      notes.clear(cel);
      expect(notes.revision.value, 2);
    });

    test('🚨and when one the content moved past is taken back — whoever '
        'waits for this number to look again would go on showing it', () {
      final store = BrushFrameStore();
      final notes = CelContentNotes(store);
      addTearDown(notes.dispose);
      final cel = key('cel');
      store.getOrCreateFrame(cel);
      notes.note(cel);
      store.markCelEdited(cel);
      expect(notes.has(cel), isFalse, reason: '⛔CONTROL: the note lapsed');
      final lapsed = notes.revision.value;

      notes.clear(cel);

      expect(notes.revision.value, greaterThan(lapsed));
    });

    test('stays for the same note made again, and for taking back a cel '
        'never noted — what every making that answers does', () {
      final store = BrushFrameStore();
      final notes = CelContentNotes(store);
      addTearDown(notes.dispose);
      final cel = key('cel');
      notes.note(cel);
      final noted = notes.revision.value;

      notes.note(cel);
      notes.clear(key('never-noted'));

      expect(notes.revision.value, noted);
    });
  });
}
