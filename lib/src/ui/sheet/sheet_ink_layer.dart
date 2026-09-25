import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';

import '../../models/brush_edit_canvas_input_settings.dart';
import '../../models/brush_frame_key.dart';
import '../../models/canvas_viewport.dart';
import '../../models/sheet_marks.dart';
import '../../models/sheet_paint_layer.dart';
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
    required this.placement,
    this.plane,
  });

  /// The window of an ink mark a sheet's walk yields — the walk the sheet's
  /// printers read too, so the brush writes where the paper shows.
  SheetInkWindow.of(SheetInk ink, {required String id, Object? plane})
    : this(id: id, key: ink.key, placement: ink.placement, plane: plane);

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

  /// Where this window shows its surface — the one mapping between ink
  /// pixels and the paper the printers lay the ink back by.
  final SheetInkPlacement placement;

  /// The window's rect in the sheet's document space.
  Rect get documentRect => placement.window;

  /// Ink-surface pixels per document unit.
  double get surfaceScale => placement.scale;

  /// Ink-surface pixel that maps to [documentRect]'s top-left.
  Offset get inkOffset => placement.origin;

  /// The viewport the interactive brush view needs so ink pixel (x, y)
  /// lands exactly where the sheet paints this window: the panel transform
  /// composed with where surface pixel (0, 0) lies on the paper.
  CanvasViewport inkViewport(CanvasViewport panelViewport) {
    final origin = placement.paperOf(Offset.zero);
    return CanvasViewport(
      zoom: panelViewport.zoom / placement.scale,
      panX: panelViewport.panX + panelViewport.zoom * origin.dx,
      panY: panelViewport.panY + panelViewport.zoom * origin.dy,
    );
  }

  /// The window's slice of its ink surface, in SURFACE pixels.
  Rect get surfaceRect => placement.surfaceRect;

  /// This window as the mark a printer lays its ink by.
  SheetInk get mark =>
      SheetInk(SheetPaintLayer.ink, key: key, placement: placement);

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

  /// The brush in hand — heard, not handed over (H40 ②, 2026-09-24): the
  /// windows read it when a stroke starts, so a brush change rebuilds no
  /// window. The hosts used to rebuild this whole layer on every one.
  final ValueListenable<BrushToolState> brushToolState;

  /// Raised while any window has a stroke in progress, so the panel's
  /// gesture layer holds navigation exactly as it does for canvas strokes.
  final ValueNotifier<bool> strokeActive;

  final BrushEditSessionState Function(SheetInkWindow window) sessionStateFor;

  final void Function(SheetInkWindow window, BrushStrokeCommitData strokeData)
  onStrokeCommitted;

  @override
  Widget build(BuildContext context) {
    BrushEditCanvasInputSettings inputSettings() =>
        brushToolState.value.toInputSettings();
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
