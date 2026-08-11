/// PICK-2: asking the OS for a folder the app may keep writing to.
///
/// The whole picker round rests on one sentence: **a project is not one
/// file.** It is `<name>.anicel` plus a sibling `<name>.assets/` folder, and
/// an autosave sidecar lands beside it every five minutes. On iOS and macOS
/// a security scope attaches to EXACTLY the item the user picked — deriving
/// the parent with `deletingLastPathComponent()` yields a path the sandbox
/// will not open — so picking the project FILE grants access to a project
/// that cannot save. The folder is the unit of permission.
///
/// What comes back is deliberately not a bare `String?`. A null path today
/// means four different things — the user cancelled, the OS handed back a
/// `content://` tree with no filesystem path, the grant was refused, or the
/// channel is not implemented — and three of them deserve to be said out
/// loud to the user. Every existing `AppStorage` method collapses all of
/// them into a safe default with `on Object { … }`, which is why a failure
/// there is invisible; this one does not.
library;

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:file_selector/file_selector.dart' as file_selector;

import 'app_documents.dart';

/// How a folder request ended.
enum FolderPickStatus {
  /// The user chose a folder and the app may write to it.
  granted,

  /// The user backed out. Not an error — say nothing.
  cancelled,

  /// The OS gave a location with no filesystem path behind it: a Drive or
  /// Dropbox document provider on Android, an SD card, a USB stick.
  ///
  /// This is the case the save stack cannot serve. Incremental saves rewrite
  /// a ZIP's central directory in place, and `<name>.assets/` is a real
  /// directory tree — neither survives a `content://` URI. The user gets the
  /// sync-app guidance rather than a project that silently fails to save.
  noFilesystemPath,

  /// The platform channel is missing or threw. Distinct from [cancelled] so
  /// a broken build says so instead of looking like a user who changed their
  /// mind.
  unavailable,
}

/// A folder the app has been granted, and the token that reopens it later.
@immutable
class FolderGrant {
  const FolderGrant({required this.status, this.path, this.bookmark});

  const FolderGrant.cancelled()
    : status = FolderPickStatus.cancelled,
      path = null,
      bookmark = null;

  const FolderGrant.noFilesystemPath()
    : status = FolderPickStatus.noFilesystemPath,
      path = null,
      bookmark = null;

  const FolderGrant.unavailable()
    : status = FolderPickStatus.unavailable,
      path = null,
      bookmark = null;

  const FolderGrant.granted({required String this.path, this.bookmark})
    : status = FolderPickStatus.granted;

  final FolderPickStatus status;

  /// A real filesystem path `dart:io` can list and write. Non-null exactly
  /// when [status] is [FolderPickStatus.granted].
  final String? path;

  /// An Apple security-scoped bookmark, base64. Null on Windows, Linux and
  /// Android, where a path is durable on its own and needs no token.
  ///
  /// This is what makes a recent-projects entry outlive a relaunch: the path
  /// alone would be remembered and then refused.
  final String? bookmark;

  bool get isGranted => status == FolderPickStatus.granted;
}

/// The one place that asks for a writable directory.
///
/// Two platforms answer differently and the difference is not cosmetic:
///
/// - **Windows, Linux** hand out real paths with no permission attached, so
///   `file_selector`'s folder dialog is the whole story.
/// - **iOS, macOS, Android** each need a grant the app has to hold onto —
///   a security scope on Apple, a real path resolved out of a SAF tree on
///   Android — so they route through the `qa_storage` channel.
abstract final class FolderPicker {
  /// Test seam. The repo's convention for a Dart→native call is an
  /// injectable override rather than a mocked channel (`setMockMethodCallHandler`
  /// appears nowhere in this codebase), and the picker layer has almost no
  /// coverage to begin with, so the seam is the test strategy.
  ///
  /// ⚠️Reset in `test/flutter_test_config.dart` — a static set by one test
  /// file otherwise leaks into every file after it.
  @visibleForTesting
  static Future<FolderGrant> Function({String? initialDirectory})?
  debugFolderPicker;

  /// Whether this platform hands out a folder grant that must be held, as
  /// opposed to a path that simply works.
  static bool get grantsAreScoped =>
      scopedForPlatform(Platform.operatingSystem);

