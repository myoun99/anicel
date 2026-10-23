import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;
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

/// Whether the app draws [cursor] itself for the pointer aiming, a [kind]:
/// exactly where the system is asked to show none ([drawingSystemCursor]),
/// or shows that pointer none at all ([systemShowsCursorFor]) — one answer,
/// so the two can never both show or both be missing.
bool appDrawsDrawingCursor(DrawingCursor cursor, PointerDeviceKind kind) =>
    !systemShowsCursorFor(kind) ||
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

/// Whether the app draws [look] itself for the pointer aiming, a [kind]:
/// where the system is asked to show none ([lookSystemCursor]), or shows
/// that pointer none at all ([systemShowsCursorFor]).
bool appDrawsLook(ToolCursorLook look, PointerDeviceKind kind) =>
    !systemShowsCursorFor(kind) ||
    lookSystemCursor(look, devicePixelRatio: 1) == SystemMouseCursors.none;

/// Whether the system shows a pointer of [kind] the cursor a region asks
/// for. The desktops show every pointer that hovers — a mouse, a pen, a
/// pad — and a finger none. iPadOS shows none: its engine has no
/// `flutter/mousecursor` handler at all.
///
/// 🚨Android shows a MOUSE alone. The cursor a region asks for lands as the
/// view's pointer icon — the engine's handler and the runner's both set it
/// (`View.setPointerIcon`) — and that icon is a mouse's: a pen hovering is
/// shown what the view resolves for a pen (`View.onResolvePointerIcon`),
/// which Flutter's view leaves to the system (AOSP: 「A pointer icon set
/// using View#setPointerIcon will now only apply to mouse pointers」).
/// ↩️The cursor was asked of the system by platform alone, so on Android
/// the crosshair was the system's for every pointer — and a hovering
/// S Pen, which the system shows none of it, had no cursor at all.
bool systemShowsCursorFor(PointerDeviceKind kind) =>
    switch (defaultTargetPlatform) {
      TargetPlatform.iOS => false,
      TargetPlatform.android =>
        kind == PointerDeviceKind.mouse || kind == PointerDeviceKind.trackpad,
      _ => kind != PointerDeviceKind.touch,
    };

/// Whether the system shows any pointer a cursor — a region that asks for
/// one where none is shown asks for nothing.
bool get _systemShowsCursors => systemShowsCursorFor(PointerDeviceKind.mouse);

/// Where the system takes a picture for its cursor, and how it is handed
/// one: Windows over its engine's own `flutter/mousecursor`
/// (`createCustomCursor/windows`), in the order Windows reads pixels; macOS,
/// Android and Linux over their runner's [runnerCursorChannel], with the
/// same two calls — make once a look and size, wear by name — in the order
/// `toByteData` hands them over (I-54 ⓔ). iPadOS takes none.
typedef _PictureDoor = ({
  MethodChannel channel,
  String make,
  String wear,
  Uint8List Function(ByteData rgba) pixels,
});

_PictureDoor? get _pictureDoor => switch (defaultTargetPlatform) {
  TargetPlatform.windows => (
    channel: SystemChannels.mouseCursor,
    make: 'createCustomCursor/windows',
    wear: 'setCustomCursor/windows',
    pixels: bgraOf,
  ),
  TargetPlatform.macOS || TargetPlatform.android || TargetPlatform.linux => (
    channel: runnerCursorChannel,
    make: runnerMakeCursor,
    wear: runnerWearCursor,
    pixels: _rgbaOf,
  ),
  TargetPlatform.iOS || TargetPlatform.fuchsia => null,
};

bool get _systemTakesPictures => _pictureDoor != null;

/// The runners' cursor channel (macOS · Android · Linux), whose engines take
/// no picture for a cursor: [runnerMakeCursor] hands one over —
/// `name`, `buffer` (premultiplied RGBA), `width`, `height`, `hotX`, `hotY`
/// (all in the screen's pixels) and `scale` (the screen's pixels a logical
/// one) — and answers its name; [runnerWearCursor] wears the one `name`d.
const runnerCursorChannel = MethodChannel('anicel/cursor');
const runnerMakeCursor = 'createCustomCursor';
const runnerWearCursor = 'setCustomCursor';

/// A [ToolCursorLook] as the system's cursor: its pixels, handed to the
/// system once a look and size and named after that — so it moves at the
/// system's speed, with nothing of the app's frame in its way. Two are the
/// same cursor when their looks are ([ToolCursorLook.key]).
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
    final door = _pictureDoor;
    if (door == null) {
      return;
    }
    final name = await _lookCursorNamed(
      door,
      cursor.look,
      cursor.devicePixelRatio,
    );
    // A cursor that came after this one while its picture was being made
    // has the system now; this one must not take it back.
    if (_disposed || name == null) {
      return;
    }
    try {
      await door.channel.invokeMethod<void>(
        door.wear,
        <String, Object>{'name': name},
      );
    } on PlatformException {
      // The system keeps the cursor it has.
    } on MissingPluginException {
      // A runner that hears no cursor channel: the same.
    }
  }

  @override
  void dispose() => _disposed = true;
}

/// The name the system knows each look at each size by — made once,
/// for the system keeps every one it is handed for the life of the window.
/// A picture the system refused is not kept: the next wearing asks again.
final Map<(TargetPlatform, Object, int), Future<String?>> _lookCursorNames =
    {};

Future<String?> _lookCursorNamed(
  _PictureDoor door,
  ToolCursorLook look,
  double devicePixelRatio,
) {
  final side = (look.extent.longestSide * devicePixelRatio).ceil();
  final key = (defaultTargetPlatform, look.key, side);
  return _lookCursorNames[key] ??= _makeLookCursor(
    door,
    look,
    side: side,
    scale: devicePixelRatio,
  ).then((name) {
    if (name == null) {
      _lookCursorNames.removeWhere((made, _) => made == key);
    }
    return name;
  });
}

Future<String?> _makeLookCursor(
  _PictureDoor door,
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
    return await door.channel.invokeMethod<String>(
      door.make,
      <String, Object>{
        'name': 'anicel-${look.key}-$side',
        'buffer': door.pixels(rgba),
        'width': side,
        'height': side,
        'hotX': look.hotspot.dx * scale,
        'hotY': look.hotspot.dy * scale,
        'scale': scale,
      },
    );
  } on PlatformException {
    return null;
  } on MissingPluginException {
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

/// [rgba] as the runners read it — as it is.
Uint8List _rgbaOf(ByteData rgba) =>
    rgba.buffer.asUint8List(rgba.offsetInBytes, rgba.lengthInBytes);
