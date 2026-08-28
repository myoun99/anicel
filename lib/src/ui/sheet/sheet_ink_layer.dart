import 'package:flutter/material.dart';

import '../../models/brush_frame_key.dart';
import '../../models/canvas_viewport.dart';
import '../../models/brush_edit_session_state.dart';
import '../../services/brush_stroke_commit_data.dart';
import '../brush/brush_tool_state.dart';
import '../canvas/interactive_brush_edit_canvas_view.dart';

/// 🚨★★★ONE ON-SHEET INK WINDOW, for every sheet that has them.
///
/// The timesheet, the conte and the cut envelope each had their own
/// `XInkWindow` + `XInkLayer` + a private `_WindowRectClipper`, and an
/// audit on 2026-08-28 (유저: 「사본은 특히 위험한대상이야」) found the
/// three [screenRect] bodies **byte-identical** and the three `build`
/// methods identical down to their comments. Only three things actually
/// differed: the widget-key prefix, whether the panel has a plane axis,
/// and where the ink scale came from.
///
/// ⛔THE THREE [inkViewport] FORMULAS WERE ALREADY ONE. The conte and the
/// envelope map surface pixel (0,0) to the window's top-left; the
/// timesheet maps [inkOffset] there instead. With `inkOffset` at the
/// origin the timesheet's expression IS the other two, term for term — so
/// this is one law with a default, not a law with an exception.
@immutable
class SheetInkWindow {
  const SheetInkWindow({
    required this.id,
    required this.key,
    required this.documentRect,
    required this.surfaceScale,
    this.plane,
    this.inkOffset = Offset.zero,
  });

  /// WHICH of the panel's ink planes this window belongs to — the
  /// timesheet's page/strip, the conte's paper/cell. ⛔This layer never
  /// reads it: it hands the window back to [SheetInkLayer.sessionStateFor]
  /// and [SheetInkLayer.onStrokeCommitted], and the panel that made the
  /// window is the only thing that knows what its planes mean. A sheet
  /// with one plane (the envelope) leaves it null.
  final Object? plane;

  /// Identifies the WINDOW, not the surface.
  ///
  /// The same strip band surface appears through TWO windows on a paged
  /// timesheet (the page's left and right halves), so the frame key cannot
  /// stand in for this.
  final String id;

  final BrushFrameKey key;

  /// The window's rect in the sheet's document space.
  final Rect documentRect;

  /// Ink-surface pixels per document unit.
  final double surfaceScale;

  /// Ink-surface pixel that maps to [documentRect]'s top-left. The origin
  /// for every sheet that gives each window its own surface; the
  /// timesheet's strip bands share one surface and slice it with this.
  final Offset inkOffset;

  /// The viewport the interactive brush view needs so ink pixel (x, y)
  /// lands exactly where the sheet paints this window: the panel transform
  /// composed with the window placement and the surface scale.
  CanvasViewport inkViewport(CanvasViewport panelViewport) {
    final inkZoom = panelViewport.zoom / surfaceScale;
    return CanvasViewport(
      zoom: inkZoom,
      panX:
          panelViewport.panX +
          panelViewport.zoom * documentRect.left -
          inkZoom * inkOffset.dx,
      panY:
          panelViewport.panY +
          panelViewport.zoom * documentRect.top -
          inkZoom * inkOffset.dy,
    );
  }

  /// The window's slice of its ink surface, in SURFACE pixels.
  ///
  /// The envelope carried this on its own window class and started at the
  /// origin, which is right for a sheet that gives each window its own
  /// surface. Starting at [inkOffset] instead is the same expression for
  /// those sheets and the correct one for a shared surface — the
  /// timesheet's strip bands.
  Rect get surfaceRect => Rect.fromLTWH(
    inkOffset.dx,
    inkOffset.dy,
    documentRect.width * surfaceScale,
    documentRect.height * surfaceScale,
  );

  /// The window's on-screen rect under the panel transform — the input hit
  /// region and the display clip.
  Rect screenRect(CanvasViewport panelViewport) => Rect.fromLTWH(
    panelViewport.panX + panelViewport.zoom * documentRect.left,
    panelViewport.panY + panelViewport.zoom * documentRect.top,
    panelViewport.zoom * documentRect.width,
    panelViewport.zoom * documentRect.height,
  );
}

/// The live ink input windows for ONE sheet panel, bottom-of-stack first.
///
/// The caller keeps its own controller and its own plane axis: it answers
/// [sessionStateFor] and [onStrokeCommitted] for a window and this widget
/// asks nothing about what a plane is. That is what let three panels with
/// three different controller shapes mount ink through one widget.
class SheetInkLayer extends StatelessWidget {
  const SheetInkLayer({
    super.key,
    required this.windows,
    required this.keyPrefix,
    required this.viewport,
    required this.brushToolState,
    required this.strokeActive,
    required this.sessionStateFor,
    required this.onStrokeCommitted,
  });

  final List<SheetInkWindow> windows;

  /// Widget-key prefix — `timesheet`, `conte`, `envelope`. Each window's
  /// key is `<prefix>-ink-<window id>`, which is what the panels spelled
  /// by hand.
  final String keyPrefix;

  /// The live panel viewport — the same transform the sheet painter takes.
  final CanvasViewport viewport;

  final BrushToolState brushToolState;

  /// Raised while any window has a stroke in progress, so the panel's
  /// gesture layer holds navigation exactly as it does for canvas strokes.
  final ValueNotifier<bool> strokeActive;

  final BrushEditSessionState Function(SheetInkWindow window) sessionStateFor;

  final void Function(SheetInkWindow window, BrushStrokeCommitData strokeData)
  onStrokeCommitted;

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
                  key: ValueKey<String>('$keyPrefix-ink-${window.id}'),
                  sessionState: sessionStateFor(window),
                  layerId: window.key.layerId,
                  frameId: window.key.frameId,
                  inputSettings: inputSettings,
                  viewport: window.inkViewport(viewport),
                  // The sheet paper is painted below this stack; an opaque
                  // background here would cover it.
                  showTransparentBackground: false,
                  onActiveStrokeChanged: (active) {
                    strokeActive.value = active;
                  },
                  onSourceStrokeCommitted: (strokeData) =>
                      onStrokeCommitted(window, strokeData),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// ⛔THE ONLY ONE. Three panels each carried a byte-identical private copy
/// of this before the 08-28 audit; `CustomClipper<Rect>` has exactly one
/// implementation in the app and this is it.
class _WindowRectClipper extends CustomClipper<Rect> {
  const _WindowRectClipper(this.rect);

  final Rect rect;

  @override
  Rect getClip(Size size) => rect;

  @override
  bool shouldReclip(covariant _WindowRectClipper oldClipper) =>
      oldClipper.rect != rect;
}
