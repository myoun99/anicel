// PEN PROBE (F-427) — does a pen that has left keep the mouse out, on THIS
// runner?
//
//   flutter run -d windows -t tool/probe/pen_probe_main.dart \
//     --dart-define=PEN_OUT=<dir>
//
// Writes `report.txt` into PEN_OUT — a line per case, `PASS` or `FAIL` with
// what came in, and `INFO` lines with what Windows answered — and exits.
//
// It runs in the REAL app process, on the app's own Windows runner and the
// app's own binding, because the answer belongs to the engine, the runner
// and the binding's echo filter (lib/src/ui/input/pen_echoes.dart): what
// `flutter test` runs has none of them. The pen is a synthetic pointer
// device (CreateSyntheticPointerDevice), so Windows itself sends the view
// the pointer messages a pen does and answers GetPointerInfo for it; the
// mouse is SendInput's, so its moves come the way a hand's do. A modal
// window is the app's own window disabled (EnableWindow), as a file dialog
// leaves it; the app is busy where this thread sleeps.
//
// 🗣️F-427 (유저 2026-10-21): 「펜으로는 그리거나 패널열거나 다 가능한데
// 마우스로 아무 조작도 안먹히는 상황이 찾아옴 … 입력 인스펙터 켜보니 펜은
// 정상인데 마우스는 움직여도 아예 아무 줄도 갱신안됨」. Of every way a pen
// here goes, only a window that could not hear it go kept it in range
// (windows/runner/pen_leaves.h says why) — and every case after a stuck one
// fails too, as the app did until it restarted.
//
// ⚠️A pen is placed from the VIRTUAL screen's corner, not the primary
// monitor's ([_virtualScreen]); placed at the view's screen point on a desk
// with a screen left of the primary one, it hovered that other screen and
// no case heard it.
//
// Measurement, not a feature: not wired into the app, no strings, no UI
// conventions apply.
import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:anicel/src/ui/debug/input_inspector.dart';
import 'package:anicel/src/ui/ui_scale_binding.dart';
import 'package:ffi/ffi.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

final _user32 = DynamicLibrary.open('user32.dll');
final _kernel32 = DynamicLibrary.open('kernel32.dll');

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
final _enableWindow = _user32
    .lookupFunction<Int32 Function(IntPtr, Int32), int Function(int, int)>(
      'EnableWindow',
    );
final _showWindow = _user32
    .lookupFunction<Int32 Function(IntPtr, Int32), int Function(int, int)>(
      'ShowWindow',
    );
final _sleep = _kernel32
    .lookupFunction<Void Function(Uint32), void Function(int)>('Sleep');
final _getLastError = _kernel32
    .lookupFunction<Uint32 Function(), int Function()>('GetLastError');
final _getClientRect = _user32
    .lookupFunction<
      Int32 Function(IntPtr, Pointer<Int32>),
      int Function(int, Pointer<Int32>)
    >('GetClientRect');
final _clientToScreen = _user32
    .lookupFunction<
      Int32 Function(IntPtr, Pointer<Int32>),
      int Function(int, Pointer<Int32>)
    >('ClientToScreen');
final _createPen = _user32
    .lookupFunction<
      IntPtr Function(Uint32, Uint32, Uint32),
      int Function(int, int, int)
    >('CreateSyntheticPointerDevice');
final _destroyPen = _user32
    .lookupFunction<Void Function(IntPtr), void Function(int)>(
      'DestroySyntheticPointerDevice',
    );
final _inject = _user32
    .lookupFunction<
      Int32 Function(IntPtr, Pointer<Uint8>, Uint32),
      int Function(int, Pointer<Uint8>, int)
    >('InjectSyntheticPointerInput');
final _getPointerInfo = _user32
    .lookupFunction<
      Int32 Function(Uint32, Pointer<Uint8>),
      int Function(int, Pointer<Uint8>)
    >('GetPointerInfo');
final _sendInput = _user32
    .lookupFunction<
      Uint32 Function(Uint32, Pointer<Uint8>, Int32),
      int Function(int, Pointer<Uint8>, int)
    >('SendInput');
