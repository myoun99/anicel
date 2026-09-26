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

  /// The rotation centre, as a displacement from the box centre in
  /// absolute canvas units — 유저 2026-09-20: 「기본값 상자안의 자리에서
  /// **얼마나 이동됬나**」, and 「**편집값은 절대값이야**」.
  double anchorX,
  double anchorY,
});

/// ONE PROJECT's selection on its canvas: the marquee (or the box a tool
/// made) and an open polygon trace. The channel below shows the one of the
/// project on screen ([CanvasSelectionCommands.document]).
///
/// 🚨I-7 (a project per tab). The channel is the app's — its keys, its
/// bindings, the modes a tool remembers — and it held this state as the one
/// document there was. With a tab per project a marquee drawn in one would
/// have clipped the strokes of the next, so the state is the project's and
/// the channel is pointed at it; a tab keeps its marquee while another is
/// in front, the way it keeps its history.
final class CanvasSelectionDocument {
  /// R28-S (R26 #18 / R27 #19): the live selection REGION lives here, not
  /// inside the selection layer's State.
  ///
  /// The layer only mounts for the selection tools, so a layer-owned
  /// region evaporated the moment the user picked the brush — which is
  /// why "선택하고 다른 툴" had nothing to act on and the selection tool
  /// read as doing nothing at all. Owning it outside the layer (on the
  /// app's channel until I-7, on the project's document since) makes the
  /// region a DOCUMENT-level fact: it survives tool switches, the ants
  /// keep showing under every tool, and painting can clip to it.
  CanvasSelectionRegion? _region;

  /// Whether [_region] is a shape a TOOL synthesized rather than one the
  /// user chose.
  ///
  /// 🚨★★★**F-108** (유저 2026-09-12: 「선택툴 안하고 그냥 변형사용시 … 변형
  /// 하고 확정하고 되돌리면 **선택툴의 개미행렬이 남아있음**. 그 상태에서
  /// 컨트롤d눌러야 되는 그런상황발생 … **법 통합하되 그런부분은 제대로
  /// 독립**」). R26 #13 had already decided that the move tool's implicit
  /// whole-picture box is not a selection, and the confirm and the revert
  /// both honoured it — but the box was written here all the same, and
  /// this is where the lift captures `regionBefore`. So the UNDO restored
  /// a selection the user never made, and it then clipped their strokes.
  ///
  /// ⛔**THE FIX IS THE NAMING, NOT A GUARD AT EACH READER.**
  /// [CanvasSelectionCommands.region] — the name every consumer outside
  /// the layer already reads — now means 「what the user selected」 and goes
  /// null while this is set. The raw geometry is
  /// [CanvasSelectionCommands.liveShape], and the only thing that wants it
  /// is the layer that draws the box. A new reader cannot pick the wrong
  /// one by accident, which is the whole point of splitting the two
  /// questions instead of adding a flag for readers to remember.
  bool _regionIsImplicit = false;

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
}

/// The imperative selection channel (P9): the app-level shortcuts
/// (Ctrl+D deselect) call in; the mounted selection layer binds the
/// handlers. Unbound calls are no-ops and [hasSelection] is false.
///
/// R17-U: also a [ChangeNotifier] — the layer pings [notifySessionChanged]
/// on selection/transform mutations so the tool settings panel's numeric
/// fields track handle drags live (notification is coalesced and deferred
/// a microtask: mutations fire inside build/gesture phases).
class CanvasSelectionCommands extends ChangeNotifier {
  /// The selection of the project on screen — see [CanvasSelectionDocument].
  CanvasSelectionDocument _document = CanvasSelectionDocument();

  CanvasSelectionDocument get document => _document;

  /// Shows [next]'s selection — the shell's move when a project tab comes on
  /// screen, made AFTER the canvas has landed what it was holding: a landing
  /// writes the region it moved, and it must write the project it lifted
  /// from.
  set document(CanvasSelectionDocument next) {
    if (identical(next, _document)) {
      return;
    }
    _document = next;
    notifySessionChanged();
  }

  /// The mode a fresh marquee/lasso combines with [region] (R26 #16).
  /// Default = 추가 (the user's stated default).
  SelectionCombineMode _combineMode = SelectionCombineMode.defaultMode;

  /// 🚨THE SELECTION — what the USER chose. Null while the live shape is a
  /// tool's own implicit target (F-108 — the document's implicit flag).
  CanvasSelectionRegion? get region =>
      _document._regionIsImplicit ? null : _document._region;

  /// The live SHAPE on the canvas, selection or not — the marquee's
  /// outline, or the box the move tool synthesized with nothing selected.
  /// ⚠️GEOMETRY. The layer that owns the box reads this to stay in step
  /// with the channel; everyone else means [region].
  CanvasSelectionRegion? get liveShape => _document._region;

