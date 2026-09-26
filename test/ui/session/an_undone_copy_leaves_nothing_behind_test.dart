import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/brush_frame_key.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/envelope/cut_envelope_ink_keys.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/timesheet_ink_keys.dart';
import 'package:anicel/src/services/brush_frame_store.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/session/cut_verbs.dart';
import 'package:anicel/src/ui/session/layer_clipboard.dart';

import '../../helpers/draw_on_current_frame.dart';

/// 🚨AN ID FREE IN THE PROJECT IS NOT FREE IN THE SESSION.
///
/// What a copy or a new cut was given — a cel's picture, a sheet's
/// handwriting — is kept in the session's stores under its ids, and an
/// undo or a delete leaves it there for the redo that hands the ids back.
/// A copy that named its ids by the first number the PROJECT had free got
/// those same ids again, and whatever it had nothing to bring for showed
/// what the undone one had (card `undone-paste-reuses-ids`).
///
/// The verbs these live in — named so `tool/mutation_run.dart` runs this
/// file for them.
LayerClipboard layerBoardOf(EditorSessionManager session) =>
    session.layerClipboard;
CutVerbs cutVerbsOf(EditorSessionManager session) => session.cutVerbs;

void main() {
  late EditorSessionManager session;
  late BitmapSurface picture;

  setUp(() {
    session = EditorSessionManager(initialProject: createDefaultProject());
    drawOnCurrentFrame(session);
    final cut = session.requireActiveCut;
    final drawn = cut.layers.firstWhere((layer) => layer.frames.isNotEmpty);
    picture = session.renderCaches.brushFrameStore.bakedSurfaceOrNull(
      session.brushFrameKeyForCut(cut, drawn.id, drawn.frames.single.id),
    )!;
  });
  tearDown(() => session.dispose());

  /// Every cel of [row] in [cut], by its picture (null for none).
  List<Object?> picturesOf(Cut cut, Layer row) => [
    for (final cel in row.frames)
      session.renderCaches.brushFrameStore.bakedSurfaceOrNull(
        session.brushFrameKeyForCut(cut, row.id, cel.id),
      ),
  ];

  /// Every picture [cut] shows, row by row.
  List<Object?> everyPictureOf(Cut cut) => [
    for (final row in cut.layers) ...picturesOf(cut, row),
  ];

  Set<LayerId> rowsNow() => {
    for (final layer in session.requireActiveCut.layers) layer.id,
  };

  Set<CutId> cutsNow() => {
    for (final track in session.repository.requireProject().tracks)
      for (final cut in track.cuts) cut.id,
  };

  Cut cutOf(CutId id) => session.cutById(id)!;

  /// A row whose one cel was never drawn on, standing where it was made.
  Layer blankRow() {
    session.layerStack.addLayerOfKind(LayerKind.animation);
    session.createDrawingAtCurrentFrame();
    final row = session.activeLayer!;
    expect(row.frames, hasLength(1), reason: 'fixture: a cel');
    expect(
      picturesOf(session.requireActiveCut, row),
      [isNull],
      reason: 'fixture: nothing drawn on it',
    );
    return row;
  }

  BrushFrameStore sheetStoreOf(BrushFrameKey key) =>
      session.renderCaches.sheetInkStoreFor(key)!;
  void writeSheet(BrushFrameKey key) =>
      sheetStoreOf(key).storeBakedSurface(key, picture);
  Object? readSheet(BrushFrameKey key) =>
      sheetStoreOf(key).bakedSurfaceOrNull(key);

  test('a row pasted after an undone paste shows its own cel — not the '
      'undone paste\'s drawing', () {
    final drawn = session.activeLayer!.id;
    final blank = blankRow();

    session.selectLayer(drawn);
    session.layerClipboard.copyActiveLayer();
    final before = rowsNow();
    session.layerClipboard.pasteLayerFromClipboard();
    final undone = session.requireActiveCut.layers.singleWhere(
      (layer) => !before.contains(layer.id),
    );
    expect(
      picturesOf(session.requireActiveCut, undone),
      [same(picture)],
      reason: 'fixture: the paste brought the drawing',
    );
    session.historyManager.undo();
    expect(rowsNow(), before, reason: 'fixture: the paste is undone');

    session.selectLayer(blank.id);
    session.layerClipboard.copyActiveLayer();
    session.layerClipboard.pasteLayerFromClipboard();
    final pasted = session.requireActiveCut.layers.singleWhere(
      (layer) => !before.contains(layer.id),
    );

    expect(picturesOf(session.requireActiveCut, pasted), [isNull]);
  });

  test('a cut duplicated after an undone duplicate shows its own cels — '
      'not the undone copy\'s drawings', () {
    final drawnCut = session.requireActiveCut.id;
    session.cutVerbs.createCut();
    final blankCut = cutsNow().difference({drawnCut}).single;
    session.selectCut(blankCut);
    // On its first row, as the drawn cut's drawing is on its own.
    session.createDrawingAtCurrentFrame();
    expect(
      everyPictureOf(cutOf(blankCut)),
      [isNull],
      reason: 'fixture: one cel, nothing drawn on it',
    );

    session.selectCut(drawnCut);
    final before = cutsNow();
    session.cutVerbs.duplicateActiveCut();
    final undone = cutsNow().difference(before).single;
    expect(
      everyPictureOf(cutOf(undone)),
      contains(same(picture)),
      reason: 'fixture: the duplicate brought the drawing',
    );
    session.historyManager.undo();
    expect(cutsNow(), before, reason: 'fixture: the duplicate is undone');

    session.selectCut(blankCut);
    session.cutVerbs.duplicateActiveCut();
    final copy = cutsNow().difference(before).single;

    expect(everyPictureOf(cutOf(copy)).whereType<Object>(), isEmpty);
  });

  test('a cut made after one was deleted starts with blank sheets — not the '
      'deleted cut\'s handwriting', () {
    final first = cutsNow();
    session.cutVerbs.createCut();
    final gone = cutsNow().difference(first).single;
    writeSheet(envelopeInkBoxKey(gone, 'memo'));
    writeSheet(timesheetInkStripKey(gone, 0));
    writeSheet(timesheetInkPageKey(gone, 0));
    session.cutCommandCoordinator.deleteCut(cutId: gone);
    expect(cutsNow(), first, reason: 'fixture: the cut is gone');

    session.cutVerbs.createCut();
    final made = cutsNow().difference(first).single;

    expect(readSheet(envelopeInkBoxKey(made, 'memo')), isNull);
    expect(readSheet(timesheetInkStripKey(made, 0)), isNull);
    expect(readSheet(timesheetInkPageKey(made, 0)), isNull);
  });

  test('a cut duplicated after an undone duplicate starts with its own '
      'sheets — not the undone copy\'s handwriting', () {
    final drawnCut = session.requireActiveCut.id;
    session.cutVerbs.createCut();
    final blankCut = cutsNow().difference({drawnCut}).single;
    writeSheet(envelopeInkBoxKey(drawnCut, 'memo'));

    session.selectCut(drawnCut);
    final before = cutsNow();
    session.cutVerbs.duplicateActiveCut();
    final undone = cutsNow().difference(before).single;
    expect(
      readSheet(envelopeInkBoxKey(undone, 'memo')),
      same(picture),
      reason: 'fixture: the duplicate brought the handwriting',
    );
    session.historyManager.undo();

    session.selectCut(blankCut);
    session.cutVerbs.duplicateActiveCut();
    final copy = cutsNow().difference(before).single;

    expect(readSheet(envelopeInkBoxKey(copy, 'memo')), isNull);
  });

  test('drawings added at a run\'s end after an undone add are new ones — '
      'not the undone drawings come back', () {
    final row = session.activeLayer!;
    Set<FrameId> drawingsOfTheRow() => {
      for (final exposure in session.layers
          .firstWhere((layer) => layer.id == row.id)
          .timeline
          .values)
        ?exposure.frameId,
    };
    Set<FrameId> addTwo() {
      final before = drawingsOfTheRow();
      session.runFramesAdd.beginRunFramesAddDrag(
        layerId: row.id,
        blockStartIndex: row.timeline.keys.first,
        atEnd: true,
      );
      session.runFramesAdd.updateRunFramesAddDrag(2);
      session.runFramesAdd.endRunFramesAddDrag();
      return drawingsOfTheRow().difference(before);
    }

    final undone = addTwo();
    expect(undone, hasLength(2), reason: 'fixture: two drawings added');
    session.historyManager.undo();

    expect(
      addTwo().intersection(undone),
      isEmpty,
      reason: 'a drawing undone keeps its picture under its id for the redo',
    );
  });

  Set<FrameId> celsOf(Cut cut) => {
    for (final row in cut.layers)
      for (final cel in row.frames) cel.id,
  };

  test('a 겸용 cut made after an undone one is a cut of its own, its conte '
      'row born with a panel of its own', () {
    session.layerStack.addLayerOfKind(LayerKind.storyboard);
    final source = session.requireActiveCut.id;
    ({CutId cut, Set<FrameId> cels}) makeLinked() {
      final before = cutsNow();
      // A 겸용 cut's rows are LINKS: they show the source's own cels, and a
      // fresh panel joins that SHARED bank (F-99) — so what is new is what
      // the source did not have BEFORE.
      final sourceCels = celsOf(cutOf(source));
      session.cutVerbs.createLinkedCutFromActiveCut();
      final made = cutsNow().difference(before).single;
      return (cut: made, cels: celsOf(cutOf(made)).difference(sourceCels));
    }

    final undone = makeLinked();
    expect(undone.cels, isNotEmpty, reason: 'fixture: a fresh conte panel');
    session.historyManager.undo();
    session.selectCut(source);

    final made = makeLinked();
    expect(made.cut, isNot(undone.cut));
    expect(made.cels.intersection(undone.cels), isEmpty);
  });

  test('a 겸용 change made again after an undone one gives the rows it '
      'brings panels of their own', () {
    session.layerStack.addLayerOfKind(LayerKind.storyboard);
    final origin = session.requireActiveCut.id;
    final first = cutsNow();
    session.cutVerbs.createCut();
    final target = cutsNow().difference(first).single;
    session.selectCut(origin);
    Set<FrameId> brought() {
      // The rows it brings are links to the origin's cels, and the fresh
      // panel a row that cannot stand empty is born with joins that shared
      // bank (F-99) — so what is new is what neither cut had BEFORE.
      final before = celsOf(cutOf(target)).union(celsOf(cutOf(origin)));
      session.cutVerbs.convertActiveCutToLinked(target);
      return celsOf(cutOf(target)).difference(before);
    }

    final undone = brought();
    expect(undone, isNotEmpty, reason: 'fixture: the conte row\'s panel');
    session.historyManager.undo();
    session.selectCut(origin);

    expect(brought().intersection(undone), isEmpty);
  });

  test('a cut made after an undone one starts with blank sheets', () {
    final first = cutsNow();
    session.cutVerbs.createCut();
    final undone = cutsNow().difference(first).single;
    writeSheet(envelopeInkBoxKey(undone, 'memo'));
    session.historyManager.undo();
    expect(cutsNow(), first, reason: 'fixture: the cut is undone');

    session.cutVerbs.createCut();
    final made = cutsNow().difference(first).single;

    expect(readSheet(envelopeInkBoxKey(made, 'memo')), isNull);
  });
}
