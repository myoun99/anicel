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
import 'file_type_groups.dart';

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

/// Which picker produced a grant.
///
/// PICK-5: the one thing that genuinely differs between a file grant and a
/// folder grant. Coverage does NOT differ — `covers` is a single expression
/// for both, because a file grant is a subtree of size one and the prefix
/// clause dies on its own. What differs is which picker to raise when a
/// grant has to be re-established, and that is the whole of why this is
/// recorded.
enum GrantKind {
  file('file'),
  folder('folder');

  const GrantKind(this.jsonValue);

  final String jsonValue;

  /// Unknown or absent decodes to [folder]: every grant written before
  /// PICK-5 was a project folder.
  static GrantKind fromJson(Object? json) {
    for (final value in values) {
      if (value.jsonValue == json) {
        return value;
      }
    }
    return folder;
  }
}

/// A path the app has been granted, and the token that reopens it later.
@immutable
class FolderGrant {
  const FolderGrant({
    required this.status,
    this.path,
    this.bookmark,
    this.kind = GrantKind.folder,
  });

  const FolderGrant.cancelled()
    : status = FolderPickStatus.cancelled,
      path = null,
      bookmark = null,
      kind = GrantKind.folder;

  const FolderGrant.noFilesystemPath()
    : status = FolderPickStatus.noFilesystemPath,
      path = null,
      bookmark = null,
      kind = GrantKind.folder;

  const FolderGrant.unavailable()
    : status = FolderPickStatus.unavailable,
      path = null,
      bookmark = null,
      kind = GrantKind.folder;

  const FolderGrant.granted({
    required String this.path,
    this.bookmark,
    this.kind = GrantKind.folder,
  }) : status = FolderPickStatus.granted;

  final FolderPickStatus status;

  /// Whether this grant was taken over a file or over a folder.
  final GrantKind kind;

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

  /// Whether this grant opens [candidate].
  ///
  /// ONE expression for both kinds. A file grant is a subtree of size one,
  /// so the prefix clause is simply never true for it — branching on [kind]
  /// here would be a second law to keep in step with the first for no gain.
  bool covers(String candidate) {
    final granted = path;
    if (granted == null) {
      return false;
    }
    final normalized = candidate.replaceAll('\\', '/');
    return normalized == granted || normalized.startsWith('$granted/');
  }

  /// How a grant is written into `project.json`, or null when it is not
  /// worth writing.
  ///
  /// The STATUS is not persisted: a stored grant is one that was granted,
  /// and a file recording "cancelled" would be a file recording nothing.
  ///
  /// ⛔ Only a grant with a BOOKMARK is stored. On Windows, Linux and
  /// Android a recorded path keeps working on its own, so writing one down
  /// would add a field that says what the path already says. On Apple the
  /// bookmark IS the grant — a path there is refused after a relaunch,
  /// which is the whole reason any of this is saved.
  Map<String, Object?>? toJson() {
    final granted = path;
    final token = bookmark;
    if (granted == null || token == null || token.isEmpty) {
      return null;
    }
    return {'path': granted, 'bookmark': token, 'kind': kind.jsonValue};
  }

  /// Null for anything that is not a complete stored grant — a hand-edited
  /// file, or one written by a build that spelled this differently. A
  /// missing grant costs a reconnect; a half-built one would be a path the
  /// app believes it may write to.
  static FolderGrant? fromJson(Object? json) {
    if (json is! Map) {
      return null;
    }
    final path = json['path'];
    final bookmark = json['bookmark'];
    if (path is! String ||
        path.isEmpty ||
        bookmark is! String ||
        bookmark.isEmpty) {
      return null;
    }
    return FolderGrant.granted(
      path: path.replaceAll('\\', '/'),
      bookmark: bookmark,
      kind: GrantKind.fromJson(json['kind']),
    );
  }

  /// The grant that opens [candidate], or null when none does.
  ///
  /// A helper rather than a `firstWhere` at each call site because the
  /// answer is "none" far more often than not — most paths on most
  /// platforms need no grant at all.
  static FolderGrant? covering(Iterable<FolderGrant> grants, String path) {
    for (final grant in grants) {
      if (grant.covers(path)) {
        return grant;
      }
    }
    return null;
  }
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

  /// The same seam for [pickFiles]. Separate rather than one overloaded hook
  /// because a test that stubs the folder picker must not accidentally stub
  /// the file picker into returning a folder.
  ///
  /// ⚠️Reset in `test/flutter_test_config.dart`, like the two below.
  @visibleForTesting
  static Future<List<FolderGrant>> Function({
    required List<file_selector.XTypeGroup> acceptedTypeGroups,
    required bool allowMultiple,
  })?
  debugFilePicker;

