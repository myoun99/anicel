import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/brush_dab.dart';
import 'package:anicel/src/models/brush_tip_shape.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/services/commands/brush_lift_move_history_command.dart';
import 'package:anicel/src/services/history_manager.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/brush_canvas_fixture.dart';

/// 🚨★★★**THE CRASH THIS WHOLE ROUND IS ABOUT** (유저 2026-08-27:
/// 「세번째, 네번째 변형쯤에서 말없이 앱 종료됨」 — iPhone, repeated
/// transforms on a large cel).
///
/// A confirmed move retains a PRE and a POST full-canvas surface, so the
/// third or fourth one crossed half a gigabyte. The budget's answer used
/// to be to DELETE the deep end — which stopped the crash by throwing the
/// user's work away, and said nothing while it did.
///
/// This drives the real command, not a fake: four confirms, a budget too
/// small for any of them, and then the whole way back. The middle steps
/// are reading their pictures off disk.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  BrushDab stampAt(double x, int colour) {
    return BrushDab(
      center: CanvasPoint(x: x, y: 8),
      color: colour,
      size: 8,
      opacity: 1,
      flow: 1,
      hardness: 1,
      tipShape: BrushTipShape.square,
      pressure: 1,
      sequence: 0,
    );
  }

  test('five confirmed transforms over one another: the budget holds, no '
      'entry is lost, and every undo still has its picture', () async {
    final coordinator = BrushCanvasFixture.createCoordinator();
    final key = coordinator.activeFrameKey;
    final history = HistoryManager()..byteBudget = 1;

    // ⚠️A confirm that CREATES its tiles owes nothing — undoing it
    // restores their absence, and no snapshot is keeping them alive. So
    // the first two put ink in two DIFFERENT tiles (one of which nothing
    // touches again, which is what makes the shared half real), and the
    // ones after paint over the same place — what a repeated transform
    // does, and what actually costs bytes.
    final pictures = <BitmapSurface>[coordinator.currentSurfaceOf(key)];
    const confirms = [
      (1200.0, 0xFF102030), // a far tile, never touched again
      (16.0, 0xFF405060),
      (16.0, 0xFF708090),
      (16.0, 0xFFA0B0C0),
      (16.0, 0xFFD0E0F0),
    ];
    for (final (x, colour) in confirms) {
      history.execute(
        BrushLiftMoveHistoryCommand(
          coordinator: coordinator,
          frameKey: key,
          preLiftSurface: coordinator.currentSurfaceOf(key),
          stampDab: stampAt(x, colour),
        ),
      );
      pictures.add(coordinator.currentSurfaceOf(key));
    }
    final residentBeforeSpill = history.retainedBytes;
    expect(
      residentBeforeSpill,
      greaterThan(0),
      reason: 'fixture premise: the confirms really do retain pixels',
    );

    await history.drainSpilling();

    expect(
      history.undoCount,
      confirms.length,
      reason: '⛔the whole round: over budget must not cost the user an edit',
    );
    expect(
      history.retainedBytes,
      lessThan(residentBeforeSpill),
      reason: 'and the claim is about RAM — the bytes are a file now',
    );

    // All the way back. Every step but the last reads its picture out of
    // the run's 휘발성 room, decodes it, and puts it on the cel.
    for (var step = confirms.length; step > 0; step -= 1) {
      history.undo();
      expect(
        coordinator.currentSurfaceOf(key),
        pictures[step - 1],
        reason: 'undo #$step came back from wherever its payload was',
      );
    }
  });
}
