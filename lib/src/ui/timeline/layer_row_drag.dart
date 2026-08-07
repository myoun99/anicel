/// Dragging a rail ROW to move it — the gesture half of the row-order
/// round, riding the policy P2a put down.
///
/// The rail row itself is the handle (user, 2026-08-07): no new column, and
/// the pen/touch split the timeline's edit gestures already use decides the
/// conflict — the rail scrolls along the SAME axis the drag runs, so
/// something has to. Pen and mouse move the row; a finger scrolls, unless
/// the input policy has been flipped to make touch edit like the pen.
///
/// Long-press is not an option here and never was: it does not fire at all
/// inside a scroll view (measured, R10).
library;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/gestures.dart' show DragStartBehavior;
import 'package:flutter/material.dart';

import '../../models/layer.dart';
import '../../models/layer_id.dart';
import '../input/app_input_settings.dart' show AppInput;
import '../input/eager_pan_gesture_recognizer.dart';
import '../theme/app_theme.dart' show AppShapes;

/// A row drag in flight, as the rails draw it.
class LayerRowDragState {
  const LayerRowDragState({
    required this.movingId,
    required this.caretSlot,
    required this.legal,
    this.joinLabel,
  });

  /// The row the pointer holds (whatever else travels with it is the
  /// policy's business, not the caret's).
  final LayerId movingId;

  /// Where the caret sits, as a gap in the surface's LAYER row list: 0 is
  /// before the first, `length` after the last.
  final int caretSlot;

  /// Whether releasing here would move anything. An illegal landing draws
  /// no caret rather than a red one — the row simply stays put.
  final bool legal;

  /// What the drop would additionally DO, for the caret to say out loud:
  /// the folder the row would join. Null when the drop only re-orders.
  ///
  /// A structural change has to be visible before the release, not
  /// discovered after it.
  final String? joinLabel;
}

/// What a rail needs to run a row drag. Null anywhere leaves the rows
/// display-only, which is what a passive host wants.
class TimelineRowDragHooks {
  const TimelineRowDragHooks({
    required this.drag,
    required this.onBegin,
    required this.onUpdate,
    required this.onEnd,
    required this.onCancel,
  });

  final ValueListenable<LayerRowDragState?> drag;

  final void Function(LayerId layerId) onBegin;

  /// The caret moved. [displayLayers] is the list the SURFACE renders, so
  /// the session can map the slot onto the model without guessing which way
  /// this rail runs.
  final void Function(List<Layer> displayLayers, int slot) onUpdate;

  final VoidCallback onEnd;
  final VoidCallback onCancel;
}

/// The caret's thickness and colour, shared by every rail that draws one.
const double layerRowCaretThickness = 2;

/// One rail row, made draggable and able to show the caret on its own
/// edges.
///
/// The caret rides HERE rather than in an overlay of its own because the
/// rail's rows are the only thing that knows where a row boundary is —
/// windowed, virtualized and (on the storyboard) unequal in height. An
/// overlay would have to re-derive that geometry, and re-derived geometry
/// is the defect this rail keeps paying for (R9 #22, R9 #25).
///
/// [child] is passed through untouched, so a memoized row stays memoized:
/// only this thin wrapper rebuilds while a drag is in flight.
class LayerRowDragTarget extends StatelessWidget {
  const LayerRowDragTarget({
    super.key,
    required this.layerId,
    required this.slotBefore,
    required this.rowExtent,
    required this.displayLayers,
    required this.axis,
    required this.hooks,
    required this.child,
    this.isLastRow = false,
  });

  final LayerId layerId;

  /// The caret slot on this row's LEADING edge; the trailing edge is
  /// [slotBefore] + 1. Stated as a slot rather than an index because a
  /// caret lives between rows, not on one.
  final int slotBefore;

  /// This row's extent along the rail (its height on the timeline, its
  /// width on the sheet) — the drag counts rows in these, never in an
  /// assumed pitch.
  final double rowExtent;

  /// The layer rows the surface is rendering, in ITS order.
  final List<Layer> displayLayers;

  /// The rail's own direction.
  final Axis axis;

  final TimelineRowDragHooks? hooks;

  /// Whether this is the last row of the rail — only it can show the
  /// trailing caret, or two adjacent rows would both draw the same gap.
  final bool isLastRow;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final hooks = this.hooks;
    if (hooks == null) {
      return child;
    }
    return _LayerRowDragBody(
      layerId: layerId,
      slotBefore: slotBefore,
      rowExtent: rowExtent,
      displayLayers: displayLayers,
      axis: axis,
      hooks: hooks,
      isLastRow: isLastRow,
      child: child,
    );
  }
}

class _LayerRowDragBody extends StatefulWidget {
  const _LayerRowDragBody({
    required this.layerId,
    required this.slotBefore,
    required this.rowExtent,
    required this.displayLayers,
    required this.axis,
    required this.hooks,
    required this.isLastRow,
    required this.child,
  });

  final LayerId layerId;
  final int slotBefore;
  final double rowExtent;
  final List<Layer> displayLayers;
  final Axis axis;
  final TimelineRowDragHooks hooks;
  final bool isLastRow;
  final Widget child;