  /// True when a region is selected — the single truth the shortcuts, the
  /// paint clip and the ants all read.
  bool get hasRegion => region != null;

  SelectionCombineMode get combineMode => _combineMode;

  set combineMode(SelectionCombineMode mode) {
    if (_combineMode == mode) {
      return;
    }
    _combineMode = mode;
    notifySessionChanged();
  }

  /// Installs [region] as the live shape. The mounted layer pushes every
  /// committed change through here, and the history command's execute/undo
  /// does the same — one write path, one truth.
  ///
  /// [implicit] marks a shape a tool synthesized (F-108): it draws and
  /// lifts like any other, and it is not a selection. ⛔The default is
  /// false because every OTHER writer is installing a real one — a history
  /// command replaying a selection, a host handing one in — and a shape
  /// that has to be declared implicit is one nobody can make by forgetting.
  void setRegion(CanvasSelectionRegion? region, {bool implicit = false}) {
    // Nothing is implicit about nothing: clearing always clears both.
    final nextImplicit = region != null && implicit;
    final document = _document;
    if (document._region == region &&
        document._regionIsImplicit == nextImplicit) {
      return;
    }
    document._region = region;
    document._regionIsImplicit = nextImplicit;
    notifySessionChanged();
  }

  List<CanvasPoint> get polygonPoints =>
      List<CanvasPoint>.unmodifiable(_document._polygonPoints);

  /// Whether a polygon trace is open. While true, undo/redo mean "take the
  /// last vertex back" / "put it back" rather than their document meanings,
  /// and the confirm action closes the trace instead of a transform box.
  bool get hasOpenPolygon => _document._polygonPoints.isNotEmpty;

  /// Whether a closed polygon could be made right now — three vertices is
  /// the least that encloses anything.
  bool get canClosePolygon => _document._polygonPoints.length >= 3;

  /// Whether [redoPolygonPoint] would put a vertex back — the question it
  /// answers by acting, asked without acting.
  bool get canRedoPolygonPoint => _document._polygonRedo.isNotEmpty;

  void addPolygonPoint(CanvasPoint point) {
    _document._polygonPoints.add(point);
    _document._polygonRedo.clear();
    notifySessionChanged();
  }

  /// Takes the last vertex back. False when there was none — the caller
  /// then lets undo mean what it usually means, so undo never becomes a
  /// dead key just because a trace was open a moment ago.
  bool undoPolygonPoint() {
    if (_document._polygonPoints.isEmpty) {
      return false;
    }
    _document._polygonRedo.add(_document._polygonPoints.removeLast());
    notifySessionChanged();
    return true;
  }

  bool redoPolygonPoint() {
    if (_document._polygonRedo.isEmpty) {
      return false;
    }
    _document._polygonPoints.add(_document._polygonRedo.removeLast());
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
        ? CanvasSelectionShape(
            List<CanvasPoint>.of(_document._polygonPoints),
          )
        : null;
    abandonPolygon();
    return closed;
  }

  /// Drops the trace with nothing committed — a tool change, a shape
  /// change, or Escape.
  void abandonPolygon() {
    if (_document._polygonPoints.isEmpty && _document._polygonRedo.isEmpty) {
      return;
    }
    _document._polygonPoints.clear();
    _document._polygonRedo.clear();
    notifySessionChanged();
  }

  bool Function()? _closePolygon;
  bool Function()? _hasSelection;
  VoidCallback? _deselect;
  bool Function()? _transformActive;
  VoidCallback? _beginTransform;
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
  void Function({required double x, required double y})? _setTransformAnchor;
  bool Function()? _undoTransformStep;
  bool Function()? _canUndoTransformStep;
  VoidCallback? _beginTransformStep;
  void Function({required bool horizontal})? _flipTransform;
  VoidCallback? _resetTransform;
  VoidCallback? _applyTransform;
  bool Function()? _canApplyTransform;
  bool Function()? _canEditTransform;
  Object? _owner;

  bool _notifyScheduled = false;