  /// The same seam for [exportFile].
  ///
  /// ⚠️Reset in `test/flutter_test_config.dart`. A test that forgets this
  /// would have its fake MOVE a real file — export is the one picker with a
  /// side effect on disk.
  @visibleForTesting
  static Future<FolderGrant> Function({
    required String sourcePath,
    String? suggestedName,
  })?
  debugFileExporter;

  /// Test seam for the OS these rules are read from.
  ///
  /// ⚠️Reset in `test/flutter_test_config.dart`, like [debugFolderPicker].
  @visibleForTesting
  static String? debugOperatingSystem;

  /// Test seam for [resolveBookmark].
  ///
  /// Reopening a stored bookmark is the one step of the grant story that
  /// cannot be reached from this workstation at all — it is native, on
  /// three platforms, none of them Windows — and it is also where the
  /// interesting answers live: a token that no longer resolves, and one
  /// that resolves to a DIFFERENT path because the file moved. Both decide
  /// whether a reference survives, so both need to be drivable.
  ///
  /// ⚠️Reset in `test/flutter_test_config.dart`, like the seams above.
  @visibleForTesting
  static Future<FolderGrant> Function(String bookmark, GrantKind kind)?
  debugBookmarkResolver;

  static String get _operatingSystem =>
      debugOperatingSystem ?? Platform.operatingSystem;

  /// Whether this platform hands out a folder grant that must be held, as
  /// opposed to a path that simply works.
  static bool get grantsAreScoped => scopedForPlatform(_operatingSystem);