  @override
  State<_LayerRowDragBody> createState() => _LayerRowDragBodyState();
}

class _LayerRowDragBodyState extends State<_LayerRowDragBody> {
  double _travelled = 0;

  void _begin() {
    _travelled = 0;
    widget.hooks.onBegin(widget.layerId);
    widget.hooks.onUpdate(widget.displayLayers, widget.slotBefore);
  }

  void _update(Offset delta) {
    _travelled += widget.axis == Axis.horizontal ? delta.dy : delta.dx;
    if (widget.rowExtent <= 0) {
      return;
    }
    // Rows CROSSED, rounded: the caret snaps to the boundary the pointer is
    // nearest, which is what makes a one-row move need only half a row of
    // travel.
    final crossed = (_travelled / widget.rowExtent).round();
    final slot = (widget.slotBefore + crossed).clamp(
      0,
      widget.displayLayers.length,
    );
    widget.hooks.onUpdate(widget.displayLayers, slot);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return ValueListenableBuilder<LayerRowDragState?>(
      valueListenable: widget.hooks.drag,
      builder: (context, drag, child) {
        final showing = drag != null && drag.legal ? drag : null;
        final leading =
            showing != null && showing.caretSlot == widget.slotBefore;
        final trailing =
            showing != null &&
            widget.isLastRow &&
            showing.caretSlot == widget.slotBefore + 1;
        final lifted = drag?.movingId == widget.layerId;
        return Stack(
          clipBehavior: Clip.none,
          children: [
            // The lifted row fades: the caret says where it is going, and
            // the row saying "not here any more" is the other half.
            Opacity(opacity: lifted ? 0.45 : 1, child: child),
            if (leading)
              _caret(colorScheme, atStart: true, label: showing.joinLabel),
            if (trailing)
              _caret(colorScheme, atStart: false, label: showing.joinLabel),
          ],
        );
      },
      child: _gestures(child: widget.child),
    );
  }

  Widget _gestures({required Widget child}) {
    return RawGestureDetector(
      // Translucent: the row's own taps (select the layer, the eye, the
      // sliders) keep firing — only the pan recognizer joins the arena.
      behavior: HitTestBehavior.translucent,
      gestures: <Type, GestureRecognizerFactory>{
        EagerPanGestureRecognizer:
            GestureRecognizerFactoryWithHandlers<EagerPanGestureRecognizer>(
              () => EagerPanGestureRecognizer(debugOwner: this),
              (recognizer) {
                // The rail SCROLLS along the same axis this drag runs, so
                // the device policy is what separates them: pen and mouse
                // move rows, a finger scrolls (UI-R22 #6).
                recognizer.supportedDevices = AppInput.timelineEditPanDevices;
                // PEN-11: RawGestureDetector does not inject these.
                recognizer.gestureSettings = MediaQuery.maybeGestureSettingsOf(
                  context,
                );
                recognizer.dragStartBehavior = DragStartBehavior.down;
                recognizer.onStart = (_) => _begin();
                recognizer.onUpdate = (details) => _update(details.delta);
                recognizer.onEnd = (_) => widget.hooks.onEnd();
                recognizer.onCancel = widget.hooks.onCancel;
              },
            ),
      },
      child: child,
    );
  }

  Widget _caret(
    ColorScheme colorScheme, {
    required bool atStart,
    String? label,
  }) {
    final horizontal = widget.axis == Axis.horizontal;
    final bar = Container(
      width: horizontal ? double.infinity : layerRowCaretThickness,
      height: horizontal ? layerRowCaretThickness : double.infinity,
      color: colorScheme.primary,
    );
    final content = label == null
        ? bar
        : Stack(
            clipBehavior: Clip.none,
            alignment: horizontal ? Alignment.centerLeft : Alignment.topCenter,
            children: [
              bar,
              // The drop does something structural, so it says so BEFORE
              // the release.
              Padding(
                padding: const EdgeInsets.only(left: 6),
                child: DecoratedBox(
                  // The app's own corner, not a circular one: a badge is a
                  // small control, and `app_shapes_coverage_test` is what
                  // keeps that from being decided per widget.
                  decoration: ShapeDecoration(
                    color: colorScheme.primary,
                    shape: AppShapes.control(14),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 1,
                    ),
                    child: Text(
                      label,
                      style: TextStyle(
                        fontSize: 10,
                        height: 1.1,
                        color: colorScheme.onPrimary,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
    return Positioned(
      key: ValueKey<String>(
        'timeline-row-caret-${atStart ? 'before' : 'after'}-${widget.layerId}',
      ),
      left: horizontal ? 0 : (atStart ? -layerRowCaretThickness / 2 : null),
      right: horizontal ? 0 : (atStart ? null : -layerRowCaretThickness / 2),
      top: horizontal ? (atStart ? -layerRowCaretThickness / 2 : null) : 0,
      bottom: horizontal ? (atStart ? null : -layerRowCaretThickness / 2) : 0,
      child: content,
    );
  }
}
