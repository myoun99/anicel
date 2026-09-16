import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../models/app_input_settings.dart' show CanvasTouchDragAction;
import '../../models/canvas_size.dart';
import '../../models/canvas_viewport.dart';
import '../../services/cache_invalidation_executor.dart';
import '../canvas/viewport_canvas_transform.dart';
import '../effective_device_pixel_ratio.dart';
import 'brush_canvas_panel.dart';

/// A PAPER panel: [BrushCanvasPanel] as the sheets mount it — no editing
/// coordinator, no frame keys, a host-local invalidation sink, a view that
/// never rotates, and a viewport snapped ONCE before any stratum reads it.
///
/// ONE recipe for the four sheet panels (the timesheet's paged and gap
/// panels, the conte, the cut envelope), which each typed it out and each
/// carried the P8 decision below. What differs are values: the paper's
/// size, the bars' contents, the fit rect, an auto-frame request, the
/// stroke gate, and the [content] Stack a host lays over the snapped view.
///
/// 🚨★★★SNAPPED ONCE, HERE (P8, 유저 답 `host` 2026-08-28).
///
/// The paper below and the ink windows above BOTH derive from
/// this. A painter that snapped for itself and an ink window
/// that snapped for itself would land on the same device grid
/// from different starting values — `round(pan) + zoom*left`
/// versus `round(pan + zoom*left)` — and part company by up to a
/// whole device pixel at fractional pans, which reads as the ink
/// jumping off the box the moment the pen lifts. One value
/// cannot drift from itself.
class SheetCanvasPanel extends StatelessWidget {
  const SheetCanvasPanel({
    super.key,
    required this.cacheInvalidationSink,
    required this.canvasSize,
    required this.viewport,
    this.viewportController,
    this.onViewportChanged,
    this.bottomBarLeading = const <Widget>[],
    this.pageStrip = const <Widget>[],
    this.bottomBarHostToken,
    this.fitFocusRect,
    this.autoFrame,
    this.contentStrokeActive,
    required this.drawingOn,
    required this.content,
  });

  final CacheInvalidationSink cacheInvalidationSink;
  final CanvasSize canvasSize;
  final CanvasViewport? viewport;
  final ValueNotifier<CanvasViewport?>? viewportController;
  final ValueChanged<CanvasViewport>? onViewportChanged;
  final List<Widget> bottomBarLeading;
  final List<Widget> pageStrip;
  final Object? bottomBarHostToken;
  final Rect? fitFocusRect;
  final CanvasAutoFrameRequest? autoFrame;
  final ValueListenable<bool>? contentStrokeActive;

  /// Whether this sheet's DRAWING is on — the sheet's answer to
  /// [BrushCanvasPanel.runsTheSelectedTool] (F-80).
  ///
  /// ⛔Asked separately from [contentStrokeActive] on purpose. That one says
  /// a stroke is LIVE right now, and reading its NULLNESS as 「this sheet
  /// takes no tool」 made one flag answer two questions (유저 2026-09-16:
  /// 「법 통일할수있을거같은데」).
  final bool drawingOn;

  /// The sheet's strata, laid over the SNAPPED viewport.
  final Widget Function(BuildContext context, CanvasViewport viewport) content;

  @override
  Widget build(BuildContext context) {
    return BrushCanvasPanel(
      coordinator: null,
      availableFrameKeys: const [],
      cacheInvalidationSink: cacheInvalidationSink,
      canvasSize: canvasSize,
      viewport: viewport,
      viewportController: viewportController,
      onViewportChanged: onViewportChanged,
      // The sheet's ink/header overlays speak zoom/pan only — the paper
      // never rotates (the timesheet's rule; P8 is the drawing canvas's).
      allowViewRotation: false,
      bottomBarLeading: bottomBarLeading,
      pageStrip: pageStrip,
      bottomBarHostToken: bottomBarHostToken,
      fitFocusRect: fitFocusRect,
      autoFrame: autoFrame,
      contentStrokeActive: contentStrokeActive,
      // F-80: a sheet runs the selected tool while its drawing is ON. With
      // it off nothing here can act, so the panel makes a plain primary
      // press pan — one that no control on the sheet has taken (a timesheet
      // head cell, a conte cell) — and one finger pans as the viewer does
      // (I-14).
      oneFingerAction: drawingOn ? null : CanvasTouchDragAction.navigate,
      runsTheSelectedTool: drawingOn,
      contentOverride: (context, rawViewport) => content(
        context,
        renderSnappedViewport(
          rawViewport,
          EffectiveDevicePixelRatio.of(context),
        ),
      ),
    );
  }
}
