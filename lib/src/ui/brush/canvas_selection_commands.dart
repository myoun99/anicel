import 'dart:async';

import 'package:flutter/foundation.dart';


import '../../models/canvas_point.dart';
import '../../services/canvas_selection.dart';
import '../../services/canvas_selection_region.dart';
import 'transform_tool_options.dart';

/// The live transform box's numeric state (R17-U tool settings inputs).
typedef SelectionTransformValues = ({
  double tx,
  double ty,
  double rotationDegrees,
  double scale,
});

/// The imperative selection channel (P9): the app-level shortcuts
/// (Ctrl+D deselect, arrow nudges) call in; the mounted selection layer
/// binds the handlers. Unbound calls are no-ops and [hasSelection] is
/// false — the arrow keys then keep their frame-flipping meaning.
///
/// R17-U: also a [ChangeNotifier] — the layer pings [notifySessionChanged]
/// on selection/transform mutations so the tool settings panel's numeric
/// fields track handle drags live (notification is coalesced and deferred
/// a microtask: mutations fire inside build/gesture phases).
class CanvasSelectionCommands extends ChangeNotifier {
  /// R28-S (R26 #18 / R27 #19): the live selection REGION lives here, not
  /// inside the selection layer's State.
  ///
  /// The layer only mounts for the selection tools, so a layer-owned
  /// region evaporated the moment the user picked the brush — which is
  /// why "선택하고 다른 툴" had nothing to act on and the selection tool
  /// read as doing nothing at all. Owning it at the app level makes the
  /// region a DOCUMENT-level fact: it survives tool switches, the ants
  /// keep showing under every tool, and painting can clip to it.
  CanvasSelectionRegion? _region;

  /// The mode a fresh marquee/lasso combines with [region] (R26 #16).
  /// Default = 추가 (the user's stated default).
  SelectionCombineMode _combineMode = SelectionCombineMode.defaultMode;

  CanvasSelectionRegion? get region => _region;

  /// True when a region is selected — the single truth the shortcuts, the
  /// paint clip and the ants all read.
  bool get hasRegion => _region != null;

  SelectionCombineMode get combineMode => _combineMode;

  set combineMode(SelectionCombineMode mode) {
    if (_combineMode == mode) {
      return;
    }
    _combineMode = mode;
    notifySessionChanged();
  }

  /// Installs [region] as the live selection. The mounted layer pushes
  /// every committed change through here, and the history command's
  /// execute/undo does the same — one write path, one truth.
  void setRegion(CanvasSelectionRegion? region) {
    if (_region == region) {
      return;
    }
    _region = region;
    notifySessionChanged();
  }

  /// The vertices of an OPEN polygon trace, oldest first; empty when none
  /// is being traced.
  ///
  /// Lives here rather than in the selection layer's State for the same
  /// reason the region does, but for a sharper case: an open trace has to
  /// survive a CUT change (유저 확정 — *"의미 잃어도 그거는 폴리곤을
  /// 완성하고 나서 결과를 어떻게 처리하느냐의 문제"*), and changing cuts
  /// remounts the layer outright. State kept down there would be gone.
  final List<CanvasPoint> _polygonPoints = [];

  /// Vertices taken back by undo, newest first — the redo side. Cleared by
  /// the next real vertex, the way every redo stack is.
  final List<CanvasPoint> _polygonRedo = [];

  List<CanvasPoint> get polygonPoints =>
      List<CanvasPoint>.unmodifiable(_polygonPoints);

  /// Whether a polygon trace is open. While true, undo/redo mean "take the
  /// last vertex back" / "put it back" rather than their document meanings,
  /// and the confirm action closes the trace instead of a transform box.
  bool get hasOpenPolygon => _polygonPoints.isNotEmpty;

  /// Whether a closed polygon could be made right now — three vertices is
  /// the least that encloses anything.
  bool get canClosePolygon => _polygonPoints.length >= 3;

  void addPolygonPoint(CanvasPoint point) {
    _polygonPoints.add(point);
    _polygonRedo.clear();
    notifySessionChanged();
  }

  /// Takes the last vertex back. False when there was none — the caller
  /// then lets undo mean what it usually means, so undo never becomes a
  /// dead key just because a trace was open a moment ago.
  bool undoPolygonPoint() {
    if (_polygonPoints.isEmpty) {
      return false;
    }
    _polygonRedo.add(_polygonPoints.removeLast());
    notifySessionChanged();
    return true;
  }

  bool redoPolygonPoint() {
    if (_polygonRedo.isEmpty) {
      return false;
    }
    _polygonPoints.add(_polygonRedo.removeLast());
    notifySessionChanged();
    return true;
  }

  /// Closes an open trace, folding its outline in wherever the active verb
  /// puts outlines. True when there WAS one — the caller then stops,
  /// because the confirm it was serving has been spent here.
  ///
  /// Without a mounted layer to fold into, the trace is dropped rather
  /// than left hanging: a confirm has to end the thing it was pressed for.
  bool closePolygon() {
    if (!hasOpenPolygon) {
      return false;
    }
    final close = _closePolygon;
    if (close != null) {
      return close();
    }
    abandonPolygon();
    return true;
  }

