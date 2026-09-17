import 'package:flutter/gestures.dart'
    show GestureMultiDragStartCallback, MultiDragGestureRecognizer;
import 'package:flutter/widgets.dart';

import 'axis_bar_gesture.dart';

/// A [Draggable] whose drag starts on the FIRST movement, for every kind of
/// pointer — the one drag source every `Draggable` in the app wears.
///
/// 🚨F-126 (유저 2026-09-13: 「마우스로는 움직여서 패널 위치 도킹가능한데
/// 펜으로는 불가능. 이유 확인해서 법 통일」). The stock recogniser waits for a
/// distance that depends on the device, so one drag started for a mouse and
/// not for a pen ([OwningMultiDragGestureRecognizer]). ⛔A plain `Draggable`
/// under `lib/src/ui` is that bug waiting for its next device, and
/// `every_drag_source_starts_on_the_first_move_test` reads the source for
/// one.
///
/// 🚨★★★**AND ONE KIND OF SOURCE WAITS — [stillOnTheThing]** (F-138, 유저
/// 확정 2026-09-18): 「미디어풀처럼 **선택할 필요, 서있는 로직이 없는곳**은
/// 지금처럼 바로드래그, **브러시처럼 서있어야 하는곳**은 누른 상자 벗어나면
/// 시작으로」. Not a second law — the same one, asked of a thing you first
/// have to STAND on, where a tremor must stay a press.
class OwningDraggable<T extends Object> extends Draggable<T> {
  const OwningDraggable({
    super.key,
    required super.child,
    required super.feedback,
    super.data,
    super.childWhenDragging,
    super.dragAnchorStrategy,
    super.maxSimultaneousDrags,
    super.onDragStarted,
    super.onDraggableCanceled,
    super.onDragEnd,
    this.stillOnTheThing,
  });

  /// Whether the pointer is still on the thing it pressed. Null = the drag
  /// starts on the first movement, which is every source without standing
  /// logic behind it. See [OwningMultiDragGestureRecognizer.stillOnTheThing]
  /// for the user's own split.
  ///
  /// ⛔**ANSWER IT WITH `pointerIsStillOn`** (`ui/input/control_press_claim`)
  /// — the same function the click question asks, so a POSITION and never a
  /// distance. It is a callback only because a recogniser has no tree of its
  /// own to ask; `a_drag_begins_when_you_leave_the_thing_test` fails a caller
  /// that answers with arithmetic of its own.
  final bool Function(Offset globalPosition)? stillOnTheThing;

  @override
  MultiDragGestureRecognizer createRecognizer(
    GestureMultiDragStartCallback onStart,
  ) => OwningMultiDragGestureRecognizer(
    allowedButtonsFilter: allowedButtonsFilter,
    stillOnTheThing: stillOnTheThing,
  )..onStart = onStart;
}
