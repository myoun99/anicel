// SHIFT PROBE (F-411) — does a modifier Windows let go of stay held in the
// engine's record, on THIS runner?
//
//   flutter run -d windows -t tool/probe/shift_probe_main.dart \
//     --dart-define=SHIFT_OUT=<dir>
//
// Writes `report.txt` into SHIFT_OUT — a line per case, `PASS` or `FAIL`
// with the keys the framework's record held, by name and by physical key —
// and exits.
//
// It runs in the REAL app process, on the app's own Windows runner, because
// the answer belongs to the engine and the runner the app ships with: what
// `flutter test` runs has neither. It hands the Flutter view the messages a
// keyboard sends, and sets this thread's key state (what GetKeyState
// answers: the engine syncs to it, and so does the runner) with
// SetKeyboardState at each step, so the messages and Windows' own answer
// agree as they would under a hand.
//
// 🗣️F-411 (유저 2026-10-19): 「보통은 D held [D]라면 D held [Shift right, D]
// 라고 되있었음 … 다른 앱 … 정상으로 쉬프트없이 q라고 입력됨 … 앱
// 재기동하니까 해결되있음」. The keys round a gray arrow under a held right
// Shift are one shape that leaves the record so; the runner's answer is for
// any shape (windows/runner/flutter_window.cpp says why).
//
// ⚠️The engine itself syncs the LAST key of each modifier it saw to Windows,
// letting go and pressing again. A case where the key left behind is that
// last one is answered by the engine whatever the runner does — so each
// stuck shape is also tried with the modifier's own key seen after it.
//
// Measurement, not a feature: not wired into the app, no strings, no UI
// conventions apply.
import 'dart:async';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

final _user32 = DynamicLibrary.open('user32.dll');
final _kernel32 = DynamicLibrary.open('kernel32.dll');

final _sendMessage = _user32
    .lookupFunction<
      IntPtr Function(IntPtr, Uint32, IntPtr, IntPtr),
      int Function(int, int, int, int)
    >('SendMessageW');
final _setKeyboardState = _user32
    .lookupFunction<
      Int32 Function(Pointer<Uint8>),
      int Function(Pointer<Uint8>)
    >('SetKeyboardState');
final _findWindowEx = _user32
    .lookupFunction<
      IntPtr Function(IntPtr, IntPtr, Pointer<Utf16>, Pointer<Utf16>),
      int Function(int, int, Pointer<Utf16>, Pointer<Utf16>)
    >('FindWindowExW');
final _getWindowThreadProcessId = _user32
    .lookupFunction<
      Uint32 Function(IntPtr, Pointer<Uint32>),
      int Function(int, Pointer<Uint32>)
    >('GetWindowThreadProcessId');
final _getCurrentThreadId = _kernel32
    .lookupFunction<Uint32 Function(), int Function()>('GetCurrentThreadId');

const _wmKeyDown = 0x0100;
const _wmKeyUp = 0x0101;
const _wmSysKeyDown = 0x0104;
const _wmSysKeyUp = 0x0105;
const _vkRight = 0x27;
const _vkD = 0x44;

/// A key message's shape: its scan code and its extended bit, which the
/// engine names the physical key by.
typedef _Shape = ({int scancode, bool extended});

/// One modifier as a keyboard sends it: the virtual key its messages carry,
/// the keys Windows says are held while it is, its own key's shape and
/// physical key, the framework's names for either side of it, and the
/// shapes a second key-down of it is sent in while it is held.
class _Modifier {
  _Modifier(
    this.name, {
    required this.key,
    required this.heldAs,
    required this.shape,
    required this.physical,
    required this.named,
    required this.otherShapes,
    this.system = false,
  });

  final String name;
  final int key;
  final Set<int> heldAs;
  final _Shape shape;
  final PhysicalKeyboardKey physical;
  final Set<LogicalKeyboardKey> named;
  final List<_Shape> otherShapes;

  /// Whether its messages are the SYS ones, as Alt's are.
  final bool system;

  int get downMessage => system ? _wmSysKeyDown : _wmKeyDown;
  int get upMessage => system ? _wmSysKeyUp : _wmKeyUp;
}

final _rightShift = _Modifier(
  'right Shift',
  key: 0x10,
  heldAs: {0x10, 0xA1},
  shape: (scancode: 0x36, extended: false),
  physical: PhysicalKeyboardKey.shiftRight,
  named: {LogicalKeyboardKey.shiftLeft, LogicalKeyboardKey.shiftRight},
  otherShapes: const [],
);

/// A scan code no key has, as software that types for a hand may send it.
/// ⚠️Not 0: measured on this runner (F-411), the engine reads a key-down
/// with no scan code as the modifier's own key, and nothing is left behind.
const _noKeysShapes = [(scancode: 0x6F, extended: false)];