  /// Closes the trace and hands back its outline, or null when there are
  /// too few vertices to enclose anything. Either way the trace is over.
  CanvasSelectionShape? takePolygonShape() {
    final closed = canClosePolygon
        ? CanvasSelectionShape(List<CanvasPoint>.of(_polygonPoints))
        : null;
    abandonPolygon();
    return closed;
  }

  /// Drops the trace with nothing committed — a tool change, a shape
  /// change, or Escape.
  void abandonPolygon() {
    if (_polygonPoints.isEmpty && _polygonRedo.isEmpty) {
      return;
    }
    _polygonPoints.clear();
    _polygonRedo.clear();
    notifySessionChanged();
  }

  bool Function()? _closePolygon;
  bool Function()? _hasSelection;
  void Function(double dx, double dy)? _nudge;
  VoidCallback? _deselect;
  bool Function()? _transformActive;
  VoidCallback? _beginTransform;
  VoidCallback? _commitTransform;
  VoidCallback? _cancelTransform;
  void Function(CanvasSelectionRegion? region)? _applyRegion;
  bool Function()? _movePending;
  VoidCallback? _confirmPendingMove;
  VoidCallback? _revertPendingMove;
  SelectionTransformValues? Function()? _transformValues;
  void Function({
    required double tx,
    required double ty,
    required double rotationDegrees,
    required double scale,
  })?
  _setTransformValues;
  void Function({required bool horizontal})? _flipTransform;
  VoidCallback? _resetTransform;
  VoidCallback? _applyTransform;
  bool Function()? _canEditTransform;

  bool _notifyScheduled = false;

  void bind({
    required bool Function() hasSelection,
    required void Function(double dx, double dy) nudge,
    required VoidCallback deselect,
    bool Function()? closePolygon,
    bool Function()? transformActive,
    VoidCallback? beginTransform,
    VoidCallback? commitTransform,
    VoidCallback? cancelTransform,
    void Function(CanvasSelectionRegion? region)? applyRegion,
    bool Function()? movePending,
    VoidCallback? confirmPendingMove,
    VoidCallback? revertPendingMove,
    SelectionTransformValues? Function()? transformValues,
    void Function({
      required double tx,
      required double ty,
      required double rotationDegrees,
      required double scale,
    })?
    setTransformValues,
    void Function({required bool horizontal})? flipTransform,
    VoidCallback? resetTransform,
    VoidCallback? applyTransform,
    bool Function()? canEditTransform,
  }) {
    _flipTransform = flipTransform;
    _resetTransform = resetTransform;
    _applyTransform = applyTransform;
    _canEditTransform = canEditTransform;
    _hasSelection = hasSelection;
    _nudge = nudge;
    _deselect = deselect;
    _closePolygon = closePolygon;
    _transformActive = transformActive;
    _beginTransform = beginTransform;
    _commitTransform = commitTransform;
    _cancelTransform = cancelTransform;
    _applyRegion = applyRegion;
    _movePending = movePending;
    _confirmPendingMove = confirmPendingMove;
    _revertPendingMove = revertPendingMove;
    _transformValues = transformValues;
    _setTransformValues = setTransformValues;
    notifySessionChanged();
  }

  void unbind() {
    _hasSelection = null;
    _nudge = null;
    _deselect = null;
    _closePolygon = null;
    _transformActive = null;
    _beginTransform = null;
    _commitTransform = null;
    _cancelTransform = null;
    _applyRegion = null;
    _movePending = null;
    _confirmPendingMove = null;
    _revertPendingMove = null;
    _transformValues = null;
    _setTransformValues = null;
    _flipTransform = null;
    _resetTransform = null;
    _applyTransform = null;
    _canEditTransform = null;
    notifySessionChanged();
  }

  /// Coalesced, microtask-deferred change ping — safe to call from any
  /// phase (the layer mutates state inside builds and gesture handlers,
  /// where a synchronous notifyListeners could re-enter the build).
  void notifySessionChanged() {
    if (_notifyScheduled) {
      return;
    }
    _notifyScheduled = true;
    scheduleMicrotask(() {
      _notifyScheduled = false;
      notifyListeners();
    });
  }

  /// Adopts a committed region — the selection history command's
  /// execute/undo path (R11-⑧), and the layer's own commit path.
  ///
  /// The region lands here FIRST (so it holds even with no layer
  /// mounted — R28-S), then reaches the mounted layer so an open
  /// move/transform session can react.
  void applyRegion(CanvasSelectionRegion? region) {
    setRegion(region);
    _applyRegion?.call(region);
  }

  /// Whether a live selection exists — arrow keys NUDGE instead of
  /// flipping frames while true (Photoshop arbitration).
  bool get hasSelection => _hasSelection?.call() ?? false;

