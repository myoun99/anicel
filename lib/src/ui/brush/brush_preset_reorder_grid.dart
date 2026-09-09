import 'dart:math' as math;

import 'package:flutter/material.dart';

/// How wide one preset cell wants to be, in logical pixels.
///
/// 🚨유저 확정: 「**260px 폭에서 2열**」, and the panel's own default width is
/// 260 — so the target is half of it, and the column count simply follows the
/// width from there (「패널 크기따라 좌우 1행에 3열 ... 패널 길어지면 4열」).
const double brushPresetCellTargetWidth = 130.0;

/// The ceiling. Four is where the user's own description stops, and a fifth
/// column at some very wide panel would make the strokes unreadable rather
/// than the panel more useful.
const int brushPresetMaxColumns = 4;

/// The height one preset cell takes.
///
/// ⚠️ONE NUMBER, because the cell is DRAWN at it and the drop slot is
/// COMPUTED from it — two copies would aim the drag at a different gap than
/// the one on screen.
const double brushPresetRowHeight = 34.0;

/// How many columns [width] holds.
int brushPresetColumnsFor(double width) {
  if (!width.isFinite || width <= 0) {
    return 1;
  }
  final fit = (width / brushPresetCellTargetWidth).floor();
  return fit.clamp(1, brushPresetMaxColumns);
}

/// A grid whose cells can be dragged into a new order.
///
/// 🚨유저 확정 (`brush-grid-reorder-Q1`, 답 1): 「2열에서도 드래그 재정렬을
/// 지킨다 — 재정렬 그리드를 직접 쓴다」. The option this beat was "grid for
/// picking, reordering in the list view", and its cost was the reason:
/// changing the order would have meant changing the VIEW first, so one job
/// would have grown two modes — and a brush dragged in the grid would do
/// nothing with no way to say why (⛔설명 문구 금지).
///
/// ⛔Flutter has no reorderable grid and neither did this repo, so this is
/// written rather than borrowed: `ReorderableListView` and
/// `SliverReorderableList` are both ONE-DIMENSIONAL, and the sixteen
/// `GridView`/`Wrap` sites here have no reordering at all.
///
/// ⚠️IT IS THE ONLY LIST. One column is a grid with one column, so there is
/// no second code path for the narrow panel and no view where dragging
/// stops working.
class BrushPresetReorderGrid extends StatefulWidget {
  const BrushPresetReorderGrid({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
    required this.itemKey,
    required this.cellHeight,
    this.scrollController,
    this.onReorder,
    this.onDragStart,
    this.onDragEnd,
  });

  final int itemCount;

  /// The cell's content. It keeps its own tap handling — a press that does
  /// not move is a pick, exactly as it was in the list.
  final Widget Function(BuildContext context, int index) itemBuilder;

  /// A stable identity per index, so a cell ANIMATES to its new place
  /// instead of being rebuilt there.
  final Key Function(int index) itemKey;

  final double cellHeight;
  final ScrollController? scrollController;

  /// Old index, new index — the same contract `ReorderableListView` used, so
  /// the panel's existing handler is unchanged.
  final void Function(int oldIndex, int newIndex)? onReorder;

  /// The rail springs its tabs open while a drag is in flight, and it has to
  /// be told: a drag reports to the cell it picked up, never to what is
  /// under it now.
  final VoidCallback? onDragStart;
  final VoidCallback? onDragEnd;

  @override
  State<BrushPresetReorderGrid> createState() => _BrushPresetReorderGridState();
}

class _BrushPresetReorderGridState extends State<BrushPresetReorderGrid> {
  /// The cell being carried, by its ORIGINAL index.
  int? _dragIndex;

  /// Where it would land if the pointer let go now.
  int? _targetIndex;

  void _endDrag({required bool accepted}) {
    final from = _dragIndex;
    final to = _targetIndex;
    setState(() {
      _dragIndex = null;
      _targetIndex = null;
    });
    widget.onDragEnd?.call();
    if (accepted && from != null && to != null && from != to) {
      widget.onReorder?.call(from, to);
    }
  }

  /// The order the cells are DRAWN in while a drag is in flight: the carried
  /// cell lifted out and put back at the target, so the gap the user is
  /// aiming at is the gap they see.
  List<int> _visualOrder() {
    final indices = [for (var i = 0; i < widget.itemCount; i += 1) i];
    final from = _dragIndex;
    final to = _targetIndex;
    if (from == null || to == null) {
      return indices;
    }
    final moved = indices.removeAt(from);
    indices.insert(to.clamp(0, indices.length), moved);
    return indices;
  }

