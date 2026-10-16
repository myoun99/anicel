import 'package:flutter_test/flutter_test.dart';

import '../helpers/dart_sources.dart';

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
/// do — those read the record, so the mirror must.
void main() {
  test('nothing in lib reads the keyboard\'s record but ModifierKeys', () {
    final hits = [
      for (final file in dartFilesUnder('lib'))
        if (libPath(file) != _theOnePlace)
          for (final read in _recordReads(file.readAsStringSync()))
            if (!_mirrors.containsKey((libPath(file), read)))
              '${libPath(file)}: $read',
    ];
    expect(
      hits,
      isEmpty,
      reason:
          'ask `ModifierKeys` — on Windows the record lets go of Shift and '
          'Ctrl under a pen or a finger. A line that must say what '
          'Flutter\'s own managers do goes in the ledger, with why',
    );
  });

  test('every mirror still reads the record, and says why', () {
    final sources = {
      for (final file in dartFilesUnder('lib'))
        libPath(file): file.readAsStringSync(),
    };
    for (final MapEntry(key: (path, read), value: why) in _mirrors.entries) {
      expect(why.length, greaterThan(20), reason: '$path needs a reason');
      expect(
        _recordReads(sources[path] ?? ''),
        contains(read),
        reason: '$path no longer reads `$read` — take it off the ledger',
      );
    }
  });

  test('the scan sees a planted read, and not a handler or a comment', () {
    const planted = '''
final keys = HardwareKeyboard.instance;
if (HardwareKeyboard.instance.isShiftPressed) {}
final pressed = ServicesBinding.instance.keyboard.logicalKeysPressed;
HardwareKeyboard.instance.addHandler(_onKey);
HardwareKeyboard.instance.removeHandler(_onKey);
/// Reads [HardwareKeyboard.instance] the way it used to.
// ↩️It was HardwareKeyboard.instance.isShiftPressed.
''';
    expect(_recordReads(planted), [
      'final keys = HardwareKeyboard.instance;',
      'if (HardwareKeyboard.instance.isShiftPressed) {}',
      'final pressed = ServicesBinding.instance.keyboard.logicalKeysPressed;',
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

final _record = RegExp(
  r'HardwareKeyboard\.instance(?!\.(?:addHandler|removeHandler)\()'
  r'|ServicesBinding\.instance\.keyboard',
);

/// The lines that say what Flutter's own shortcut managers do — they read
/// the record, so these must — keyed by file and line, with why.
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
};
