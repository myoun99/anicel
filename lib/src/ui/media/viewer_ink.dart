import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/widgets.dart';

import '../../models/brush_frame_key.dart';
import '../../models/canvas_size.dart';
import '../../models/canvas_viewport.dart';
import '../../models/sheet_marks.dart';
import '../../models/sheet_paper.dart' show SheetPaper;
import '../../models/viewer_ink_keys.dart';
import '../../services/brush_frame_editing_coordinator.dart';
import '../../services/brush_frame_store.dart';
import '../../services/cache_invalidation_executor.dart';
import '../../services/history_manager.dart';
import '../brush/brush_tool_state.dart';
import '../sheet/sheet_ink_controller.dart';
import '../sheet/sheet_ink_layer.dart';

/// The ink the viewers write on the files the project carries (I-114):
/// the session's viewer ink store, through a plane of its own per page
/// size — a file's pages may differ, and a coordinator holds one size. The
/// plane of a window is its page's surface size.
class ViewerInkController extends SheetInkController<CanvasSize> {
  ViewerInkController({required BrushFrameStore store})
    : _store = store,
      super(const {}) {
    store.celPixelRevision.addListener(notifyListeners);
  }

  final BrushFrameStore _store;

  final Map<CanvasSize, InkPlaneSlot> _pages = {};

  /// Where a plane stands before its first page is selected — never a page
  /// of a file, and never written: every read and commit selects the
  /// window's own page first.
  static final BrushFrameKey _standing = viewerInkPageKey('standing', -1);

  @override
  BrushFrameEditingCoordinator coordinatorFor(CanvasSize plane) => _pages
      .putIfAbsent(
        plane,
        () => InkPlaneSlot(store: _store, initialFrameKey: _standing)
          ..syncTo(plane),
      )
      .coordinator;

  @override
  BrushFrameStore storeFor(CanvasSize plane) => _store;


  @override
  void dispose() {
    _store.celPixelRevision.removeListener(notifyListeners);
    super.dispose();
  }
}

/// Surface pixels per unit of a page — a file of pixels is written at its
/// own pixels; one drawn at any size (a PDF's points) at the sheets' 300dpi
/// paper, so a pen on it is as fine as on the conte's.
double viewerInkScale({required bool drawnAtAnySize}) =>
    drawnAtAnySize ? SheetPaper.conte.dpi / 72 : 1;

/// The window a viewer writes [page] of the carried file [carry] through —
/// the page's whole picture, nothing round it (「밖 배경영역 말고」), at
/// [scale] surface pixels per page unit.
SheetInkWindow viewerInkWindow({
  required String carry,
  required int page,
  required Rect rect,
  required double scale,
}) => SheetInkWindow(
  id: 'page-$page',
  key: viewerInkPageKey(carry, page),
  plane: viewerInkPlaneOf(rect.size, scale),
  placement: SheetInkPlacement(window: rect, scale: scale),
);

/// The surface size a page of [size] page units is written on at [scale].
CanvasSize viewerInkPlaneOf(Size size, double scale) => CanvasSize(
  width: (size.width * scale).ceil().clamp(1, 1 << 15).toInt(),
  height: (size.height * scale).ceil().clamp(1, 1 << 15).toInt(),
);

/// The viewer's ink windows, mounted while its brush is on — the one
/// [SheetInkLayer] every sheet writes through, each window's plane its
/// page's surface size.
class ViewerInkOverlay extends StatelessWidget {
  const ViewerInkOverlay({
    super.key,
    required this.keyPrefix,
    required this.controller,
    required this.windows,
    required this.brushToolState,
    required this.historyManager,
    required this.viewport,
    required this.strokeActive,
    required this.strokes,
    this.cacheInvalidationSink,
  });

  /// The viewer's own key prefix — the main viewer's and the sub viewer's.
  final String keyPrefix;

  final ViewerInkController controller;
  final List<SheetInkWindow> windows;

  /// Forwarded to [SheetInkLayer.brushToolState] — heard, not handed over.
  final ValueListenable<BrushToolState> brushToolState;
  final HistoryManager historyManager;
  final CanvasViewport viewport;

  /// Forwarded to [SheetInkLayer.strokeActive].
  final ValueNotifier<bool> strokeActive;

  /// Forwarded to [SheetInkLayer.strokes].
  final SheetInkStrokes strokes;

  final CacheInvalidationSink? cacheInvalidationSink;

  @override
  Widget build(BuildContext context) => SheetInkLayer(
    windows: windows,
    keyPrefix: keyPrefix,
    viewport: viewport,
    brushToolState: brushToolState,
    strokeActive: strokeActive,
    strokes: strokes,
    history: historyManager.gestures,
    inkChanges: controller,
    sessionStateFor: (window) =>
        controller.sessionStateFor(window.plane! as CanvasSize, window.key),
    onStrokeCommitted: (window, strokeData) => controller.commitStroke(
      plane: window.plane! as CanvasSize,
      key: window.key,
      strokeData: strokeData,
      historyManager: historyManager,
      cacheInvalidationSink: cacheInvalidationSink,
    ),
  );
}