  /// Which slot a pointer at [local] is over.
  int _slotAt(Offset local, int columns, double cellWidth) {
    final column = (local.dx / cellWidth).floor().clamp(0, columns - 1);
    final row = math.max(0, (local.dy / widget.cellHeight).floor());
    final slot = row * columns + column;
    return slot.clamp(0, math.max(0, widget.itemCount - 1));
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : brushPresetCellTargetWidth;
        final columns = brushPresetColumnsFor(width);
        final cellWidth = width / columns;
        final rows = (widget.itemCount / columns).ceil();
        final order = _visualOrder();

        Widget cellAt(int slot) {
          final index = order[slot];
          final left = (slot % columns) * cellWidth;
          final top = (slot ~/ columns) * widget.cellHeight;
          // ⚠️The caller's key goes on a real BOX, not on the
          // `AnimatedPositioned`: that one is a `Positioned` underneath, which
          // has no render object, so `tester.getCenter` — and anything else
          // that measures a cell — would find nothing to measure.
          final child = SizedBox(
            key: widget.itemKey(index),
            width: cellWidth,
            height: widget.cellHeight,
            child: widget.itemBuilder(context, index),
          );
          return AnimatedPositioned(
            key: ValueKey<Key>(widget.itemKey(index)),
            duration: const Duration(milliseconds: 140),
            curve: Curves.easeOut,
            left: left,
            top: top,
            width: cellWidth,
            height: widget.cellHeight,
            child: widget.onReorder == null
                ? child
                : Draggable<int>(
                    data: index,
                    dragAnchorStrategy: childDragAnchorStrategy,
                    feedback: Material(
                      color: Colors.transparent,
                      child: SizedBox(
                        width: cellWidth,
                        height: widget.cellHeight,
                        child: Opacity(opacity: 0.85, child: child),
                      ),
                    ),
                    // ⛔The SPACE stays and only the CONTENT changes (「자리는
                    // 항상 예약하고 내용만 바꾼다」): the slot keeps the cell's
                    // exact size so nothing after it jumps, and shows the gap
                    // the drop is aiming at.
                    //
                    // ⚠️It is a bare box rather than a dimmed copy of the
                    // row, and that is not cosmetic: `Draggable` BUILDS the
                    // feedback as a second subtree, so a copy would put every
                    // key inside the row — the cell's own tap key included —
                    // into the tree twice.
                    childWhenDragging: SizedBox(
                      width: cellWidth,
                      height: widget.cellHeight,
                    ),
                    onDragStarted: () {
                      setState(() {
                        _dragIndex = index;
                        _targetIndex = index;
                      });
                      widget.onDragStart?.call();
                    },
                    onDraggableCanceled: (_, _) => _endDrag(accepted: false),
                    onDragEnd: (details) {
                      if (details.wasAccepted) {
                        return;
                      }
                      _endDrag(accepted: false);
                    },
                    child: child,
                  ),
          );
        }

        final stack = SizedBox(
          height: rows * widget.cellHeight,
          child: Stack(
            clipBehavior: Clip.none,
            children: [for (var slot = 0; slot < order.length; slot += 1) cellAt(slot)],
          ),
        );

        final body = widget.onReorder == null
            ? stack
            : DragTarget<int>(
                onWillAcceptWithDetails: (_) => true,
                onMove: (details) {
                  final box = context.findRenderObject() as RenderBox?;
                  if (box == null) {
                    return;
                  }
                  // ⚠️The feedback's TOP-LEFT is what `details.offset`
                  // reports, so the slot is read from the cell's middle —
                  // otherwise a cell dropped on its own right half would
                  // read as the slot before it.
                  final local = box.globalToLocal(
                    details.offset +
                        Offset(cellWidth / 2, widget.cellHeight / 2),
                  );
                  final slot = _slotAt(local, columns, cellWidth);
                  if (slot != _targetIndex) {
                    setState(() => _targetIndex = slot);
                  }
                },
                onLeave: (_) {},
                onAcceptWithDetails: (_) => _endDrag(accepted: true),
                builder: (context, _, _) => stack,
              );

        return SingleChildScrollView(
          controller: widget.scrollController,
          child: body,
        );
      },
    );
  }
}
