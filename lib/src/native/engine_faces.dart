import 'dart:io' show File, FileSystemEntityType, Platform;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show listEquals, visibleForTesting;
import 'package:flutter/services.dart' show rootBundle;
import 'package:gpu_engine/gpu_engine.dart';

import '../core/made_once.dart';
import '../core/path_names.dart' show folderOfPath, pathInFolder;
import '../services/persistence/app_documents.dart' show AppStorage;
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
  static MadeOnce<GpuFaces> _bundled = MadeOnce();

  /// Test seam: none read, as a launch finds them — for a test of the first
  /// read, wherever its file runs in its process (card
  /// bundled-files-find-the-engine-already-open, 2026-11-23: two files went
  /// red behind a file that had read them). What was read stays with what
  /// holds it — the letters set in it — and the next ask reads the files
  /// again.
  @visibleForTesting
  static void debugForget() {
    _bundled = MadeOnce();
    _ordered.clear();
  }

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
  /// are the same either way, and only the copy is lost — the test
  /// runner's bundle is no folder, and an APK built with its fonts
  /// compressed holds no span of them ([spansInTheApk]).
  @visibleForTesting
  static Future<GpuFaces> read() async {
    final handing = GpuFacesHanding();
    final files = [
      for (final (family, face) in AppTypography.canvasLetterFaces.indexed)
        for (final file in face.files) (family: family, file: file),
    ];
    final keys = [for (final (:file, family: _) in files) file];
    final spans = bundleInTheApk
        ? await spansInTheApk(keys)
        : spansInFolder(bundleFolder, keys);
    for (final (place, (:family, :file)) in files.indexed) {
      final span = spans[place];
      if (span != null && handing.addAt(family, span)) {
        continue;
      }
      handing.add(family, Uint8List.sublistView(await rootBundle.load(file)));
    }
    return handing.done();
  }

  /// Where each of [files] lies in [folder] — the whole of its file — or
  /// null for one that is no file there, or for all where there is no
  /// folder.
  @visibleForTesting
  static List<FileSpan?> spansInFolder(
    String? folder,
    List<String> files,
  ) => [
    for (final file in files)
      if (folder == null) null else _wholeFileAt(pathInFolder(folder, file)),
  ];

  static FileSpan? _wholeFileAt(String path) {
    final told = File(path).statSync();
    return told.type == FileSystemEntityType.file
        ? (path: path, offset: 0, length: told.size)
        : null;
  }

  /// Whether the bundle lies in the APK (Android), its files asked of the
  /// OS ([spansInTheApk]) rather than found in a folder ([bundleFolder]).
  /// A test says its own.
  @visibleForTesting
  static bool bundleInTheApk = Platform.isAndroid;

  /// Where each of [files] lies stored in the APK, as Android's own
  /// AssetManager says it (`qa_storage` `bundledFiles`, MainActivity.kt) —
  /// or null for one it holds compressed, and for all if the OS says
  /// nothing.
  ///
  /// 🗣️유저 11-22 (engine-fonts-held-twice-Q1): 「글꼴을 압축 없이 두고 둘
  /// 다 비춰 쓴다」 — the fonts lie stored in the APK
  /// (`android/app/build.gradle.kts` `noCompress`), so Flutter maps them
  /// and the engine maps the same pages.
  @visibleForTesting
  static Future<List<FileSpan?>> spansInTheApk(List<String> files) async {
    final told = await _askedOfTheOs(files);
    return [
      for (final (place, _) in files.indexed)
        _spanOf(told != null && place < told.length ? told[place] : null),
    ];
  }

  static Future<List<Object?>?> _askedOfTheOs(List<String> files) async {
    try {
      return await AppStorage.channel.invokeListMethod<Object?>(
        'bundledFiles',
        files,
      );
    } on Object {
      return null;
    }
  }

  static FileSpan? _spanOf(Object? told) => switch (told) {
    {
      'path': final String path,
      'offset': final int offset,
      'length': final int length,
    } =>
      (path: path, offset: offset, length: length),
    _ => null,
  };

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
