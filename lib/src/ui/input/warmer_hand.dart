import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart' show KeyEvent;

import '../playback/playback_prerender_scheduler.dart';

/// 🗣️H57-Q2 = 1 (유저 2026-11-19 「손이 닿는 조작은 전부 「손」으로 — 입구
/// 한 곳」, 「굽기 가볍게는 그대로 진행」): every input the hand makes — a
/// press held, a wheel's notch, a trackpad's pan or zoom, a key — is told
/// to the warmer of the project on screen from the window's one input
/// entry, the global pointer route and the keyboard (`HomePage`), not
/// gesture by gesture. A pointer that only moves over the window (a hover)
/// is no hand on it.
///
/// A press holds the warmer while a contact is down — the census's one
/// answer ([heard]'s `down`), which learns every way a press is over — and
/// lets it go with a fresh quiet window
/// ([PlaybackPrerenderScheduler.endInputHold]); every other input opens the
/// quiet window again ([PlaybackPrerenderScheduler.notifyEditActivity]).
///
/// ⚠️The places that told the warmer before stay (H57-Q2's answer): a
/// frame chosen, a cut switched, an edit, a pen's stroke and a range
/// dragged are told so by calls no input makes too.
///
/// 🔬Main PC, S5_BA cut 352 copy, profile (11-19): wheeling over the
/// timeline while the ruler's band filled stopped the UI thread 22–46 ms
/// two or three times in two seconds, and not once the band was full;
/// the wheel told as a hand, not while it wheeled.
final class WarmerHand {
  WarmerHand(this._warmerOnScreen);

  /// The warmer of the project on screen, or null where none is.
  final PlaybackPrerenderScheduler? Function() _warmerOnScreen;

  /// The warmer the press down now holds — the one it was taken on,
  /// whichever project is on screen when it lets go.
  PlaybackPrerenderScheduler? _held;

  /// [event] off the global pointer route; [down] whether a contact is
  /// down once it was heard.
  void heard(PointerEvent event, {required bool down}) {
    if (event is PointerHoverEvent ||
        event is PointerAddedEvent ||
        event is PointerRemovedEvent) {
      return;
    }
    final warmer = _warmerOnScreen();
    final held = _held;
    if (down && held == null) {
      _held = warmer?..beginInputHold();
    } else if (!down && held != null) {
      _held = null;
      held.endInputHold();
    }
    warmer?.notifyEditActivity();
  }

  /// A key down, repeated or up. ⛔Never handles it: the key goes on to
  /// whoever it is for.
  bool heardKey(KeyEvent event) {
    _warmerOnScreen()?.notifyEditActivity();
    return false;
  }
}
