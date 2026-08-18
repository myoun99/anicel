import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/gestures.dart' show DragStartBehavior;
import 'package:flutter/material.dart';

import '../input/app_input_settings.dart' show AppInput;
import '../input/eager_pan_gesture_recognizer.dart';
import '../debug/input_inspector.dart' show InputInspector;
import '../widgets/instant_tap_region.dart' show InstantTapRegion;

import '../../models/layer.dart';
import '../../models/layer_id.dart';
import '../../models/timeline_frame_range.dart';
import '../../models/timeline_row_address.dart';
import 'property_lane_model.dart';
import 'timeline_edge_auto_pan.dart' show edgeAutoPanApply;
import 'timeline_frame_geometry.dart';
import 'timeline_row_span_resolver.dart' show resolveBlockMoveTargetLayer;
import 'timeline_exposure_comma_drag_policy.dart';
import 'transform_lane_policy.dart' show laneSelectionCoversBandRow;

/// Session-level hooks for the frame-range MOVE drag (UI-R8) — the grid
/// resolves the pointer's row into [onUpdate]'s target layer before
/// forwarding, exactly like the block-move callbacks it succeeds.
class TimelineRangeMoveCallbacks {
  const TimelineRangeMoveCallbacks({
    required this.onBegin,
    required this.onUpdate,
    required this.onEnd,
    required this.onCancel,
  });

  /// Starts moving the CURRENT selection; false = nothing to move.
  ///
  /// [grabLayerId] is the row the pointer went DOWN on (R27 #8). The row
  /// hop a step asks for is "this row lands on the row under the
  /// pointer" — measuring it from the selection's anchor instead made the
  /// hop wrong whenever the two differed (select upward, grab the block).
  final bool Function(LayerId grabLayerId) onBegin;
  final void Function({required int frameDelta, LayerId? targetLayerId})
  onUpdate;
  final VoidCallback onEnd;
  final VoidCallback onCancel;
}

/// Host-level hooks for the whole range feature (UI-R8), threaded from the
/// tab host into both grids as ONE bundle: the session's selection state,
/// the select-drag hook, the tap-clear and the move-drag session.
class TimelineFrameRangeHooks {
  const TimelineFrameRangeHooks({
    required this.selection,
    required this.onSelectUpdate,
    required this.onClear,
    required this.move,
  });

  final ValueListenable<TimelineFrameRangeSelection?> selection;

  /// [headLayerId] is the row under the pointer (UI-R17 #8 — the grid
  /// resolves cross-row drags like it does for moves); null/anchor keeps
  /// the single-layer selection. [headLaneId] is non-null when that row
  /// is a property LANE row (R27 #14): the drag then reaches down the
  /// layer's own lane group instead of skipping past it to the next
  /// layer's cells.
  ///
  /// [spanRows] is what the drag SWEPT, sliced off the mounting surface's own
  /// display row list — the authoritative span since 2026-08-12. Empty from a
  /// surface that has no row list in reach, which then keeps the older
  /// layer-derived behaviour.
  final void Function(
    LayerId layerId,
    int anchorIndex,
    int headIndex, {
    LayerId? headLayerId,
    String? headLaneId,
    List<TimelineRowAddress> spanRows,
  })
  onSelectUpdate;
  final VoidCallback onClear;
  final TimelineRangeMoveCallbacks move;
}

/// Grid-side adapter (Axis-shared): resolves the gesture layer's row
/// deltas against the current display rows and forwards to the session
/// move hooks — the block-move resolver's successor.
class TimelineRangeMoveRowResolver {
  TimelineRangeMoveRowResolver();

  List<TimelineDisplayRow> rows = const [];
  TimelineRangeMoveCallbacks? session;
  LayerId? _sourceLayerId;

  bool begin(LayerId layerId) {
    final callbacks = session;
    if (callbacks == null) {
      return false;
    }
    final accepted = callbacks.onBegin(layerId);
    _sourceLayerId = accepted ? layerId : null;
    return accepted;
  }

