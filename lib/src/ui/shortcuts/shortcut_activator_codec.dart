import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// (De)serialization + display labels for [SingleActivator] — the shape
/// the shortcut override store persists ({key: logical key id, ctrl/shift/
/// alt/meta flags, false omitted}).
Map<String, Object?> singleActivatorToJson(SingleActivator activator) => {
  'key': activator.trigger.keyId,
  if (activator.control) 'ctrl': true,
  if (activator.shift) 'shift': true,
  if (activator.alt) 'alt': true,
  if (activator.meta) 'meta': true,
};

/// Null on malformed/unknown entries (a corrupt override entry must not
/// fail the editor — the action keeps its remaining activators).
SingleActivator? singleActivatorFromJson(Object? json) {
  if (json is! Map) {
    return null;
  }
  final keyId = json['key'];
  if (keyId is! int) {
    return null;
  }
  final trigger =
      LogicalKeyboardKey.findKeyByKeyId(keyId) ?? LogicalKeyboardKey(keyId);
  return SingleActivator(
    trigger,
    control: json['ctrl'] == true,
    shift: json['shift'] == true,
    alt: json['alt'] == true,
    meta: json['meta'] == true,
  );
}

/// Shift, Ctrl, Alt and ⌘ — a key that modifies another rather than being
/// one. ★One question, two readers: the settings dialog waits past these for
/// the real trigger, and the playback gate does not count one pressed alone
/// (유저 2026-09-13, I-19-zoom-key-playback: 「수식키는 혼자선 입력으로 치지
/// 않는다」).
bool isModifierKey(LogicalKeyboardKey key) => _modifierKeys.contains(key);

final Set<LogicalKeyboardKey> _modifierKeys = {
  LogicalKeyboardKey.controlLeft,
  LogicalKeyboardKey.controlRight,
  LogicalKeyboardKey.shiftLeft,
  LogicalKeyboardKey.shiftRight,
  LogicalKeyboardKey.altLeft,
  LogicalKeyboardKey.altRight,
  LogicalKeyboardKey.metaLeft,
  LogicalKeyboardKey.metaRight,
};

/// Whether [platform]'s COMMAND modifier is ⌘ rather than Ctrl: macOS, and
/// iOS — an iPad's hardware keyboard.
///
/// 🗣️유저 2026-09-13 (I-19): 「맥은 컨트롤키가 다르다 했던가? 쉬프트도? 그런
/// 멀티플랫폼부분도 신경써서 해줘」. Shift is the same key everywhere — only
/// its glyph differs. The key that differs is the one the registry writes as
/// `control`.
bool commandIsMeta([TargetPlatform? platform]) =>
    switch (platform ?? defaultTargetPlatform) {
      TargetPlatform.macOS || TargetPlatform.iOS => true,
      _ => false,
    };

/// A registry default as [platform] presses it.
///
/// ★The registry writes the command modifier ONCE, as `control`, and each
/// platform reads it in its own key: Ctrl on Windows, Linux and Android, ⌘ on
/// macOS and iOS — Ctrl+Z is ⌘Z on a Mac, the way every Mac app spells undo.
/// ⛔A key the user RECORDS is stored exactly as it was pressed and never
/// passes through here.
SingleActivator platformActivator(
  SingleActivator activator, [
  TargetPlatform? platform,
]) {
  if (!activator.control || !commandIsMeta(platform)) {
    return activator;
  }
  return SingleActivator(
    activator.trigger,
    shift: activator.shift,
    alt: activator.alt,
    meta: true,
    numLock: activator.numLock,
    includeRepeats: activator.includeRepeats,
  );
}

/// How a shortcut is written on [platform]: 'Ctrl+Shift+Z' on Windows and
/// the rest, '⇧⌘Z' on a Mac or an iPad — the modifier glyphs in the order
/// Apple's own menus print them (⌃⌥⇧⌘), with no separators. The settings
/// dialog's chips and every tooltip read this one spelling.
String singleActivatorLabel(
  SingleActivator activator, [
  TargetPlatform? platform,
]) {
  if (commandIsMeta(platform)) {
    return [
      if (activator.control) '⌃',
      if (activator.alt) '⌥',
      if (activator.shift) '⇧',
      if (activator.meta) '⌘',
      _triggerLabel(activator.trigger, apple: true),
    ].join();
  }
  final parts = <String>[
    if (activator.control) 'Ctrl',
    if (activator.alt) 'Alt',
    if (activator.shift) 'Shift',
    if (activator.meta)
      (platform ?? defaultTargetPlatform) == TargetPlatform.windows
          ? 'Win'
          : 'Meta',
    _triggerLabel(activator.trigger, apple: false),
  ];
  return parts.join('+');
}

String _triggerLabel(LogicalKeyboardKey trigger, {required bool apple}) {
  if (trigger == LogicalKeyboardKey.space) {
    return 'Space';
  }
  if (trigger == LogicalKeyboardKey.arrowLeft) {
    return '←';
  }
  if (trigger == LogicalKeyboardKey.arrowRight) {
    return '→';
  }
  if (trigger == LogicalKeyboardKey.arrowUp) {
    return '↑';
  }
  if (trigger == LogicalKeyboardKey.arrowDown) {
    return '↓';
  }
  if (trigger == LogicalKeyboardKey.comma) {
    return ',';
  }
  if (trigger == LogicalKeyboardKey.period) {
    return '.';
  }
  if (apple) {
    if (trigger == LogicalKeyboardKey.backspace) {
      return '⌫';
    }
    if (trigger == LogicalKeyboardKey.delete) {
      return '⌦';
    }
    if (trigger == LogicalKeyboardKey.enter) {
      return '↩';
    }
    if (trigger == LogicalKeyboardKey.escape) {
      return '⎋';
    }
  }
  final label = trigger.keyLabel;
  if (label.isEmpty) {
    return trigger.debugName ?? '?';
  }
  // A letter reads in capitals (Ctrl+Z); a NAMED key keeps its own case —
  // upper-casing every label printed ENTER and BACKSPACE.
  return label.length == 1 ? label.toUpperCase() : label;
}

/// Value equality for activators (SingleActivator has none of its own):
/// the settings dialog and the merge logic compare trigger + modifiers.
bool activatorsEqual(SingleActivator a, SingleActivator b) =>
    a.trigger == b.trigger &&
    a.control == b.control &&
    a.shift == b.shift &&
    a.alt == b.alt &&
    a.meta == b.meta;

/// A map key with value equality for conflict detection.
String activatorKey(SingleActivator a) =>
    '${a.trigger.keyId}:${a.control}:${a.shift}:${a.alt}:${a.meta}';
