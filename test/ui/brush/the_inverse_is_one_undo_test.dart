import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/pasteboard_bounds.dart';
import 'package:anicel/src/services/canvas_selection.dart';
import 'package:anicel/src/services/canvas_selection_region.dart';
import 'package:anicel/src/services/history_manager.dart';
import 'package:anicel/src/ui/brush/canvas_selection_commands.dart';
import 'package:anicel/src/ui/brush/selection_shape_history_command.dart';

/// 🚨I-23 — 선택 반전 through the selection channel: ONE undo step, the
/// same history door every selection change takes.
///
/// An open box lands FIRST, as an entry of its own, and the inverse is of
/// what that landing left — so one Ctrl+Z takes the inverse back and not
/// the move under it.
void main() {
  const canvas = CanvasSize(width: 20, height: 15);
  final wall = canvas.pasteboardRect;

  CanvasSelectionShape rect(double l, double t, double r, double b) =>
      CanvasSelectionShape.rect(left: l, top: t, right: r, bottom: b);

  CanvasSelectionRegion wholeWall() => CanvasSelectionRegion.shape(
    rect(wall.left, wall.top, wall.right, wall.bottom),
  );

  /// The channel wired the way the canvas panel wires it: every selection
  /// change recorded as one [SelectionShapeHistoryCommand].
  ({CanvasSelectionCommands commands, HistoryManager history}) wired() {
    final commands = CanvasSelectionCommands();
    final history = HistoryManager();
    commands.regionHistoryRecorder = (before, after) => history.execute(
      SelectionShapeHistoryCommand(
        channel: commands,
        before: before,
        after: after,
      ),
    );
    return (commands: commands, history: history);
  }

  test('an inverse is ONE undo step, and undo and redo walk it', () {
    final (:commands, :history) = wired();
    final selected = CanvasSelectionRegion.shape(rect(2, 3, 12, 9));
    commands.setRegion(selected);
    final inverse = CanvasSelectionRegion.invertedWithin(selected, wall);

    commands.invertSelection(canvasSize: canvas);

    expect(history.undoCount, 1);
    expect(commands.region, inverse);
    history.undo();
    expect(commands.region, selected, reason: 'undo puts the selection back');
    history.redo();
    expect(commands.region, inverse, reason: 'redo inverts it again');
  });

  test('with nothing selected it selects the whole wall', () {
    final (:commands, :history) = wired();

    commands.invertSelection(canvasSize: canvas);

    expect(commands.region, wholeWall());
    expect(history.undoCount, 1);
    history.undo();
    expect(commands.region, isNull);
  });

  test('pressed twice from nothing it comes back to nothing', () {
    final (:commands, :history) = wired();

    commands.invertSelection(canvasSize: canvas);
    commands.invertSelection(canvasSize: canvas);

    expect(commands.region, isNull, reason: 'the inverse of everything');
    expect(history.undoCount, 2, reason: 'each press is its own step');
  });

  test('the move tool\'s own box is not a selection — the inverse does not '
      'see it (F-108)', () {
    final (:commands, :history) = wired();
    commands.setRegion(
      CanvasSelectionRegion.shape(rect(2, 3, 12, 9)),
      implicit: true,
    );

    commands.invertSelection(canvasSize: canvas);

    expect(commands.region, wholeWall());
    expect(history.undoCount, 1);
  });

  test('an open box lands FIRST, as its own entry — one undo takes back '
      'the inverse and nothing else', () {
    final (:commands, :history) = wired();
    final selected = CanvasSelectionRegion.shape(rect(2, 3, 12, 9));
    commands.setRegion(selected);
    final landed = selected.translated(dx: 5, dy: 0);
    var pending = true;
    // Stands in for a mounted selection layer holding a box: its confirm
    // is an entry of its own, and it carries the outline to where the box
    // put it.
    final owner = Object();
    commands.bind(
      owner,
      hasSelection: () => commands.region != null,
      deselect: () {},
      movePending: () => pending,
      confirmPendingMove: () {
        if (!pending) {
          return;
        }
        pending = false;
        commands.regionHistoryRecorder!(commands.region, landed);
      },
    );
    addTearDown(() => commands.unbind(owner));

    commands.invertSelection(canvasSize: canvas);

    expect(history.undoCount, 2, reason: 'the landing, then the inverse');
    expect(
      commands.region,
      CanvasSelectionRegion.invertedWithin(landed, wall),
      reason: 'the inverse of what the box LANDED',
    );
    history.undo();
    expect(commands.region, landed, reason: 'one undo: the inverse only');
  });

  test('without a history host it applies directly', () {
    final commands = CanvasSelectionCommands();

    commands.invertSelection(canvasSize: canvas);

    expect(commands.region, wholeWall());
  });
}
