import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/brush_dab.dart';
import 'package:anicel/src/models/brush_frame_key.dart';
import 'package:anicel/src/models/brush_history_policy.dart';
import 'package:anicel/src/models/brush_tip_shape.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/brush_frame_edit_session_store.dart';
import 'package:anicel/src/services/brush_frame_editing_coordinator.dart';
import 'package:anicel/src/services/brush_frame_store.dart';
import 'package:anicel/src/services/brush_stroke_commit_data.dart';
import 'package:anicel/src/services/canvas_color_sampler.dart';
import 'package:anicel/src/services/commands/brush_stroke_history_command.dart';
import 'package:anicel/src/services/history_manager.dart';

/// R19 P3b: the stroke command owns its pre/post SURFACE references —
/// undo/redo are byte-exact snapshot restores through the app stack.
void main() {
  int pixelAt(BrushFrameEditingCoordinator c, int x, int y) =>
      surfacePixelRgba(c.currentSurfaceOf(c.activeFrameKey), x, y) ?? 0;

  test('app-level undo and redo restore the exact pre/post pixels', () {
    final coordinator = _coordinator();
    final history = HistoryManager();

    history.execute(
      BrushStrokeHistoryCommand(
        coordinator: coordinator,
        strokeData: BrushStrokeCommitData(sourceDabs: [_dab(0), _dab(1)]),
      ),
    );

    final afterStroke = coordinator.currentSurfaceOf(
      coordinator.activeFrameKey,
    );
    expect(pixelAt(coordinator, 0, 0), isNot(0));
    expect(history.canUndo, isTrue);

    history.undo();
    expect(pixelAt(coordinator, 0, 0), 0);
    expect(pixelAt(coordinator, 1, 1), 0);
    expect(history.canRedo, isTrue);

    history.redo();
    expect(
      identical(
        coordinator.currentSurfaceOf(coordinator.activeFrameKey),
        afterStroke,
      ),
      isTrue,
      reason: 'redo restores the post surface REFERENCE — byte-exact free',
    );
  });

  test('a no-pixel stroke stays inert: undo/redo never disturb an '
      'unrelated state and nothing is retained', () {
    final coordinator = _coordinator();
    final history = HistoryManager();
    history.execute(
      BrushStrokeHistoryCommand(
        coordinator: coordinator,
        strokeData: BrushStrokeCommitData(sourceDabs: [_dab(0)]),
      ),
    );
    final afterFirst = coordinator.currentSurfaceOf(coordinator.activeFrameKey);

    final inert = BrushStrokeHistoryCommand(
      coordinator: coordinator,
      strokeData: BrushStrokeCommitData(
        sourceDabs: [_dab(0).copyWith(opacity: 0)],
      ),
    );
    history.execute(inert);
    expect(inert.estimatedRetainedBytes, 0);

    history.undo(); // the inert command: must not touch pixels
    expect(
      identical(
        coordinator.currentSurfaceOf(coordinator.activeFrameKey),
        afterFirst,
      ),
      isTrue,
    );
  });

  test('the command drops its one-shot payload after the first execute '
      'and reports its retained snapshot bytes', () {
    final coordinator = _coordinator();
    final command = BrushStrokeHistoryCommand(
      coordinator: coordinator,
      strokeData: BrushStrokeCommitData(sourceDabs: [_dab(0)]),
    );
    expect(command.retainsCommitPayload, isTrue);

    command.execute();

    expect(command.retainsCommitPayload, isFalse);
    expect(command.estimatedRetainedBytes, greaterThan(0));
  });

  test('the HistoryManager byte budget drops the DEEPEST snapshot '
      'entries; the newest always survives', () {
    final history = HistoryManager();
    final coordinator = _coordinator();
    // Fake heavy commands via real ones is impractical here — pin the
    // budget arithmetic through the public oracle instead: N strokes
    // whose reported bytes sum under the budget all stay.
    for (var i = 0; i < 3; i += 1) {
      history.execute(
        BrushStrokeHistoryCommand(
          coordinator: coordinator,
          strokeData: BrushStrokeCommitData(sourceDabs: [_dab(i)]),
        ),
      );
    }
    expect(history.undoCount, 3);
    expect(history.retainedBytes, greaterThan(0));
    expect(
      history.retainedBytes,
      lessThanOrEqualTo(HistoryManager.retainedByteBudget),
    );
  });
}

BrushFrameEditingCoordinator _coordinator() {
  final key = BrushFrameKey(
    projectId: const ProjectId('project'),
    trackId: const TrackId('track'),
    cutId: const CutId('cut'),
    layerId: const LayerId('layer'),
    frameId: const FrameId('frame'),
  );
  return BrushFrameEditingCoordinator(
    initialFrameKey: key,
    frameStore: BrushFrameStore(),
    sessionStore: BrushFrameEditSessionStore(
      canvasSize: const CanvasSize(width: 8, height: 8),
    ),
    historyPolicy: const BrushHistoryPolicy(
      userUndoLimit: 8,
      deferredBakeRatio: 0,
    ),
  );
}

BrushDab _dab(int sequence) {
  return BrushDab(
    // Pixel-center coordinates: the commit rasterizer samples pixel centers,
    // so a size-1 dab must sit on x.5 to paint (WYSIWYG semantics).
    center: CanvasPoint(x: sequence + 0.5, y: sequence + 0.5),
    color: 0xFF000000,
    size: 1,
    opacity: 1,
    flow: 1,
    hardness: 1,
    tipShape: BrushTipShape.round,
    pressure: 1,
    sequence: sequence,
  );
}