  void update(int frameDelta, int rowDelta) {
    final callbacks = session;
    final sourceLayerId = _sourceLayerId;
    if (callbacks == null || sourceLayerId == null) {
      return;
    }
    callbacks.onUpdate(
      frameDelta: frameDelta,
      targetLayerId: resolveBlockMoveTargetLayer(
        rows: rows,
        sourceLayerId: sourceLayerId,
        rowDelta: rowDelta,
      ),
    );
  }

  void end() {
    _sourceLayerId = null;
    session?.onEnd();
  }

  void cancel() {
    _sourceLayerId = null;
    session?.onCancel();
  }
}

/// The grid-level bundle every cells row mounts (UI-R8): ONE gesture layer
/// whose pan decides its mode at press — inside the current selection =
/// MOVE the range, anywhere else = (re)SELECT a range. Taps fall through
/// to the cells (playhead select) and clear the selection.
class TimelineRangeGestureCallbacks {
  const TimelineRangeGestureCallbacks({
    required this.isInSelection,
    required this.onSelectUpdate,
    required this.onTapClear,
    required this.onMoveBegin,
    required this.onMoveUpdate,
    required this.onMoveEnd,
    required this.onMoveCancel,
  });

  /// "Is this cell inside the live selection?" — read at PRESS to pick the
  /// drag's mode (inside = MOVE, anywhere else = SELECT).
  ///
  /// A predicate rather than the selection object itself: the timeline
  /// answers from its [TimelineFrameRangeSelection], the storyboard's cut
  /// row from its selected cut run, and the gesture has no business
  /// knowing which. It stays a callback (not a rebuild input) for the same
  /// reason the listenable did — this layer has nothing to lay out or
  /// paint, so a selection change must never rebuild it.
  final bool Function(TimelineRowAddress row, int frameIndex) isInSelection;

  /// A select-drag step: anchor = where the drag started, head = the
  /// pointer's frame now (the session snaps to whole blocks).
  ///
  /// [headCrossOffset] is the pointer's CROSS-AXIS position in pixels,
  /// measured from this row's top (negative above it) — the raw material
  /// for the Excel-style cross-row select (UI-R17 #8). It is deliberately
  /// NOT a row count: this layer does not know how tall the other rows
  /// are, and R9 #25 is the bug that guess produced. The mount resolves it
  /// with the heights it paints — see `timeline_row_cross_offset.dart`.
  final void Function(
    TimelineRowAddress row,
    int anchorIndex,
    int headIndex,
    double headCrossOffset,
  )
  onSelectUpdate;

  /// A plain tap on the cells (no drag): clears the selection — the row's
  /// own pointer-down keeps doing the playhead/cut select.
  ///
  /// R10 note: this one deliberately does NOT seek, though its lane
  /// sibling does. A cells row's press policy is already tuned — it stands
  /// down inside a live selection so a move can start (UI-R22 #2) and it
  /// stands down for touch while touch owns the scroll (UI-R23 feedback
  /// #2, "the first scroll touch kept moving the playhead"). Seeking on
  /// the release would walk straight back through both.
  final void Function(TimelineRowAddress row) onTapClear;

  /// Move mode (handle-level): pure grid geometry — frame steps along the
  /// main axis, ROW steps across it (the mount maps rows onto layers or
  /// tracks). [frameIndex] is where the pointer went DOWN, which is what
  /// tells a cut row WHICH block was grabbed.
  final bool Function(TimelineRowAddress row, int frameIndex) onMoveBegin;
  final void Function(int frameDelta, int rowDelta) onMoveUpdate;
  final VoidCallback onMoveEnd;
  final VoidCallback onMoveCancel;
}

enum _RangeDragMode { none, select, move }

/// The row-wide gesture layer for range selection + range move (UI-R8).
/// Replaces the block-body move handle: dragging frames now SELECTS, and
/// dragging the selected span moves it (TVP style). Translucent + pen/
/// mouse only, so taps keep falling through to the cells and a finger
/// still scrolls the grid (the block-move handle's arena contract).
///
/// Row-addressed rather than layer-addressed: the storyboard's CUT row
/// mounts this same layer with a [TrackRowAddress], so the four surfaces
/// share one drag state machine instead of one of them owning a lookalike.
class TimelineFrameRangeGestureLayer extends StatefulWidget {
  const TimelineFrameRangeGestureLayer({
    super.key,
    required this.row,
    required this.geometry,
    required this.crossAxisExtent,
    required this.callbacks,
    this.axis = Axis.horizontal,
  });

