/// A list whose rows you STAND on with a press and move with a drag that
/// leaves the row — the brush rail's group tabs and the colour panel's
/// palettes, one code (I-131, 유저 2026-10-28: 「이름 탭다운하고 드래그하면
/// 브러시 그룹 이동하는 로직 법 통일/재사용해서 드래그」).
library;

import 'package:flutter/gestures.dart' show MultiDragGestureRecognizer;
import 'package:flutter/material.dart';

import '../input/control_press_claim.dart';
import 'app_tooltip.dart';
import 'axis_bar_gesture.dart' show OwningMultiDragGestureRecognizer;

/// Wraps a reorderable item so PRESSING it takes any open tooltip down.
///
/// ⚠️Pointer DOWN, not `onReorderStart`. Measured: dismissing from
/// `onReorderStart` only changes which form of the assert fires — by then
/// the list is already inside the machinery that re-parents items, and
/// removing an overlay entry there is itself the illegal mutation. Pointer
/// down is a plain gesture callback with no layout in flight, and it is
/// also simply when a tooltip should go: the hand has stopped hovering and
/// started doing.
///
/// A `Listener` consumes nothing, so the drag recogniser underneath is
/// untouched.
Widget dismissTooltipsOnPress(Widget child) => Listener(
  onPointerDown: (_) => AppTooltip.dismissAllToolTips(),
  child: child,
);

/// What a row is built with: whether a row is being carried, and the grip
/// that makes a part of the row the thing you stand on to move it.
class StandOnRow {
  const StandOnRow._({required this.reordering, required this.grip});

  /// True while a row is carried, and for one frame past the drop: the
  /// rows must hold no tooltip then.
  final bool reordering;

  /// `handle` as the part of the row a drag that leaves it moves the row
  /// by — the whole of a brush group's tab, a palette's name (I-131: 「이름
  /// 탭다운하고 드래그하면」).
  final Widget Function(Widget handle) grip;
}

/// [itemCount] rows, each built by [itemBuilder], moved by a drag that
/// leaves the part of the row it gripped ([canMove] says which rows move).
class StandOnReorderList extends StatefulWidget {
  const StandOnReorderList({
    super.key,
    required this.listKey,
    required this.itemCount,
    required this.entryKeyOf,
    required this.itemBuilder,
    required this.canMove,
    required this.onReorderItem,
    this.scrollController,
    this.header,
    this.padding,
  });

  /// The key of the list itself.
  final Key listKey;
  final int itemCount;

  /// Row [index]'s key — what the list knows it by while it moves.
  final Key Function(int index) entryKeyOf;

  /// Row [index], gripped where its [StandOnRow.grip] says.
  final Widget Function(BuildContext context, int index, StandOnRow row)
  itemBuilder;

  final bool Function(int index) canMove;

  /// The row at `oldIndex` lands at `newIndex`, a TARGET — see
  /// `reorderAnchorAt`.
  final void Function(int oldIndex, int newIndex) onReorderItem;

  final ScrollController? scrollController;

  /// What stands above the rows and never moves.
  final Widget? header;
  final EdgeInsets? padding;

  @override
  State<StandOnReorderList> createState() => _StandOnReorderListState();
}

class _StandOnReorderListState extends State<StandOnReorderList> {
  /// True while a row is being dragged.
  ///
  /// A `Tooltip` is an `OverlayPortal`, and reordering re-parents items
  /// through the inactive list by global key. If autoscroll brings one back
  /// while the panel's `LayoutBuilder` is mid-layout, the portal tries to
  /// add itself to the overlay right then and trips
  /// "a _RenderLayoutBuilder was mutated in performLayout" — which takes the
  /// whole rail red. Dropping the tooltips for the duration of a drag leaves
  /// nothing in the item that reaches for the overlay.
  ///
  /// 🚨유저, R4 #11: 브러시그룹을 드래그로 옮기면 2번째 버튼부터 끝까지
  /// 빨간 에러 뜨고 콘솔에 무한 에러.
  ///
  /// ★This flag was only ever HALF the guard, and the missing half is
  /// [dismissTooltipsOnPress]. It stops a tooltip from being BORN during a
  /// drag; it does nothing about one that was ALREADY UP when the drag
  /// started — which is the common case, because the hand that drags a tab
  /// has been resting on it. That live overlay entry is what gets
  /// re-parented mid-layout. Measured, not reasoned: dropping the ⋯ menu did
  /// not fix it, and neither did keeping the tooltip widget mounted; only
  /// having no LIVE tooltip at drag start did.
  bool _reordering = false;

