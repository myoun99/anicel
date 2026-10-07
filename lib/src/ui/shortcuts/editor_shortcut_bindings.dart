import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../debug/key_trace.dart';
import 'editor_action_registry.dart';
import 'focused_text_field.dart';
import 'sheet_arrow.dart';
import 'shortcut_activator_codec.dart';
import 'shortcut_presets.dart';
import 'shortcut_settings_store.dart';
import 'touch_shortcuts.dart';

/// The LIVE shortcut bindings: the keys of the preset in use merged with the
/// user's persisted overrides. Notifies on every change so the app-level
/// Shortcuts map, the menu labels and the settings dialog all rebuild
/// from one source.
class EditorShortcutBindings extends ChangeNotifier {
  EditorShortcutBindings({
    this.store,
  }) : definitions = editorActionDefinitions;

  /// Null disables persistence (tests, and FLUTTER_TEST runs).
  final ShortcutSettingsStore? store;

  final List<EditorActionDefinition> definitions;

  /// The layout the keys start from (I-63).
  ///
  /// ⚠️It starts as [ShortcutPreset.anicel] — the keys this app had before
  /// there were presets, so nobody's keys move by themselves. Which preset a
  /// NEW install opens with is asked on the board (I-63-Q5); the first words
  /// (유저 2026-10-03: 「기본값은 일반으로」) named a preset that became two.
  ShortcutPreset get preset => _preset;
  ShortcutPreset _preset = ShortcutPreset.anicel;

  /// What the user recorded, PER PRESET: a key recorded while one layout is
  /// in use is a change to that layout, and stays with it.
  ///
  /// ⚠️Not said by the user — asked on the board (I-63-Q6). One set over
  /// every preset would carry a repair made for one program's layout (a key
  /// moved off a clash that only that layout has) into the others.
  final Map<ShortcutPreset, Map<String, List<SingleActivator>>>
  _overridesByPreset = {
    for (final preset in ShortcutPreset.values) preset: {},
  };

  Map<String, List<SingleActivator>> get _overrides =>
      _overridesByPreset[_preset]!;

  /// Starts from [preset]'s keys, under whatever was recorded while it was
  /// last in use. Persists and notifies.
  void setPreset(ShortcutPreset preset) {
    if (preset == _preset) {
      return;
    }
    _preset = preset;
    _persist();
    notifyListeners();
  }

  EditorActionDefinition? definitionFor(String actionId) {
    for (final definition in definitions) {
      if (definition.id == actionId) {
        return definition;
      }
    }
    return null;
  }

  /// The keys the preset in use ships [actionId] with ([presetActivators]),
  /// as THIS platform presses them: the command modifier written as Ctrl is
  /// ⌘ on a Mac or an iPad ([platformActivator]).
  List<SingleActivator> defaultActivatorsFor(String actionId) {
    final definition = definitionFor(actionId);
    return [
      if (definition != null)
        for (final activator in presetActivators(_preset, definition))
          platformActivator(activator),
    ];
  }

  /// The action's LIVE activators (override or defaults). An override may
  /// be an empty list = the action is deliberately unbound.
  List<SingleActivator> activatorsFor(String actionId) {
    return _overrides[actionId] ?? defaultActivatorsFor(actionId);
  }

  /// The first live activator — what menu items show as their shortcut
  /// label; null while unbound.
  SingleActivator? primaryActivatorFor(String actionId) {
    final activators = activatorsFor(actionId);
    return activators.isEmpty ? null : activators.first;
  }

  /// Whether [event] presses a view-ZOOM action through its live keys —
  /// the question the playback gate asks for R6q3.
  bool zoomsViewOn(KeyEvent event) {
    for (final definition in definitions) {
      if (definition.zoomsView && presses(definition.id, event)) {
        return true;
      }
    }
    return false;
  }