  /// The row this layer covers — a layer's cells or a track's cuts.
  final TimelineRowAddress row;

  /// The LIVE frame-axis geometry (R28 #4): read at gesture time, so a zoom
  /// step never rebuilds this layer — it has nothing to lay out or paint.
  final TimelineFrameGeometryHandle geometry;

  /// Row height (horizontal) / column width (X-sheet) — also the cross-
  /// axis row step for move drags.
  final double crossAxisExtent;

  final TimelineRangeGestureCallbacks callbacks;
  final Axis axis;

  @override
  State<TimelineFrameRangeGestureLayer> createState() =>
      _TimelineFrameRangeGestureLayerState();
}

class _TimelineFrameRangeGestureLayerState
    extends State<TimelineFrameRangeGestureLayer> {
  _RangeDragMode _mode = _RangeDragMode.none;
  int _anchorIndex = 0;
  double _mainDelta = 0;
  double _crossDelta = 0;
  int _lastFrames = 0;
  int _lastRows = 0;

  /// D42: what the edge auto-pan has scrolled since the press, per axis.
  /// SELECT is position-based and `localPosition` rides the pointer-down
  /// hit-test transform — it does not see content scrolled after the down,
  /// so the applied deltas are ADDED to it before the frame/cross reads.
  /// Plain fields, no setState: this layer has nothing to lay out or
  /// paint.
  double _scrolledMain = 0;
  double _scrolledCross = 0;

  /// Whether this press already dropped the range on its DOWN (R5 #12), so
  /// the release below does not say the same thing a second time.
  bool _clearedOnDown = false;

  int _frameAt(Offset localPosition) {
    final main = widget.axis == Axis.horizontal
        ? localPosition.dx
        : localPosition.dy;
    final cell =
        ((main - widget.geometry.value.leadingFrameSpacerWidth) /
                widget.geometry.value.frameCellExtent)
            .floor();
    final frame = widget.geometry.value.frameStartIndex + cell;
    return frame < 0 ? 0 : frame;
  }

  void _startDrag(Offset localPosition) {
    _scrolledMain = 0;
    _scrolledCross = 0;
    final frame = _frameAt(localPosition);
    final insideSelection = widget.callbacks.isInSelection(widget.row, frame);
    if (insideSelection && widget.callbacks.onMoveBegin(widget.row, frame)) {
      setState(() {
        _mode = _RangeDragMode.move;
        _mainDelta = 0;
        _crossDelta = 0;
        _lastFrames = 0;
        _lastRows = 0;
      });
      return;
    }
    _mode = _RangeDragMode.select;
    _anchorIndex = frame;
    widget.callbacks.onSelectUpdate(widget.row, frame, frame, 0);
  }

  /// The pointer's cross-axis offset from THIS row's top (Excel cross-row
  /// select): it may run past the row's own bounds during the pan, which
  /// is the whole point — a negative value is above this row.
  ///
  /// Raw pixels, not a row count: dividing by this row's height would
  /// assume every other row matches it (R9 #25).
  double _crossOffsetAt(Offset localPosition) {
    return widget.axis == Axis.horizontal
        ? localPosition.dy
        : localPosition.dx;
  }

  void _updateDrag(DragUpdateDetails details) {
    if (_mode == _RangeDragMode.none) {
      return;
    }
    // D42: reaching a viewport edge auto-pans on BOTH axes — the row
    // drag's own convention (per pointer move, no timer), landed on the
    // one row-level gesture all four surfaces share. What was scrolled
    // joins the travel below, or the drag freezes the moment the view
    // starts moving under the pointer.
    final horizontal = widget.axis == Axis.horizontal;
    _scrolledMain += edgeAutoPanApply(
      context: context,
      globalPosition: details.globalPosition,
      axis: widget.axis,
    );
    final appliedCross = edgeAutoPanApply(
      context: context,
      globalPosition: details.globalPosition,
      axis: horizontal ? Axis.vertical : Axis.horizontal,
    );
    _scrolledCross += appliedCross;
    switch (_mode) {
      case _RangeDragMode.none:
        return;
      case _RangeDragMode.select:
        final local =
            details.localPosition +
            (horizontal
                ? Offset(_scrolledMain, _scrolledCross)
                : Offset(_scrolledCross, _scrolledMain));
        widget.callbacks.onSelectUpdate(
          widget.row,
          _anchorIndex,
          _frameAt(local),
          _crossOffsetAt(local),
        );
      case _RangeDragMode.move:
        // MOVE accumulates deltas, so only THIS step's applied pan joins —
        // details.delta is stated in the global frame and never sees the
        // content move. `_scrolledMain` was just incremented by exactly
        // this step's main-axis application.
        _mainDelta += horizontal ? details.delta.dx : details.delta.dy;
        _crossDelta += horizontal ? details.delta.dy : details.delta.dx;
        final frames = commaDragFrameDelta(
          accumulatedDelta: _mainDelta + _scrolledMain,
          frameCellExtent: widget.geometry.value.frameCellExtent,
        );
        // R27 #12: the row axis has a deadband — a horizontal sweep's
        // wobble must not hand the step to the row-change path.
        final rows = timelineRowStepDelta(
          accumulatedDelta: _crossDelta + _scrolledCross,
          rowExtent: widget.crossAxisExtent,
        );
        if (frames == _lastFrames && rows == _lastRows) {
          return;
        }
        _lastFrames = frames;
        _lastRows = rows;
        widget.callbacks.onMoveUpdate(frames, rows);
    }
  }

  void _endDrag() {
    final mode = _mode;
    _mode = _RangeDragMode.none;
    if (mode == _RangeDragMode.move) {
      setState(() {});
      widget.callbacks.onMoveEnd();
    }
  }

  void _cancelDrag() {
    final mode = _mode;
    _mode = _RangeDragMode.none;
    if (mode == _RangeDragMode.move) {
      setState(() {});
      widget.callbacks.onMoveCancel();
    }
  }

  @override
  void dispose() {
    // A mid-drag unmount (row scrolled out of the window) commits the move
    // AFTER the frame rather than leaking an open session (R12-③ rule).
    if (_mode == _RangeDragMode.move) {
      final callbacks = widget.callbacks;
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => callbacks.onMoveEnd(),
      );
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      key: ValueKey<String>('timeline-range-gesture-${widget.row.keySuffix}'),
      // Two detectors: the TAP (any device — a finger tap clears the
      // selection too) and the PAN. Touch joined the pan set (UI-R17
      // #6/#8): stylus pens report as TOUCH on some Windows/tablet
      // drivers, which left range selection pen-dead there — cell-area
      // panning stays available on the rulers/scrollbars.
      // PEN-10 probe: with the Input Inspector open, a down REACHING
      // this layer logs 'IN' — a 'tl dn' without a matching 'IN' is the
      // hit-test-exclusion smoking gun.
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (event) {
          if (InputInspector.visible.value) {
            InputInspector.note('tl IN=${event.kind.name}');
          }
          // R5 #12: a press OUTSIDE the selection drops it HERE, on the
          // down, not on the release.
          //
          // The tap-up clear alone made the same row feel slower than any
          // other row: pressing a different row drops the range through
          // the layer select, which is a pointer-DOWN path, while pressing
          // elsewhere in the same row had to wait for the tap to win an
          // arena it shares with the pan — and a press that drifts a few
          // pixels never becomes a tap at all, so the range simply stayed.
          //
          // Inside the selection is left alone: that press may be the
          // start of a MOVE, and a tap that turns out to be only a tap
          // still clears on the release below.
          //
          // DEVICE-GATED to the edit set — the same one the pan below
          // takes. A finger that owns the scroll must not drop a selection
          // by starting to scroll over it; its TAP still clears, on the
          // release, exactly as before (UI-R23 feedback #2's rule, which
          // an ungated down would have walked straight back through).
          _clearedOnDown =
              AppInput.timelineEditPanDevices.contains(event.kind) &&
              !widget.callbacks.isInSelection(
                widget.row,
                _frameAt(event.localPosition),
              );
          if (_clearedOnDown) {
            widget.callbacks.onTapClear(widget.row);
          }
        },
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          // The release still clears for everything the down could not
          // decide: a press inside the selection that turned out to be a
          // tap, and the devices the down stands down for.
          onTapUp: (_) {
            if (!_clearedOnDown) {
              widget.callbacks.onTapClear(widget.row);
            }
          },
          child: RawGestureDetector(
            // Translucent: the cells' pointer-down select keeps firing;
            // only the pan recognizer competes in the arena. Touch joins
            // per the input policy (UI-R22 #6): editing unless the timeline
            // scroll owns touch. EAGER slop (UI-R22F #2): the edit pan
            // accepts at the viewport recognizers' hit slop, so slow small
            // pen drags select instead of losing the arena to the scroll.
            behavior: HitTestBehavior.translucent,
            gestures: <Type, GestureRecognizerFactory>{
              EagerPanGestureRecognizer:
                  GestureRecognizerFactoryWithHandlers<
                    EagerPanGestureRecognizer
                  >(() => EagerPanGestureRecognizer(debugOwner: this), (
                    recognizer,
                  ) {
                    recognizer.supportedDevices =
                        AppInput.timelineEditPanDevices;
                    // PEN-11: RawGestureDetector does NOT inject the
                    // device gesture settings (only GestureDetector
                    // does) — without them this pan waits for kTouchSlop
                    // 18 while the viewport accepts at the DEVICE hit
                    // slop (~8 on Android): slow pen drags lost the
                    // arena on tablets.
                    recognizer.gestureSettings =
                        MediaQuery.maybeGestureSettingsOf(context);
                    recognizer.dragStartBehavior = DragStartBehavior.down;
                    recognizer.onStart = (details) =>
                        _startDrag(details.localPosition);
                    recognizer.onUpdate = _updateDrag;
                    recognizer.onEnd = (_) => _endDrag();
                    recognizer.onCancel = _cancelDrag;
                  }),
            },
          ),
        ),
      ),
    );
  }
}

