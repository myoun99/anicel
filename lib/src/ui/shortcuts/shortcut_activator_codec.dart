import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/input/modifier_keys.dart';

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
  final activator = SingleActivator(
    trigger,
    control: json['ctrl'] == true,
    shift: json['shift'] == true,
    alt: json['alt'] == true,
    meta: json['meta'] == true,
  );
  // Modifiers alone with none of them is no key at all.
  return isModifiersAlone(activator) && !_holdsAModifier(activator)
      ? null
      : activator;
}

/// The trigger of a key that is its modifiers ALONE — Alt held by itself,
/// Ctrl+Alt with no other key — the modifiers being the activator's own
/// flags ([isModifiersAlone]).
///
/// 🗣️F-603 (유저 2026-11-16): 「tvp의 캔버스 누르는동안 이동 단축키는 alt
/// … 단축키등록시 alt나 컨트롤키를 눌러도 단축키등록안됨. 다 가능하게」.
/// Every key goes about as a [SingleActivator] — the registry, the presets,
/// the shortcut file, the clashes, the labels — and Flutter's refuses a
/// modifier as its trigger. So a key that is modifiers alone is one with no
/// other key: this trigger, which no keyboard sends (a plane Flutter's key
/// ids leave unused). It is pressed through the form its action reads it in
/// (`EditorShortcutBindings`), never as a [SingleActivator] matches.
/// ⛔Not one of the modifiers as the trigger, past the assert: Ctrl+Alt
/// would be two keys then, one for each order they went down in — and held
/// keys are a STATE, not an order (I-88).
const LogicalKeyboardKey modifiersAlone = LogicalKeyboardKey(0x00a00000000);

/// The key that is [control], [shift], [alt] and [meta] — those held — alone
/// ([modifiersAlone]).
SingleActivator modifiersAloneActivator({
  bool control = false,
  bool shift = false,
  bool alt = false,
  bool meta = false,
}) => SingleActivator(
  modifiersAlone,
  control: control,
  shift: shift,
  alt: alt,
  meta: meta,
);

/// Whether [activator] is a key that is its modifiers alone
/// ([modifiersAlone]).
bool isModifiersAlone(SingleActivator activator) =>
    activator.trigger == modifiersAlone;

bool _holdsAModifier(SingleActivator activator) =>
    activator.control || activator.shift || activator.alt || activator.meta;

/// The keys of [alone]'s modifiers, either side of each — the keys whose
/// going down presses it (`ModifiersDownActivator`).
List<LogicalKeyboardKey> modifierKeysOf(SingleActivator alone) => [
  if (alone.control) ...const [
    LogicalKeyboardKey.controlLeft,
    LogicalKeyboardKey.controlRight,
  ],
  if (alone.shift) ...const [
    LogicalKeyboardKey.shiftLeft,
    LogicalKeyboardKey.shiftRight,
  ],
  if (alone.alt) ...const [
    LogicalKeyboardKey.altLeft,
    LogicalKeyboardKey.altRight,
  ],
  if (alone.meta) ...const [
    LogicalKeyboardKey.metaLeft,
    LogicalKeyboardKey.metaRight,
  ],
];

/// Whether the modifier [key] is — on either side — held now, as
/// [ModifierKeys] says; false for a key that is none.
///
/// 🚨A MODIFIER'S OWN KEY-UP IS NOT ITS RELEASE (card
/// a-held-modifiers-repeat-is-heard-as-a-press): under a pen's or a
/// finger's move Windows' engine lets go of Shift and Ctrl with the key
/// still down, and drops the real release that comes after. So what a
/// modifier's key-up — or any event — asks is this.
bool modifierHeld(LogicalKeyboardKey key) {
  if (key == LogicalKeyboardKey.controlLeft ||
      key == LogicalKeyboardKey.controlRight) {
    return ModifierKeys.isControlPressed;
  }
  if (key == LogicalKeyboardKey.shiftLeft ||
      key == LogicalKeyboardKey.shiftRight) {
    return ModifierKeys.isShiftPressed;
  }
  if (key == LogicalKeyboardKey.altLeft ||
      key == LogicalKeyboardKey.altRight) {
    return ModifierKeys.isAltPressed;
  }
  if (key == LogicalKeyboardKey.metaLeft ||
      key == LogicalKeyboardKey.metaRight) {
    return ModifierKeys.isMetaPressed;
  }
  return false;
}

/// Shift, Ctrl, Alt and ⌘ — a key that modifies another rather than being
/// one. ★One question, two readers: the settings dialog waits past these for
/// the real trigger — and takes them alone once one is let go with nothing
/// else pressed (F-603) — and the playback gate does not count one pressed
/// alone (유저 2026-09-13, I-19-zoom-key-playback: 「수식키는 혼자선 입력으로
/// 치지 않는다」).
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

/// [activator] pressed under the other command key: its Ctrl is ⌘ and its
/// ⌘ Ctrl ([commandIsMeta]).
SingleActivator commandSwapped(SingleActivator activator) => SingleActivator(
  activator.trigger,
  control: activator.meta,
  shift: activator.shift,
  alt: activator.alt,
  meta: activator.control,
  numLock: activator.numLock,
  includeRepeats: activator.includeRepeats,
);

/// How a shortcut is written on [platform]: 'Ctrl+Shift+Z' on Windows and
/// the rest, '⇧⌘Z' on a Mac or an iPad — the modifier glyphs in the order
/// Apple's own menus print them (⌃⌥⇧⌘), with no separators. The settings
/// dialog's chips and every tooltip read this one spelling. A key that is
/// modifiers alone is its modifiers: 'Alt', '⌥' ([modifiersAlone]).
String singleActivatorLabel(
  SingleActivator activator, [
  TargetPlatform? platform,
]) {
  final alone = isModifiersAlone(activator);
  if (commandIsMeta(platform)) {
    return [
      if (activator.control) '⌃',
      if (activator.alt) '⌥',
      if (activator.shift) '⇧',
      if (activator.meta) '⌘',
      if (!alone) _triggerLabel(activator.trigger, apple: true),
    ].join();
  }
  final parts = <String>[
    if (activator.control) 'Ctrl',
    if (activator.alt) 'Alt',
    if (activator.shift) 'Shift',
    if (activator.meta)
      if ((platform ?? defaultTargetPlatform) == TargetPlatform.windows)
        'Win'
      else
        'Meta',
    if (!alone) _triggerLabel(activator.trigger, apple: false),
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
