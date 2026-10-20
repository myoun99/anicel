// SHIFT PROBE (F-411) — does a modifier Windows let go of stay held in the
// engine's record, on THIS runner?
//
//   flutter run -d windows -t tool/probe/shift_probe_main.dart \
//     --dart-define=SHIFT_OUT=<dir>
//
// Writes `report.txt` into SHIFT_OUT — a line per case, `PASS` or `FAIL`
// with what the framework's record held at a D — and exits.
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

/// One modifier as a keyboard sends it: the virtual key its messages carry,
/// the keys Windows says are held while it is, its own key's shape, and the
/// framework's names for either side of it.
class _Modifier {
  _Modifier(
    this.name, {
    required this.key,
    required this.heldAs,
    required this.scancode,
    required this.named,
    this.extended = false,
    this.system = false,
  });

  final String name;
  final int key;
  final Set<int> heldAs;
  final int scancode;
  final Set<LogicalKeyboardKey> named;
  final bool extended;

  /// Whether its messages are the SYS ones, as Alt's are.
  final bool system;

  int get downMessage => system ? _wmSysKeyDown : _wmKeyDown;
  int get upMessage => system ? _wmSysKeyUp : _wmKeyUp;
}

final _rightShift = _Modifier(
  'right Shift',
  key: 0x10,
  heldAs: {0x10, 0xA1},
  scancode: 0x36,
  named: {LogicalKeyboardKey.shiftLeft, LogicalKeyboardKey.shiftRight},
);

/// The modifiers whose key-down can come in another shape than their own
/// key's — here a scan code no key has, as software that types for a hand
/// sends it.
final _modifiers = [
  _Modifier(
    'left Ctrl',
    key: 0x11,
    heldAs: {0x11, 0xA2},
    scancode: 0x1D,
    named: {LogicalKeyboardKey.controlLeft, LogicalKeyboardKey.controlRight},
  ),
  _Modifier(
    'left Alt',
    key: 0x12,
    heldAs: {0x12, 0xA4},
    scancode: 0x38,
    named: {LogicalKeyboardKey.altLeft, LogicalKeyboardKey.altRight},
    system: true,
  ),
  _Modifier(
    'left Windows',
    key: 0x5B,
    heldAs: {0x5B},
    scancode: 0x5B,
    named: {LogicalKeyboardKey.metaLeft, LogicalKeyboardKey.metaRight},
    extended: true,
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

int _lparam(int scancode, {required bool up, bool extended = false}) =>
    1 |
    (scancode << 16) |
    (extended ? 1 << 24 : 0) |
    (up ? (1 << 30) | (1 << 31) : 0);

class _Keyboard {
  _Keyboard(this.view) {
    HardwareKeyboard.instance.addHandler(_note);
  }

  final int view;
  Set<LogicalKeyboardKey> _heldAtD = const {};

  bool _note(KeyEvent event) {
    if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.keyD) {
      _heldAtD = {...HardwareKeyboard.instance.logicalKeysPressed};
    }
    return false;
  }

  Set<LogicalKeyboardKey> get held => {
    ...HardwareKeyboard.instance.logicalKeysPressed,
  };

  Future<void> send(int message, int key, int lparam) async {
    _sendMessage(view, message, key, lparam);
    await Future<void>.delayed(const Duration(milliseconds: 60));
  }

  Future<Set<LogicalKeyboardKey>> pressD() async {
    await send(_wmKeyDown, _vkD, _lparam(0x20, up: false));
    await send(_wmKeyUp, _vkD, _lparam(0x20, up: true));
    return _heldAtD;
  }

  Future<void> down(_Modifier modifier) async {
    _windowsHolds(modifier.heldAs);
    await send(
      modifier.downMessage,
      modifier.key,
      _lparam(modifier.scancode, up: false, extended: modifier.extended),
    );
  }

  /// A second key-down of [modifier] while it is held, in a shape that is
  /// not its own key's.
  Future<void> downInAnotherShape(_Modifier modifier) =>
      send(modifier.downMessage, modifier.key, _lparam(0x00, up: false));

  Future<void> up(_Modifier modifier) async {
    _windowsHolds({});
    await send(
      modifier.upMessage,
      modifier.key,
      _lparam(modifier.scancode, up: true, extended: modifier.extended),
    );
  }

  /// What a keyboard sends round a gray arrow while Shift is held: the
  /// fake Shift up and down, with the extended bit, round the arrow.
  Future<void> arrowUnderShift() async {
    await send(_wmKeyUp, 0x10, _lparam(0x36, up: true, extended: true));
    await send(_wmKeyDown, _vkRight, _lparam(0x4D, up: false, extended: true));
    await send(_wmKeyUp, _vkRight, _lparam(0x4D, up: true, extended: true));
    await send(_wmKeyDown, 0x10, _lparam(0x36, up: false, extended: true));
  }
}

String _named(Set<LogicalKeyboardKey> held) =>
    '[${held.map((key) => key.debugName).join(', ')}]';

Future<List<String>> _cases(_Keyboard keys) async {
  final lines = <String>[];
  void expectHeld(
    String name,
    _Modifier modifier,
    Set<LogicalKeyboardKey> held, {
    required bool isHeld,
  }) {
    final passed = held.any(modifier.named.contains) == isHeld;
    lines.add('${passed ? 'PASS' : 'FAIL'} $name: held ${_named(held)}');
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
    keys.held,
    isHeld: false,
  );
  expectHeld(
    'let go of after an arrow, let go of at D',
    shift,
    await keys.pressD(),
    isHeld: false,
  );

  for (final modifier in _modifiers) {
    await keys.down(modifier);
    await keys.downInAnotherShape(modifier);
    expectHeld(
      '${modifier.name} held twice, still held',
      modifier,
      await keys.pressD(),
      isHeld: true,
    );
    await keys.up(modifier);
    expectHeld(
      '${modifier.name} let go of, let go of at once',
      modifier,
      keys.held,
      isHeld: false,
    );
    expectHeld(
      '${modifier.name} let go of, let go of at D',
      modifier,
      await keys.pressD(),
      isHeld: false,
    );
  }

  await keys.down(shift);
  await keys.up(shift);
  expectHeld('a plain press lets go', shift, keys.held, isHeld: false);
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
