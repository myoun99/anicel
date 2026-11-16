import 'package:flutter/gestures.dart'
    show
        PointerDownEvent,
        PointerEvent,
        PointerPanZoomStartEvent,
        PointerSignalEvent;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show SingleActivator;

import '../../services/input/modifier_keys.dart';
import 'shortcut_activator_codec.dart'
    show isModifierKey, modifiersAloneActivator;

/// MODIFIERS PRESSED ALONE: held, with no other key and no pointer's press
/// after the last of them went down — then let go. A press of their own,
/// of every modifier held as the last went down: Ctrl, then Alt, then
/// either let go is Ctrl+Alt.
///
/// ★ONE reading, three readers (the rule of three): the playback gate stops
/// on one (🗣️I-19-zoom-key-playback, 유저 2026-09-13: 「수식키는 혼자선
/// 입력으로 치지 않는다」 — let go with nothing after it, it was a press
/// after all), a pressed action whose key is modifiers alone runs on one
/// (🗣️F-603-Q1, 유저 2026-11-16: 「뗐을 때 — 그 사이에 다른 키나 클릭이
/// 없었으면 발동」), and the shortcut window records one (F-603). ↩️The
/// gate and the window each read it their own way till then.
///
/// 🚨ASKED OF [ModifierKeys], NOT READ OFF A KEY EVENT (card
/// a-held-modifiers-repeat-is-heard-as-a-press; 관제 2026-11-15 19:53:
/// 「러너는 만들지 않고 재생 정지 문이 `ModifierKeys` 에 묻게」). On
/// Windows a pen's or a finger's move lets go of Shift and Ctrl in the
/// engine's record with the key still down, the held key's repeat comes
/// next as a new key-down, and the release after a move is dropped
/// ([ModifierKeys]; counted on the app's own runner, F-592). ↩️Read as
/// edges — a modifier's key-down armed the gate and its key-up stopped — a
/// Shift held while the canvas played stopped it at the first move of a
/// hovering pen (read off the code, 2026-11-15; not tried by hand). So a
/// key event and a pointer event are only WHEN to ask: the release no
/// event tells of is found at the next of either.
class LoneModifiers {
  /// The modifiers held at the last ask, a bit each.
  int _held = 0;

  /// The modifiers held as the last of them went down, with nothing after
  /// it yet — null once something came after, or none went down.
  SingleActivator? _alone;

  /// The key event the last ask was heard at, and what it found
  /// ([pressedAt]).
  KeyEvent? _heardAt;
  SingleActivator? _found;

  /// Hears [event]: the modifiers pressed alone, when this ask finds one of
  /// them let go — else null. A key's down that is no modifier comes after
  /// them.
  SingleActivator? hearKey(KeyEvent event) {
    final found = _ask(
      after: event is KeyDownEvent && !isModifierKey(event.logicalKey),
    );
    _heardAt = event;
    _found = found;
    return found;
  }

  /// Hears [event] as [hearKey] does a key's: a press, a wheel notch or a
  /// pinch comes after them.
  SingleActivator? hearPointer(PointerEvent event) {
    _heardAt = null;
    _found = null;
    return _ask(
      after:
          event is PointerDownEvent ||
          event is PointerSignalEvent ||
          event is PointerPanZoomStartEvent,
    );
  }

  /// What [hearKey] found at [event] — null unless it was the last event
  /// heard.
  SingleActivator? pressedAt(KeyEvent event) =>
      identical(event, _heardAt) ? _found : null;

  /// Nothing held now is pressed alone, whenever it is let go.
  void forget() => _alone = null;

  /// The modifiers held now, asked; a let-go one is found before [after]
  /// is — the release came first.
  SingleActivator? _ask({required bool after}) {
    final held =
        (ModifierKeys.isShiftPressed ? _shift : 0) |
        (ModifierKeys.isControlPressed ? _control : 0) |
        (ModifierKeys.isAltPressed ? _alt : 0) |
        (ModifierKeys.isMetaPressed ? _meta : 0);
    final before = _held;
    _held = held;
    SingleActivator? found;
    if (before & ~held != 0) {
      found = _alone;
      _alone = null;
    }
    if (after) {
      _alone = null;
    } else if (held & ~before != 0) {
      _alone = modifiersAloneActivator(
        control: held & _control != 0,
        shift: held & _shift != 0,
        alt: held & _alt != 0,
        meta: held & _meta != 0,
      );
    }
    return found;
  }

  static const _shift = 1;
  static const _control = 2;
  static const _alt = 4;
  static const _meta = 8;
}
