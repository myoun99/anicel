import 'package:flutter_test/flutter_test.dart';

import '../helpers/dart_sources.dart';
import '../helpers/source_ledger.dart';

/// 🚨WHETHER A MODIFIER KEY IS HELD IS ASKED OF `ModifierKeys`
/// (`lib/src/services/input/modifier_keys.dart`).
///
/// 🗣️I-61 (유저 2026-10-16): 「마우스로는 작동하는거 확인했는데 왜 펜으로는
/// 작동안하는지? … 설마 법 통일 제대로 안되있는거같은데」. Ten places read
/// the keyboard's record straight — the stroke's 45° Shift, the shape's
/// ratio, the marquee's chord, the transform's Alt, the text box's Ctrl,
/// the slider's fine Shift, the text field's arrows, the shortcut
/// recorder, the inspector's held keys and the held view keys' binding —
/// and on Windows that record lets go of Shift and Ctrl under every pen
/// and finger move. A reader of the record is wrong under a pen and right
/// under a mouse, so this SCANS SOURCE: a behaviour test driven by a mouse
/// passes it.
///
/// What may still name the record: a key handler joining or leaving it, and
/// the lines in [_mirrors], which say what Flutter's own shortcut managers
/// and scroll views do — those read the record, so the mirror must.
void main() {
  test('nothing in lib reads the keyboard\'s record but ModifierKeys — and '
      'every mirror still reads it', () {
    expectSetMatchesLedger(
      [
        for (final file in dartFilesUnder('lib'))
          if (libPath(file) != _theOnePlace)
            for (final read in _recordReads(file.readAsStringSync()))
              (libPath(file), read),
      ],
      _mirrors.keys,
      unledgered:
          'ask `ModifierKeys` — on Windows the record lets go of Shift and '
          'Ctrl under a pen or a finger. A line that must say what '
          'Flutter\'s own managers do goes in the ledger, with why',
      paidOff: 'these no longer read the record — take them off the ledger',
    );
  });

  test('every mirror says why', () {
    expectEveryEntrySaysWhy(_mirrors);
  });

  test('the scan sees a planted read, and not a handler or a comment', () {
    const planted = '''
final keys = HardwareKeyboard.instance;
if (HardwareKeyboard.instance.isShiftPressed) {}
final pressed = ServicesBinding.instance.keyboard.logicalKeysPressed;
shift: WidgetsBinding.instance.keyboard.isShiftPressed ||
final keyboard = WidgetsBinding.instance.keyboard;
if (binding.keyboard.isControlPressed) {}
HardwareKeyboard.instance.addHandler(_onKey);
HardwareKeyboard.instance.removeHandler(_onKey);
for (final key in ModifierKeys.keyboard.logicalKeysPressed) {}
if (ModifierKeys.keyboard.isShiftPressed) {}
/// Reads [HardwareKeyboard.instance] the way it used to.
// ↩️It was HardwareKeyboard.instance.isShiftPressed.
''';
    expect(_recordReads(planted), [
      'final keys = HardwareKeyboard.instance;',
      'if (HardwareKeyboard.instance.isShiftPressed) {}',
      'final pressed = ServicesBinding.instance.keyboard.logicalKeysPressed;',
      'shift: WidgetsBinding.instance.keyboard.isShiftPressed ||',
      'final keyboard = WidgetsBinding.instance.keyboard;',
      'if (binding.keyboard.isControlPressed) {}',
    ]);
  });

  // 🚨Card a-held-modifiers-repeat-is-heard-as-a-press (관제 2026-11-15
  // 19:53). On Windows the engine lets go of Shift and Ctrl at a pen's or a
  // finger's move with the key still down, hands the held key's repeat on
  // as a new key-down and drops the release that comes after a move — so a
  // handler that reads a modifier's own key-down as "pressed" or its key-up
  // as "let go" is wrong under a pen and right under a mouse, as a reader
  // of the record was. The playback gate read them so till that day.
  test('every line of lib that names a modifier\'s own key says what it '
      'reads off that key\'s events', () {
    expectSetMatchesLedger(
      [
        for (final file in dartFilesUnder('lib'))
          if (!_whereTheyAreNamed.contains(libPath(file)))
            for (final line in _ownKeyNames(file.readAsStringSync()))
              (libPath(file), line),
      ],
      _ownKeyReaders.keys,
      unledgered:
          'a modifier\'s own key-down or key-up is not the key pressed or '
          'let go under a pen — ask `ModifierKeys` when the event comes. A '
          'line that reads neither off it goes in the ledger, with what it '
          'reads',
      paidOff: 'these no longer name a modifier\'s own key — take them off '
          'the ledger',
    );
  });

  test('every reader of a modifier\'s own key says why', () {
    expectEveryEntrySaysWhy(_ownKeyReaders);
  });

  test('the scan sees a planted name of a modifier\'s own key, and not a '
      'comment', () {
    const planted = '''
if (isModifierKey(event.logicalKey)) {
if (event.logicalKey == LogicalKeyboardKey.shiftLeft) {
key == LogicalKeyboardKey.altLeft || key == LogicalKeyboardKey.altRight;
if (event.physicalKey == PhysicalKeyboardKey.controlRight) {}
const SingleActivator(LogicalKeyboardKey.keyZ, shift: true);
// ↩️It was LogicalKeyboardKey.shiftLeft.
/// Not [isModifierKey(key)].
''';
    expect(_ownKeyNames(planted), [
      'if (isModifierKey(event.logicalKey)) {',
      'if (event.logicalKey == LogicalKeyboardKey.shiftLeft) {',
      'key == LogicalKeyboardKey.altLeft || key == LogicalKeyboardKey.altRight;',
      'if (event.physicalKey == PhysicalKeyboardKey.controlRight) {}',
    ]);
  });
}

