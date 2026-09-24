import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../brush/brush_tool_state.dart';
import '../brush/temporary_tool.dart';
import '../canvas/canvas_pan_hold.dart';
import 'editor_action_registry.dart';
import 'editor_shortcut_bindings.dart';

/// The keys that are HELD rather than pressed (I-15).
///
/// 🗣️유저 2026-09-11: 「손바닥 툴을 만들지는 않음. 다만 단축키에 이동?
/// 추가하는건 추가하고, 기본값을 휠클릭이 아니라 스페이스바로 이동. 그리고
/// 기존 재생단축키가 스페이스바인데 그냥 해제. 스포이드는 그대로 해서
/// 누르는동안 툴 바뀌도록」 — and, while doing it, 「법 하나 통일하는거
/// 유념해줘」.
///
/// ★ONE LAW FOR EVERY HELD INPUT: while it is held its action is in force,
/// and letting go ends it. A pen or mouse button always worked that way
/// (PEN-7a — the tool switches through [TemporaryTool], a wheel click
/// pans); a held key now goes through the same two doors: the eyedropper
/// through [TemporaryTool], the pan through [CanvasPanHold].
///
/// ⚠️TAKEN on the shortcut road, LET GO on the keyboard's. A press is taken
/// where every shortcut is (`EditorShortcutManager`), so a focused text
/// field keeps its space bar the way it keeps its letters; a release is
/// heard app-wide, because a key let go after the focus moved must still
/// let go.
final class EditorKeyHolds {
  EditorKeyHolds({
    required this.bindings,
    required this.tool,
    required this.temporaryTool,
    required this.strokeLive,
  }) {
    HardwareKeyboard.instance.addHandler(_onKey);
    strokeLive.addListener(_onStrokeLive);
  }

  final EditorShortcutBindings bindings;
  final ValueListenable<BrushToolState> tool;
  final TemporaryTool temporaryTool;

  /// True while a stroke is being drawn. A tool switch WAITS for it to end
  /// — the pen's own law: a barrel button that rises mid-stroke never
  /// hijacks the live line. The pan needs no wait: a press already down
  /// keeps its route, so the pan only ever takes the NEXT press.
  final ValueListenable<bool> strokeLive;

  final Map<LogicalKeyboardKey, _KeyHold> _held = {};

  /// Eyedropper keys that came down mid-stroke: held, and in force the
  /// moment the stroke ends.
  final Set<LogicalKeyboardKey> _waiting = {};

  /// A key event on the shortcut road. HANDLED when it belongs to the pan —
  /// the space bar then does nothing else, its repeats included; the
  /// eyedropper's Alt passes on, because it still modifies whatever it is
  /// held with.
  KeyEventResult engage(KeyEvent event) {
    final key = event.logicalKey;
    if (event is! KeyDownEvent || _held.containsKey(key)) {
      return _held[key] == _KeyHold.pan
          ? KeyEventResult.handled
          : KeyEventResult.ignored;
    }
    if (bindings.presses(EditorActionIds.canvasPanHold, event)) {
      _held[key] = _KeyHold.pan;
      CanvasPanHold.held.value = true;
      return KeyEventResult.handled;
    }
    if (_isEyedropperKey(key)) {
      if (strokeLive.value) {
        _waiting.add(key);
      } else {
        _holdEyedropper(key);
      }
    }
    return KeyEventResult.ignored;
  }

  /// The eyedropper takes hold over the tools the drawing view presses
  /// for — where a held pen button stands in for a tool too. A second Alt
  /// joins the hold already in force.
  void _holdEyedropper(LogicalKeyboardKey key) {
    final joining = _held.containsValue(_KeyHold.eyedropper);
    if (!joining && !canvasToolTakesDrawingPress(tool.value.tool)) {
      return;
    }
    _held[key] = _KeyHold.eyedropper;
    temporaryTool.hold(CanvasTool.eyedropper);
  }

  void _onStrokeLive() {
    if (strokeLive.value || _waiting.isEmpty) {
      return;
    }
    // ⚠️Not now: a stroke also ends inside a TEARDOWN (a panel unmounting
    // mid-stroke lets go of it), and switching the tool there would
    // rebuild a tree that is being taken down.
    scheduleMicrotask(_takeWaiting);
  }

  void _takeWaiting() {
    // A new stroke may have begun before the wait resolved.
    if (strokeLive.value) {
      return;
    }
    final waiting = [..._waiting];
    _waiting.clear();
    waiting.forEach(_holdEyedropper);
  }

  /// Every key let go, app-wide. Never consumes.
  bool _onKey(KeyEvent event) {
    if (event is KeyUpEvent) {
      final key = event.logicalKey;
      _waiting.remove(key);
      final hold = _held.remove(key);
      if (hold != null) {
        _end(hold);
      }
    }
    return false;
  }

  /// Ends [hold] — unless another key still holds it.
  void _end(_KeyHold hold) {
    if (_held.containsValue(hold)) {
      return;
    }
    switch (hold) {
      case _KeyHold.pan:
        CanvasPanHold.held.value = false;
      case _KeyHold.eyedropper:
        temporaryTool.release(keep: false);
    }
  }

  /// A shell that goes away holds nothing. The pan's flag is app-wide, so
  /// it lets go; a switched tool goes with the shell that owns it — putting
  /// it back would rebuild a tree that is being taken down.
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    strokeLive.removeListener(_onStrokeLive);
    _waiting.clear();
    _held.clear();
    CanvasPanHold.held.value = false;
  }
}

/// What a held key stands for while it is down.
enum _KeyHold { pan, eyedropper }

/// The eyedropper's key — Alt, as it always was (유저: 「스포이드는
/// 그대로」). ⛔Not a registry binding: Flutter's [SingleActivator] refuses
/// a modifier as its trigger, and Alt held ALONE is the gesture.
bool _isEyedropperKey(LogicalKeyboardKey key) =>
    key == LogicalKeyboardKey.altLeft || key == LogicalKeyboardKey.altRight;
