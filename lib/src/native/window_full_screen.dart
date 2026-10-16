import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../services/persistence/app_window_store.dart';

/// 🗣️I-103 ② (유저 2026-10-15): 「전체창모드를 옵션으로서 만들고싶음」 — and
/// I-103-Q2 (2026-10-16): on the desktops a switch, on and off, remembered
/// for the next run; the iPad and Android stay full screen as they always
/// are (`main()`'s immersive mode), with no switch at all.
///
/// Full screen is the WINDOW's: on, its frame, its title bar and the taskbar
/// — on the Mac the menu bar and the Dock — give way and the app covers the
/// screen; off, the window is back at the size and place it had. Each
/// desktop runner throws its own OS's switch over [channel].
///
/// ★[on] FOLLOWS THE WINDOW, never the asking: a runner says when its window
/// went in or out ([changedMethod]) — after this app's own switch, and after
/// the Mac's green button or a Linux window manager's key, which throw the
/// same switch without asking anyone. A mark that moved on the asking would
/// stand wrong wherever the window did not follow.
abstract final class WindowFullScreen {
  /// The runners' channel and its two methods, spelled again in
  /// `flutter_window.cpp`, `MainFlutterWindow.swift` and
  /// `window_full_screen.cc`; `the_window_is_switched_one_way_test.dart`
  /// reads all four.
  static const channel = MethodChannel('anicel/window');
  static const setMethod = 'setFullScreen';
  static const changedMethod = 'fullScreenChanged';

  /// The platforms with the switch: the three desktops.
  static const Set<TargetPlatform> platforms = {
    TargetPlatform.windows,
    TargetPlatform.macOS,
    TargetPlatform.linux,
  };

  /// Whether this platform has the switch ([platforms]).
  static bool get offered => platforms.contains(defaultTargetPlatform);

  /// Whether the window is full screen, as its runner last said since
  /// [restore].
  static ValueListenable<bool> get on => _on;
  static final ValueNotifier<bool> _on = ValueNotifier(false);

  /// Where [on] is remembered — the app's, handed to [restore].
  static late AppWindowStore _store;

  /// Puts the window as the last run left it — BEFORE the first frame, so
  /// it opens that way rather than opening and then jumping — and from then
  /// on hears the runner and keeps [store] up to date. Once, from `main()`.
  static Future<void> restore(AppWindowStore store) async {
    if (!offered) {
      return;
    }
    _store = store;
    channel.setMethodCallHandler(_heard);
    if (await store.loadFullScreen() ?? false) {
      await set(true);
    }
  }

  /// Asks the window to go full screen, or to come back from it.
  static Future<void> set(bool value) async {
    try {
      await channel.invokeMethod<void>(setMethod, value);
    } on Exception {
      // A runner without the switch: the window stays as it is, and so
      // does [on].
    }
  }

  static Future<Object?> _heard(MethodCall call) async {
    if (call.method == changedMethod && call.arguments is bool) {
      _on.value = call.arguments as bool;
      unawaited(_store.saveFullScreen(_on.value));
    }
    return null;
  }
}