const _theOnePlace = 'lib/src/services/input/modifier_keys.dart';

/// Each line of [source] that reaches the keyboard's record for anything
/// but a handler — trimmed, comments skipped.
List<String> _recordReads(String source) => [
  for (final line in source.split('\n'))
    if (!line.trimLeft().startsWith('//') && _record.hasMatch(line))
      line.trim(),
];

/// The record by its own name, through any binding's `keyboard` (every
/// binding is the services one — `WidgetsBinding.instance.keyboard`
/// compiles where `HardwareKeyboard` is not imported), or read off a
/// keyboard that is not `ModifierKeys`'s.
final _record = RegExp(
  r'HardwareKeyboard\.instance(?!\.(?:addHandler|removeHandler)\()'
  r'|\w*Binding\.instance\.keyboard\b'
  r'|(?<!ModifierKeys)\.keyboard\.'
  r'(?:is\w+Pressed|logicalKeysPressed|physicalKeysPressed)\b',
);

/// The lines that say what Flutter's own shortcut managers and scroll views
/// do — they read the record, so these must — keyed by file and line, with
/// why.
const _mirrors = <(String, String), String>{
  (
    'lib/src/ui/shortcuts/editor_shortcut_bindings.dart',
    '.where((entry) => entry.key.accepts(event, HardwareKeyboard.instance))',
  ): 'the input inspector\'s `bind` line: what the manager above it just '
      'ran, which it found by reading the record',
  (
    'lib/src/ui/shortcuts/editor_shortcut_bindings.dart',
    'final keyboard = HardwareKeyboard.instance;',
  ): 'whether a focused field\'s own shortcut table takes the key — a '
      'table run by a manager that reads the record',
  (
    'lib/src/ui/input/wheel_law.dart',
    'HardwareKeyboard.instance.logicalKeysPressed.any(flipKeys.contains);',
  ): 'whether Shift turns a mouse notch the other way — the sheet\'s own '
      'scroll views beside the slide ask the record (`Scrollable.'
      '_pointerSignalEventDelta`), and a slide that read it more loosely '
      'would take a notch they leave the frames (F-447)',
};