final _windowFromPoint = _user32
    .lookupFunction<IntPtr Function(Int64), int Function(int)>(
      'WindowFromPoint',
    );
final _getAncestor = _user32
    .lookupFunction<IntPtr Function(IntPtr, Uint32), int Function(int, int)>(
      'GetAncestor',
    );
final _getForegroundWindow = _user32
    .lookupFunction<IntPtr Function(), int Function()>('GetForegroundWindow');
final _setForegroundWindow = _user32
    .lookupFunction<Int32 Function(IntPtr), int Function(int)>(
      'SetForegroundWindow',
    );
final _isWindowVisible = _user32
    .lookupFunction<Int32 Function(IntPtr), int Function(int)>(
      'IsWindowVisible',
    );
final _getCursorPos = _user32
    .lookupFunction<
      Int32 Function(Pointer<Int32>),
      int Function(Pointer<Int32>)
    >(
      'GetCursorPos',
    );
final _setCursorPos = _user32
    .lookupFunction<Int32 Function(Int32, Int32), int Function(int, int)>(
      'SetCursorPos',
    );

const _ptPen = 3;
const _feedbackDefault = 1;
const _flagInRange = 0x2;
const _flagUpdate = 0x20000;
const _flagInContact = 0x4;
const _flagDown = 0x10000;
const _flagUp = 0x40000;
const _penInverted = 0x2;

// POINTER_TYPE_INFO on 64-bit Windows: the type, then the pen's
// POINTER_PEN_INFO at 8 — its POINTER_INFO (96 bytes) and the pen's own
// fields after it. The union is a touch's size, 144.
const _typeInfoSize = 152;
const _penAt = 8;
const _pointerInfoSize = 96;

// INPUT on 64-bit Windows: the type, then a MOUSEINPUT at 8.
const _inputSize = 40;
const _inputMouse = 0;
const _mouseMove = 0x1;

typedef _Point = ({int x, int y});

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

/// The middle of [view]'s client area, on the screen.
_Point _middleOf(int view) {
  final rect = calloc<Int32>(4);
  try {
    _getClientRect(view, rect);
    rect[0] = rect[2] ~/ 2;
    rect[1] = rect[3] ~/ 2;
    _clientToScreen(view, rect);
    return (x: rect[0], y: rect[1]);
  } finally {
    calloc.free(rect);
  }
}

const _gaRoot = 2;

final _getSystemMetrics = _user32
    .lookupFunction<Int32 Function(Int32), int Function(int)>(
      'GetSystemMetrics',
    );

/// The virtual screen's top left: InjectSyntheticPointerInput places a pen
/// from there, not from the primary monitor's corner — on a desk with a
/// screen left of the primary one, a pen at the view's screen point lands
/// on that other screen.
_Point _virtualScreen() =>
    (x: _getSystemMetrics(76), y: _getSystemMetrics(77));

/// Where things stand at [at]: the window under it, the foreground window,
/// whether the view's window shows, and where the cursor is.
String _where(int view, _Point at) {
  final top = _getAncestor(view, _gaRoot);
  final under = _windowFromPoint((at.y << 32) | (at.x & 0xffffffff));
  final cursor = calloc<Int32>(2);
  try {
    final gotCursor = _getCursorPos(cursor) != 0;
    final where = gotCursor ? '(${cursor[0]}, ${cursor[1]})' : 'unknown';
    return 'view $view top $top visible ${_isWindowVisible(top)} · '
        'under $at $under (root ${_getAncestor(under, _gaRoot)}) · '
        'foreground ${_getForegroundWindow()} · cursor $where';
  } finally {
    calloc.free(cursor);
  }
}

/// The cursor goes to [at] before a hand moves it, so its moves are over
/// the view.
Future<void> _parkCursor(_Point at) async {
  _setCursorPos(at.x, at.y);
  await _settle();
}

/// What came in through the app's binding, by kind, since [reset].
class _Heard {
  int mouse = 0;
  int pen = 0;
  int echoesAtReset = 0;
  int sent = 0;