  /// Whether [event] presses [actionId] through one of its live keys, in
  /// any of the forms [pressableForms] names.
  ///
  /// ★THE ONE ANSWER to 「does this key press that action」: the app-level
  /// [shortcuts] map is built from the same forms, and the held keys and the
  /// playback gate ask here — so a key a layout types differently presses
  /// all three or none of them.
  bool presses(String actionId, KeyEvent event) {
    for (final activator in activatorsFor(actionId)) {
      for (final form in _formsOf(actionId, activator)) {
        if (form.accepts(event, HardwareKeyboard.instance)) {
          return true;
        }
      }
    }
    return false;
  }

  /// How the sheet in front of the user turns the arrows (F-241) — the
  /// shell hands its flip HUD in. Null reads every arrow as the timeline
  /// does.
  SheetArrowTurn? sheet;

  /// The sheet's direction keys as the bindings stand: every key bound bare
  /// to a move that walks a way — not its one-frame step — in the order the
  /// move lists them (F-261, [SheetKeys]).
  SheetKeys get sheetKeys {
    final keysByArrow = {
      for (final arrow in SheetArrow.values) arrow: <LogicalKeyboardKey>[],
    };
    for (final definition in definitions) {
      if (definition.sheetMove case (:final arrow, fine: false)) {
        keysByArrow[arrow]!.addAll([
          for (final activator in activatorsFor(definition.id))
            if (!activator.shift &&
                !activator.control &&
                !activator.alt &&
                !activator.meta)
              activator.trigger,
        ]);
      }
    }
    return SheetKeys(keysByArrow);
  }

  /// [activator]'s pressable forms for [actionId]: a DIRECTION key of a move
  /// on the sheet ([EditorActionDefinition.sheetMove]) is matched turned.
  Iterable<ShortcutActivator> _formsOf(
    String actionId,
    SingleActivator activator,
  ) {
    final place = _turnOf(actionId, activator);
    return place == null
        ? pressableForms(activator)
        : [SheetTurnedActivator(activator, () => sheet, place.keys)];
  }

  /// Where [activator] of [actionId] turns: its key's place among the
  /// direction keys, or null when it does not turn.
  ({SheetKeys keys, SheetArrow arrow, int set})? _turnOf(
    String actionId,
    SingleActivator activator,
  ) {
    if (definitionFor(actionId)?.sheetMove == null) {
      return null;
    }
    final keys = sheetKeys;
    final place = keys.placeOf(activator.trigger);
    return place == null
        ? null
        : (keys: keys, arrow: place.arrow, set: place.set);
  }

  /// [activator] as it reads on the sheet in front of the user — a turned
  /// key shows the key that presses it HERE (유저 F-241: 「단축키 바뀐
  /// 상황에서 그에맞게 텍스트 내용도 변경」).
  SingleActivator shownActivatorFor(
    String actionId,
    SingleActivator activator,
  ) {
    final turn = sheet;
    final place = _turnOf(actionId, activator);
    if (turn == null || place == null) {
      return activator;
    }
    final shown = turn.sheetArrowFor(place.arrow);
    return _withTrigger(activator, place.keys.keyAt(shown, place.set));
  }

  /// [pressed], recorded for [actionId] on the sheet in front of the user,
  /// as it is kept: a turned key is kept as the timeline reads it, so it
  /// turns again on the other sheet.
  SingleActivator keptActivatorFor(
    String actionId,
    SingleActivator pressed,
  ) {
    final turn = sheet;
    final place = _turnOf(actionId, pressed);
    if (turn == null || place == null) {
      return pressed;
    }
    final kept = turn.timelineArrowFor(place.arrow);
    return _withTrigger(pressed, place.keys.keyAt(kept, place.set));
  }

  static SingleActivator _withTrigger(
    SingleActivator activator,
    LogicalKeyboardKey trigger,
  ) => SingleActivator(
    trigger,
    control: activator.control,
    shift: activator.shift,
    alt: activator.alt,
    meta: activator.meta,
  );

  bool isOverridden(String actionId) => _overrides.containsKey(actionId);