/// The LANE bands' gesture bundle (UI-R23 #3 part 2): the (layer, lane)
/// selection domain — a band pan SELECTS on that lane, a pan starting
/// inside the lane selection MOVES its keys along the frame axis. Fully
/// independent of the cells' [TimelineRangeGestureCallbacks].
class TimelineLaneRangeCallbacks {
  const TimelineLaneRangeCallbacks({
    required this.selection,
    required this.onSelectUpdate,
    required this.onTapAt,
    required this.onMoveBegin,
    required this.onMoveUpdate,
    required this.onMoveEnd,
    required this.onMoveCancel,
  });

  /// The session's live LANE selection (read at press to pick the mode).
  final ValueListenable<TimelineLaneSelection?> selection;

  /// A select-drag step. [headRowDelta] (R26 #3, the cells' Excel rule on
  /// lane rows) is the pointer's row offset from the anchor lane row —
  /// the host maps it onto the layer's displayed lane list to span the
  /// selection across lane rows.
  final void Function(
    LayerId layerId,
    String laneId,
    int anchorIndex,
    int headIndex,
    int headRowDelta,
  )
  onSelectUpdate;

  /// A press on the band: STAND on [frameIndex] of this (layer, lane) —
  /// seek there and take the lane as the current row. Whether it also
  /// clears the selection is the session's question (`standOnRow`'s T10
  /// guard: outside clears, inside holds for the move).
  ///
  /// R10: a lane band paints its cells rather than mounting cell widgets,
  /// and the seek lived on the cell widget, so property rows were the one
  /// place with visible frame cells that the playhead could not be put on.
  /// One rule instead: wherever frame cells exist, you can stand.
  ///
  /// C6 (2026-08-17): fired by the cells' shared press region — pen/mouse
  /// on the DOWN, before a pan may follow — so ranging on an fx row stands
  /// first exactly as ranging on a cells row does.
  final void Function(LayerId layerId, String laneId, int frameIndex) onTapAt;

