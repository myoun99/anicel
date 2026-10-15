import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// A layer that answers SOME of its pixels lets every other one through:
/// [child] is hit only where [admits] says the position is its own, so a
/// press anywhere else falls to what lies under it.
///
/// ⛔Refusing in the gesture callbacks is too late. An eager pan, an owning
/// drag or an opaque listener claims the arena the moment it is HIT, so a
/// layer with nothing to say at a position must not be hit there at all.
///
/// ⚠️ONE WIDGET for it. The storyboard's strip gesture, the rows' edit
/// chrome and the canvas box's press area each wrote this proxy box out by
/// hand (`_FrameHitGate`, `_ChromeHitGate`, `_BoxPressArea`); a header
/// graph's handles (I-89 ③) would have been the fourth.
class HitGate extends SingleChildRenderObjectWidget {
  const HitGate({super.key, required this.admits, super.child});

  /// Whether a pointer at this local position is [child]'s.
  final bool Function(Offset position) admits;

  @override
  RenderHitGate createRenderObject(BuildContext context) =>
      RenderHitGate(admits);

  @override
  void updateRenderObject(BuildContext context, RenderHitGate renderObject) {
    renderObject.admits = admits;
  }
}

/// [HitGate]'s box.
class RenderHitGate extends RenderProxyBox {
  RenderHitGate(this.admits);

  bool Function(Offset position) admits;

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) =>
      size.contains(position) &&
      admits(position) &&
      super.hitTest(result, position: position);
}
