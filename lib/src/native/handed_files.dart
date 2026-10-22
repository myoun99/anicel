import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// 🗣️open-door-windows-open-with-Q1 (유저 2026-10-22: 「떠 있는 창의 새
/// 탭으로」): a file opened with Anicel while one runs opens in that one.
/// Windows starts another Anicel for it, which hands the paths to the running
/// window and ends (`windows/runner/main.cpp`); the window says them here
/// ([openMethod]), and they go where the files a launch was handed go.
abstract final class HandedFiles {
  /// The runner's channel and its method, spelled again in
  /// `flutter_window.cpp`; `a_file_opened_again_joins_the_running_window_test`
  /// reads both.
  static const channel = MethodChannel('anicel/handed_files');
  static const openMethod = 'open';

  /// Hands [open] each list of paths the runner says — and with null, hears
  /// nothing any more.
  static void listen(ValueSetter<List<String>>? open) {
    if (open == null) {
      channel.setMethodCallHandler(null);
      return;
    }
    channel.setMethodCallHandler((call) async {
      final paths = call.arguments;
      if (call.method == openMethod && paths is List) {
        open(paths.whereType<String>().toList());
      }
      return null;
    });
  }
}