  final bool Function() onMoveBegin;
  final void Function(int frameDelta) onMoveUpdate;
  final VoidCallback onMoveEnd;
  final VoidCallback onMoveCancel;
}

/// The band-wide gesture layer for ONE property lane (UI-R23 #3 part 2)
/// — the lane counterpart of [TimelineFrameRangeGestureLayer]: same
/// EAGER pan (UI-R22F #2), same device policy, same dispose-commits rule
/// (R12-③). Select drags report a cross-axis ROW delta (R26 #3) so the
/// selection spans lane rows like the cells span layers; moves stay
/// frame-axis only.
class TimelineLaneRangeGestureLayer extends StatefulWidget {
  const TimelineLaneRangeGestureLayer({
    super.key,
    required this.layer,
    required this.laneId,
    required this.frameStartIndex,
    required this.leadingFrameSpacerWidth,
    required this.frameCellExtent,
    required this.crossAxisExtent,
    required this.callbacks,
    this.axis = Axis.horizontal,
  });

  final Layer layer;
  final String laneId;
  final int frameStartIndex;
  final double leadingFrameSpacerWidth;
  final double frameCellExtent;

  /// Lane-row height (horizontal) / column width (X-sheet) — the select
  /// drag's cross-axis row step (lane rows share one extent).
  final double crossAxisExtent;