  @override
  Widget build(BuildContext context) => ReorderableListView.builder(
    key: widget.listKey,
    scrollController: widget.scrollController,
    padding: widget.padding,
    header: widget.header,
    buildDefaultDragHandles: false,
    itemCount: widget.itemCount,
    onReorderStart: (_) => setState(() => _reordering = true),
    // 🚨★★★THE FLAG OUTLIVES THE DROP BY A FRAME (유저 2026-09-01, F-60,
    // with the recipe: 「3번째 브러시 그룹을 드래그해서 4번째랑
    // 자리바꾸기 … 커밋될때? 끝날때 빨간화면떴어」).
    //
    // ⛔Clearing it here — synchronously — put the tooltips back in the
    // SAME frame that `ReorderableListView` revives the dragged item from
    // the inactive list by global key. Flutter named the collision itself:
    //
    //   A _RenderLayoutBuilder was mutated in performLayout.
    //   _RenderTheater._addDeferredChild ← _OverlayEntryLocation._activate
    //     ← _OverlayPortalElement.activate ← Element._activateRecursively
    //   error-causing widget: ReorderableListView-[brush-preset-tab-rail]
    //
    // A `Tooltip` is an `OverlayPortal`; reviving one adds a deferred child
    // to the theater, and that is illegal inside the panel's
    // `LayoutBuilder` layout callback. Everything after it in 유저's log —
    // the ink `referenceBox.attached` asserts, the semantics
    // `traversalParentIdentifier` failure, buttons vanishing on hover
    // across the whole app — is the wreckage of that one frame.
    //
    // ⚠️A post-frame callback, not a timer: the next frame is exactly when
    // the revival is over and no more than that.
    onReorderEnd: (_) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        setState(() => _reordering = false);
      });
    },
    onReorderItem: widget.onReorderItem,
    itemBuilder: _row,
  );

  /// Row [index], gripped where it says ([StandOnRow.grip]).
  Widget _row(BuildContext context, int index) => KeyedSubtree(
    key: widget.entryKeyOf(index),
    child: widget.itemBuilder(
      context,
      index,
      StandOnRow._(
        reordering: _reordering,
        grip: (handle) => _grip(index, handle),
      ),
    ),
  );

  /// [handle] as what row [index] is moved by — when it moves at all.
  Widget _grip(int index, Widget handle) => widget.canMove(index)
      ? dismissTooltipsOnPress(
          // ⛔The Builder is here for its CONTEXT, as the brush cell's is:
          // the predicate needs the handle's own box.
          Builder(
            builder: (handleContext) => _StandOnDragStartListener(
              index: index,
              stillOnTheThing: (global) =>
                  pointerIsStillOn(handleContext, global),
              // The WHOLE handle is stood on, its empty room too — a press
              // anywhere on it is its own ([ControlPressClaim]), and a
              // palette's name is shorter than the row it stands in.
              // Measured: a drag begun beside the name's last letter never
              // reached the listener.
              child: Listener(behavior: HitTestBehavior.opaque, child: handle),
            ),
          ),
        )
      : handle;
}

/// A row's reorder, started by the brush cell's own recogniser.
///
/// 🗣️F-198 (유저 2026-09-27: 「그냥 브라시 그룹 동작하듯이 하라고. 펜다운하면
/// 선택되고 그런거 싹 다 통일하면 해결이잖아」). The tab and the cell are both
/// things you STAND on — pressing picks — so they take a drag by one rule,
/// F-138-Q1's: the first move claims the pointer and leaving the thing
/// starts the drag ([OwningMultiDragGestureRecognizer.stillOnTheThing]).
/// ⛔Flutter's own listener waited for the device's slop — one pixel for a
/// mouse, eighteen for a pen — the distance 유저 had struck out on
/// 2026-08-30 (「1px 이동했는지 같은 px 이동으로 판단하는거 … 싹 깔끔하게
/// 걷어내」); the tab kept it only because no one had asked it.
class _StandOnDragStartListener extends ReorderableDragStartListener {
  const _StandOnDragStartListener({
    required super.index,
    required super.child,
    required this.stillOnTheThing,
  });

  final bool Function(Offset globalPosition) stillOnTheThing;

  @override
  MultiDragGestureRecognizer createRecognizer() =>
      OwningMultiDragGestureRecognizer(
        debugOwner: this,
        stillOnTheThing: stillOnTheThing,
      );
}