  bool isTouchOverridden(String actionId) =>
      _touchOverrides.containsKey(actionId);

  /// The app-level Shortcuts map: every live activator → the action's
  /// intent. On a conflict (one activator bound to several actions) the
  /// LAST registry entry wins here; [conflictedActionIds] surfaces the
  /// clash to the settings dialog.
  Map<ShortcutActivator, Intent> get shortcuts {
    final map = <ShortcutActivator, Intent>{};
    for (final definition in definitions) {
      // A HELD action is taken on the way past (EditorKeyHolds), never
      // dispatched as an intent.
      if (definition.hold) {
        continue;
      }
      for (final activator in activatorsFor(definition.id)) {
        for (final form in _formsOf(definition.id, activator)) {
          map[form] = EditorActionIntent(definition.id);
        }
      }
    }
    return map;
  }

  /// Action ids whose activators collide with another action's (the
  /// settings dialog highlights them).
  Set<String> get conflictedActionIds => _conflictedIds(
    (actionId) => activatorsFor(actionId).map(activatorKey),
  );

  /// Every action id that shares one of its [keysOf] keys with another
  /// action — the key→actions inversion both conflict queries are.
  Set<String> _conflictedIds<K>(Iterable<K> Function(String actionId) keysOf) {
    final byKey = <K, List<String>>{};
    for (final definition in definitions) {
      for (final key in keysOf(definition.id)) {
        byKey.putIfAbsent(key, () => []).add(definition.id);
      }
    }
    return {
      for (final ids in byKey.values)
        if (ids.length > 1) ...ids,
    };
  }

  /// Replaces [actionId]'s activators; a value equal to the defaults
  /// clears the override. Persists and notifies.
  void setActivators(String actionId, List<SingleActivator> activators) {
    final defaults = defaultActivatorsFor(actionId);
    final matchesDefaults =
        activators.length == defaults.length &&
        [
          for (var i = 0; i < activators.length; i += 1)
            activatorsEqual(activators[i], defaults[i]),
        ].every((equal) => equal);
    if (matchesDefaults) {
      _overrides.remove(actionId);
    } else {
      _overrides[actionId] = List.unmodifiable(activators);
    }
    _persist();
    notifyListeners();
  }

  void resetAction(String actionId) {
    final removedKeys = _overrides.remove(actionId) != null;
    final removedTouch = _touchOverrides.remove(actionId) != null;
    if (removedKeys || removedTouch) {
      _persist();
      notifyListeners();
    }
  }

  /// Back to the keys the preset in use ships with, and the registry's touch
  /// gestures. What was recorded under another preset stays with it.
  void resetAll() {
    if (_overrides.isEmpty && _touchOverrides.isEmpty) {
      return;
    }
    _overrides.clear();
    _touchOverrides.clear();
    _persist();
    notifyListeners();
  }

  // --- Touch gestures (R11-⑨) ----------------------------------------------
  //
  // Every registry action may bind ONE multi-finger gesture, mirroring the
  // key overrides: registry default + persisted user override, an explicit
  // null override = deliberately unbound.

  final Map<String, TouchGesture?> _touchOverrides = {};

  /// The action's LIVE touch gesture (override or registry default).
  TouchGesture? touchGestureFor(String actionId) {
    if (_touchOverrides.containsKey(actionId)) {
      return _touchOverrides[actionId];
    }
    return TouchGesture.fromName(definitionFor(actionId)?.defaultTouchGesture);
  }

  /// The dispatch lookup for a fired gesture; null while unbound. On a
  /// conflict the LAST registry entry wins (keyboard parity);
  /// [touchConflictedActionIds] surfaces the clash to the dialog.
  String? actionIdForTouchGesture(TouchGesture gesture) {
    String? actionId;
    for (final definition in definitions) {
      if (touchGestureFor(definition.id) == gesture) {
        actionId = definition.id;
      }
    }
    return actionId;
  }