  final TimelineLaneRangeCallbacks callbacks;
  final Axis axis;

  @override
  State<TimelineLaneRangeGestureLayer> createState() =>
      _TimelineLaneRangeGestureLayerState();
}

class _TimelineLaneRangeGestureLayerState
    extends State<TimelineLaneRangeGestureLayer> {
  _RangeDragMode _mode = _RangeDragMode.none;
  int _anchorIndex = 0;
  double _mainDelta = 0;
  int _lastFrames = 0;

  /// D42: the edge auto-pan's applied scroll since the press (see the
  /// cells layer's fields — the same staleness, the same fold).
  double _scrolledMain = 0;
  double _scrolledCross = 0;

  // Lane rows are not memoized (their bands rebuild on every host pass), so
  // this layer keeps the plain scalars — the live-geometry treatment buys
  // nothing where the widget rebuilds anyway.
  int _frameAt(Offset localPosition) {
    final main = widget.axis == Axis.horizontal
        ? localPosition.dx
        : localPosition.dy;
    final cell =
        ((main - widget.leadingFrameSpacerWidth) / widget.frameCellExtent)
            .floor();
    final frame = widget.frameStartIndex + cell;
    return frame < 0 ? 0 : frame;
  }

  void _startDrag(Offset localPosition) {
    _scrolledMain = 0;
    _scrolledCross = 0;
    final frame = _frameAt(localPosition);
    final selection = widget.callbacks.selection.value;
    // R26 #3 follow-up: the HEADER band counts as inside a whole-group
    // selection, so one drag on it grabs every member lane's keys (user
    // rule: "한번에 잡아 이동" — the shared band-row predicate).
    final insideSelection =
        selection != null &&
        laneSelectionCoversBandRow(selection, widget.layer.id, widget.laneId) &&
        selection.contains(frame);
    if (insideSelection && widget.callbacks.onMoveBegin()) {
      _mode = _RangeDragMode.move;
      _mainDelta = 0;
      _lastFrames = 0;
      return;
    }
    _mode = _RangeDragMode.select;
    _anchorIndex = frame;
    widget.callbacks.onSelectUpdate(
      widget.layer.id,
      widget.laneId,
      frame,
      frame,
      0,
    );
  }

  /// The lane-row delta of the pointer relative to THIS lane row (R26 #3
  /// cross-row select): the cross-axis local position may run past the
  /// row's own bounds during the pan.
  int _rowDeltaAt(Offset localPosition) {
    final cross = widget.axis == Axis.horizontal
        ? localPosition.dy
        : localPosition.dx;
    if (widget.crossAxisExtent <= 0) {
      return 0;
    }
    return (cross / widget.crossAxisExtent).floor();
  }

  void _updateDrag(DragUpdateDetails details) {
    if (_mode == _RangeDragMode.none) {
      return;
    }
    // D42: the same edge auto-pan fold as the cells layer — the lane
    // family closes the matrix.
    final horizontal = widget.axis == Axis.horizontal;
    _scrolledMain += edgeAutoPanApply(
      context: context,
      globalPosition: details.globalPosition,
      axis: widget.axis,
    );
    _scrolledCross += edgeAutoPanApply(
      context: context,
      globalPosition: details.globalPosition,
      axis: horizontal ? Axis.vertical : Axis.horizontal,
    );
    switch (_mode) {
      case _RangeDragMode.none:
        return;
      case _RangeDragMode.select:
        final local =
            details.localPosition +
            (horizontal
                ? Offset(_scrolledMain, _scrolledCross)
                : Offset(_scrolledCross, _scrolledMain));
        widget.callbacks.onSelectUpdate(
          widget.layer.id,
          widget.laneId,
          _anchorIndex,
          _frameAt(local),
          _rowDeltaAt(local),
        );
      case _RangeDragMode.move:
        _mainDelta += horizontal ? details.delta.dx : details.delta.dy;
        final frames = commaDragFrameDelta(
          accumulatedDelta: _mainDelta + _scrolledMain,
          frameCellExtent: widget.frameCellExtent,
        );
        if (frames == _lastFrames) {
          return;
        }
        _lastFrames = frames;
        widget.callbacks.onMoveUpdate(frames);
    }
  }

  void _endDrag() {
    final mode = _mode;
    _mode = _RangeDragMode.none;
    if (mode == _RangeDragMode.move) {
      widget.callbacks.onMoveEnd();
    }
  }

  void _cancelDrag() {
    final mode = _mode;
    _mode = _RangeDragMode.none;
    if (mode == _RangeDragMode.move) {
      widget.callbacks.onMoveCancel();
    }
  }

  @override
  void dispose() {
    // A mid-drag unmount commits the move AFTER the frame rather than
    // leaking an open session (the R12-③ rule).
    if (_mode == _RangeDragMode.move) {
      final callbacks = widget.callbacks;
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => callbacks.onMoveEnd(),
      );
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      key: ValueKey<String>(
        'timeline-lane-range-layer-${widget.layer.id}-${widget.laneId}',
      ),
      // 🚨C6 (2026-08-17): STANDING rides the CELLS' own press region — the
      // shared [InstantTapRegion] with the shared device gate, exactly as
      // `timelineRowCellsPaintArea` mounts it. It used to be a
      // GestureDetector tap, which fires only on a settled RELEASE — so a
      // range drag on an fx header/member selected without ever standing,
      // while every cells row stood first and then ranged (「일반 행은
      // 해당 인덱스에 서고 → 범위」). Pen/mouse stand on the DOWN now, a
      // finger on its settled release, and whether the press CLEARS is
      // still the session's one question (`standOnRow`'s T10 guard), so a
      // press inside the lane selection stands without wiping the move it
      // is starting.
      child: InstantTapRegion(
        behavior: HitTestBehavior.translucent,
        pressSeeksFor: AppInput.timelineCellPressSeeks,
        onTap: (localPosition) => widget.callbacks.onTapAt(
          widget.layer.id,
          widget.laneId,
          _frameAt(localPosition),
        ),
        child: RawGestureDetector(
          behavior: HitTestBehavior.translucent,
          gestures: <Type, GestureRecognizerFactory>{
            EagerPanGestureRecognizer:
                GestureRecognizerFactoryWithHandlers<EagerPanGestureRecognizer>(
                  () => EagerPanGestureRecognizer(debugOwner: this),
                  (recognizer) {
                    recognizer.supportedDevices =
                        AppInput.timelineEditPanDevices;
                    // PEN-11: device gesture settings (RawGestureDetector
                    // does not inject them — kTouchSlop 18 vs device ~8).
                    recognizer.gestureSettings =
                        MediaQuery.maybeGestureSettingsOf(context);
                    recognizer.dragStartBehavior = DragStartBehavior.down;
                    recognizer.onStart = (details) =>
                        _startDrag(details.localPosition);
                    recognizer.onUpdate = _updateDrag;
                    recognizer.onEnd = (_) => _endDrag();
                    recognizer.onCancel = _cancelDrag;
                  },
                ),
          },
        ),
      ),
    );
  }
}