  /// ⚠️Owner-scoped — see `TimelineLayerNavCommands.bind` for the failure
  /// an unconditional `unbind()` produced (유저 #13, 2026-08-14).
  void bind(
    Object owner, {
    required bool Function() hasSelection,
    required VoidCallback deselect,
    bool Function()? closePolygon,
    bool Function()? transformActive,
    VoidCallback? beginTransform,
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
    void Function({required double x, required double y})? setTransformAnchor,
    bool Function()? undoTransformStep,
    bool Function()? canUndoTransformStep,
    VoidCallback? beginTransformStep,
    void Function({required bool horizontal})? flipTransform,
    VoidCallback? resetTransform,
    VoidCallback? applyTransform,
    bool Function()? canApplyTransform,
    bool Function()? canEditTransform,
  }) {
    _owner = owner;
    _flipTransform = flipTransform;
    _resetTransform = resetTransform;
    _applyTransform = applyTransform;
    _canApplyTransform = canApplyTransform;
    _canEditTransform = canEditTransform;
    _hasSelection = hasSelection;
    _deselect = deselect;
    _closePolygon = closePolygon;
    _transformActive = transformActive;
    _beginTransform = beginTransform;
    _cancelTransform = cancelTransform;
    _applyRegion = applyRegion;
    _movePending = movePending;
    _confirmPendingMove = confirmPendingMove;
    _revertPendingMove = revertPendingMove;
    _transformValues = transformValues;
    _setTransformValues = setTransformValues;
    _setTransformAnchor = setTransformAnchor;
    _undoTransformStep = undoTransformStep;
    _canUndoTransformStep = canUndoTransformStep;
    _beginTransformStep = beginTransformStep;
    notifySessionChanged();
  }