  void reset() {
    mouse = 0;
    pen = 0;
    sent = 0;
    echoesAtReset = InputInspector.echoes;
  }

  int get echoes => InputInspector.echoes - echoesAtReset;

  void hear(PointerEvent event) {
    switch (event.kind) {
      case PointerDeviceKind.mouse:
        mouse += 1;
      case PointerDeviceKind.stylus || PointerDeviceKind.invertedStylus:
        pen += 1;
      case PointerDeviceKind.touch ||
          PointerDeviceKind.trackpad ||
          PointerDeviceKind.unknown:
    }
  }

  @override
  String toString() =>
      'mouse $mouse · pen $pen · echoes kept out $echoes · sent $sent';
}

class _Pen {
  _Pen(this.device);

  final int device;

  /// One frame, injected while this thread does not take it in: the view
  /// reads it when the thread next turns to its messages.
  void now(_Point at, {required bool inRange, bool inverted = false}) =>
      raw(
        at,
        inRange ? _flagInRange | _flagUpdate : _flagUpdate,
        inverted: inverted,
      );

  /// One frame of [flags] — a hover, a press, a stroke, a lift or a leave.
  void raw(_Point at, int flags, {bool inverted = false}) {
    final info = calloc<Uint8>(_typeInfoSize);
    try {
      final words = info.cast<Uint32>();
      words[0] = _ptPen;
      words[(_penAt + 0) ~/ 4] = _ptPen;
      words[(_penAt + 12) ~/ 4] = flags;
      final ints = info.cast<Int32>();
      ints[(_penAt + 32) ~/ 4] = at.x - _virtualScreen().x;
      ints[(_penAt + 36) ~/ 4] = at.y - _virtualScreen().y;
      words[(_penAt + _pointerInfoSize) ~/ 4] = inverted ? _penInverted : 0;
      if (_inject(device, info, 1) == 0) {
        throw StateError(
          'InjectSyntheticPointerInput failed: ${_getLastError()}',
        );
      }
    } finally {
      calloc.free(info);
    }
  }

  Future<void> frame(
    _Point at, {
    required bool inRange,
    bool inverted = false,
  }) async {
    now(at, inRange: inRange, inverted: inverted);
    await _settle();
  }

  Future<void> hover(_Point from, {bool inverted = false}) async {
    for (var step = 0; step < 3; step++) {
      await frame(
        (x: from.x + 4 * step, y: from.y),
        inRange: true,
        inverted: inverted,
      );
    }
  }

  Future<void> leave(_Point at, {bool inverted = false}) =>
      frame(at, inRange: false, inverted: inverted);
}

/// A hand moves the mouse right by [dx] three times; [heard] counts the
/// moves SendInput took.
Future<void> _mouseMoves(_Heard heard, {int dx = 8}) async {
  final input = calloc<Uint8>(_inputSize);
  try {
    for (var step = 0; step < 3; step++) {
      input.cast<Uint32>()[0] = _inputMouse;
      input.cast<Int32>()[2] = dx;
      input.cast<Int32>()[3] = 0;
      input.cast<Uint32>()[5] = _mouseMove;
      heard.sent += _sendInput(1, input, _inputSize);
      await _settle();
    }
  } finally {
    calloc.free(input);
  }
}

Future<void> _settle() async {
  await Future<void>.delayed(const Duration(milliseconds: 60));
  await WidgetsBinding.instance.endOfFrame;
}

/// The pointers Windows answers GetPointerInfo for, asked from this thread
/// (the view's) outside any of their messages: id, type and flags.
String _windowsPointers() {
  final info = calloc<Uint8>(_pointerInfoSize);
  try {
    final found = <String>[];
    for (var id = 0; id < 4096; id++) {
      if (_getPointerInfo(id, info) != 0) {
        final words = info.cast<Uint32>();
        found.add(
          'id $id type ${words[0]} flags 0x${words[3].toRadixString(16)}',
        );
      }
    }
    return found.isEmpty ? 'none' : found.join(', ');
  } finally {
    calloc.free(info);
  }
}

