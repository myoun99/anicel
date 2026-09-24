import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';

import '../../models/canvas_viewport.dart';
import '../../services/cache_invalidation_executor.dart';
import '../../services/history_manager.dart';
import '../brush/brush_tool_state.dart';
import '../sheet/sheet_ink_layer.dart';
import 'cut_envelope_ink.dart';

/// The envelope's ink input layer: one brush canvas per MOUNTED box.
///
/// Mounting is gated ([mountedEnvelopeInkWindows]) because the analog form
/// has 86 inking boxes and each window costs a session. With the gate the
/// count sits at conte's order of magnitude, which is what lets this keep
/// the per-window structure — a stroke stays in the box it started in for
/// free, through pointer capture, instead of being routed by hand.
///
/// The gate is applied by the HOST, not here: the page painter has to skip
/// exactly the boxes this layer mounts, and one shared list is what keeps
/// the two from ever disagreeing (which would double-composite a stroke,
/// or lose it).
class CutEnvelopeInkOverlay extends StatelessWidget {
  const CutEnvelopeInkOverlay({
    super.key,
    required this.controller,
    required this.windows,
    required this.brushToolState,
    required this.historyManager,
    required this.viewport,
    required this.strokeActive,
    this.cacheInvalidationSink,
  });

  final CutEnvelopeInkController controller;

  /// The windows to mount — already gated.
  final List<SheetInkWindow> windows;

  /// Forwarded to [SheetInkLayer.brushToolState] — heard, not handed over.
  final ValueListenable<BrushToolState> brushToolState;
  final HistoryManager historyManager;

  /// The live panel viewport — the same transform the painter applies.
  final CanvasViewport viewport;

  /// Raised while any window has a stroke in progress, so the panel's
  /// gesture layer holds navigation exactly as it does for canvas strokes.
  final ValueNotifier<bool> strokeActive;

  final CacheInvalidationSink? cacheInvalidationSink;

  @override
  Widget build(BuildContext context) {
    return SheetInkLayer(
      windows: windows,
      keyPrefix: 'envelope',
      viewport: viewport,
      brushToolState: brushToolState,
      strokeActive: strokeActive,
      // ⛔One plane, so the window's plane stays null and this controller
      // never asks. That is the whole shape of the envelope's difference.
      sessionStateFor: (window) => controller.sessionStateFor(null, window.key),
      onStrokeCommitted: (window, strokeData) => controller.commitStroke(
        plane: null,
        key: window.key,
        strokeData: strokeData,
        historyManager: historyManager,
        cacheInvalidationSink: cacheInvalidationSink,
      ),
    );
  }
}