  /// Action ids whose touch gesture collides with another action's.
  Set<String> get touchConflictedActionIds => _conflictedIds((actionId) {
    final gesture = touchGestureFor(actionId);
    return gesture == null ? const <TouchGesture>[] : [gesture];
  });

  /// Binds (or with null, unbinds) [actionId]'s touch gesture; a value
  /// equal to the registry default clears the override.
  void setTouchGesture(String actionId, TouchGesture? gesture) {
    final defaultGesture = TouchGesture.fromName(
      definitionFor(actionId)?.defaultTouchGesture,
    );
    if (gesture == defaultGesture) {
      _touchOverrides.remove(actionId);
    } else {
      _touchOverrides[actionId] = gesture;
    }
    _persist();
    notifyListeners();
  }

  /// Loads the persisted preset and overrides (unknown action ids and
  /// malformed entries are dropped, and a preset no build knows reads as the
  /// registry's own — an app update or corrupt file never breaks bindings).
  Future<void> restore() async {
    final payload = await store?.load();
    final byPreset = payload?['overrides'];
    if (byPreset is! Map) {
      return;
    }
    // ⚠️NOT the preset an install with no file opens on ([preset]'s first
    // value) — the two only agree today. A file that names no preset this
    // build knows was written over the registry's keys: before the presets,
    // or by a build whose preset this one lacks.
    _preset = ShortcutPreset.named(payload?['preset']) ?? ShortcutPreset.anicel;
    for (final MapEntry(key: preset, value: overrides)
        in _overridesByPreset.entries) {
      overrides
        ..clear()
        ..addAll(_keyOverridesFrom(byPreset[preset.name]));
    }
    _restoreTouch(payload?['touch']);
    notifyListeners();
  }

  /// One preset's recorded keys out of its saved [json].
  Map<String, List<SingleActivator>> _keyOverridesFrom(Object? json) {
    if (json is! Map) {
      return const {};
    }
    return {
      for (final MapEntry(key: actionId, value: listJson) in json.entries)
        if (actionId is String &&
            definitionFor(actionId) != null &&
            listJson is List)
          actionId: List.unmodifiable([
            for (final activatorJson in listJson)
              ?singleActivatorFromJson(activatorJson),
          ]),
    };
  }

  void _restoreTouch(Object? touchJson) {
    _touchOverrides.clear();
    if (touchJson is! Map) {
      return;
    }
    for (final entry in touchJson.entries) {
      final actionId = entry.key;
      if (actionId is! String || definitionFor(actionId) == null) {
        continue;
      }
      final name = entry.value;
      if (name == null) {
        _touchOverrides[actionId] = null;
      } else if (name is String) {
        final gesture = TouchGesture.fromName(name);
        if (gesture != null) {
          _touchOverrides[actionId] = gesture;
        }
      }
    }
  }

  Future<void> _pendingPersist = Future<void>.value();

  /// Resolves once the file holds the last overrides written — awaited by
  /// tests and available for a shutdown flush. The writes keep their order
  /// ([saveVersionedSettings]), so the last one written is the one kept.
  Future<void> get pendingPersist => _pendingPersist;

  void _persist() {
    final store = this.store;
    if (store == null) {
      return;
    }
    final payload = {
      'preset': _preset.name,
      'overrides': {
        for (final MapEntry(key: preset, value: overrides)
            in _overridesByPreset.entries)
          preset.name: {
            for (final entry in overrides.entries)
              entry.key: [
                for (final activator in entry.value)
                  singleActivatorToJson(activator),
              ],
          },
      },
      'touch': {
        for (final entry in _touchOverrides.entries)
          entry.key: entry.value?.name,
      },
    };
    _pendingPersist = store.save(payload);
  }
}

