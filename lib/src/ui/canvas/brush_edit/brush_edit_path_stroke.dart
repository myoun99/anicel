part of '../interactive_brush_edit_canvas_view.dart';

/// THE STROKE A TOOL LAYS — a path handed over whole and drawn as ONE
/// stroke of the brush in hand: the shape tool's rectangle, ellipse or
/// line, where its line is of the brush type (I-69).
///
/// 🚨★★★IT IS THE STROKE, NOT A STROKE LIKE IT. The path goes through
/// [_BrushEditStroke]'s own arming, its own advance and the one landing
/// ([_BrushEditPress.landActiveStroke]) — the spacing, the dynamics, the
/// ground mixing, the symmetry copies, the tip stamps, the overlay and the
/// promotion a pen stroke through the same points gets — so a shape is
/// undone, clipped by the selection and saved exactly as a stroke is.
/// 🗣️유저 2026-10-04: 「브러시 상태를 그대로 사용해서 도형그림 … 그냥 진짜
/// 브러시랑 똑같이 래스터라이즈되있는 도형」. ⛔A second generator of dabs
/// beside the stroke's would be the copy that drifts.
///
/// What differs is only what a pen brings and a tool does not: no pointer,
/// no pressure to read (the stroke is laid at full pressure the whole
/// way), no hand to steady and no ray to snap to — its points go straight
/// to the stroke's advance ([_BrushEditStroke.beginToolStroke]).
class _BrushEditPathStroke {
  _BrushEditPathStroke(this._state);

  final _InteractiveBrushEditCanvasViewState _state;

  /// Draws [path] — two or more points in this view's own space — as one
  /// stroke, and answers whether it is drawn, or will be once the cel it
  /// asked for is there. Published as a [PathStroker] while the view is
  /// mounted.
  bool strokeAlong(List<CanvasPoint> path) {
    if (path.length < 2 || _state._activeDrawingPointer != null) {
      return false;
    }
    if (!_state.widget.editable) {
      // Nothing to draw on: ask for the cel, as a press that draws does
      // (I-10, [_BrushEditCelPress]). ⚠️The shape tool's own press has
      // asked already and its cel is here by now
      // (`CanvasSelectionLayer.onPressNeedsCel`); this is for a caller that
      // did not, and its block is settled as a step of its own before the
      // stroke can claim it.
      if (!(_state.widget.onPressNeedsCel?.call() ?? false)) {
        return false;
      }
      // The block is made inside that call and the rebuild that brings its
      // cel is the next frame's; the path is laid when that frame is done.
      // ⚠️After the frame, never inside it: the landing calls out to the
      // host, and a callback that reaches a `setState` during build is the
      // mid-stroke flip's red screen (R13-4).
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_state.mounted && _state.widget.editable) {
          strokeAlong(path);
        }
      });
      SchedulerBinding.instance.ensureVisualUpdate();
      return true;
    }
    // F-196: the row first — a row that takes no strokes shows no line.
    if (!_state.widget.rowAcceptsStrokes) {
      return false;
    }
    _state._stroke.beginToolStroke(
      path.first,
      startsInsidePasteboard: _state._isInsidePasteboard(path.first),
      // One path, one roll: the same shape drawn again rolls the same
      // scatter and jitter.
      dice: Object.hashAll(path),
    );
    for (final point in path.skip(1)) {
      _state._stroke.advanceStrokeTo(point);
    }
    _state._press.landActiveStroke();
    return true;
  }
}
