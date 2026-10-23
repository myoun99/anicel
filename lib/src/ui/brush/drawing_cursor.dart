import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../models/app_input_settings.dart';
import '../canvas/raster_picture.dart' show withPicture;
import 'tool_cursor_look.dart';

/// The system cursor the drawing tools ask for over the canvas, for the
/// cursor the user chose (I-54) — [SystemMouseCursors.none] wherever the
/// app draws it instead ([appDrawsDrawingCursor]).
///
/// 🗣️유저 2026-09-30: the pen and the crosshair 「os커서를 바꿈으로서 앱이랑
/// 관계없이 빠르게」 — so each is the system's wherever the system can wear
/// it, and the app's only where it cannot. The tip's outline is the app's
/// everywhere: it is the brush's own shape, and no system cursor has one.
///
/// [devicePixelRatio] is the screen's own: a system cursor is a picture in
/// the screen's pixels.
MouseCursor drawingSystemCursor(
  DrawingCursor cursor, {
  required double devicePixelRatio,
}) => switch (cursor) {
  DrawingCursor.brush => SystemMouseCursors.none,
  DrawingCursor.pen => lookSystemCursor(
    penCursorLook(),
    devicePixelRatio: devicePixelRatio,
  ),
  DrawingCursor.crosshair =>
    _systemShowsCursors ? SystemMouseCursors.precise : SystemMouseCursors.none,
};

/// Whether the app draws [cursor] itself: exactly where the system is asked
/// to show none ([drawingSystemCursor]) — one answer, so the two can never
/// both show or both be missing.
bool appDrawsDrawingCursor(DrawingCursor cursor) =>
    drawingSystemCursor(cursor, devicePixelRatio: 1) ==
    SystemMouseCursors.none;

/// A cursor of one size as the system's — the pen (I-54), the fill's bucket
/// and the eyedropper (F-441) — wherever the system takes a picture for its
/// cursor, and [SystemMouseCursors.none], the app drawing [look], anywhere
/// else.
///
/// 🗣️F-441 (유저 2026-10-23): 「채우기도구처럼 크기를 크게 키울 필요가 없는
/// 고정크기 커서 도구는 기본적으로 os커서로서 변환해서 사용. 지금 앱 커서라
/// 느린게 보임」.
MouseCursor lookSystemCursor(
  ToolCursorLook look, {
  required double devicePixelRatio,
}) => _systemTakesPictures
    ? LookMouseCursor(look, devicePixelRatio: devicePixelRatio)
    : SystemMouseCursors.none;

/// Whether the app draws [look] itself: where the system is asked to show
/// none ([lookSystemCursor]).
bool appDrawsLook(ToolCursorLook look) =>
    lookSystemCursor(look, devicePixelRatio: 1) == SystemMouseCursors.none;

/// Whether the system shows the cursor a region asks for: everywhere but
/// iPadOS, whose engine has no `flutter/mousecursor` handler at all.
bool get _systemShowsCursors => defaultTargetPlatform != TargetPlatform.iOS;

/// Whether the system takes a picture for its cursor: Windows, whose engine
/// takes one over `flutter/mousecursor` (`createCustomCursor/windows`).
///
/// ⚠️macOS, Android and Linux take one only through the runner (I-54 ⓔ);
/// until then the app draws the looks there.
bool get _systemTakesPictures =>
    defaultTargetPlatform == TargetPlatform.windows;

/// A [ToolCursorLook] as the system's cursor: its pixels, handed to Windows
/// once a look and size and named after that — so it moves at the system's
/// speed, with nothing of the app's frame in its way. Two are the same
/// cursor when their looks are ([ToolCursorLook.key]).
@immutable
class LookMouseCursor extends MouseCursor {
  const LookMouseCursor(this.look, {required this.devicePixelRatio});

  final ToolCursorLook look;

  /// The screen's pixels per logical pixel, which the picture is made at.
  final double devicePixelRatio;

  @override
  @protected
  MouseCursorSession createSession(int device) =>
      _LookCursorSession(this, device);

  @override
  String get debugDescription =>
      'LookMouseCursor(${look.key}, $devicePixelRatio)';

  @override
  bool operator ==(Object other) =>
      other is LookMouseCursor &&
      other.look.key == look.key &&
      other.devicePixelRatio == devicePixelRatio;

  @override
  int get hashCode => Object.hash(look.key, devicePixelRatio);
}

class _LookCursorSession extends MouseCursorSession {
  _LookCursorSession(LookMouseCursor super.cursor, super.device);

  @override
  LookMouseCursor get cursor => super.cursor as LookMouseCursor;

  bool _disposed = false;

  @override
  Future<void> activate() async {
    final name = await _lookCursorNamed(
      cursor.look,
      cursor.devicePixelRatio,
    );
    // A cursor that came after this one while its picture was being made
    // has the system now; this one must not take it back.
    if (_disposed || name == null) {
      return;
    }
    try {
      await SystemChannels.mouseCursor.invokeMethod<void>(
        'setCustomCursor/windows',
        <String, Object>{'name': name},
      );
    } on PlatformException {
      // The system keeps the cursor it has.
    }
  }

  @override
  void dispose() => _disposed = true;
}

/// The name Windows knows each look at each size by — made once, for the
/// engine keeps every one it is handed for the life of the window.
final Map<(Object, int), Future<String?>> _lookCursorNames = {};

Future<String?> _lookCursorNamed(
  ToolCursorLook look,
  double devicePixelRatio,
) {
  final side = (look.extent.longestSide * devicePixelRatio).ceil();
  return _lookCursorNames[(look.key, side)] ??= _makeLookCursor(
    look,
    side: side,
    scale: devicePixelRatio,
  );
}

Future<String?> _makeLookCursor(
  ToolCursorLook look, {
  required int side,
  required double scale,
}) async {
  final recorder = ui.PictureRecorder();
  look.painter.paint(ui.Canvas(recorder)..scale(scale), look.extent);
  final image = await withPicture(
    recorder,
    (picture) => picture.toImage(side, side),
  );
  final ByteData? rgba;
  try {
    rgba = await image.toByteData();
  } finally {
    image.dispose();
  }
  if (rgba == null) {
    return null;
  }
  try {
    return await SystemChannels.mouseCursor.invokeMethod<String>(
      'createCustomCursor/windows',
      <String, Object>{
        'name': 'anicel-${look.key}-$side',
        'buffer': bgraOf(rgba),
        'width': side,
        'height': side,
        'hotX': look.hotspot.dx * scale,
        'hotY': look.hotspot.dy * scale,
      },
    );
  } on PlatformException {
    return null;
  }
}

/// [rgba] — `toByteData`'s premultiplied RGBA — in the order Windows reads
/// a cursor's pixels: blue, green, red, alpha.
@visibleForTesting
Uint8List bgraOf(ByteData rgba) {
  final bytes = Uint8List.fromList(
    rgba.buffer.asUint8List(rgba.offsetInBytes, rgba.lengthInBytes),
  );
  for (var i = 0; i + 3 < bytes.length; i += 4) {
    final red = bytes[i];
    bytes[i] = bytes[i + 2];
    bytes[i + 2] = red;
  }
  return bytes;
}
