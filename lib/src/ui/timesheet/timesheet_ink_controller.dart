import '../../models/brush_frame_key.dart';
import '../../models/canvas_size.dart';
import '../../models/cut_id.dart';
import '../../models/frame_id.dart';
import '../../models/layer_id.dart';
import '../../models/project_id.dart';
import '../../models/track_id.dart';
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
  page,
}

/// Owns the sheet ink stores: brush strokes on the timesheet, kept in
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
  TimesheetInkController()
    : this._(
        InkPlaneSlot(store: BrushFrameStore(), initialFrameKey: _initKey),
        InkPlaneSlot(store: BrushFrameStore(), initialFrameKey: _initKey),
      );

  TimesheetInkController._(this._strip, this._page)
    : super({TimesheetInkPlane.strip: _strip, TimesheetInkPlane.page: _page});

  /// Ink resolution multiplier over document space (72px per frame row —
  /// the plan's 4×). Affordable because the live-stroke rasterizer is
  /// tile-sparse: stroke cost scales with the ink actually drawn, never
  /// with the logical surface size.
  static const int inkScale = 4;

  /// The ink store is namespaced by these synthetic ids; they only need to
  /// be unique inside the controller's own stores.
  static const ProjectId inkProjectId = ProjectId('timesheet-ink');
  static const TrackId inkTrackId = TrackId('timesheet-ink');
  static const LayerId stripLayerId = LayerId('sheet-strip');
  static const LayerId pageLayerId = LayerId('sheet-page');

  static BrushFrameKey stripBandKey(CutId cutId, int band) {
    return BrushFrameKey(
      projectId: inkProjectId,
      trackId: inkTrackId,
      cutId: cutId,
      layerId: stripLayerId,
      frameId: FrameId('sheet-strip-${cutId.value}-b$band'),
    );
  }

  static BrushFrameKey pageKey(CutId cutId, int page) {
    return BrushFrameKey(
      projectId: inkProjectId,
      trackId: inkTrackId,
      cutId: cutId,
      layerId: pageLayerId,
      frameId: FrameId('sheet-page-${cutId.value}-p$page'),
    );
  }

  static const BrushFrameKey _initKey = BrushFrameKey(
    projectId: inkProjectId,
    trackId: inkTrackId,
    cutId: CutId('timesheet-ink-init'),
    layerId: stripLayerId,
    frameId: FrameId('timesheet-ink-init'),
  );

  final InkPlaneSlot _strip;
  final InkPlaneSlot _page;

  /// One page band of frame rows × the half column width, at [inkScale].
  CanvasSize? get stripBandSurfaceSize => _strip.size;

  /// The whole PAGED paper, at [inkScale].
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
        width: (pagedLayout.halfWidth * inkScale).ceil(),
        height:
            (document.pageFrameCount * TimesheetDocumentLayout.rowHeight)
                .ceil() *
            inkScale,
      ),
    );
    _page.syncTo(
      CanvasSize(
        width: (pagedLayout.paperWidth * inkScale).ceil(),
        height: (pagedLayout.paperHeight * inkScale).ceil(),
      ),
    );
  }
}
