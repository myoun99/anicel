import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../services/persistence/app_support_path.dart';
import '../ui/text/app_strings.dart';
import '../ui/theme/app_theme.dart';

/// 🗣️I-106-Q3/Q4/Q5 (유저 2026-10-20): the desktop launch splash — the teal
/// A and the white name over the desktop — stands until the first frame,
/// on every desktop. 🗣️I-106 (2026-10-21): under the name it says what the
/// launch is doing — 「투명하게 하고있는걸 보여주면되. 시간이 매우
/// 짧더라도」 — every stage, however short, with dots that turn once a
/// second (「엔진 시작. 엔진 시작.. 엔진 시작...」), and no progress bar.
///
/// The stages run in [stageNames]' order. The runner says the first two
/// itself, before Dart runs — from what the LAST launch left in
/// [labelsFileName], since only Dart knows the app's language and face —
/// and Dart says the last two over [channel].
///
/// The face goes to the runner as FILES, not names: the names are
/// [AppTypography]'s alone (`the_app_has_one_face_test`), and they are
/// Flutter's family names, which a font file need not carry. The runner
/// loads the files in order — the first speaks, the rest fill in what it
/// lacks — and none at all means the OS's face (Chinese, as in the app).
///
/// The Windows and Linux runners hear the first frame from their own
/// embedders (`SetNextFrameCallback`, FlView's "first-frame") and close
/// the splash themselves. The macOS embedder offers no such hook
/// (FlutterViewController.h declares none — checked 2026-10-20), so on
/// the Mac, and only there, Dart says it.
abstract final class LaunchSplash {
  /// Spelled again in `flutter_window.cpp`, `MainFlutterWindow.swift` and
  /// `my_application.cc`. [stageMethod] carries `[faceFiles, name]`.
  static const channel = MethodChannel('anicel/launch');
  static const stageMethod = 'stage';
  static const firstFrameMethod = 'firstFrame';

  /// The face's files on the first line — tab-separated, relative to
  /// `flutter_assets` — then one stage name a line, in [stageNames]' order.
  /// Written by a run, read by the next one's runner: the lifetime
  /// `memory-log.txt` has. Spelled again in each runner's `launch_splash`.
  static const labelsFileName = 'launch-labels.txt';

  /// The platforms with the splash: the three desktops.
  static const Set<TargetPlatform> platforms = {
    TargetPlatform.windows,
    TargetPlatform.macOS,
    TargetPlatform.linux,
  };

  /// The launch's stages, in the order they run: the engine starting and
  /// the plugins registering (the runner's), the app preparing in `main()`
  /// and the first screen drawing (Dart's).
  static List<String> stageNames(AppStrings strings) => [
    strings.launchStageEngine,
    strings.launchStagePlugins,
    strings.launchStageApp,
    strings.launchStageFirstFrame,
  ];

  /// The files of [families], in order, as the font manifest lists them —
  /// each family's upright regular face.
  @visibleForTesting
  static List<String> faceFiles(List<String> families, String manifest) {
    final entries = (jsonDecode(manifest) as List).cast<Map<String, dynamic>>();
    return [
      for (final family in families)
        for (final entry in entries)
          if (entry['family'] == family)
            for (final font in (entry['fonts'] as List)
                .cast<Map<String, dynamic>>()
                .where((font) => font['weight'] == null && font['style'] == null)
                .take(1))
              font['asset'] as String,
    ];
  }

  static bool get _shown => platforms.contains(defaultTargetPlatform);

  /// The face [AppTypography] gives the app's language, as files.
  static String _faceFilesLine = '';

  /// Says the app is preparing, and leaves the face and the stage names
  /// for the next launch's runner. Once, from `main()`, as soon as the
  /// language is known.
  static Future<void> preparing(AppStrings strings) async {
    if (!_shown) {
      return;
    }
    final families = [
      ?AppTypography.familyFor(AppText.language),
      ...?AppTypography.fallbackFor(AppText.language),
    ];
    try {
      _faceFilesLine = faceFiles(
        families,
        await rootBundle.loadString('FontManifest.json'),
      ).join('\t');
    } on Object {
      // The runner then speaks in the OS's face.
      _faceFilesLine = '';
    }
    final names = stageNames(strings);
    _say(names[2]);
    final labels = File(
      testRedirectedAppSupportPath(labelsFileName, sandbox: 'launch'),
    );
    unawaited(
      labels.parent
          .create(recursive: true)
          .then(
            (_) => labels.writeAsString(
              '$_faceFilesLine\n${names.join('\n')}\n',
            ),
          )
          .then<void>(
            (_) {},
            // The next launch then shows last time's names, or none.
            onError: (Object _) {},
          ),
    );
  }

  /// Says the first screen is drawing, and on the Mac closes the splash
  /// once it is on screen. Once, from `main()`, before `runApp`.
  static void drawing(AppStrings strings) {
    if (!_shown) {
      return;
    }
    _say(stageNames(strings)[3]);
    if (defaultTargetPlatform != TargetPlatform.macOS) {
      return;
    }
    unawaited(
      WidgetsBinding.instance.waitUntilFirstFrameRasterized.then(
        (_) => channel.invokeMethod<void>(firstFrameMethod),
      ),
    );
  }

  static void _say(String name) => unawaited(
    channel.invokeMethod<void>(stageMethod, [_faceFilesLine, name]),
  );
}