  /// The decision as a pure function of the OS name.
  ///
  /// Split out so a test can pin all five platforms from the Windows
  /// workstation. Asserted through the getter it could only ever be
  /// `expect(false, false)` here — and a test written as
  /// `expect(grantsAreScoped, Platform.isIOS || …)` restates the
  /// implementation, so reducing the getter to `Platform.isIOS` left it
  /// green while sending macOS and Android down the desktop branch, losing
  /// bookmarks on one and SAF resolution on the other.
  @visibleForTesting
  static bool scopedForPlatform(String operatingSystem) =>
      operatingSystem == 'ios' ||
      operatingSystem == 'macos' ||
      operatingSystem == 'android';

  /// Asks the user for a folder.
  ///
  /// [initialDirectory] is a hint only; every platform is free to ignore it,
  /// and iOS always does — its document picker reopens wherever the user
  /// last was, which is the behaviour they expect from Files.
  static Future<FolderGrant> pick({String? initialDirectory}) async {
    final override = debugFolderPicker;
    if (override != null) {
      return override(initialDirectory: initialDirectory);
    }
    if (!grantsAreScoped) {
      // Desktop: a folder path is a folder path. No grant, no bookmark.
      try {
        final picked = await file_selector.getDirectoryPath(
          initialDirectory: initialDirectory,
        );
        return picked == null
            ? const FolderGrant.cancelled()
            : FolderGrant.granted(path: _normalize(picked));
      } on Object {
        return const FolderGrant.unavailable();
      }
    }
    return _invoke('pickProjectFolder', {'initialDirectory': initialDirectory});
  }

  /// Reopens a folder from a stored [bookmark], re-acquiring the security
  /// scope. Returns a grant whose path may DIFFER from the original — a
  /// bookmark tracks the folder, so this is how a moved or renamed project
  /// folder is followed rather than lost.
  ///
  /// [FolderPickStatus.unavailable] here means the bookmark is stale: the
  /// provider was reinstalled, the account changed, or the folder is gone.
  /// The caller keeps the row and offers to reconnect instead of deleting
  /// what the user may still want.
  static Future<FolderGrant> resolveBookmark(String bookmark) async {
    if (!grantsAreScoped) {
      return const FolderGrant.unavailable();
    }
    return _invoke('resolveFolderBookmark', {'bookmark': bookmark});
  }

  static Future<FolderGrant> _invoke(
    String method,
    Map<String, Object?> arguments,
  ) async {
    try {
      return decodeChannelAnswer(
        await AppStorage.channel.invokeMapMethod<Object?, Object?>(
          method,
          arguments,
        ),
      );
    } on Object {
      return const FolderGrant.unavailable();
    }
  }

  /// Turns a native answer into a grant.
  ///
  /// Pure, and public to tests on purpose. This is the part most likely to
  /// be wrong and the part hardest to reach: the channel is only consulted
  /// on the three scoped platforms, so on the Windows workstation this app
  /// is written on the branch that decodes it is unreachable through
  /// [pick]. Left inline it would ship untested.
  ///
  /// The status is a STRING rather than an absent path because the four
  /// outcomes are not interchangeable — a cancel and a Drive folder with no
  /// filesystem path want different words on screen. An unrecognised status
  /// becomes [FolderPickStatus.unavailable] rather than quietly a cancel, so
  /// a native that grows a case Dart has not learned yet is loud instead of
  /// looking like a user who changed their mind.
  @visibleForTesting
  static FolderGrant decodeChannelAnswer(Map<Object?, Object?>? answer) {
    if (answer == null) {
      return const FolderGrant.unavailable();
    }
    final path = answer['path'];
    switch (answer['status']) {
      case 'granted' when path is String && path.isNotEmpty:
        final bookmark = answer['bookmark'];
        return FolderGrant.granted(
          path: _normalize(path),
          bookmark: bookmark is String && bookmark.isNotEmpty ? bookmark : null,
        );
      // A native that says "granted" and forgets the path is broken, not
      // successful. Falls through to unavailable rather than producing a
      // grant with a null path that every caller would then have to guard.
      case 'cancelled':
        return const FolderGrant.cancelled();
      case 'noFilesystemPath':
        return const FolderGrant.noFilesystemPath();
      default:
        return const FolderGrant.unavailable();
    }
  }

  static String _normalize(String path) => path.replaceAll('\\', '/');
}