/// Where the modifiers' own keys are named for everyone else: the set
/// `isModifierKey` answers from, and the left keys `ModifierKeys` puts back
/// where the record let go.
const _whereTheyAreNamed = {
  'lib/src/services/input/modifier_keys.dart',
  'lib/src/ui/shortcuts/shortcut_activator_codec.dart',
};

/// Each line of [source] that names a modifier's own key — through
/// `isModifierKey`, or by the key — trimmed, comments skipped.
List<String> _ownKeyNames(String source) => [
  for (final line in source.split('\n'))
    if (!line.trimLeft().startsWith('//') && _ownKey.hasMatch(line))
      line.trim(),
];

final _ownKey = RegExp(
  r'\bisModifierKey\('
  r'|\b(?:Logical|Physical)KeyboardKey\.(?:shift|control|alt|meta)'
  r'(?:Left|Right)?\b',
);

/// The lines that name a modifier's own key, keyed by file and line, with
/// what each reads off that key's events — none a press or a release the
/// engine may make up or drop.
const _ownKeyReaders = <(String, String), String>{
  (
    'lib/src/ui/playback/playback_actuation_gate.dart',
    'if (isModifierKey(event.logicalKey)) {',
  ): 'that a modifier\'s own event is no input and is not eaten (I-19) — '
      'neither a press nor a release is read off it: both are asked '
      '(`_askTheModifiers`)',
  (
    'lib/src/ui/shortcuts/editor_key_holds.dart',
    'if (event is KeyUpEvent && !isModifierKey(key)) {',
  ): 'that a key-up lets go of what its key held — every key BUT a '
      'modifier, whose release is asked of `ModifierKeys` '
      '(`_letGoOfModifiersNoLongerHeld`)',
  (
    'lib/src/ui/shortcuts/editor_key_holds.dart',
    'if (isModifierKey(key) && !modifierHeld(key)) key,',
  ): 'that a modifier holding or waiting lets go once `modifierHeld` — '
      '`ModifierKeys` — says none of its kind is held, asked at every key '
      'and pointer event: the release a pen\'s move drops is found at the '
      'next of either (F-603)',
  (
    'lib/src/ui/shortcuts/editor_key_holds.dart',
    'if (isModifierKey(key)) {',
  ): 'when to ask the held view key\'s press again, a down and an up '
      'alike — the modifiers it is asked with are `ModifierKeys`\'',
  (
    'lib/src/ui/shortcuts/editor_key_holds.dart',
    'isModifierKey(key) &&',
  ): 'that a modifier going down under a held Alt, under a tool whose own '
      'drag reads Alt, holds nothing (F-299-Q1) — whether Alt is held is '
      'asked of `ModifierKeys`; a repeat heard as a key-down only asks again',
  (
    'lib/src/ui/shortcuts/editor_key_holds.dart',
    'isModifierKey(key) ? KeyEventResult.ignored : KeyEventResult.handled;',
  ): 'that a modifier a hold took passes on still, to modify what it is '
      'held with — no press or release is read off it',
  (
    'lib/src/ui/shortcuts/editor_key_holds.dart',
    'key == LogicalKeyboardKey.altLeft || key == LogicalKeyboardKey.altRight;',
  ): 'whether a hold already taken is on Alt — a second Alt joins it '
      'rather than being the tool\'s (F-299-Q1) — its release is asked of '
      '`ModifierKeys` with the rest',
  (
    'lib/src/ui/shortcuts/shortcut_settings_dialog.dart',
    'if (event is KeyUpEvent && isModifierKey(key)) {',
  ): 'when to ask whether the modifiers being recorded alone are let go — '
      'asked of `modifierHeld`, not read off the key-up (F-603)',
  (
    'lib/src/ui/shortcuts/shortcut_settings_dialog.dart',
    'if (isModifierKey(key)) {',
  ): 'that a chord being recorded waits for the key its modifiers modify '
      '— which are held is asked of `ModifierKeys` at that key',
};
