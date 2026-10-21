import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../brush/brush_tool_state.dart';
import '../brush/temporary_tool.dart';
import '../canvas/canvas_line_hold.dart';
import '../canvas/canvas_view_hold.dart';
import 'editor_action_registry.dart';
import 'editor_shortcut_bindings.dart';
import 'shortcut_activator_codec.dart' show isModifierKey;

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
/// through [TemporaryTool], the pan and the turn through [CanvasViewHold].
/// The line from the last stroke (I-119) is held the same way, through
/// [CanvasLineHold].
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
    required ValueListenable<bool> strokeLive,
  }) : _strokeLive = strokeLive {
    HardwareKeyboard.instance.addHandler(_onKey);
    CanvasViewHold.reask = _reaskTheView;
    strokeLive.addListener(_onStrokeLive);
  }

  final EditorShortcutBindings bindings;
  final ValueListenable<BrushToolState> tool;
  final TemporaryTool temporaryTool;

  /// True while a stroke is being drawn. A tool switch WAITS for it to end
  /// — the pen's own law: a barrel button that rises mid-stroke never
  /// hijacks the live line. The pan needs no wait: a press already down
  /// keeps its route, so the pan only ever takes the NEXT press.
  ValueListenable<bool> get strokeLive => _strokeLive;
  ValueListenable<bool> _strokeLive;

  /// Hears [next] instead — the stroke of the project that came on screen.
  ///
  /// 🚨The holds are the WINDOW's and outlive a project tab switch (I-7):
  /// a key held across one must still let go of what it took, so the
  /// shell points this at the new project rather than making another.
  set strokeLive(ValueListenable<bool> next) {
    if (identical(next, _strokeLive)) {
      return;
    }
    _strokeLive.removeListener(_onStrokeLive);
    _strokeLive = next;
    next.addListener(_onStrokeLive);
    _onStrokeLive();
  }

  final Map<LogicalKeyboardKey, _KeyHold> _held = {};

  /// The presses holding the view, by key, the latest last — kept to be
  /// asked again as the modifiers change under them. 🗣️I-88 (유저
  /// 2026-10-09): 「스페이스바+컨트롤상태에선 회전으로 작동하도록」 — a STATE of
  /// the keys, not an order: Space then the turn's modifier turns, and that
  /// modifier let go pans again. ↩️I-88-Q1 moved the turn to Shift+Space;
  /// the law did not move with it.
  final Map<LogicalKeyboardKey, KeyEvent> _viewPresses = {};

  /// Eyedropper keys that came down mid-stroke: held, and in force the
  /// moment the stroke ends.
  final Set<LogicalKeyboardKey> _waiting = {};

  /// A key event on the shortcut road. HANDLED when it holds the view or
  /// the line — the space bar then does nothing else, its repeats
  /// included; the eyedropper's Alt passes on, because it still modifies
  /// whatever it is held with.
  KeyEventResult engage(KeyEvent event) {
    final key = event.logicalKey;
    if (event is! KeyDownEvent || _held.containsKey(key)) {
      return switch (_held[key]) {
        _KeyHold.view || _KeyHold.line => KeyEventResult.handled,
        _ => KeyEventResult.ignored,
      };
    }
    final view = _viewHoldOf(event);
    if (view != null) {
      _held[key] = _KeyHold.view;
      _viewPresses[key] = event;
      CanvasViewHold.held.value = view;
      return KeyEventResult.handled;
    }
    if (bindings.presses(EditorActionIds.canvasLineHold, event)) {
      _held[key] = _KeyHold.line;
      CanvasLineHold.held.value = true;
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

  /// What [press] holds the view for, with the modifiers as they stand —
  /// or null.
  ViewHold? _viewHoldOf(KeyEvent press) {
    if (bindings.presses(EditorActionIds.canvasRotateHold, press)) {
      return ViewHold.turn;
    }
    if (bindings.presses(EditorActionIds.canvasPanHold, press)) {
      return ViewHold.pan;
    }
    return null;
  }

  /// The eyedropper takes hold whatever tool is in hand (F-299) — but for
  /// the tools whose own drag reads Alt ([canvasToolReadsAlt]), which keep
  /// it. A second Alt joins the hold already in force.
  void _holdEyedropper(LogicalKeyboardKey key) {
    final joining = _held.containsValue(_KeyHold.eyedropper);
    if (!joining && canvasToolReadsAlt(tool.value.tool)) {
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

  /// Every key let go, app-wide — and every modifier that goes down or up
  /// under a held view key, which asks that key's press again. Never
  /// consumes.
  bool _onKey(KeyEvent event) {
    if (event is KeyUpEvent) {
      final key = event.logicalKey;
      _waiting.remove(key);
      _viewPresses.remove(key);
      final hold = _held.remove(key);
      if (hold != null) {
        _end(hold);
      }
    }
    if (isModifierKey(event.logicalKey)) {
      _reaskTheView();
    }
    return false;
  }

  /// The held view press asked again, with the modifiers as they are held
  /// now: when one goes down or up, and when a press reads the hold
  /// ([CanvasViewHold.atThePress]). A modifier that turns the press into
  /// neither keeps the hold as it is: Alt under Space is not a reason to
  /// let the view go.
  void _reaskTheView() {
    if (_viewPresses.isEmpty) {
      return;
    }
    final view = _viewHoldOf(_viewPresses.values.last);
    if (view != null) {
      CanvasViewHold.held.value = view;
    }
  }

  /// Ends [hold] — unless another key still holds it.
  void _end(_KeyHold hold) {
    if (_held.containsValue(hold)) {
      return;
    }
    switch (hold) {
      case _KeyHold.view:
        CanvasViewHold.held.value = null;
      case _KeyHold.line:
        CanvasLineHold.held.value = false;
      case _KeyHold.eyedropper:
        temporaryTool.release(keep: false);
    }
  }

  /// Every hold ends — the window lost the OS's focus, and a key let go
  /// while another app has it is never heard here ([_onKey] hears every
  /// release this window gets, and that one it does not get).
  void letGoOfEverything() {
    _waiting.clear();
    _viewPresses.clear();
    final holds = {..._held.values};
    _held.clear();
    holds.forEach(_end);
  }

  /// A shell that goes away holds nothing. The view's hold is app-wide, so
  /// it lets go; a switched tool goes with the shell that owns it — putting
  /// it back would rebuild a tree that is being taken down.
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    if (CanvasViewHold.reask == _reaskTheView) {
      CanvasViewHold.reask = null;
    }
    _strokeLive.removeListener(_onStrokeLive);
    _waiting.clear();
    _viewPresses.clear();
    _held.clear();
    CanvasViewHold.held.value = null;
    CanvasLineHold.held.value = false;
  }
}

/// What a held key stands for while it is down — the view (a pan or a
/// turn, [CanvasViewHold]), the line from the last stroke
/// ([CanvasLineHold]) or the eyedropper.
enum _KeyHold { view, line, eyedropper }

/// The eyedropper's key — Alt, as it always was (유저: 「스포이드는
/// 그대로」). ⛔Not a registry binding: Flutter's [SingleActivator] refuses
/// a modifier as its trigger, and Alt held ALONE is the gesture.
bool _isEyedropperKey(LogicalKeyboardKey key) =>
    key == LogicalKeyboardKey.altLeft || key == LogicalKeyboardKey.altRight;
