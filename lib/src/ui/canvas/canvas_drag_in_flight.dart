import 'package:flutter/foundation.dart';

/// Whether a drag on a canvas's selection layer is in flight — a marquee,
/// a lasso, the outline of a shape fill, a cut or a shape, a box carried —
/// on any canvas.
///
/// 🔎I-110 (검증/서피스 11-17, 실기): Alt pressed while a lasso fill was being
/// traced painted nothing — the eyedropper Alt holds took the tool from
/// under the drag. A held key waited for a stroke and not for a drag, while
/// a canvas's mapped buttons take the tool from under neither (`_busy`).
/// The held keys wait for both now (`EditorKeyHolds`).
///
/// ⚠️App-wide and static, as the view's hold is (`CanvasViewHold`): a key is
/// held for the app, not for one panel. Written only by the canvas panels,
/// each for its own drag; read by the shell's held keys.
abstract final class CanvasDragInFlight {
  /// True while any canvas has a drag in flight.
  static final ValueNotifier<bool> live = ValueNotifier<bool>(false);

  /// The canvases whose drag is in flight — by owner, so a panel saying it
  /// twice, or going away mid-drag, cannot leave the window held.
  static final Set<Object> _owners = {};

  /// [owner]'s drag goes up ([active]) or lands.
  static void report(Object owner, {required bool active}) {
    if (active) {
      _owners.add(owner);
    } else {
      _owners.remove(owner);
    }
    live.value = _owners.isNotEmpty;
  }
}