  // `referencesExpire` / `referencesExpireForPlatform` are GONE, and the
  // reason is worth keeping.
  //
  // They said: a path recorded on Apple stops working at the next relaunch
  // unless the grant that produced it was kept — which decided whether
  // importing by REFERENCE was safe by default, and is why Apple alone
  // started on Copy.
  //
  // Both halves of that stopped being true. Grants are kept now (they are
  // written into `project.json` and re-resolved on open), so a recorded
  // path survives. And the import default moved to Copy everywhere for an
  // unrelated reason — video is never carried, so the "3GB duplicate" fear
  // that pushed the default the other way went with it.
  //
  // ⚠️A predicate whose last consumer left is not merely unused: this one
  // would have gone on ANSWERING, and answering wrongly. Deleted rather
  // than left for someone to trust.

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
    return (await _invoke('pickProjectFolder', {
      'initialDirectory': initialDirectory,
    }, GrantKind.folder)).first;
  }

  /// PICK-5: asks the user for FILES, in place, with a grant on each.
  ///
  /// This exists because `file_selector` cannot serve a REFERENCE on either
  /// mobile platform. Both of its pickers copy:
  ///
  ///   - iOS opens the document picker in `.import` mode, which duplicates
  ///     the chosen file into the app sandbox and returns the copy.
  ///   - Android reads the `content://` document through
  ///     `getPathFromCopyOfFileFromUri`, which writes into `getCacheDir()`
  ///     with `deleteOnExit` on the directory.
  ///
  /// A media asset imported "by reference" therefore pointed at a temporary
  /// duplicate: the original was never referenced, no bookmark could be
  /// minted for it (the app never saw its URL), and the copy disappears on
  /// the next cache sweep. Copy-on-import happened to hide this on Apple —
  /// it copies the copy into the project, which survives — but a reference
  /// was broken from the start.
  ///
  /// Windows and Linux keep using the plugin: they hand back real paths,
  /// attach no permission, and copy nothing.
  static Future<List<FolderGrant>> pickFiles({
    required List<file_selector.XTypeGroup> acceptedTypeGroups,
    bool allowMultiple = false,
    String? initialDirectory,
  }) async {
    final override = debugFilePicker;
    if (override != null) {
      return override(
        acceptedTypeGroups: acceptedTypeGroups,
        allowMultiple: allowMultiple,
      );
    }
    if (!grantsAreScoped) {
      try {
        // `initialDirectory` is a desktop hint only — the Apple pickers
        // reopen wherever the user last was, which is the behaviour Files
        // trains them to expect.
        final picked = allowMultiple
            ? await file_selector.openFiles(
                acceptedTypeGroups: acceptedTypeGroups,
                initialDirectory: initialDirectory,
              )
            : <file_selector.XFile?>[
                await file_selector.openFile(
                  acceptedTypeGroups: acceptedTypeGroups,
                  initialDirectory: initialDirectory,
                ),
              ].whereType<file_selector.XFile>().toList();
        if (picked.isEmpty) {
          return const [FolderGrant.cancelled()];
        }
        return [
          for (final file in picked)
            FolderGrant.granted(
              path: _normalize(file.path),
              kind: GrantKind.file,
            ),
        ];
      } on Object {
        return const [FolderGrant.unavailable()];
      }
    }
    return _invoke('pickFiles', {
      'utis': FileTypeGroups.utisFor(acceptedTypeGroups),
      'mimeTypes': FileTypeGroups.mimeTypesFor(acceptedTypeGroups),
      'allowMultiple': allowMultiple,
    }, GrantKind.file);
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
  /// PICK-6: hands a finished file to the location the user picks.
  ///
  /// **The file is written FIRST**, into the app container, and this places
  /// it. That order is not a preference — iOS has no save panel (Apple never
  /// built one), so "ask where, then write there" is not available. Rather
  /// than let one platform invert the flow, every platform shares the one
  /// contract: *move this file to where the user says, and tell me where
  /// that turned out to be.*
  ///
  /// ⚠️[sourcePath] is CONSUMED on success — the file is moved, not copied.
  /// Callers must treat the returned path as the only copy from then on.
  ///
  /// ★On Apple this is the mode that reaches Google Drive; folder mode does
  /// not ([[ipad-cloud-project-location]]). The bookmark that comes back is
  /// what lets every later save write there with no UI at all.
  static Future<FolderGrant> exportFile({
    required String sourcePath,
    String? suggestedName,
    String? initialDirectory,
  }) async {
    final override = debugFileExporter;
    if (override != null) {
      return override(sourcePath: sourcePath, suggestedName: suggestedName);
    }
    if (!grantsAreScoped) {
      // Windows and Linux have a real save dialog and no permission to
      // hold, so the plugin is the whole story — but the CONTRACT is the
      // same, which is why the move happens here.
      try {
        final location = await file_selector.getSaveLocation(
          suggestedName: suggestedName ?? _fileNameOf(sourcePath),
          initialDirectory: initialDirectory,
        );
        if (location == null) {
          return const FolderGrant.cancelled();
        }
        final destination = _normalize(location.path);
        await File(sourcePath).rename(destination);
        return FolderGrant.granted(path: destination, kind: GrantKind.file);
      } on Object {
        return const FolderGrant.unavailable();
      }
    }
    return (await _invoke('exportFile', {
      'sourcePath': sourcePath,
      'suggestedName': suggestedName ?? _fileNameOf(sourcePath),
    }, GrantKind.file)).first;
  }

  static String _fileNameOf(String path) {
    final normalized = _normalize(path);
    final slash = normalized.lastIndexOf('/');
    return slash < 0 ? normalized : normalized.substring(slash + 1);
  }

  static Future<FolderGrant> resolveBookmark(
    String bookmark, {
    GrantKind kind = GrantKind.folder,
  }) async {
    final override = debugBookmarkResolver;
    if (override != null) {
      return override(bookmark, kind);
    }
    if (!grantsAreScoped) {
      return const FolderGrant.unavailable();
    }
    return (await _invoke('resolveBookmark', {
      'bookmark': bookmark,
    }, kind)).first;
  }

  static Future<List<FolderGrant>> _invoke(
    String method,
    Map<String, Object?> arguments,
    GrantKind kind,
  ) async {
    try {
      return decodeChannelAnswer(
        await AppStorage.channel.invokeMapMethod<Object?, Object?>(
          method,
          arguments,
        ),
        kind: kind,
      );
    } on Object {
      return const [FolderGrant.unavailable()];
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
  /// NEVER empty: a failure arrives as a single grant carrying the status,
  /// so no caller has to decide what an empty list would have meant.
  ///
  /// The payload shape is `{status, items: [{path, bookmark}]}` for one item
  /// and for many alike. A single-item dialect would have been smaller here
  /// and a standing hazard there — the channel has no compiler to notice
  /// when one of the three platform runners keeps speaking the old one.
  @visibleForTesting
  static List<FolderGrant> decodeChannelAnswer(
    Map<Object?, Object?>? answer, {
    GrantKind kind = GrantKind.folder,
  }) {
    if (answer == null) {
      return const [FolderGrant.unavailable()];
    }
    switch (answer['status']) {
      case 'granted':
        final items = answer['items'];
        if (items is! List) {
          // A native that says "granted" and forgets the items is broken,
          // not successful.
          return const [FolderGrant.unavailable()];
        }
        final grants = <FolderGrant>[];
        for (final item in items) {
          if (item is! Map) {
            continue;
          }
          final path = item['path'];
          if (path is! String || path.isEmpty) {
            // Same rule per item: a granted entry with no path is dropped
            // rather than becoming a grant every caller would have to guard.
            continue;
          }
          final bookmark = item['bookmark'];
          grants.add(
            FolderGrant.granted(
              path: _normalize(path),
              bookmark: bookmark is String && bookmark.isNotEmpty
                  ? bookmark
                  : null,
              kind: kind,
            ),
          );
        }
        return grants.isEmpty ? const [FolderGrant.unavailable()] : grants;
      case 'cancelled':
        return const [FolderGrant.cancelled()];
      case 'noFilesystemPath':
        return const [FolderGrant.noFilesystemPath()];
      default:
        return const [FolderGrant.unavailable()];
    }
  }

  static String _normalize(String path) => path.replaceAll('\\', '/');
}
