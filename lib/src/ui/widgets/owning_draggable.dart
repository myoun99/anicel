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
  });

  @override
  MultiDragGestureRecognizer createRecognizer(
    GestureMultiDragStartCallback onStart,
  ) => OwningMultiDragGestureRecognizer(
    allowedButtonsFilter: allowedButtonsFilter,
  )..onStart = onStart;
}
