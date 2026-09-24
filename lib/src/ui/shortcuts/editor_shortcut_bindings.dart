import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'editor_action_registry.dart';
import 'focused_text_field.dart';
import 'shortcut_activator_codec.dart';
import 'shortcut_settings_store.dart';
import 'touch_shortcuts.dart';

/// The LIVE shortcut bindings: registry defaults merged with the user's
/// persisted overrides. Notifies on every change so the app-level
/// Shortcuts map, the menu labels and the settings dialog all rebuild
/// from one source.
class EditorShortcutBindings extends ChangeNotifier {
  EditorShortcutBindings({
    this.store,
  }) : definitions = editorActionDefinitions;

  /// Null disables persistence (tests, and FLUTTER_TEST runs).
  final ShortcutSettingsStore? store;

  final List<EditorActionDefinition> definitions;

  final Map<String, List<SingleActivator>> _overrides = {};

  EditorActionDefinition? definitionFor(String actionId) {
    for (final definition in definitions) {
      if (definition.id == actionId) {
        return definition;
      }
    }
    return null;
  }

  /// The registry's defaults as THIS platform presses them: the command
  /// modifier the registry writes as Ctrl is ⌘ on a Mac or an iPad
  /// ([platformActivator]).
  List<SingleActivator> defaultActivatorsFor(String actionId) => [
    for (final activator
        in definitionFor(actionId)?.defaultActivators ??
            const <SingleActivator>[])
      platformActivator(activator),
  ];

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
      if (!definition.zoomsView) {
        continue;
      }
      for (final activator in activatorsFor(definition.id)) {
        if (activator.accepts(event, HardwareKeyboard.instance)) {
          return true;
        }
      }
    }
    return false;
  }

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
        map[activator] = EditorActionIntent(definition.id);
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

  /// Loads persisted overrides (unknown action ids and malformed entries
  /// are dropped — an app update or corrupt file never breaks bindings).
  Future<void> restore() async {
    final payload = await store?.load();
    final overridesJson = payload?['overrides'];
    if (overridesJson is! Map) {
      return;
    }
    _overrides.clear();
    for (final entry in overridesJson.entries) {
      final actionId = entry.key;
      if (actionId is! String || definitionFor(actionId) == null) {
        continue;
      }
      final listJson = entry.value;
      if (listJson is! List) {
        continue;
      }
      _overrides[actionId] = List.unmodifiable([
        for (final activatorJson in listJson)
          ?singleActivatorFromJson(activatorJson),
      ]);
    }
    _touchOverrides.clear();
    final touchJson = payload?['touch'];
    if (touchJson is Map) {
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
    notifyListeners();
  }

  Future<void> _pendingPersist = Future<void>.value();

  /// Resolves when every override write issued so far has hit disk —
  /// awaited by tests and available for a shutdown flush. Writes chain,
  /// so ordering (last writer wins) is preserved.
  Future<void> get pendingPersist => _pendingPersist;

  void _persist() {
    final store = this.store;
    if (store == null) {
      return;
    }
    final payload = {
      'overrides': {
        for (final entry in _overrides.entries)
          entry.key: [
            for (final activator in entry.value)
              singleActivatorToJson(activator),
          ],
      },
      'touch': {
        for (final entry in _touchOverrides.entries)
          entry.key: entry.value?.name,
      },
    };
    _pendingPersist = _pendingPersist.then((_) => store.save(payload));
  }
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
    if (_fieldKeeps(event)) {
      return KeyEventResult.ignored;
    }
    final held = onHoldKey?.call(event) ?? KeyEventResult.ignored;
    if (held == KeyEventResult.handled) {
      return held;
    }
    return super.handleKeypress(context, event);
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