/// Every form in which [activator] can be pressed: the key itself, and —
/// where a layout puts the character that key names on Shift — the
/// combination that TYPES it.
///
/// 🚨★★A KEY IS THE CHARACTER IT TYPES (a-key-is-the-character-it-types).
/// 🗣️유저 2026-09-13 (I-19): 「일본어 키보드나 한국어 상태등 키보드가 영어가
/// 아닐때도 대응하도록」. A binding like `=` names a character, but a
/// [SingleActivator] matches a logical KEY, and Windows names a printable
/// key by what it types UNSHIFTED. On a JIS keyboard `=` is Shift+-: the
/// event is `minus` with Shift held, typing '=', and `SingleActivator(equal)`
/// never sees it — the Solo key had no way in at all. ↩️Solo ships on T
/// since F-261; the law stands for every binding that names a character,
/// the ones a user records included.
///
/// ⛔ONLY UNDER SHIFT, and that is not a preference. Shift is the one way a
/// character arrives under ANOTHER key's name (a key is named by its
/// unshifted character), so it is exactly the case a key binding misses. A
/// plain [CharacterActivator] would also answer keys that type the same
/// character without Shift — the numpad's `.` would step a frame the way
/// `.` does, which nobody asked for.
///
/// ⚠️Only a binding with no Shift of its own names a character; Shift+.
/// names the `>` KEY. And only one printed character that is not a letter:
/// a letter key reports its own letter on every layout already.
/// ⚠️Where the platform types no character — Windows under Ctrl — the typed
/// form never matches, and the key alone answers as it always did.
/// ⚠️A key bound explicitly beats the typed form of another binding: the
/// Shortcuts manager tries keyed activators before unkeyed ones.
Iterable<ShortcutActivator> pressableForms(SingleActivator activator) sync* {
  yield activator;
  final label = activator.trigger.keyLabel;
  final namesACharacter =
      !activator.shift &&
      label.runes.length == 1 &&
      label.trim().isNotEmpty &&
      label.toLowerCase() == label.toUpperCase();
  if (namesACharacter) {
    yield ShiftTypedActivator(
      CharacterActivator(
        label,
        control: activator.control,
        alt: activator.alt,
        meta: activator.meta,
      ),
    );
  }
}

/// [timeline] — a direction key written as the timeline reads it — pressed
/// on whichever sheet is up: the key that arrives is turned by [turn] to its
/// set's key for the way it reads before it is matched (F-241,
/// `SheetArrowTurn`; F-261, [SheetKeys]). Null turns nothing.
class SheetTurnedActivator extends ShortcutActivator {
  const SheetTurnedActivator(this.timeline, this.turn, this.keys);

  final SingleActivator timeline;
  final SheetArrowTurn? Function() turn;
  final SheetKeys keys;

  /// The keys of [timeline]'s set — the only ones that can turn into it.
  @override
  Iterable<LogicalKeyboardKey> get triggers =>
      keys.setOf(keys.placeOf(timeline.trigger)!.set);

  @override
  bool accepts(KeyEvent event, HardwareKeyboard state) {
    final pressed = keys.placeOf(event.logicalKey);
    if (pressed == null) {
      return false;
    }
    final read = turn()?.timelineArrowFor(pressed.arrow) ?? pressed.arrow;
    return timeline.accepts(
      _withKey(event, keys.keyAt(read, pressed.set)),
      state,
    );
  }

  static KeyEvent _withKey(KeyEvent event, LogicalKeyboardKey key) =>
      switch (event) {
        KeyDownEvent() => KeyDownEvent(
          physicalKey: event.physicalKey,
          logicalKey: key,
          character: event.character,
          timeStamp: event.timeStamp,
          synthesized: event.synthesized,
          deviceType: event.deviceType,
        ),
        KeyRepeatEvent() => KeyRepeatEvent(
          physicalKey: event.physicalKey,
          logicalKey: key,
          character: event.character,
          timeStamp: event.timeStamp,
          deviceType: event.deviceType,
        ),
        _ => KeyUpEvent(
          physicalKey: event.physicalKey,
          logicalKey: key,
          timeStamp: event.timeStamp,
          synthesized: event.synthesized,
          deviceType: event.deviceType,
        ),
      };