  /// Moves the selection by canvas pixels (one undo entry per call).
  void nudge(double dx, double dy) => _nudge?.call(dx, dy);

  /// Records a region change as ONE undoable step. Set by the canvas
  /// panel (it owns the history manager); null applies changes directly.
  void Function(CanvasSelectionRegion? before, CanvasSelectionRegion? after)?
  regionHistoryRecorder;

  /// Ctrl+D. With a selection layer mounted it runs the layer's own
  /// deselect (which also ends any pending move session); with none —
  /// the brush is armed and the region is just showing its ants — the
  /// channel clears the region itself, through the same history recorder
  /// the layer uses. Ctrl+D never becomes a dead key just because the
  /// active tool is not a selection tool (R28-S).
  void deselect() {
    final layerDeselect = _deselect;
    if (layerDeselect != null) {
      layerDeselect();
      return;
    }
    final before = _region;
    if (before == null) {
      return;
    }
    final record = regionHistoryRecorder;
    if (record != null) {
      record(before, null);
      return;
    }
    setRegion(null);
  }

  /// Whether a free-transform session is open (Enter/Escape then
  /// commit/cancel it instead of their usual meanings).
  bool get transformActive => _transformActive?.call() ?? false;

  /// Ctrl+T: opens the free-transform box on the live selection.
  void beginTransform() => _beginTransform?.call();


  /// Enter: commits the open transform as one undo entry.
  void commitTransform() => _commitTransform?.call();

  /// Escape: discards the open transform.
  void cancelTransform() => _cancelTransform?.call();

  /// Whether a TVP-style move session awaits its confirm (R16-①).
  bool get movePending => _movePending?.call() ?? false;

  /// Adopts the pending move into history as ONE undo entry — called by
  /// the confirm button, Enter, tool switches, and the history manager's
  /// pre-undo/redo hook. No-op without a pending session.
  void confirmPendingMove() => _confirmPendingMove?.call();

  /// Reverts the pending move: the pixels return EXACTLY to where the
  /// session found them (a fresh lift disappears entirely), no history
  /// entry. The "되돌리기" choice in the R17-① confirm prompt.
  void revertPendingMove() => _revertPendingMove?.call();

  /// The open transform box's numeric state, or null when no box is up
  /// (the settings fields then show the identity).
  SelectionTransformValues? get transformValues => _transformValues?.call();

  /// Applies numeric transform values to the live selection (R17-U): the
  /// layer opens a session if none is up, sets the affine, and shows the
  /// result on the float — Enter confirms, Escape reverts, as always.
  void setTransformValues({
    required double tx,
    required double ty,
    required double rotationDegrees,
    required double scale,
  }) => _setTransformValues?.call(
    tx: tx,
    ty: ty,
    rotationDegrees: rotationDegrees,
    scale: scale,
  );

  /// Mirrors the open box about its centre — a sign flip on one scale
  /// axis, not a new kind of transform. Works in every mode: 퍼스 and 메쉬
  /// carry their offsets through the same affine, so the warp mirrors with
  /// the picture instead of staying behind.
  ///
  /// With no box open this OPENS one, the way the numeric channels do.
  void flipTransform({required bool horizontal}) =>
      _flipTransform?.call(horizontal: horizontal);

  /// 리셋: every value, not just the numbers — the affine AND the
  /// perspective/mesh offsets (유저 확정 08-13: "리셋은 전부").
  void resetTransform() => _resetTransform?.call();

  /// 적용, and the system 확정 button's transform-tool meaning, which are
  /// deliberately the same verb reached from two doors (유저 확정 08-13):
  ///
  /// - the box has been transformed → commit it, one undo entry;
  /// - nothing has been transformed → **replay the last committed
  ///   transform's values** into the box, in whatever mode is armed now.
  ///   It does NOT commit: the recalled values land where they can be seen
  ///   and adjusted, and a second press applies them.
  void applyTransform() => _applyTransform?.call();

  /// Whether the transform tool would accept an edit right now.
  ///
  /// 유저 확정 08-13: picking the tool is always allowed even with an empty
  /// cel — the refusal moved from the tool switch to the edit itself, and
  /// it refuses QUIETLY (the controls go flat; no snackbar, because a
  /// snackbar per canvas tap on an empty layer is a nag, not an answer).
  bool get canEditTransform => _canEditTransform?.call() ?? false;

  /// The last committed transform, replayed by [applyTransform] when there
  /// is nothing to commit.
  ///
  /// It lives HERE rather than in the canvas layer because the layer
  /// unmounts on every tool switch (R28-S) — a recall that forgets itself
  /// when you pick up the brush is not a recall. One slot for the whole
  /// session, deliberately not per layer: 유저 확정 08-13 "전역 하나. 즉
  /// 어떤 크기의 소재든 같은 값을 변형주도록".
  TransformRecall? transformRecall;
}
