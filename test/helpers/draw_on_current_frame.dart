import 'package:anicel/src/models/brush_dab.dart';
import 'package:anicel/src/models/brush_history_policy.dart';
import 'package:anicel/src/models/brush_tip_shape.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/services/brush_frame_edit_session_store.dart';
import 'package:anicel/src/services/brush_frame_editing_coordinator.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';

/// Puts one real drawing — a cel with a dab of ink — on [s]'s current frame:
/// the work a save has to carry.
///
/// ⛔ONE COPY. Three save tests wrote this out byte for byte (the audit's
/// copy count, 2026-09-15: coordinated_replace_fallback_test,
/// save_as_staging_archive_test, save_progress_report_test); a fixture that
/// drifts in one of them tests a different drawing than the other two claim.
///
/// ⚠️The ink goes through a coordinator of its own, straight into the
/// session's frame store — NOT through the history manager.
void drawOnCurrentFrame(EditorSessionManager s) {
  s.createDrawingAtCurrentFrame();
  final selection = s.editingCanvas.activeBrushEditorSelection!;
  BrushFrameEditingCoordinator(
    initialFrameKey: s.brushFrameKeyForCut(
      s.requireActiveCut,
      selection.layerId,
      selection.frameId,
    ),
    frameStore: s.renderCaches.brushFrameStore,
    sessionStore: BrushFrameEditSessionStore(
      canvasSize: s.requireActiveCut.canvasSize,
      tileSize: 256,
    ),
    historyPolicy: const BrushHistoryPolicy(),
  ).commitSourceStroke(
    sourceDabs: [
      BrushDab(
        center: CanvasPoint(x: 10, y: 10),
        color: 0xFF000000,
        size: 4,
        opacity: 1,
        flow: 1,
        hardness: 1,
        tipShape: BrushTipShape.round,
        pressure: 1,
        sequence: 0,
      ),
    ],
  );
}