  void unbind(Object owner) {
    if (!identical(_owner, owner)) {
      return;
    }
    _owner = null;
    _hasSelection = null;
    _deselect = null;
    _closePolygon = null;
    _transformActive = null;
    _beginTransform = null;
    _cancelTransform = null;
    _applyRegion = null;
    _movePending = null;
    _confirmPendingMove = null;
    _revertPendingMove = null;
    _transformValues = null;
    _setTransformValues = null;
    _setTransformAnchor = null;
    _undoTransformStep = null;
    _canUndoTransformStep = null;
    _beginTransformStep = null;
    _flipTransform = null;
    _resetTransform = null;
    _applyTransform = null;
    _canApplyTransform = null;
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

  /// Whether a live selection exists.
  ///
  /// ↩️While true the arrow keys NUDGED the selection instead of flipping
  /// frames (Photoshop arbitration). 유저 2026-09-12: 「선택툴 선택한채로
  /// 화살표키누르면 그림 이동되는데 왜 멋대로 넣은거지? 기능부터 잔존코드 싹
  /// 삭제」 — the arrows walk the sheet whatever is selected, and the nudge
  /// is gone.
  bool get hasSelection => _hasSelection?.call() ?? false;

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
    final before = _document._region;
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

  /// Whether a free-transform session is open (Escape then cancels it, and
  /// 확정 answers with [applyTransform]).
  bool get transformActive => _transformActive?.call() ?? false;

  /// Ctrl+T: opens the free-transform box on the live selection.
  void beginTransform() => _beginTransform?.call();

  /// Escape: discards the open transform.
  void cancelTransform() => _cancelTransform?.call();

  /// Whether a TVP-style move session awaits its confirm (R16-①).
  bool get movePending => _movePending?.call() ?? false;

  /// Lands the session — the open box, then the move it rides — as ONE undo
  /// entry. Called by tool switches, the history manager's pre-undo/redo
  /// hook, and [applyTransform] when the session holds changes. No-op
  /// without a session.
  void confirmPendingMove() => _confirmPendingMove?.call();

  /// Reverts the pending move: the pixels return EXACTLY to where the
  /// session found them (a fresh lift disappears entirely), no history
  /// entry. The "되돌리기" choice in the R17-① confirm prompt.
  void revertPendingMove() => _revertPendingMove?.call();

  /// The open transform box's numeric state, or null when no box is up
  /// (the settings fields then show the identity).
  SelectionTransformValues? get transformValues => _transformValues?.call();

  /// 🚨★★★**THE SAME NUMBERS, LIVE — and a notifier so that only the DIGITS
  /// rebuild.**
  ///
  /// 🗣️유저 2026-09-18 (F-164): 「변형중에 툴도구의 X,Y값같은거 **실시간으로
  /// 바뀌게** 해주고. **무겁지 않을 구조로 패널리빌드하지말고 글자만 바꾸게**」.
  ///
  /// ⛔It is deliberately NOT a `notifyListeners` on this channel: that is
  /// how the settings panel already learns things, and it rebuilds the
  /// whole panel. A transform drag is a pointer-rate event, and the layer
  /// beside it learned this the hard way — 「a rebuild per pointer move on
  /// this layer is the R4 #3 hazard」 — which is why its own cursor band is
  /// a listenable the painter reads and not state anybody sets.
  ///
  /// ⚠️Same source as [transformValues], never a second computation: the
  /// layer publishes here with the value it would answer with.
  final ValueNotifier<SelectionTransformValues?> liveTransformValues =
      ValueNotifier<SelectionTransformValues?>(null);

  /// The layer publishing what the box is showing right now.
  void publishTransformValues(SelectionTransformValues? values) {
    final current = liveTransformValues.value;
    if (current == values) {
      return;
    }
    liveTransformValues.value = values;
  }

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

  /// Moves the rotation centre — the cross — to a displacement from the box
  /// centre, in absolute canvas units.
  ///
  /// ⛔**ITS OWN VERB, and the reason is the question it answers.** The four
  /// above are the EDIT; the anchor is where the next turn happens, which
  /// `SelectionAffine.isIdentity` already says out loud by leaving it out.
  /// Folding it into that call would force every caller who only wanted to
  /// type an X to restate the anchor — and the version of that with a
  /// default would silently put the cross back in the middle.
  void setTransformAnchor({required double x, required double y}) =>
      _setTransformAnchor?.call(x: x, y: y);

  /// Takes ONE operation back inside an open transform box.
  ///
  /// 🗣️유저 2026-09-20: 「**변형도구 사용시 변형에 대한 조작마다 언두로
  /// 기록**된단거야 … **확정하면 변형 하나로서의 언두만 작동**」.
  ///
  /// Returns false when there is nothing left to take — no box, or a box
  /// standing as it opened — and then undo means what it always means.
  /// ⛔Exactly [undoPolygonPoint]'s contract, because it is exactly the
  /// same question: 「is the key the user pressed about the thing they are
  /// in the middle of, or about the document?」
  bool undoTransformStep() => _undoTransformStep?.call() ?? false;

  /// Whether [undoTransformStep] would take an operation back — the
  /// question it answers by acting, asked without acting.
  bool get canUndoTransformStep => _canUndoTransformStep?.call() ?? false;

  /// Marks the start of an operation that is NOT a canvas gesture — a
  /// scrub on a tool-settings channel, or a typed value.
  ///
  /// ⚠️The canvas takes its own step when a drag begins, because it can
  /// see the press. A label scrub is one operation made of forty writes,
  /// and only the label knows where it started — so it says so.
  void beginTransformStep() => _beginTransformStep?.call();

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

  /// 적용 — 확정 while a transform is in play (`ConfirmVerb`), so the tool
  /// settings button, the box's ✓ and Enter are one verb (유저 확정 08-13,
  /// and 09-24 confirm-button-Q2 「변형중이면 확정」):
  ///
  /// - the session holds changes → land it, one undo entry;
  /// - it holds none → **replay the last committed transform's values**
  ///   into the box, in whatever mode is armed now. It does NOT commit: the
  ///   recalled values land where they can be seen and adjusted, and a
  ///   second press applies them.
  void applyTransform() => _applyTransform?.call();

  /// Whether [applyTransform] has anything to do — the same answer the press
  /// acts on, so a button that asks is never lit for a no-op.
  bool get canApplyTransform => _canApplyTransform?.call() ?? false;

  /// Whether the transform tool would accept an edit right now.
  ///
  /// 유저 확정 08-13: picking the tool is always allowed even with an empty
  /// cel — the refusal moved from the tool switch to the edit itself, and
  /// it refuses QUIETLY (the controls go flat; no snackbar, because a
  /// snackbar per canvas tap on an empty layer is a nag, not an answer).
  bool get canEditTransform => _canEditTransform?.call() ?? false;

  /// The last committed transform PER MODE, replayed by [applyTransform]
  /// when there is nothing to commit.
  ///
  /// It lives HERE rather than in the canvas layer because the layer
  /// unmounts on every tool switch (R28-S) — a recall that forgets itself
  /// when you pick up the brush is not a recall.
  ///
  /// 🚨★★★KEYED BY MODE, 유저 2026-08-29: 「**툴마다 기억하는게 다름**:
  /// 일반변형 고른 상태로 엔터하면 직전 일반변형 값을 재현, 자유변형 고른
  /// 상태로 엔터하면 직전 자유변형을 재현」. One slot could only answer for
  /// whichever mode committed last, so arming 일반 and pressing Enter
  /// replayed a 퍼스 warp — or nothing, if the affine happened to be
  /// identity.
  ///
  /// ⛔THIS IS NOT THE AXIS 08-13 SETTLED. That day's 「전역 하나」 was about
  /// not keying the recall PER LAYER (「어떤 크기의 소재든 같은 값을
  /// 변형주도록」), and it still holds: no entry here is a layer's. Mode is a
  /// different question, and the user answered it separately.
  final Map<TransformMode, TransformRecall> transformRecalls =
      <TransformMode, TransformRecall>{};

  /// The recall the ARMED mode would replay, or null.
  TransformRecall? recallFor(TransformMode mode) => transformRecalls[mode];
}
