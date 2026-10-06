import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/services/commands/cel_text_edit_command.dart';
import 'package:anicel/src/services/history_manager.dart';
import 'package:anicel/src/services/undo_surface_snapshot.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/cel_text_fixture.dart';

/// 🚨★★★AN UNDO ENTRY KEEPS A TEXT'S PLATE AS IT KEEPS A TILE (R9-rest).
///
/// A text carries its pixels (`CelText.plate`), so an edit of one — a
/// letter typed, a text moved — leaves the plate it replaced held by the
/// undo entry and by nothing else. An entry that did not count it weighed
/// nothing however large the letters: two hundred moves of a large title
/// were a gigabyte the byte budget could not see, and could not park.
///
/// So a plate's tiles are tiles of the picture like any other — the ones
/// the cel still holds are shared and cost nothing, the ones it does not
/// are billed, parked and read back — and what tells a plate's tile from a
/// drawing's on the same coordinate is WHERE it is kept (`KeptTilePlace`).
///
/// ⚠️What the engine draws is not asked here: every plate is a tile the
/// test made, and a text's settings do not have to match it.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final a = TileCoord(x: 0, y: 0);
  final b = TileCoord(x: 1, y: 0);
  final c = TileCoord(x: 2, y: 0);
  final tileBytes = BitmapTile.bytesFor(celTextTestTileSize);

  /// A tile of its own — another object every time, whatever it holds.
  BitmapTile tile(int shade) => tileFilledWith([shade, shade, shade, 255]);
  final ink = tile(9);

  /// The cel's drawing with one text over it, said and plated as told.
  BitmapSurface carrying(
    Map<TileCoord, BitmapTile> plate, {
    String words = 'text',
  }) => drawingOf({a: ink}).withTexts([textOf(1, words: words, plate: plate)]);

  group('what a picture alone holds', () {
    test('a plate tile the other picture does not hold is this one\'s, '
        'named by its text and its coordinate — one both hold is not', () {
      final kept = tile(1);
      final replaced = tile(2);
      final before = carrying({a: kept, b: replaced});
      final after = carrying({a: kept, b: tile(3)});

      final alone = before.keptTilesNotSharedWith(after);

      expect(alone.keys, [(text: 1, coord: b)]);
      expect(alone.values.single, same(replaced));
      expect(before.bytesNotSharedWith(after), tileBytes);
    });

    test('🚨a drawing tile and a plate tile on ONE coordinate are two '
        'tiles, told apart by where each is kept', () {
      final drawn = tile(1);
      final plate = tile(2);
      final picture = drawingOf({a: drawn}).withTexts([
        textOf(4, plate: {a: plate}),
      ]);

      final all = picture.keptTiles;

      expect(all, hasLength(2));
      expect(all[(text: null, coord: a)], same(drawn));
      expect(all[(text: 4, coord: a)], same(plate));
      expect(all.length, picture.keptTileCount);
      expect(picture.bytesNotSharedWith(null), 2 * tileBytes);
    });

    test('a kept tile is read back from where it is kept, and nowhere '
        'else', () {
      final drawn = tile(1);
      final plate = tile(2);
      final picture = drawingOf({a: drawn}).withTexts([
        textOf(4, plate: {a: plate}),
        textOf(5, plate: {b: tile(3)}),
      ]);

      expect(picture.keptTileAt((text: null, coord: a)), same(drawn));
      expect(picture.keptTileAt((text: 4, coord: a)), same(plate));
      expect(picture.keptTileAt((text: 4, coord: b)), isNull);
      expect(picture.keptTileAt((text: 5, coord: a)), isNull);
      expect(picture.keptTileAt((text: 6, coord: a)), isNull);
      expect(picture.keptTileAt((text: null, coord: b)), isNull);
    });
  });

  group('an undo entry of a text edit', () {
    test('🚨weighs the plate it alone holds: the one replaced while the '
        'edit stands, the new one once it is undone', () {
      final kept = tile(1);
      final pair = UndoSurfacePair(
        key: celTextTestKey,
        before: carrying({a: kept, b: tile(2)}),
        after: carrying({a: kept, b: tile(3), c: tile(4)}, words: 'longer'),
      );

      expect(pair.residentBytes(undone: false), tileBytes);
      expect(pair.residentBytes(undone: true), 2 * tileBytes);
    });

    test('a stroke on a cel that carries texts owes nothing for them: both '
        'pictures hold the same plates', () {
      final text = textOf(1, plate: {b: tile(2), c: tile(3)});
      final pair = UndoSurfacePair(
        key: celTextTestKey,
        before: drawingOf({a: ink}).withTexts([text]),
        after: drawingOf({a: tile(5)}).withTexts([text]),
      );

      expect(
        pair.residentBytes(undone: false),
        tileBytes,
        reason: 'the one drawing tile the stroke replaced',
      );
    });

    test('the step says so, and the stack\'s byte budget sees it', () {
      final coordinator = editingStackOn(carrying({b: tile(2), c: tile(3)}));
      final history = HistoryManager();
      final command = CelTextEditCommand.put(
        coordinator: coordinator,
        frameKey: celTextTestKey,
        id: 1,
        content: textOf(1, words: 'set again').content,
        plate: {b: tile(4)},
      );

      history.execute(command);

      expect(command.estimatedRetainedBytes(undone: false), 2 * tileBytes);
      expect(command.estimatedRetainedBytes(undone: true), tileBytes);
      expect(history.retainedBytes, 2 * tileBytes);
    });
  });

  group('parked', () {
    test('🚨its plate goes to the room with the drawing: nothing is held, '
        'and the picture comes back whole — the plate tile it owned read '
        'back, the ones it shared the cel\'s very tiles', () async {
      final shared = tile(1);
      final replaced = tile(2);
      final before = carrying({a: shared, b: replaced}, words: 'before');
      final live = carrying({a: shared, b: tile(3)}, words: 'after');
      final snapshot = UndoSurfaceSnapshot(
        key: celTextTestKey,
        snapshot: before,
        sharedWith: live,
      );
      expect(snapshot.residentBytes, tileBytes, reason: '⛔fixture');

      expect(await snapshot.park(), isTrue);

      expect(snapshot.isParked, isTrue);
      expect(snapshot.residentBytes, 0);

      final back = snapshot.surfaceOver(live)!;

      expect(back, before);
      expect(back.texts.single.plate[a], same(shared));
      expect(
        back.texts.single.plate[b],
        isNot(same(replaced)),
        reason: 'it was let go of, and came back from the room',
      );
      expect(back.tileAt(a), same(ink));
      expect(snapshot.residentBytes, tileBytes, reason: 'resident again');
    });

    test('a text edit that changed no tile at all lets go without a file, '
        'and still comes back saying what it said', () async {
      final plate = tile(1);
      final before = carrying({b: plate}, words: 'before');
      final live = carrying({b: plate}, words: 'after');
      final snapshot = UndoSurfaceSnapshot(
        key: celTextTestKey,
        snapshot: before,
        sharedWith: live,
      );
      expect(snapshot.residentBytes, 0, reason: '⛔fixture: all shared');

      expect(await snapshot.park(), isTrue);
      final back = snapshot.surfaceOver(live)!;

      expect(back.texts.single.content.text, 'before');
      expect(back.texts.single.plate[b], same(plate));
    });

    test('every text comes back in its place, with or without a plate of '
        'its own', () async {
      final shared = tile(1);
      final before = drawingOf({a: tile(7)}).withTexts([
        textOf(1, words: 'under', plate: {b: shared}),
        textOf(2, words: 'no plate'),
        textOf(5, words: 'over', plate: {b: tile(2), c: tile(3)}),
      ]);
      final live = drawingOf({a: ink}).withTexts([
        textOf(1, words: 'under', plate: {b: shared}),
      ]);
      final snapshot = UndoSurfaceSnapshot(
        key: celTextTestKey,
        snapshot: before,
        sharedWith: live,
      );

      expect(await snapshot.park(), isTrue);

      expect(snapshot.surfaceOver(live), before);
    });

    test('⛔it refuses rather than hand back a text with a hole in it: a '
        'plate tile it shared that the cel no longer holds', () async {
      final shared = tile(1);
      final before = carrying({a: shared, b: tile(2)});
      final live = carrying({a: shared, b: tile(3)});
      final snapshot = UndoSurfaceSnapshot(
        key: celTextTestKey,
        snapshot: before,
        sharedWith: live,
      );
      expect(await snapshot.park(), isTrue);

      expect(
        snapshot.surfaceOver(carrying({b: tile(3)})),
        isNull,
        reason: 'the shared plate tile is gone',
      );
      expect(
        snapshot.surfaceOver(drawingOf({a: ink})),
        isNull,
        reason: 'the text is gone',
      );
      expect(snapshot.surfaceOver(live), before, reason: 'and still whole');
    });

    test('the step parked and then undone sets the text back as it was', () async {
      final replaced = tile(2);
      final coordinator = editingStackOn(
        carrying({b: replaced}, words: 'before'),
      );
      final command = CelTextEditCommand.put(
        coordinator: coordinator,
        frameKey: celTextTestKey,
        id: 1,
        content: textOf(1, words: 'after').content,
        plate: {b: tile(3)},
      )..execute();

      expect(await command.parkPayload(), isTrue);

      expect(command.estimatedRetainedBytes(undone: false), 0);

      command.undo();

      final back = coordinator.currentSurfaceOf(celTextTestKey).texts.single;
      expect(back.content.text, 'before');
      expect(back.plate, {b: replaced});
    });
  });
}
