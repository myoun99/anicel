import 'dart:async';

import 'package:flutter/services.dart';

import '../services/persistence/app_window_store.dart';
import 'window_full_screen.dart';

/// 🗣️I-116 (유저 2026-10-21): 「세션 기억으로서 마지막에 열엇던 크기,위치
/// 기억하도록. 닫고 열때 마지막크기/위치로 열고싶음」 — on the desktops the
/// window opens where the last run left it, at its size, maximized if it was.
///
/// The frame is the RUNNER's, in its own OS's numbers ([WindowFrame]): each
/// runner says where its window stands once it has moved or changed size
/// ([changedMethod]), and is handed that back at the next start
/// ([setMethod]); the app only keeps it. A runner puts a frame no screen
/// shows any longer where a screen does — its OS's way.
///
/// ★A window that is full screen says nothing: what it comes back to is
/// what the next run opens at, under the full screen
/// ([WindowFullScreen.restore], which runs after this one).
abstract final class WindowPlace {
  /// The runners' channel and its two methods, spelled again in
  /// `flutter_window.cpp`, `MainFlutterWindow.swift` and `window_place.cc`;
  /// `the_window_keeps_its_place_test.dart` reads all four.
  static const channel = MethodChannel('anicel/window_place');
  static const setMethod = 'setPlace';
  static const changedMethod = 'placeChanged';

  static late AppWindowStore _store;

  /// The last frame kept, so a word that moves nothing writes nothing.
  static WindowFrame? _kept;

  /// Puts the window where the last run left it — BEFORE the first frame,
  /// so it opens there rather than opening and then jumping — and from then
  /// on hears the runner and keeps [store] up to date. Once, from `main()`.
  static Future<void> restore(AppWindowStore store) async {
    if (!WindowFullScreen.offered) {
      return;
    }
    _store = store;
    channel.setMethodCallHandler(_heard);
    final frame = _kept = await store.loadFrame();
    if (frame == null) {
      return;
    }
    try {
      await channel.invokeMethod<void>(setMethod, windowFrameToJson(frame));
    } on Exception {
      // A runner that cannot place its window: it opens where it would.
    }
  }

  static Future<Object?> _heard(MethodCall call) async {
    if (call.method != changedMethod) {
      return null;
    }
    final frame = windowFrameFromJson(call.arguments);
    if (frame != null && frame != _kept) {
      _kept = frame;
      unawaited(_store.saveFrame(frame));
    }
    return null;
  }
}
