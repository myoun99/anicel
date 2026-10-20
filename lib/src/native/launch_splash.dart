import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// 🗣️I-106-Q3/Q4/Q5 (유저 2026-10-20): the desktop launch splash — the teal
/// A and the white name over the desktop — stands until the first frame,
/// on every desktop.
///
/// The Windows and Linux runners hear the first frame from their own
/// embedders (`SetNextFrameCallback`, FlView's "first-frame") and close
/// the splash themselves. The macOS embedder offers no such hook
/// (FlutterViewController.h declares none — checked 2026-10-20), so on
/// the Mac, and only there, Dart says it over [channel].
abstract final class LaunchSplash {
  /// Spelled again in `MainFlutterWindow.swift`.
  static const channel = MethodChannel('anicel/launch');
  static const firstFrameMethod = 'firstFrame';

  /// Tells the Mac runner once the first frame is on screen. Once, from
  /// `main()`, before `runApp`.
  static void closeAtFirstFrame() {
    if (defaultTargetPlatform != TargetPlatform.macOS) {
      return;
    }
    unawaited(
      WidgetsBinding.instance.waitUntilFirstFrameRasterized.then(
        (_) => channel.invokeMethod<void>(firstFrameMethod),
      ),
    );
  }
}