  @override
  String debugDescribeKeys() =>
      'sheet-turned ${timeline.debugDescribeKeys()}';
}

/// [typed]'s character reached with Shift held — the form [pressableForms]
/// adds for a layout that puts that character on Shift.
class ShiftTypedActivator extends ShortcutActivator {
  const ShiftTypedActivator(this.typed);

  final CharacterActivator typed;

  @override
  bool accepts(KeyEvent event, HardwareKeyboard state) =>
      state.isShiftPressed && typed.accepts(event, state);

  @override
  String debugDescribeKeys() => 'Shift-typed ${typed.debugDescribeKeys()}';
}

/// The app-level ShortcutManager, and what it leaves to a text field.
///
/// A focused field keeps two kinds of key: every BARE key (typing 'b' into a
/// rename dialog never switches tools) and every key the field's own text
/// shortcuts bind (Ctrl+C, ⌘Z …). Any other modified key still resolves
/// here while a field has focus — Ctrl+S saves from inside a rename box.
class EditorShortcutManager extends ShortcutManager {
  EditorShortcutManager({super.shortcuts, this.onHoldKey});

  /// The held keys (I-15, `EditorKeyHolds.engage`) — taken on THIS road,
  /// after the text-field guard, so a focused field keeps its space bar the
  /// same way it keeps its letters.
  final KeyEventResult Function(KeyEvent event)? onHoldKey;

  @override
  KeyEventResult handleKeypress(BuildContext context, KeyEvent event) {
    // F-241: every answer goes to the input inspector's `bind` line.
    if (_fieldKeeps(event)) {
      KeyTrace.answered(event, 'kept by the focused text field');
      return KeyEventResult.ignored;
    }
    final held = onHoldKey?.call(event) ?? KeyEventResult.ignored;
    if (held == KeyEventResult.handled) {
      KeyTrace.answered(event, 'held');
      return held;
    }
    final result = super.handleKeypress(context, event);
    if (event is! KeyUpEvent) {
      final intent = shortcuts.entries
          .where((entry) => entry.key.accepts(event, HardwareKeyboard.instance))
          .firstOrNull
          ?.value;
      KeyTrace.answered(
        event,
        '${intent is EditorActionIntent ? intent.actionId : 'no binding'}'
        ' (${result.name})',
      );
    }
    return result;
  }

  /// Whether the text field that has focus keeps [event] for itself.
  ///
  /// 🚨I-19 (2026-09-13). Modified keys used to pass straight through, on
  /// the premise that 「the ones the field itself owns (Ctrl+Z) are consumed
  /// below us」. They never were: the platform's text shortcuts are mounted
  /// by the APP, above this manager, and a key climbs from the field — so it
  /// reaches this manager first. 🧪Measured: with Ctrl+C bound here, Ctrl+C
  /// in a focused TextField fired the binding, and so did Ctrl+V, Ctrl+X,
  /// Ctrl+Z and a Mac's ⌘C. Binding Ctrl+C to the timeline's copy would
  /// have made a rename box copy a FRAME.
  ///
  /// ★So the field's own path is asked: a key that another shortcut table
  /// between the field and the app binds belongs to that table — the text
  /// system's, in each platform's own modifier — and stands down here. The
  /// premise is made true rather than assumed.
  bool _fieldKeeps(KeyEvent event) {
    final focusContext = focusedTextField();
    if (focusContext == null) {
      return false;
    }
    final keyboard = HardwareKeyboard.instance;
    if (!keyboard.isControlPressed && !keyboard.isMetaPressed) {
      return true;
    }
    var bound = false;
    focusContext.visitAncestorElements((element) {
      final widget = element.widget;
      bound =
          widget is Shortcuts &&
          !identical(widget.manager, this) &&
          widget.shortcuts.keys.any(
            (activator) => activator.accepts(event, keyboard),
          );
      return !bound;
    });
    return bound;
  }
}
