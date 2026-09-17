import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../input/control_press_claim.dart' show pointerIsStillOn;
import '../widgets/owning_draggable.dart';

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

/// The FLOOR a preset cell stands on: what the tip icon needs, and what
/// every view but one has always measured.
const double brushPresetRowHeight = 34.0;

/// The gap a cell insets itself by, so two cells do not touch. ⚠️It is part
/// of the ALLOTMENT and not of what gets drawn — the grid hands out
/// [brushPresetRowHeightFor] and the row draws inside it less this twice.
const double brushPresetCellGap = 1.0;

/// The breathing room inside the drawn row, above and below its right area.
const double brushPresetRowPadding = 2.0;

/// The stroke sample's own height — 「크기는 지금과같음」 (유저 2026-09-16).
///
/// 🔬It is written as what it HAS been rather than a fresh number: 34 less
/// the gap and the padding, twice each, is the 28 the sample has measured
/// since the row was built. ⛔A leftover ("whatever the name does not take")
/// would have shrunk the sample by exactly the band F-82 adds.
const double brushPresetStrokeBandHeight =
    brushPresetRowHeight - (brushPresetCellGap + brushPresetRowPadding) * 2;

/// The band the NAME writes in, under the stroke (F-82).
const double brushPresetNameBandHeight = 14.0;

/// The height one preset cell is ALLOTTED, in the view it is drawn in.
///
/// ⚠️ONE ANSWER, because the cell is DRAWN at it and the drop slot is
/// COMPUTED from it — two copies would aim the drag at a different gap than
/// the one on screen.
///
/// 🚨★★★F-82 (유저 2026-09-16: 「이름 공간 따로 할당 … 위에 스트로크 프리뷰
/// (크기는 지금과같음), 아래를 브러시 이름」). The right area stacks what the
/// view has turned on, so a cell is as tall as its contents — and never
/// shorter than the floor, which is what keeps every OTHER view exactly the
/// height it already was: a stroke alone lands back on 34 to the pixel, and
/// a bare tip or a lone name is held up by the floor.
double brushPresetRowHeightFor({
  required bool showName,
  required bool showStrokePreview,
}) {
  final stacked =
      (showStrokePreview ? brushPresetStrokeBandHeight : 0.0) +
      (showName ? brushPresetNameBandHeight : 0.0);
  return math.max(
    brushPresetRowHeight,
    stacked + (brushPresetCellGap + brushPresetRowPadding) * 2,
  );
}

/// How long a cell takes to slide to its new slot during a REORDER.
///
/// ⛔A RESIZE GETS `Duration.zero` INSTEAD — see the comment in the grid's
/// `build`. 유저 H33: a splitter drag re-lays the grid out on every frame, and
/// a 140ms ease-out restarting on each one is what they saw as 「쓸데없는
/// 애니메이션」.
const Duration brushPresetReorderDuration = Duration(milliseconds: 140);

/// How many columns [width] holds, for cells [cellWidth] wide — at most
/// [maxColumns], or as many as fit when that is null (H37: a list of bare
/// tips has no strokes to keep readable).
int brushPresetColumnsFor(
  double width, {
  double cellWidth = brushPresetCellTargetWidth,
  int? maxColumns = brushPresetMaxColumns,
}) {
  if (!width.isFinite || width <= 0) {
    return 1;
  }
  final fit = (width / cellWidth).floor();
  return fit.clamp(1, maxColumns ?? math.max(1, fit));
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
    this.cellTargetWidth = brushPresetCellTargetWidth,
    this.maxColumns = brushPresetMaxColumns,
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

  /// How wide a cell wants to be, and the most columns there may be — the
  /// panel's answer to what a cell is showing (H37).
  final double cellTargetWidth;
  final int? maxColumns;

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

  /// The geometry the last build laid out, so this one can tell a resize
  /// from a reorder — see the comment in [build].
  int? _laidOutColumns;
  double? _laidOutCellWidth;

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
            : widget.cellTargetWidth;
        final columns = brushPresetColumnsFor(
          width,
          cellWidth: widget.cellTargetWidth,
          maxColumns: widget.maxColumns,
        );
        final cellWidth = width / columns;
        final rows = (widget.itemCount / columns).ceil();
        final order = _visualOrder();

        // 🚨A RESIZE IS NOT A REORDER (유저 2026-09-10, H33: 「열이 바껴서 3개나
        // 4개로 늘어날때 필요없는 쓸데없는 애니메이션 있거든? 그냥 그런거 싹
        // 빼고 심플하게 열이 두개 세개로 그냥 늘어나게만」).
        //
        // A cell's position changes for exactly two reasons, and only one of
        // them is worth animating. The ORDER changing is a thing the user did
        // and wants to follow with their eye. The panel getting wider is not:
        // every frame of a splitter drag re-lays the grid out, so a 140ms
        // ease-out restarts on every one of them and the cells swim along
        // behind the splitter instead of going where they belong.
        //
        // ⛔So the duration is zero for the build that re-lays out, and back
        // to 140ms for the next one. The animation is kept for the reorder it
        // was written for.
        //
        // ⚠️CELL WIDTH, not just the column count: a splitter spends most of
        // its frames INSIDE one count, and the cells have to follow it there
        // too. Both null on the first build reads as "re-laid out", which is
        // right — a first build must not animate either.
        final relaidOut =
            _laidOutColumns != columns || _laidOutCellWidth != cellWidth;
        // ⚠️Written during build ON PURPOSE and with no setState: this is
        // layout the builder just derived, remembered so the NEXT build can
        // tell what changed. Calling setState here would be the loop.
        _laidOutColumns = columns;
        _laidOutCellWidth = cellWidth;

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
            duration: relaidOut ? Duration.zero : brushPresetReorderDuration,
            curve: Curves.easeOut,
            left: left,
            top: top,
            width: cellWidth,
            height: widget.cellHeight,
            child: widget.onReorder == null
                ? child
                // F-126: a pen lifts a cell on its first move, as a mouse
                // does ([OwningDraggable]).
                : Builder(
                    // 🚨★★★F-138 (유저 확정 2026-09-18, `F-138-Q1` 답 ①):
                    // 「브러시처럼 **서있어야 하는곳**은 누른 상자 벗어나면
                    // 시작으로」. A preset cell is a thing you STAND on —
                    // pressing it picks the brush — so a pen's tremor must
                    // stay a press. ⛔The Builder is here for its CONTEXT:
                    // the predicate needs the cell's own box, and a const
                    // widget cannot reach one.
                    builder: (cellContext) => OwningDraggable<int>(
                      stillOnTheThing: (global) =>
                          pointerIsStillOn(cellContext, global),
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