final _modifiers = [
  _Modifier(
    'left Ctrl',
    key: 0x11,
    heldAs: {0x11, 0xA2},
    shape: (scancode: 0x1D, extended: false),
    physical: PhysicalKeyboardKey.controlLeft,
    named: {LogicalKeyboardKey.controlLeft, LogicalKeyboardKey.controlRight},
    otherShapes: _noKeysShapes,
  ),
  _Modifier(
    'left Alt',
    key: 0x12,
    heldAs: {0x12, 0xA4},
    shape: (scancode: 0x38, extended: false),
    physical: PhysicalKeyboardKey.altLeft,
    named: {LogicalKeyboardKey.altLeft, LogicalKeyboardKey.altRight},
    otherShapes: _noKeysShapes,
    system: true,
  ),
  _Modifier(
    'left Windows',
    key: 0x5B,
    heldAs: {0x5B},
    shape: (scancode: 0x5B, extended: true),
    physical: PhysicalKeyboardKey.metaLeft,
    named: {LogicalKeyboardKey.metaLeft, LogicalKeyboardKey.metaRight},
    otherShapes: [..._noKeysShapes, (scancode: 0x5B, extended: false)],
  ),
];

/// This thread's own FLUTTERVIEW, under the runner's window.
int _view() {
  final runnerClass = 'FLUTTER_RUNNER_WIN32_WINDOW'.toNativeUtf16();
  final viewClass = 'FLUTTERVIEW'.toNativeUtf16();
  try {
    final me = _getCurrentThreadId();
    var top = 0;
    while (true) {
      top = _findWindowEx(0, top, runnerClass, nullptr);
      if (top == 0) {
        throw StateError('no runner window on this thread');
      }
      if (_getWindowThreadProcessId(top, nullptr) == me) {
        final view = _findWindowEx(top, 0, viewClass, nullptr);
        if (view != 0) {
          return view;
        }
      }
    }
  } finally {
    calloc
      ..free(runnerClass)
      ..free(viewClass);
  }
}

/// Windows says the keys in [down] are held, and no other.
void _windowsHolds(Set<int> down) {
  final state = calloc<Uint8>(256);
  try {
    for (final key in down) {
      state[key] = 0x80;
    }
    _setKeyboardState(state);
  } finally {
    calloc.free(state);
  }
}

int _lparam(_Shape shape, {required bool up, bool wasDown = false}) =>
    1 |
    (shape.scancode << 16) |
    (shape.extended ? 1 << 24 : 0) |
    (up || wasDown ? 1 << 30 : 0) |
    (up ? 1 << 31 : 0);

/// What the framework's record holds: its keys' names and physical keys.
typedef _Held = ({
  Set<LogicalKeyboardKey> logical,
  Set<PhysicalKeyboardKey> physical,
});

_Held _record() => (
  logical: {...HardwareKeyboard.instance.logicalKeysPressed},
  physical: {...HardwareKeyboard.instance.physicalKeysPressed},
);

class _Keyboard {
  _Keyboard(this.view) {
    HardwareKeyboard.instance.addHandler(_note);
  }

  final int view;
  _Held _atD = (logical: const {}, physical: const {});
  final _wentUp = <PhysicalKeyboardKey>{};