Future<List<String>> _cases(_Pen pen, int view, _Heard heard) async {
  final lines = <String>[];
  final at = _middleOf(view);

  void expect(String name, bool passed) {
    lines.add('${passed ? 'PASS' : 'FAIL'} $name: $heard');
  }

  lines.add('INFO at start: ${_where(view, at)}');
  final top = _getAncestor(view, _gaRoot);
  lines.add('INFO brought to the front: ${_setForegroundWindow(top)}');
  await _parkCursor(at);
  lines.add('INFO cursor parked: ${_where(view, at)}');

  heard.reset();
  await _mouseMoves(heard);
  expect('a mouse alone is heard', heard.mouse > 0 && heard.echoes == 0);

  await pen.hover(at);
  lines.add('INFO in range, Windows answers: ${_windowsPointers()}');
  lines.add('INFO engine sent: ${_penSent()}');
  await pen.leave(at);
  lines.add('INFO left, Windows answers: ${_windowsPointers()}');
  lines.add('INFO engine sent: ${_penSent()}');
  await _parkCursor(at);
  heard.reset();
  await _mouseMoves(heard);
  expect(
    'a pen that hovered and left lets the mouse in',
    heard.mouse > 0 && heard.echoes == 0,
  );

  await _parkCursor(at);
  heard.reset();
  await pen.hover(at);
  await _mouseMoves(heard);
  expect(
    'a pen in range keeps the mouse out (F-400)',
    heard.mouse == 0,
  );
  await pen.leave(at);
  lines.add('INFO engine sent: ${_penSent()}');

  await pen.hover(at);
  await pen.hover(at, inverted: true);
  lines.add('INFO turned in range, Windows answers: ${_windowsPointers()}');
  await pen.leave(at, inverted: true);
  lines.add('INFO engine sent: ${_penSent()}');
  await _parkCursor(at);
  heard.reset();
  await _mouseMoves(heard, dx: -8);
  expect(
    'a pen that turned to its eraser in range and left lets the mouse in',
    heard.mouse > 0 && heard.echoes == 0,
  );

  await pen.hover(at, inverted: true);
  await pen.hover(at);
  await pen.leave(at);
  lines.add('INFO engine sent: ${_penSent()}');
  await _parkCursor(at);
  heard.reset();
  await _mouseMoves(heard);
  expect(
    'a pen that turned to its tip in range and left lets the mouse in',
    heard.mouse > 0 && heard.echoes == 0,
  );

  // The app busy — a long frame holds the thread the view's messages come
  // to (Dart runs on it) — while the pen goes: its leave waits in the queue
  // until the pointer is gone.
  await pen.hover(at);
  pen.now(at, inRange: true);
  _sleep(150);
  pen.now(at, inRange: false);
  _sleep(150);
  await _settle();
  lines.add('INFO engine sent: ${_penSent()}');
  await _parkCursor(at);
  heard.reset();
  await _mouseMoves(heard);
  expect(
    'a pen that left while the app was busy lets the mouse in',
    heard.mouse > 0 && heard.echoes == 0,
  );

  for (var step = 0; step < 3; step++) {
    pen.now((x: at.x + 4 * step, y: at.y), inRange: true);
    _sleep(20);
  }
  pen.now(at, inRange: false);
  _sleep(150);
  await _settle();
  lines.add('INFO engine sent: ${_penSent()}');
  await _parkCursor(at);
  heard.reset();
  await _mouseMoves(heard);
  expect(
    'a pen that came and went while the app was busy lets the mouse in',
    heard.mouse > 0 && heard.echoes == 0,
  );

  await pen.hover(at);
  pen.now(at, inRange: true, inverted: true);
  _sleep(20);
  pen.now(at, inRange: false, inverted: true);
  _sleep(150);
  await _settle();
  lines.add('INFO engine sent: ${_penSent()}');
  await _parkCursor(at);
  heard.reset();
  await _mouseMoves(heard);
  expect(
    'a pen that turned and left while the app was busy lets the mouse in',
    heard.mouse > 0 && heard.echoes == 0,
  );

  Future<void> stroke({void Function()? midway}) async {
    final to = (x: at.x + 6, y: at.y);
    pen.raw(at, _flagInRange | _flagInContact | _flagDown);
    await _settle();
    midway?.call();
    pen.raw(to, _flagInRange | _flagInContact | _flagUpdate);
    await _settle();
    pen.raw(to, _flagInRange | _flagUp);
    await _settle();
  }

  Future<void> mouseAfter(String name) async {
    lines.add('INFO engine sent: ${_penSent()}');
    _setForegroundWindow(top);
    await _parkCursor(at);
    heard.reset();
    await _mouseMoves(heard);
    expect(name, heard.mouse > 0 && heard.echoes == 0);
  }

  await pen.hover(at);
  await stroke();
  await pen.leave(at);
  await mouseAfter('a pen that drew and left lets the mouse in');

  // A modal window up — a file dialog a pen's tap opened: Windows disables
  // the app's window under it while the pen goes.
  await pen.hover(at);
  _enableWindow(top, 0);
  await pen.hover(at);
  await pen.leave(at);
  _enableWindow(top, 1);
  await mouseAfter('a pen that left while a modal window held the app lets '
      'the mouse in');

  await pen.hover(at);
  await stroke(midway: () => _enableWindow(top, 0));
  await pen.leave(at);
  _enableWindow(top, 1);
  await mouseAfter('a pen pressed as a modal window came up lets the mouse '
      'in');

  // The pen still over the app when the modal window goes: it is heard
  // again, and its leave too.
  await pen.hover(at);
  _enableWindow(top, 0);
  await pen.hover(at);
  _enableWindow(top, 1);
  await _settle();
  _penSent();
  heard.reset();
  await pen.hover(at);
  final heardAgain = heard.pen;
  await pen.leave(at);
  expect(
    'a pen still over the app as a modal window went is heard again',
    heardAgain > 0,
  );
  await mouseAfter('a pen still over the app as a modal window went leaves, '
      'and lets the mouse in');

  await pen.hover(at);
  _showWindow(top, 0);
  await _settle();
  await pen.hover(at);
  await pen.leave(at);
  _showWindow(top, 5);
  await _settle();
  await mouseAfter('a pen that left while the window was hidden lets the '
      'mouse in');
  return lines;
}
Future<void> main() async {
  AnicelBinding.ensureInitialized();
  _tapThePen();
  final heard = _Heard();
  runApp(
    Listener(
      behavior: HitTestBehavior.opaque,
      onPointerHover: heard.hear,
      onPointerMove: heard.hear,
      onPointerDown: heard.hear,
      child: const SizedBox.expand(),
    ),
  );
  await WidgetsBinding.instance.endOfFrame;
  await Future<void>.delayed(const Duration(milliseconds: 500));
  final out = Directory(const String.fromEnvironment('PEN_OUT'));
  final device = _createPen(_ptPen, 1, _feedbackDefault);
  final lines = <String>[];
  if (device == 0) {
    lines.add('FAIL no synthetic pen: ${_getLastError()}');
  } else {
    try {
      lines.addAll(await _cases(_Pen(device), _view(), heard));
    } on Object catch (error) {
      lines.add('FAIL $error');
    } finally {
      _destroyPen(device);
    }
  }
  out.createSync(recursive: true);
  File('${out.path}/report.txt').writeAsStringSync('${lines.join('\n')}\n');
  exit(lines.every((line) => !line.startsWith('FAIL')) ? 0 : 1);
}

/// What the engine sent for any pen since the last [_penSent], before the
/// binding's own filter: kind, change and device of each.
final _rawPen = <String>[];

void _tapThePen() {
  final dispatcher = ui.PlatformDispatcher.instance;
  final through = dispatcher.onPointerDataPacket;
  dispatcher.onPointerDataPacket = (packet) {
    for (final data in packet.data) {
      if (data.kind != PointerDeviceKind.mouse) {
        _rawPen.add('${data.kind.name} ${data.change.name} ${data.device}');
      }
    }
    through?.call(packet);
  };
}

String _penSent() {
  final sent = _rawPen.isEmpty ? 'nothing' : _rawPen.join(', ');
  _rawPen.clear();
  return sent;
}
