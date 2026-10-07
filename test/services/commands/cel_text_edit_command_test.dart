import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/brush_frame_key.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/cel_text.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/text_cel_style.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/brush_frame_editing_coordinator.dart';
import 'package:anicel/src/services/cel_text_laying.dart';
import 'package:anicel/src/services/commands/cel_text_edit_command.dart';
import 'package:anicel/src/services/history_manager.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/cel_text_fixture.dart';

/// R9-rest (the text tool): one edit of the texts a cel carries is ONE step
/// of history — a text set, a text set differently, a text taken off, a
/// text turned into drawing — and the step is the cel's picture before and
/// after, so an undo puts the letters, their settings and their pixels back
/// together.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const key = celTextTestKey;
  const other = BrushFrameKey(
    projectId: ProjectId('p'),
    trackId: TrackId('t'),
    cutId: CutId('c'),
    layerId: LayerId('l'),
    frameId: FrameId('g'),
  );
  final a = TileCoord(x: 0, y: 0);
  final b = TileCoord(x: 1, y: 0);
  final ink = tileOf({
    (1, 1): [9, 9, 9, 255],
  });
  final red = tileOf({
    (2, 2): [200, 0, 0, 255],
  });
  final blue = tileOf({
    (3, 3): [0, 0, 200, 255],
  });

  CelTextContent says(String words) => CelTextContent(
    spans: [CelTextSpan(text: words, style: const TextLetterStyle())],
    anchor: CanvasPoint(x: 4, y: 4),
  );

  ({BrushFrameEditingCoordinator coordinator, HistoryManager history})
  cel({List<CelText> texts = const []}) => (
    coordinator: editingStackOn(drawingOf({a: ink}).withTexts(texts)),
    history: HistoryManager(),
  );

  List<CelText> textsOn(BrushFrameEditingCoordinator coordinator) =>
      coordinator.currentSurfaceOf(key).texts;

  CelTextEditCommand put(
    BrushFrameEditingCoordinator coordinator,
    String words,
    Map<TileCoord, BitmapTile> plate, {
    int? id,
    BrushFrameKey on = key,
  }) => CelTextEditCommand.put(
    coordinator: coordinator,
    frameKey: on,
    content: says(words),
    plate: plate,
    id: id,
  );

  group('a new text', () {
    test('goes on top of the texts the cel carries, under an id of its '
        'own — and the drawing is the tiles it was', () {
      final (:coordinator, :history) = cel(
        texts: [
          textOf(3, words: 'first', plate: {a: red}),
        ],
      );
      final drawing = coordinator.currentSurfaceOf(key).tileAt(a);
      final command = put(coordinator, 'second', {b: blue});
      expect(command.textId, isNull, reason: 'not on the cel yet');

      history.execute(command);

      final texts = textsOn(coordinator);
      expect([for (final text in texts) text.content.text], [
        'first',
        'second',
      ]);
      expect(texts.last.id, 4, reason: 'one past the largest there');
      expect(command.textId, 4);
      expect(texts.last.plate[b], same(blue));
      expect(coordinator.currentSurfaceOf(key).tileAt(a), same(drawing));
    });

    test('🚨one undo takes it off and one redo sets it back — the very '
        'pictures', () {
      final (:coordinator, :history) = cel();
      final before = coordinator.currentSurfaceOf(key);
      history.execute(put(coordinator, 'hello', {b: blue}));
      final after = coordinator.currentSurfaceOf(key);
      expect(after.texts, hasLength(1), reason: '⛔fixture');

      history.undo();
      expect(coordinator.currentSurfaceOf(key), before);
      expect(textsOn(coordinator), isEmpty);

      history.redo();
      expect(coordinator.currentSurfaceOf(key), after);
      expect(textsOn(coordinator).single.id, 1);
    });
  });

  group('a text set differently', () {
    test('keeps its id and its place among the others', () {
      final (:coordinator, :history) = cel(
        texts: [
          textOf(1, words: 'under', plate: {a: red}),
          textOf(2, words: 'middle', plate: {a: red}),
          textOf(5, words: 'over', plate: {a: red}),
        ],
      );
      final command = put(coordinator, 'MIDDLE', {b: blue}, id: 2);

      history.execute(command);

      expect(
        [for (final text in textsOn(coordinator)) (text.id, text.content.text)],
        [(1, 'under'), (2, 'MIDDLE'), (5, 'over')],
      );
      expect(textsOn(coordinator)[1].plate, {b: blue});
      expect(command.textId, 2);

      history.undo();
      expect(textsOn(coordinator)[1].content.text, 'middle');
      expect(textsOn(coordinator)[1].plate, {a: red});
    });

    test('set exactly as it was, it is no step at all: nothing is held and '
        'an undo moves nothing', () {
      final (:coordinator, :history) = cel(
        texts: [
          textOf(1, words: 'same', plate: {a: red}),
        ],
      );
      final standing = coordinator.currentSurfaceOf(key);
      final asItIs = textsOn(coordinator).single;
      final command = CelTextEditCommand.put(
        coordinator: coordinator,
        frameKey: key,
        content: asItIs.content,
        plate: asItIs.plate,
        id: 1,
      );

      history.execute(command);

      expect(command.surfaces, isNull);
      expect(command.estimatedRetainedBytes(undone: false), 0);
      expect(coordinator.currentSurfaceOf(key), same(standing));
      command.undo();
      expect(coordinator.currentSurfaceOf(key), same(standing));
    });
  });

  group('a text taken off', () {
    test('leaves the others where they stood, and one undo sets it back in '
        'its place', () {
      final (:coordinator, :history) = cel(
        texts: [
          textOf(1, words: 'under', plate: {a: red}),
          textOf(2, words: 'gone', plate: {b: blue}),
          textOf(3, words: 'over', plate: {a: red}),
        ],
      );

      history.execute(
        CelTextEditCommand.remove(
          coordinator: coordinator,
          frameKey: key,
          id: 2,
        ),
      );

      expect([for (final text in textsOn(coordinator)) text.id], [1, 3]);

      history.undo();
      expect([for (final text in textsOn(coordinator)) text.id], [1, 2, 3]);
      expect(textsOn(coordinator)[1].plate[b], same(blue));
    });

    test('a text the cel no longer carries is no step', () {
      final (:coordinator, :history) = cel();
      final standing = coordinator.currentSurfaceOf(key);
      final command = CelTextEditCommand.remove(
        coordinator: coordinator,
        frameKey: key,
        id: 9,
      );

      history.execute(command);

      expect(command.surfaces, isNull);
      expect(coordinator.currentSurfaceOf(key), same(standing));
    });
  });

  group('a text turned into drawing', () {
    CelTextEditCommand turn(
      BrushFrameEditingCoordinator coordinator,
      int id,
    ) => CelTextEditCommand.intoDrawing(
      coordinator: coordinator,
      frameKey: key,
      id: id,
    );

    test('🚨is off the cel as a text and in its drawing, as ONE step: one '
        'undo gives the text back — the very picture — and one redo turns '
        'it again', () {
      final (:coordinator, :history) = cel(
        texts: [
          textOf(3, words: 'kept', plate: {a: red, b: blue}),
        ],
      );
      final before = coordinator.currentSurfaceOf(key);

      history.execute(turn(coordinator, 3));

      final after = coordinator.currentSurfaceOf(key);
      expect(after.texts, isEmpty);
      expect(pixelOf(after, a, 2, 2), [200, 0, 0, 255], reason: 'its ink');
      expect(pixelOf(after, a, 1, 1), [9, 9, 9, 255], reason: 'the drawing');
      expect(pixelOf(after, b, 3, 3), [0, 0, 200, 255], reason: 'bare paper');
      expect(after, celSurfaceWithTextAsDrawing(before, 3));
      expect(history.undoCount, 1);

      history.undo();
      expect(coordinator.currentSurfaceOf(key), before);
      expect(textsOn(coordinator).single.plate[a], same(red));

      history.redo();
      expect(coordinator.currentSurfaceOf(key), after);
    });

    test('the texts it does not cover stay, where they stood', () {
      final (:coordinator, :history) = cel(
        texts: [
          textOf(1, words: 'under', plate: {b: blue}),
          textOf(2, words: 'turned', plate: {a: red}),
          textOf(3, words: 'over', plate: {a: blue}),
        ],
      );

      history.execute(turn(coordinator, 2));

      expect([for (final text in textsOn(coordinator)) text.id], [1, 3]);
      history.undo();
      expect([for (final text in textsOn(coordinator)) text.id], [1, 2, 3]);
    });

    test('a text the cel no longer carries is no step: nothing is held', () {
      final (:coordinator, :history) = cel(
        texts: [
          textOf(3, plate: {a: red}),
        ],
      );
      final standing = coordinator.currentSurfaceOf(key);
      final command = turn(coordinator, 9);

      history.execute(command);

      expect(command.surfaces, isNull);
      expect(command.estimatedRetainedBytes(undone: false), 0);
      expect(coordinator.currentSurfaceOf(key), same(standing));
    });

    test('🚨into the cel AS IT STANDS when the step lands — over what was '
        'drawn meanwhile', () {
      final (:coordinator, :history) = cel(
        texts: [
          textOf(3, plate: {a: red}),
        ],
      );
      final command = turn(coordinator, 3);
      // The cel is drawn on between the step being made and its landing.
      final drawnOn = coordinator.currentSurfaceOf(key).putTiles([
        (coord: b, tile: blue),
      ]);
      coordinator.restoreSurfaceSnapshot(key, drawnOn);

      history.execute(command);

      final landed = coordinator.currentSurfaceOf(key);
      expect(landed.tileAt(b), same(blue), reason: 'what was drawn meanwhile');
      expect(landed.texts, isEmpty);
      expect(pixelOf(landed, a, 2, 2), [200, 0, 0, 255]);
      history.undo();
      expect(coordinator.currentSurfaceOf(key), drawnOn);
    });

    test('the store hears of it', () {
      final (:coordinator, history: _) = cel(
        texts: [
          textOf(3, plate: {a: red}),
        ],
      );
      final revision = coordinator.frameStore
          .getOrCreateFrame(key)
          .sourceRevision;

      turn(coordinator, 3).execute();

      expect(
        coordinator.frameStore.getOrCreateFrame(key).sourceRevision,
        greaterThan(revision),
      );
    });
  });

  group('where it lands', () {
    test('🚨on the cel AS IT STANDS when the step lands — what was drawn '
        'meanwhile stays', () {
      final (:coordinator, :history) = cel();
      final command = put(coordinator, 'late', {b: blue});
      // The cel changes between the edit being made and its landing.
      final drawnOn = drawingOf({a: ink, b: red});
      coordinator.restoreSurfaceSnapshot(key, drawnOn);

      history.execute(command);

      final landed = coordinator.currentSurfaceOf(key);
      expect(landed.tileAt(b), same(red), reason: 'the drawing made meanwhile');
      expect(landed.texts.single.content.text, 'late');
      history.undo();
      expect(coordinator.currentSurfaceOf(key), drawnOn);
    });

    test('on the cel it NAMES, whichever cel the panel stands on', () {
      final (:coordinator, :history) = cel();
      coordinator.restoreSurfaceSnapshot(other, drawingOf({a: ink}));
      final standing = coordinator.currentSurfaceOf(key);

      history.execute(put(coordinator, 'there', {b: blue}, on: other));

      expect(coordinator.currentSurfaceOf(other).texts, hasLength(1));
      expect(coordinator.currentSurfaceOf(key), same(standing));
      history.undo();
      expect(coordinator.currentSurfaceOf(other).texts, isEmpty);
    });

    test('the store hears of it: the cel is a picture for its texts alone', () {
      final coordinator = editingStack();
      final revision = coordinator.frameStore
          .getOrCreateFrame(key)
          .sourceRevision;

      put(coordinator, 'only', {b: blue}).execute();

      expect(coordinator.frameStore.celHasRenderableContent(key), isTrue);
      expect(
        coordinator.frameStore.getOrCreateFrame(key).sourceRevision,
        greaterThan(revision),
      );
    });
  });

  group('what the step holds', () {
    test('the plate it was handed is let go once it has landed — from then '
        'on the pair holds the picture', () {
      final (:coordinator, :history) = cel();
      final command = put(coordinator, 'held', {b: blue});
      expect(command.retainsPutPayload, isTrue);
      expect(command.surfaces, isNull);

      history.execute(command);

      expect(command.retainsPutPayload, isFalse);
      expect(command.surfaces, isNotNull);
    });

    test('it is named for what it did', () {
      final (:coordinator, history: _) = cel();

      expect(put(coordinator, 'x', {b: blue}).description, 'Set text');
      expect(
        CelTextEditCommand.remove(
          coordinator: coordinator,
          frameKey: key,
          id: 1,
        ).description,
        'Delete text',
      );
      expect(
        CelTextEditCommand.intoDrawing(
          coordinator: coordinator,
          frameKey: key,
          id: 1,
        ).description,
        'Text to drawing',
      );
    });
  });
}
