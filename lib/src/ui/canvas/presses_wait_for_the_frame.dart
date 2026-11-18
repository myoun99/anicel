import 'package:flutter/gestures.dart';
import 'package:flutter/scheduler.dart' show SchedulerBinding;
import 'package:flutter/widgets.dart';

import '../session/stands_with_its_picture.dart';

/// 🗣️11-15 ① (나) (유저, TVPaint 에서 확인: 「옮기자마자는 해당상황
/// tvp에서 확인했는데 나 였어. 그대로가자」): a press on a canvas that
/// stands, while a move of its playhead waits for the frame's pictures
/// ([StandsWithItsPicture]), is HELD — every point of it, as the OS handed
/// them — and goes to the canvas from its first point once the move
/// lands: drawn on the frame moved to, never on the one shown meanwhile.
/// The canvas under it takes no press meanwhile, whatever the tool.
/// Every press, held or not, tells [moves] it came: the steps in line go
/// with it ([StandsWithItsPicture.aPressCame]).
///
/// 🚨HANDED ON AS ITSELF: the press is let go where it was first taken
/// (a cancel), and each of its points is handed to the binding again —
/// the same events, so what was paired with them stays theirs (the
/// driver's pressure at a point, `PenPath`) — after the frame that shows
/// the move is laid out. The points after come the usual way.
///
/// [moves] is null where the canvas does not stand — a run plays: nothing
/// waits, nothing is held.
class PressesWaitForTheFrame extends StatefulWidget {
  const PressesWaitForTheFrame({
    super.key,
    required this.moves,
    required this.child,
  });

  final StandsWithItsPicture? moves;
  final Widget child;

  @override
  State<PressesWaitForTheFrame> createState() => _PressesWaitForTheFrameState();
}

class _PressesWaitForTheFrameState extends State<PressesWaitForTheFrame> {
  /// Each press held, its points as they came — by pointer.
  final Map<int, List<PointerEvent>> _held = {};

  /// Whether the canvas takes no press: a move waits.
  bool _waits = false;

  /// The moves the presses are held for — told when they are handed on,
  /// whichever the canvas stands by then.
  StandsWithItsPicture? _heldFor;

  @override
  void initState() {
    super.initState();
    _hear(widget.moves);
  }

  @override
  void didUpdateWidget(PressesWaitForTheFrame oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.moves, widget.moves)) {
      _hearNoMore(oldWidget.moves);
      _hear(widget.moves);
    }
  }

  @override
  void dispose() {
    _hearNoMore(widget.moves);
    super.dispose();
  }

  void _hear(StandsWithItsPicture? moves) {
    moves?.shownBy(this);
    moves?.waitsFor.addListener(_waitsMoved);
    _waits = moves?.waitsFor.value != null;
  }

  void _hearNoMore(StandsWithItsPicture? moves) {
    moves?.waitsFor.removeListener(_waitsMoved);
    moves?.noLongerShownBy(this);
    if (_waits) {
      _waits = false;
      _handOnAfterTheFrame();
    }
  }

  void _waitsMoved() {
    final waits = widget.moves?.waitsFor.value != null;
    if (waits == _waits) {
      return;
    }
    setState(() => _waits = waits);
    if (!waits) {
      _handOnAfterTheFrame();
    }
  }

  /// Hands the held presses on once the frame the move lands on is built:
  /// they go to the canvas that stands on it.
  void _handOnAfterTheFrame() {
    if (_held.isEmpty) {
      return;
    }
    SchedulerBinding.instance
      ..addPostFrameCallback((_) => _handOn())
      ..ensureVisualUpdate();
  }

  void _handOn() {
    if (_held.isEmpty) {
      return;
    }
    final held = Map.of(_held);
    _held.clear();
    final binding = GestureBinding.instance;
    // Past this widget again as they go: held no more, and taking the
    // canvas, so none of them is held a second time.
    for (final points in held.values) {
      final last = points.last;
      if (last is! PointerUpEvent && last is! PointerCancelEvent) {
        // Let go where it was first taken: its points to come are the
        // canvas's.
        binding.handlePointerEvent(
          PointerCancelEvent(
            timeStamp: last.timeStamp,
            pointer: last.pointer,
            kind: last.kind,
            device: last.device,
            position: last.position,
            viewId: last.viewId,
          ),
        );
      }
      points.forEach(binding.handlePointerEvent);
    }
    _heldFor?.holdsAPress(held: false);
    _heldFor = null;
  }

  void _pointer(PointerEvent event) {
    if (event is PointerDownEvent) {
      widget.moves?.aPressCame();
    }
    final held = _held[event.pointer];
    if (held != null) {
      held.add(event);
      return;
    }
    if (event is PointerDownEvent && _waits) {
      _held[event.pointer] = [event];
      _heldFor = widget.moves?..holdsAPress(held: true);
    }
  }

  @override
  Widget build(BuildContext context) => Listener(
    behavior: _waits ? HitTestBehavior.opaque : HitTestBehavior.deferToChild,
    onPointerDown: _pointer,
    onPointerMove: _pointer,
    onPointerUp: _pointer,
    onPointerCancel: _pointer,
    child: IgnorePointer(ignoring: _waits, child: widget.child),
  );
}
