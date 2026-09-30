import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/widgets.dart';

import '../canvas/canvas_pan_hold.dart';
import '../canvas/canvas_press.dart' show canvasPressButtons, canvasPressPans;
import 'value_control_pointers.dart';

/// The canvas's pan on a panel that SCROLLS: Space held, or a mouse button
/// Input Settings maps to 「손바닥」, grabs the panel and moves its content
/// with the hand.
///
/// 🗣️R26 #34 (유저 2026-07-20): 「팬이 발동하는 숏컷(현 기본값인 2핑거
/// 드래그나 휠클릭)의 경우, 타임라인에서는 팬으로 작동하도록 로직공통화」 —
/// answered R26-rest-Q2 (2026-09-30): 「캔버스 설정을 그대로 따른다」. ONE
/// predicate, the canvas's own [canvasPressPans] (never a copy), and ONE
/// stand-down, [PanHoldGate].
///
/// It hears the press ABOVE the panel (translucent), so it still hears it
/// while the gate below has every tool standing down, and it claims the
/// pointer at its down: a control the pan starts over or crosses never fires
/// ([claimPointerForValueControl]). Touch is not its — a finger scrolls
/// through the panel's own scrollers.
class PanelPanDriver extends StatefulWidget {
  const PanelPanDriver({
    super.key,
    required this.controllers,
    required this.child,
  });

  /// The panel's scroll controllers: every attached position moves along its
  /// own axis.
  final List<ScrollController> controllers;
  final Widget child;

  @override
  State<PanelPanDriver> createState() => _PanelPanDriverState();
}

class _PanelPanDriverState extends State<PanelPanDriver> {
  int? _pointer;
  Offset _last = Offset.zero;

  void _down(PointerDownEvent event) {
    if (_pointer != null ||
        event.kind == PointerDeviceKind.touch ||
        !canvasPressPans(canvasPressButtons(event))) {
      return;
    }
    _pointer = event.pointer;
    _last = event.position;
    claimPointerForValueControl(event.pointer);
  }

  void _move(PointerMoveEvent event) {
    if (event.pointer != _pointer) {
      return;
    }
    final delta = event.position - _last;
    _last = event.position;
    for (final controller in widget.controllers) {
      for (final position in controller.positions) {
        final along = position.axis == Axis.horizontal ? delta.dx : delta.dy;
        // The content goes WITH the hand: dragging down shows what was above.
        final to = (position.pixels - along).clamp(
          position.minScrollExtent,
          position.maxScrollExtent,
        );
        if (to != position.pixels) {
          position.jumpTo(to);
        }
      }
    }
  }

  void _end(PointerEvent event) {
    if (event.pointer != _pointer) {
      return;
    }
    _pointer = null;
    releasePointerForValueControl(event.pointer);
  }

  @override
  void dispose() {
    if (_pointer case final pointer?) {
      releasePointerForValueControl(pointer);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Listener(
    behavior: HitTestBehavior.translucent,
    onPointerDown: _down,
    onPointerMove: _move,
    onPointerUp: _end,
    onPointerCancel: _end,
    child: PanHoldGate(child: widget.child),
  );
}
