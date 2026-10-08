import 'package:flutter/services.dart';

/// Where a key went, for the input inspector (F-241) — the lines the
/// shortcut table and the playback gate write about a key they answered.
///
/// A leaf: it imports nothing of the app, so the table and the gate can
/// write here without importing the inspector, whose card imports widgets
/// that import the table (an import loop). The inspector plugs [sink] in
/// while it is shown; with it hidden the lines go nowhere.
abstract final class KeyTrace {
  /// Where the lines go — null while the inspector is hidden.
  static void Function(String line)? sink;

  /// [event]'s key and its time — what pairs a `key`, `bind` and `eat` line
  /// about one press, whatever order they are written in.
  static String stamp(KeyEvent event) =>
      '@${event.timeStamp.inMilliseconds} '
      '${event.logicalKey.debugName ?? event.logicalKey.keyLabel}'
      '${event is KeyRepeatEvent ? ' (repeat)' : ''}';

  /// The shortcut table's [answer] to [event]: the action it ran, no
  /// binding, or a focused field keeping it.
  static void answered(KeyEvent event, String answer) =>
      sink?.call('bind ${stamp(event)} → $answer');

  /// [event] stopped playback and does nothing else.
  static void spentOnAStop(KeyEvent event) =>
      sink?.call('eat ${stamp(event)} → stopped playback');

  /// [verb] — undo, redo — was asked for and REFUSED because a contact is
  /// down (F-173). Whatever door asked: a key, a button, a finger tap. The
  /// inspector's `census` line says which contact (F-232).
  static void refusedUnderAContact(String verb) =>
      sink?.call('gate $verb refused → a contact is down');
}
