import 'dart:io' show Platform;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show listEquals, visibleForTesting;
import 'package:flutter/services.dart' show rootBundle;
import 'package:gpu_engine/gpu_engine.dart';

import '../core/made_once.dart';
import '../core/path_names.dart' show folderOfPath, pathInFolder;
import '../ui/theme/app_theme.dart' show AppTypography;

/// THE FACES THE GPU ENGINE SETS LETTERS IN: the app's bundled families
/// ([AppTypography.canvasLetterFaces] — BIZ UDPGothic, 나눔고딕, Noto Sans
/// SC) read from its bundle once, as one [GpuFaces] the process keeps, and
/// laid in whatever order of them a style goes down — the canvas letters'
/// own, or the UI's, which a Chinese UI begins with Noto Sans SC
/// ([AppTypography.fallbackFor]) — sharing those files
/// ([GpuFaces.ordered]).
///
/// ⚠️ONE READ OF THE FILES: they are 35 MB (BIZ UDPGothic 9.3, 나눔고딕
/// 4.1, Noto Sans SC 21.7), held from the first letters the engine sets to
/// the process' end — mapped where the bundle is files, else copied
/// ([read]) — and a second [GpuFaces] read again would hold them twice.
abstract final class EngineFaces {
  /// The bundled families, in [AppTypography.canvasLetterFaces]' order.
  ///
  /// ⚠️THE FACES ARE KEPT, NOT THE FUTURE OF THEM: a future answers whoever
  /// awaits it in the zone it was made in, and that zone may be gone — each
  /// widget test runs in one of its own, and a second test awaiting the
  /// first one's future never woke (11-08). The law of every such keeping
  /// since 2026-11-23 ([MadeOnce]).
  static Future<GpuFaces> bundled() => _bundled.of(read);
  static final _bundled = MadeOnce<GpuFaces>();

  /// The bundled families read anew — what [bundled] keeps; a test's own
  /// read is kept by no one. Each file mapped by the engine from where the
  /// bundle lies ([bundleFolder]) — copied by no one, the pages Flutter's
  /// own mapping of it shows ([GpuFacesHanding.addAt]) —, else handed to it
  /// as soon as the bundle has read it, so the copy it costs falls in the
  /// turn its read ends and not all six in one ([GpuFacesHanding.add]).
  ///
  /// 🗣️유저 (engine-fonts-held-twice): 「사본이나 ram에있는걸 최대한
  /// 없애고싶어서」. 🔬공통 11-21, a Windows release run: Flutter maps the
  /// six files and copies none; the engine's copy was the only one — 35 MB
  /// of the 505 MB the memory tab calls this app's.
  ///
  /// ⚠️A file the engine cannot map is read through the bundle: the letters
  /// are the same either way, and only the copy is lost — Android's bundle
  /// is no folder (its files lie in the APK, compressed), and neither is
  /// the test runner's.
  @visibleForTesting
  static Future<GpuFaces> read() async {
    final handing = GpuFacesHanding();
    final folder = bundleFolder;
    for (final (family, face) in AppTypography.canvasLetterFaces.indexed) {
      for (final file in face.files) {
        if (folder != null &&
            handing.addAt(family, pathInFolder(folder, file))) {
          continue;
        }
        handing.add(family, Uint8List.sublistView(await rootBundle.load(file)));
      }
    }
    return handing.done();
  }

  /// Where the app's bundle lies as files on this device — the folder its
  /// keys are paths in — or null where it is no folder ([bundleFolderOf]).
  /// A test names its own.
  @visibleForTesting
  static String? bundleFolder = bundleFolderOf(
    Platform.resolvedExecutable,
    Platform.operatingSystem,
  );

  /// Where an app run as [executable] on [operatingSystem] finds its bundle
  /// as files — `flutter_assets`, where Flutter's embedder reads it — or
  /// null where it is no folder: Android's lies in the APK.
  ///
  /// ⚠️Flutter's layout, spelled again by each desktop runner's splash
  /// (`launch_splash.cpp` `AssetsFolder`, `launch_splash.cc`,
  /// `MainFlutterWindow.swift`) and, on iOS, by Flutter itself
  /// (`FlutterNSBundleUtils.mm` `kDefaultAssetPath`).
  @visibleForTesting
  static String? bundleFolderOf(String executable, String operatingSystem) {
    final inBundle = switch (operatingSystem) {
      'windows' || 'linux' => 'data/flutter_assets',
      'macos' => '../Frameworks/App.framework/Resources/flutter_assets',
      'ios' => 'Frameworks/App.framework/flutter_assets',
      _ => null,
    };
    return inBundle == null
        ? null
        : pathInFolder(folderOfPath(executable), inBundle);
  }

  /// Whether the bundle's have been read ([bundled]): what a paint asks
  /// before [inOrder], waiting for nothing.
  static bool get areRead => _bundled.isMade;

  /// The bundled families in the order [order] names them — each by its
  /// place among [AppTypography.canvasLetterFaces] —, made the first time
  /// that order is asked for and kept. Asked once they are read
  /// ([areRead]).
  static GpuFaces inOrder(List<int> order) {
    final all = _bundled.orNull!;
    if (listEquals(order, _bundledOrder)) {
      return all;
    }
    return _ordered[order.join(',')] ??= all.ordered(order);
  }

  static final Map<String, GpuFaces> _ordered = {};

  static final List<int> _bundledOrder = [
    for (final (place, _) in AppTypography.canvasLetterFaces.indexed) place,
  ];
}
