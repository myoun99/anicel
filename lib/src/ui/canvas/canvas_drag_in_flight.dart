import 'package:flutter/foundation.dart';

/// Whether a drag on a canvas's layer is in flight, on any canvas — the
/// selection layer's (a marquee, a lasso, the outline of a shape fill, a
/// cut or a shape, a box carried), the text layer's, a guide handle's, the
/// stamp's.
///
/// 🔎I-110 (검증/서피스 11-17, 실기): Alt pressed while a lasso fill was being
/// traced painted nothing — the eyedropper Alt holds took the tool from
/// under the drag. ⛔ONE answer for whoever would take the tool: the held
/// keys (`EditorKeyHolds`) and every canvas's mapped buttons (`_busy`).
/// ↩️The keys waited for a stroke alone, the buttons for a selection's drag
/// besides, and neither for the text's — whose layer, taken away mid drag,
/// went on hearing the hand.
///
/// ⚠️App-wide and static, as the view's hold is (`CanvasViewHold`): the tool
/// is the app's, not one panel's. Each layer says so for its own drag, at
/// its one door, and lets go of it when it goes away.
abstract final class CanvasDragInFlight {
  /// True while any canvas has a drag in flight.
  static final ValueNotifier<bool> live = ValueNotifier<bool>(false);

  /// The layers whose drag is in flight — by owner, so one saying it twice
  /// counts once, and one letting go leaves another's held.
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
