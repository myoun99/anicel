import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/flip_column_step.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/ui/canvas/flip_hud_model.dart';

/// THE flip rule: one column, either way. A column is a block that covers
/// frames, or a single frame nothing covers.
///
/// The step is unbounded on purpose. Rightward nothing ends the axis —
/// running out of blocks, or out of the cut, is the caller's business —
/// and leftward the only real floor is the start of the film, which the
/// caller owns too.
void main() {
  /// `1---x2---` — the user's own case. Block '1' holds frames 0..3, one
  /// uncovered frame at 4, block '2' holds 5..8.
  FlipColumn? gapped(int frame) {
    if (frame >= 0 && frame < 4) {
      return (start: 0, endExclusive: 4);
    }
    if (frame >= 5 && frame < 9) {
      return (start: 5, endExclusive: 9);
    }
    return null;
  }

  /// `1---2---` — the same two blocks with nothing between them.
  FlipColumn? glued(int frame) {
    if (frame >= 0 && frame < 4) {
      return (start: 0, endExclusive: 4);
    }
    if (frame >= 4 && frame < 8) {
      return (start: 4, endExclusive: 8);
    }
    return null;
  }

  int step(FlipColumnAt columnAt, int frame, int direction) =>
      flipColumnStep(frame: frame, direction: direction, columnAt: columnAt);

  group('rightwards', () {
    test('a head lands on where its block ENDS, not on the next block', () {
      // The reported case: from '1' you reach x, not '2'.
      expect(step(gapped, 0, 1), 4);
    });

    test('the gap frame then leads into the next block', () {
      expect(step(gapped, 4, 1), 5);
    });

    test('a glued neighbour IS where the block ends, so nothing changes', () {
      expect(step(glued, 0, 1), 4);
    });

    test('a hold belongs to its block, so one step leaves the whole run', () {
      expect(step(gapped, 2, 1), 4);
      expect(step(gapped, 3, 1), 4);
    });

    test('★ rightwards is never blocked — past the last block, past the '
        'end of everything', () {
      // The axis does not stop where the material does. What lies past a
      // cut's last frame is the caller's question, not the step's.
      expect(step(gapped, 5, 1), 9);
      expect(step(gapped, 8, 1), 9, reason: 'mid-hold of the last block');
      expect(step(gapped, 9, 1), 10);
      expect(step(gapped, 400, 1), 401);
    });
  });

  group('leftwards — the direction that was wrong', () {
    test('from a block head, back into the gap before it', () {
      // Was jumping all the way to block 1's head, skipping x entirely.
      expect(step(gapped, 5, -1), 4);
    });

    test('from the frame after a block ends, to that block HEAD', () {
      expect(step(gapped, 4, -1), 0);
    });

    test('glued blocks step head to head', () {
      expect(step(glued, 4, -1), 0);
    });

    test('walks off the front, for the caller to floor at the film start', () {
      expect(step(gapped, 0, -1), -1);
      expect(step(gapped, 2, -1), -1, reason: 'from inside the first column');
    });
  });

  group('the two directions undo each other', () {
    test('every column is reachable both ways', () {
      final forward = <int>[0];
      var frame = 0;
      while (frame < 9) {
        frame = step(gapped, frame, 1);
        if (frame < 9) {
          forward.add(frame);
        }
      }
      expect(forward, [0, 4, 5]);

      final backward = <int>[];
      frame = 5;
      while (frame > 0) {
        frame = step(gapped, frame, -1);
        backward.add(frame);
      }
      expect(backward, [4, 0]);
    });
  });

  group('degenerate axes', () {
    test('a zero direction stands still', () {
      expect(step(gapped, 3, 0), 3);
    });

    test('a bare axis walks one frame at a time', () {
      FlipColumn? nothing(int frame) => null;
      expect(step(nothing, 0, 1), 1);
      expect(step(nothing, 4, 1), 5);
      expect(step(nothing, 3, -1), 2);
      expect(step(nothing, 0, -1), -1);
    });
  });

  group('★ one step = one HUD column', () {
    test('the walk visits exactly the columns the window draws', () {
      // The window and the movement must not be able to disagree about
      // what a column is: this is the guard that keeps them one rule.
      const row = FlipHudRow(
        name: 'A',
        kind: LayerKind.animation,
        runs: [
          FlipHudRun(startIndex: 2, length: 3, label: '1'),
          FlipHudRun(startIndex: 5, length: 2, label: '2'),
          FlipHudRun(startIndex: 10, length: 1, label: '3'),
        ],
      );
      const frameCount = 15;
      FlipColumn? columnAt(int frame) {
        final run = row.runAt(frame);
        return run == null
            ? null
            : (start: run.startIndex, endExclusive: run.endIndexExclusive);
      }

      final visited = <int>[0];
      var frame = 0;
      while (true) {
        frame = step(columnAt, frame, 1);
        if (frame >= frameCount) {
          break;
        }
        visited.add(frame);
      }

      expect(
        visited,
        flipHudBlockSlots(row, frameCount).map((slot) => slot.startIndex),
      );
    });
  });
}
