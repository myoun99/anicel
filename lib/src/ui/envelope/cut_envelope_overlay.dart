import 'package:flutter/material.dart';

import '../../models/canvas_viewport.dart';
import '../../services/cache_invalidation_executor.dart';
import '../../services/history_manager.dart';
import '../brush/brush_tool_state.dart';
import '../canvas/interactive_brush_edit_canvas_view.dart';
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
  final List<EnvelopeInkWindow> windows;

  final BrushToolState brushToolState;
  final HistoryManager historyManager;

  /// The live panel viewport — the same transform the painter applies.
  final CanvasViewport viewport;

  /// Raised while any window has a stroke in progress, so the panel's
  /// gesture layer holds navigation exactly as it does for canvas strokes.
  final ValueNotifier<bool> strokeActive;

  final CacheInvalidationSink? cacheInvalidationSink;

  @override
  Widget build(BuildContext context) {
    final inputSettings = brushToolState.toInputSettings();
    return Stack(
      children: [
        for (final window in windows)
          Positioned.fill(
            child: ClipRect(
              clipper: _WindowRectClipper(window.screenRect(viewport)),
              child: RepaintBoundary(
                child: InteractiveBrushEditCanvasView(
                  key: ValueKey<String>('envelope-ink-${window.boxId}'),
                  sessionState: controller.sessionStateFor(window.key),
                  layerId: window.key.layerId,
                  frameId: window.key.frameId,
                  inputSettings: inputSettings,
                  viewport: window.inkViewport(viewport),
                  // The paper is painted below this stack; an opaque
                  // background here would cover it.
                  showTransparentBackground: false,
                  onActiveStrokeChanged: (active) {
                    strokeActive.value = active;
                  },
                  onSourceStrokeCommitted: (strokeData) {
                    controller.commitStroke(
                      key: window.key,
                      strokeData: strokeData,
                      historyManager: historyManager,
                      cacheInvalidationSink: cacheInvalidationSink,
                    );
                  },
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _WindowRectClipper extends CustomClipper<Rect> {
  const _WindowRectClipper(this.rect);

  final Rect rect;

  @override
  Rect getClip(Size size) => rect;

  @override
  bool shouldReclip(_WindowRectClipper oldClipper) => oldClipper.rect != rect;
}
