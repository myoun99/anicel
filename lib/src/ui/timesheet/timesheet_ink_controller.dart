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

/// Which sheet ink plane a stroke lands on.
enum TimesheetInkPlane {
  /// Frame-anchored ink over the half's column area: X = within-half
  /// offset, Y = frame row axis. One surface per PAGE BAND of frames
  /// (`sheet-strip-<cut>-b<n>`), so annotations follow their frames and
  /// switch losslessly between the paged and continuous views.
  strip,

  /// Paper-anchored ink over the whole page (header fields, Direction
  /// memo band, margins) — one surface per page
  /// (`sheet-page-<cut>-p<n>`); the continuous view shows page 1's in its
  /// identical header geometry.
  page;

  /// The plane [key]'s ink lives on — its layer says; the ink walk and the
  /// sheet's printing both ask here.
  static TimesheetInkPlane of(BrushFrameKey key) =>
      key.layerId == timesheetInkStripLayerId ? strip : page;
}

/// The timesheet's ink: brush strokes on the timesheet, kept in
/// coordinators/stores fully SEPARATE from the session's cel
/// [BrushFrameStore] so sheet ink can never leak into cel rendering or
/// export. Strokes commit through the app [HistoryManager] with the same
/// [BrushStrokeHistoryCommand] the drawing canvas uses (undo parity), and
/// erase reuses the same blend routes untouched.
///
/// 🚨It EXTENDS [SheetInkController] (F-80 ②, 2026-09-15). It was a plain
/// notifier beside that class, repeating its session lookup, its commit
/// and its has-ink oracle around two planes of its own — so the law that
/// makes a sheet hear its ink come back through undo had to be written in
/// the shared class, and would have reached every sheet but this one.
class TimesheetInkController extends SheetInkController<TimesheetInkPlane> {
  /// The strip and page stores are the SESSION's when it hands them in, so
  /// the project archive saves and opens the timesheet's ink with the
  /// conte's and the envelope's; a test's controller makes its own.
  TimesheetInkController({
    BrushFrameStore? stripStore,
    BrushFrameStore? pageStore,
  }) : this._(
         InkPlaneSlot(
           store: stripStore ?? BrushFrameStore(),
           initialFrameKey: _initKey,
         ),
         InkPlaneSlot(
           store: pageStore ?? BrushFrameStore(),
           initialFrameKey: _initKey,
         ),
       );

  TimesheetInkController._(this._strip, this._page)
    : super({TimesheetInkPlane.strip: _strip, TimesheetInkPlane.page: _page});

  static const BrushFrameKey _initKey = BrushFrameKey(
    projectId: timesheetInkProjectId,
    trackId: timesheetInkTrackId,
    cutId: CutId('timesheet-ink-init'),
    layerId: timesheetInkStripLayerId,
    frameId: FrameId('timesheet-ink-init'),
  );

  final InkPlaneSlot _strip;
  final InkPlaneSlot _page;

  /// One page band of frame rows × the half column width, at
  /// [timesheetInkScale].
  CanvasSize? get stripBandSurfaceSize => _strip.size;

  /// The whole PAGED paper, at [timesheetInkScale].
  CanvasSize? get pageSurfaceSize => _page.size;

  /// Adopts the sheet geometry from the PAGED layout (both view modes
  /// share it — the paper never resizes with the view toggle). Geometry
  /// changes rebuild the ink sessions from their durable commands with
  /// stroke coordinates preserved (top-left anchored, like canvas resize).
  ///
  /// Never notifies: callers run this during build.
  void syncGeometry(TimesheetDocumentLayout pagedLayout) {
    final document = pagedLayout.document;
    _strip.syncTo(
      CanvasSize(
        width: (pagedLayout.halfWidth * timesheetInkScale).ceil(),
        height:
            (document.pageFrameCount * TimesheetDocumentLayout.rowHeight)
                .ceil() *
            timesheetInkScale,
      ),
    );
    _page.syncTo(
      CanvasSize(
        width: (pagedLayout.paperWidth * timesheetInkScale).ceil(),
        height: (pagedLayout.paperHeight * timesheetInkScale).ceil(),
      ),
    );
  }
}
