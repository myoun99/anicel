import 'package:anicel/src/models/brush_dab.dart';
import 'package:anicel/src/models/brush_frame_key.dart';
import 'package:anicel/src/models/brush_history_policy.dart';
import 'package:anicel/src/models/brush_tip_shape.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
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
  inkTheCurrentCel(s);
}

/// The dab of ink [drawOnCurrentFrame] puts down, into the cel [s] already
/// stands on — for a test that has to see that cel BEFORE it is inked.
void inkTheCurrentCel(EditorSessionManager s) {
  final selection = s.editingCanvas.activeBrushEditorSelection!;
  inkCel(
    s,
    s.brushFrameKeyForCut(
      s.requireActiveCut,
      selection.layerId,
      selection.frameId,
    ),
    canvasSize: s.requireActiveCut.canvasSize,
    at: CanvasPoint(x: 10, y: 10),
    size: 4,
  );
}

/// A round dab of black ink, [size] across at [at], into [key]'s cel — any
/// cel of [s]'s, the one stood on or not — the way [inkTheCurrentCel] puts
/// its own: through a coordinator of its own, straight into the frame store.
void inkCel(
  EditorSessionManager s,
  BrushFrameKey key, {
  required CanvasSize canvasSize,
  required CanvasPoint at,
  required double size,
  BrushTipShape tipShape = BrushTipShape.round,
}) {
  BrushFrameEditingCoordinator(
    initialFrameKey: key,
    frameStore: s.renderCaches.brushFrameStore,
    sessionStore: BrushFrameEditSessionStore(
      canvasSize: canvasSize,
      tileSize: 256,
    ),
    historyPolicy: const BrushHistoryPolicy(),
  ).commitSourceStroke(
    sourceDabs: [
      BrushDab(
        center: at,
        color: 0xFF000000,
        size: size,
        opacity: 1,
        flow: 1,
        hardness: 1,
        tipShape: tipShape,
        pressure: 1,
        sequence: 0,
      ),
    ],
  );
}