  bool _note(KeyEvent event) {
    if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.keyD) {
      _atD = _record();
    }
    if (event is KeyUpEvent && !event.synthesized) {
      _wentUp.add(event.physicalKey);
    }
    return false;
  }

  /// Whether [key] has gone up since the last modifier went [down], by a
  /// key-up the engine was handed.
  ///
  /// ⚠️Not one the engine made up to sync itself (`synthesized`): a mouse
  /// message carries the modifiers the hand holds, none here, and the
  /// engine lets Shift go and presses it again at the next key — measured
  /// on this runner as the window comes up under the pointer. That is the
  /// engine's own, before and after the runner's answer; what the runner
  /// hands it is a key-up like a keyboard's.
  bool wentUp(PhysicalKeyboardKey key) => _wentUp.contains(key);

  Future<void> send(int message, int key, int lparam) async {
    _sendMessage(view, message, key, lparam);
    await Future<void>.delayed(const Duration(milliseconds: 60));
  }

  Future<_Held> pressD() async {
    const d = (scancode: 0x20, extended: false);
    await send(_wmKeyDown, _vkD, _lparam(d, up: false));
    await send(_wmKeyUp, _vkD, _lparam(d, up: true));
    return _atD;
  }

  Future<void> down(_Modifier modifier) async {
    _wentUp.clear();
    _windowsHolds(modifier.heldAs);
    await send(
      modifier.downMessage,
      modifier.key,
      _lparam(modifier.shape, up: false),
    );
  }

  /// [modifier]'s own key repeating while it is held: the last key of it
  /// the engine saw is then its own.
  Future<void> repeat(_Modifier modifier) => send(
    modifier.downMessage,
    modifier.key,
    _lparam(modifier.shape, up: false, wasDown: true),
  );

  /// A second key-down of [modifier] while it is held, in [shape].
  Future<void> downAs(_Modifier modifier, _Shape shape) =>
      send(modifier.downMessage, modifier.key, _lparam(shape, up: false));

  Future<void> up(_Modifier modifier) async {
    _windowsHolds({});
    await send(
      modifier.upMessage,
      modifier.key,
      _lparam(modifier.shape, up: true),
    );
  }

  /// What a keyboard sends round a gray arrow while Shift is held: the
  /// fake Shift up and down, with the extended bit, round the arrow.
  Future<void> arrowUnderShift() async {
    const fake = (scancode: 0x36, extended: true);
    const arrow = (scancode: 0x4D, extended: true);
    await send(_wmKeyUp, 0x10, _lparam(fake, up: true));
    await send(_wmKeyDown, _vkRight, _lparam(arrow, up: false));
    await send(_wmKeyUp, _vkRight, _lparam(arrow, up: true));
    await send(_wmKeyDown, 0x10, _lparam(fake, up: false));
  }
}

String _shown(_Held held) =>
    'logical [${held.logical.map((key) => key.debugName).join(', ')}] '
    'physical [${held.physical.map((key) => key.debugName).join(', ')}]';

String _shapeName(_Shape shape) =>
    '${shape.scancode.toRadixString(16)}${shape.extended ? ' extended' : ''}';

Future<List<String>> _cases(_Keyboard keys) async {
  final lines = <String>[];

  /// Held: the record names [modifier] and holds its own key, which has
  /// not gone up meanwhile. Let go of: the record names it no more.
  void expectHeld(
    String name,
    _Modifier modifier,
    _Held held, {
    required bool isHeld,
  }) {
    final named = held.logical.any(modifier.named.contains);
    final wentUp = keys.wentUp(modifier.physical);
    final passed = isHeld
        ? named && held.physical.contains(modifier.physical) && !wentUp
        : !named;
    lines.add(
      '${passed ? 'PASS' : 'FAIL'} $name: ${_shown(held)}'
      '${isHeld && wentUp ? ' — its key went up meanwhile' : ''}',
    );
  }

  final shift = _rightShift;
  await keys.down(shift);
  expectHeld(
    'a right Shift held is held',
    shift,
    await keys.pressD(),
    isHeld: true,
  );
  await keys.arrowUnderShift();
  expectHeld(
    'held through an arrow, still held',
    shift,
    await keys.pressD(),
    isHeld: true,
  );
  await keys.up(shift);
  expectHeld(
    'let go of after an arrow, let go of at once',
    shift,
    _record(),
    isHeld: false,
  );
  expectHeld(
    'let go of after an arrow, let go of at D',
    shift,
    await keys.pressD(),
    isHeld: false,
  );

  await keys.down(shift);
  await keys.arrowUnderShift();
  await keys.repeat(shift);
  expectHeld(
    'held through an arrow and its own repeat, still held',
    shift,
    await keys.pressD(),
    isHeld: true,
  );
  await keys.up(shift);
  expectHeld(
    'let go of after an arrow and its own repeat, let go of at once',
    shift,
    _record(),
    isHeld: false,
  );

  for (final modifier in _modifiers) {
    for (final shape in modifier.otherShapes) {
      final named = '${modifier.name} and ${_shapeName(shape)}';
      await keys.down(modifier);
      await keys.downAs(modifier, shape);
      await keys.repeat(modifier);
      expectHeld(
        '$named held, still held',
        modifier,
        await keys.pressD(),
        isHeld: true,
      );
      await keys.up(modifier);
      expectHeld(
        '$named let go of, let go of at once',
        modifier,
        _record(),
        isHeld: false,
      );
    }
  }

  await keys.down(shift);
  await keys.up(shift);
  expectHeld('a plain press lets go', shift, _record(), isHeld: false);
  return lines;
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const SizedBox());
  await WidgetsBinding.instance.endOfFrame;
  final out = Directory(const String.fromEnvironment('SHIFT_OUT'));
  final lines = await _cases(_Keyboard(_view()));
  _windowsHolds({});
  out.createSync(recursive: true);
  File('${out.path}/report.txt').writeAsStringSync('${lines.join('\n')}\n');
  exit(lines.every((line) => line.startsWith('PASS')) ? 0 : 1);
}
