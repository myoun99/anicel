import '../../models/brush_frame_key.dart';
import '../../models/canvas_size.dart';
import '../../models/cut_id.dart';
import '../../models/frame_id.dart';
import '../../models/timesheet_ink_keys.dart';
import '../../services/brush_frame_store.dart';
import '../../services/commands/brush_stroke_history_command.dart';
import '../../services/history_manager.dart';
import '../sheet/sheet_ink_controller.dart';
import 'timesheet_document_painter.dart';

/// The timesheet's ink: brush strokes on the timesheet, kept in a
/// coordinator/store fully SEPARATE from the session's cel
/// [BrushFrameStore] so sheet ink can never leak into cel rendering or
/// export. Strokes commit through the app [HistoryManager] with the same
/// [BrushStrokeHistoryCommand] the drawing canvas uses (undo parity), and
/// erase reuses the same blend routes untouched.
///
/// ONE plane: the paper (F-252, 유저 2026-10-01 「잉크는 용지에
/// 귀속됨」) — one surface per page ([timesheetInkPageKey]), the header,
/// the memo band, the margins and the column grid alike. ↩️The column grid
/// had a frame-anchored plane of its own, and F-252-Q1 (10-08) took it out.
///
/// 🚨It EXTENDS [SheetInkController] (F-80 ②, 2026-09-15). It was a plain
/// notifier beside that class, repeating its session lookup, its commit
/// and its has-ink oracle around two planes of its own — so the law that
/// makes a sheet hear its ink come back through undo had to be written in
/// the shared class, and would have reached every sheet but this one.
class TimesheetInkController extends SheetInkController<Null> {
  /// The store is the SESSION's when it hands it in, so the project
  /// archive saves and opens the timesheet's ink with the conte's and the
  /// envelope's; a test's controller makes its own.
  TimesheetInkController({BrushFrameStore? store})
    : this._(
        InkPlaneSlot(
          store: store ?? BrushFrameStore(),
          initialFrameKey: _initKey,
        ),
      );

  TimesheetInkController._(this._page) : super({null: _page});

  static const BrushFrameKey _initKey = BrushFrameKey(
    projectId: timesheetInkProjectId,
    trackId: timesheetInkTrackId,
    cutId: CutId('timesheet-ink-init'),
    layerId: timesheetInkPageLayerId,
    frameId: FrameId('timesheet-ink-init'),
  );

  final InkPlaneSlot _page;

  /// The whole paper, pixel for pixel
  /// ([TimesheetDocumentLayout.paperPixelSize]).
  CanvasSize? get pageSurfaceSize => _page.size;

  /// Adopts the paper's size from [layout]. A size change rebuilds the ink
  /// session from its durable commands with stroke coordinates preserved
  /// (top-left anchored, like canvas resize).
  ///
  /// Never notifies: callers run this during build.
  void syncGeometry(TimesheetDocumentLayout layout) =>
      _page.syncTo(layout.paperPixelSize);
}
