/// PICK-2: asking the OS for a location the app may keep writing to.
///
/// This file's original headline — "a project is not one file" — is the
/// world it was built for and no longer the world it serves. The single-file
/// format removed the `.assets/` sibling and moved the recovery snapshot
/// into the app container, so since PICK-6 the project FILE is the unit of
/// permission for open and Save As; folder grants remain for the jobs that
/// genuinely read a folder (cut-folder import, sequence export, the
/// desktop recordings/conform locations).
///
/// What comes back is deliberately not a bare `String?`. A null path today
/// means four different things — the user cancelled, the OS handed back a
/// `content://` tree with no filesystem path, the grant was refused, or the
/// channel is not implemented — and three of them deserve to be said out
/// loud to the user. Every existing `AppStorage` method collapses all of
/// them into a safe default with `on Object { … }`, which is why a failure
/// there is invisible; this one does not.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:file_selector/file_selector.dart' as file_selector;

import '../../core/path_names.dart';
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
  /// This is the case the save stack cannot serve: incremental saves rewrite
  /// a ZIP's central directory in place, which does not survive a
  /// `content://` URI. The user gets the sync-app guidance rather than a
  /// project that silently fails to save.
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
/// The user stopped waiting for a file to arrive.
///
/// Its own type because it is not a failure: nothing was applied, nothing
/// is broken, and the door that raised the wait should close quietly
/// rather than say something went wrong.
class MaterializeCancelled implements Exception {
  const MaterializeCancelled();

  @override
  String toString() => 'MaterializeCancelled';
}

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

  /// The same seam for [pickSaveDestination].
  ///
  /// ⚠️Reset in `test/flutter_test_config.dart`, like the seams above.
  @visibleForTesting
  static Future<FolderGrant> Function({
    required String suggestedName,
    String? initialDirectory,
  })?
  debugSaveDestinationPicker;

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
  // unrelated reason — at the time, video could not be carried at all, so
  // the "3GB duplicate" fear that pushed the default the other way went
  // with it.
  //
  // ⚠️That last clause is HISTORY, not a fact about today: the per-kind
  // ceiling died 2026-08-14 and video carries now like anything else
  // ([MediaAsset.carried] is the whole answer; the kind only picks the
  // import default). It is written in the past tense because the sentence
  // above it is about why a predicate was deleted, and a reader who takes
  // it for the present would conclude a 3GB movie cannot be inside a
  // project file.
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

  /// Whether this platform has a FILE COORDINATOR to appeal to.
  ///
  /// 🚨A DIFFERENT QUESTION from [grantsAreScoped], and letting one flag
  /// answer both is what this pair is here to stop. Android takes scoped
  /// grants and has no `NSFileCoordinator`: both coordinated helpers
  /// reach `notImplemented` there and answer false — which the open's
  /// wait would read as 「the provider has not finished downloading」 and
  /// retry against for a full minute, for a method that will never
  /// exist. The coordinator is Apple's, and only Apple's.
  static bool get hasFileCoordinator =>
      coordinatorForPlatform(_operatingSystem);

  @visibleForTesting
  static bool coordinatorForPlatform(String operatingSystem) =>
      operatingSystem == 'ios' || operatingSystem == 'macos';

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
      final picked = await _pickedDirectory(initialDirectory);
      if (picked == null) {
        return const FolderGrant.unavailable();
      }
      return picked.isEmpty
          ? const FolderGrant.cancelled()
          : FolderGrant.granted(path: _normalize(picked));
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
        // trains them to expect. Under the same F-14 hint rule as the
        // other three dialogs ([askingAgainWithoutHint]): a hint the
        // platform refuses must not read as "no picker" on the OPEN door.
        final picked = await askingAgainWithoutHint(
          (hint) async => allowMultiple
              ? await file_selector.openFiles(
                  acceptedTypeGroups: acceptedTypeGroups,
                  initialDirectory: hint,
                )
              : <file_selector.XFile?>[
                  await file_selector.openFile(
                    acceptedTypeGroups: acceptedTypeGroups,
                    initialDirectory: hint,
                  ),
                ].whereType<file_selector.XFile>().toList(),
          initialDirectory,
        );
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

  /// PICK-6: hands a finished file to the location the user picks — the
  /// SCOPED platforms' half of Save As.
  ///
  /// **The file is written FIRST**, into the app container, and this places
  /// it. That order is not a preference — iOS has no save panel (Apple never
  /// built one), so "ask where, then write there" is not available, and
  /// Android's CREATE_DOCUMENT flow has the same shape.
  ///
  /// Desktop does NOT come here: it has a real save dialog, so
  /// [pickSaveDestination] answers with a path and the save writes there
  /// itself. It used to — this method staged the file in the system temp
  /// and `File.rename`d it into place, which cannot cross volumes, so Save
  /// As to any drive but the temp's failed outright (OS error 17, measured
  /// on this repo's workstation) and a Save As pointed at the LIVE project
  /// replaced it before the save could read its own cels. No surveyed pro
  /// desktop app moves a staged file between volumes; the convention is
  /// "dialog returns a path, the app writes there".
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
  }) async {
    final override = debugFileExporter;
    if (override != null) {
      return override(sourcePath: sourcePath, suggestedName: suggestedName);
    }
    if (!grantsAreScoped) {
      throw StateError(
        'exportFile is the scoped-platform Save As; the desktop flow asks '
        'pickSaveDestination for a path and writes there itself.',
      );
    }
    return (await _invoke('exportFile', {
      'sourcePath': sourcePath,
      'suggestedName': suggestedName ?? fileNameOfPath(sourcePath),
    }, GrantKind.file)).first;
  }

  /// Save As on the platforms that HAVE a save dialog: the dialog answers
  /// with a path — nothing is created and nothing moves. The save that
  /// follows writes the file at that path itself (temp beside the
  /// destination + rename, atomic against whatever it replaces), which is
  /// what every surveyed desktop pro tool does.
  ///
  /// [acceptedTypeGroups] reaches the dialog's file-type filter. ⚠️The
  /// Windows plugin passes the filter to the dialog but never calls
  /// SetDefaultExtension, so a name typed bare comes back bare — the CALLER
  /// answers the suffix, and has to re-ask the replace question the dialog
  /// asked about the un-suffixed name.
  static Future<FolderGrant> pickSaveDestination({
    required String suggestedName,
    String? initialDirectory,
    List<file_selector.XTypeGroup> acceptedTypeGroups = const [],
  }) async {
    final override = debugSaveDestinationPicker;
    if (override != null) {
      return override(
        suggestedName: suggestedName,
        initialDirectory: initialDirectory,
      );
    }
    if (grantsAreScoped) {
      throw StateError(
        'Scoped platforms have no save dialog; Save As goes through '
        'exportFile there.',
      );
    }
    try {
      final location = await _pickedSaveLocation(
        suggestedName: suggestedName,
        initialDirectory: initialDirectory,
        acceptedTypeGroups: acceptedTypeGroups,
      );
      if (location == null) {
        return const FolderGrant.cancelled();
      }
      return FolderGrant.granted(
        path: _normalize(location.path),
        kind: GrantKind.file,
      );
    } on Object {
      return const FolderGrant.unavailable();
    }
  }

  /// The folder the user picked: `null` when the picker itself would not
  /// open, an EMPTY string when they cancelled, the path otherwise.
  ///
  /// 🚨F-14 (유저 2026-08-24): 「윈도우에서 저장 시 드라이브에 저장하려고하면
  /// **폴더선택을 열 수 없었다고 뜨고 저장안됨**」. The hint is what refused:
  /// a directory the platform will not accept as a starting point throws out
  /// of `getDirectoryPath`, and the catch turned that into "no picker".
  ///
  /// ★[initialDirectory] is documented right here as a HINT — 「every
  /// platform is free to ignore it」 — so it may not be able to stop the
  /// picker from opening at all. It is dropped and asked again.
  /// Runs [ask] with the hint, and again WITHOUT it if the hint threw.
  ///
  /// ⛔The second attempt is not a retry of a failure — it is the same
  /// question with the optional half removed. A hint that the platform will
  /// not start in may not be able to stop the picker from opening at all.
  ///
  /// Rethrows when the hintless attempt fails too: that is a real refusal,
  /// and the callers turn it into [FolderPickStatus.unavailable].
  @visibleForTesting
  static Future<T> askingAgainWithoutHint<T>(
    Future<T> Function(String? initialDirectory) ask,
    String? initialDirectory,
  ) async {
    try {
      return await ask(initialDirectory);
    } on Object {
      if (initialDirectory == null) {
        rethrow;
      }
    }
    return ask(null);
  }

  static Future<String?> _pickedDirectory(String? initialDirectory) async {
    try {
      return await askingAgainWithoutHint(
        (hint) async =>
            await file_selector.getDirectoryPath(initialDirectory: hint) ?? '',
        initialDirectory,
      );
    } on Object {
      return null;
    }
  }

  /// [file_selector.getSaveLocation] under the same hint rule.
  static Future<file_selector.FileSaveLocation?> _pickedSaveLocation({
    required String suggestedName,
    String? initialDirectory,
    List<file_selector.XTypeGroup> acceptedTypeGroups = const [],
  }) => askingAgainWithoutHint(
    (hint) => file_selector.getSaveLocation(
      suggestedName: suggestedName,
      initialDirectory: hint,
      acceptedTypeGroups: acceptedTypeGroups,
    ),
    initialDirectory,
  );

  /// Reopens a stored [bookmark], re-acquiring the security scope. Returns
  /// a grant whose path may DIFFER from the original — a bookmark tracks
  /// its item, so this is how a moved or renamed project is followed rather
  /// than lost.
  ///
  /// [FolderPickStatus.unavailable] here means the bookmark is stale: the
  /// provider was reinstalled, the account changed, or the item is gone.
  /// The caller keeps the row and offers to reconnect instead of deleting
  /// what the user may still want.
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

  /// The shape every coordinated call has: honour the test seam, answer
  /// false where there is no coordinator, else ask the channel and report
  /// whether it landed.
  ///
  /// ⛔THE SEAM AND THE GUARD ARE THE SAME LAW. Written out per method,
  /// a new coordinated call arrives with a channel invocation and no
  /// `hasFileCoordinator` guard — which on a desktop build is a
  /// MissingPluginException instead of a false. [override] is the seam
  /// already bound to its arguments, so one funnel serves a call that
  /// names two paths and a call that names one.
  static Future<bool> _askCoordinator(
    String method,
    Map<String, Object?> arguments,
    Future<bool> Function()? override,
  ) async {
    if (override != null) {
      return override();
    }
    if (!hasFileCoordinator) {
      return false;
    }
    final answer = await _invoke(method, arguments, GrantKind.file);
    return answer.first.isGranted;
  }

  static Future<bool> _coordinated(
    String method,
    Future<bool> Function({
      required String sourcePath,
      required String destinationPath,
    })?
    override, {
    required String sourcePath,
    required String destinationPath,
  }) => _askCoordinator(
    method,
    {'sourcePath': sourcePath, 'destinationPath': destinationPath},
    override == null
        ? null
        : () =>
              override(sourcePath: sourcePath, destinationPath: destinationPath),
  );

  /// Test seam for [readInPlaceCoordinated]. ⚠️Reset in
  /// `test/flutter_test_config.dart`.
  static Future<bool> Function(String path)? debugCoordinatedInPlaceReader;

  /// Reads [path] through the platform's file COORDINATION and copies
  /// NOTHING — the coordinated read the open needed all along.
  ///
  /// 🚨★★★A COORDINATED READ IS HOW A FILE PROVIDER IS ASKED FOR THE
  /// CURRENT ITEM. [requestFileDownload] speaks iCloud's API and every
  /// other provider ignores it, so on 2026-09-13 an iPad opening a Drive
  /// project「in place」read the copy Drive had cached from the iPad's own
  /// first save — one cut of twelve — while the desktop's revision sat in
  /// the cloud. A plain `dart:io` read never involves the provider;
  /// coordination does, and it is the only lever an app has (the M-1
  /// family: an uncoordinated write is one the provider never uploads).
  /// The native side opens the item inside the coordination block and
  /// closes it again; the bytes are then read where they lie.
  static Future<bool> readInPlaceCoordinated(String path) {
    final override = debugCoordinatedInPlaceReader;
    return _askCoordinator(
      'readInPlaceCoordinated',
      {'sourcePath': path},
      override == null ? null : () => override(path),
    );
  }

  /// Test seam for [touchFileCoordinated]. ⚠️Reset in
  /// `test/flutter_test_config.dart`.
  static Future<bool> Function(String path)? debugCoordinatedToucher;

  /// Tells the platform's file COORDINATION that [path]'s content changed
  /// — a coordinated write whose block writes nothing, after an append the
  /// app made in place.
  ///
  /// 🚨★★★ONE LAW FOR A GRANTED PATH: where the platform has a coordinator,
  /// every write ends in it. An append is a plain `dart:io` write into the
  /// item; a File Provider learns of a change through coordination and
  /// through nothing else, so a save that appended and stopped there was a
  /// save the provider never uploaded — the strokes were there on reopen
  /// and Drive's modified date never moved (M-1, 2026-09-11). A local file
  /// pays nothing here: with no presenter and no provider, the coordinator
  /// runs the empty block and returns.
  ///
  /// ⛔NOT「when the path is a provider item」. That was the first draft —
  /// a native check of `NSFileProviderManager` choosing the road per file —
  /// and it was two rules for one write, with a test of which that this
  /// app has no business inventing (유저 2026-09-13: 「규칙 통합이 아니라
  /// 두 개 준비하는 걸로 보이는데」). Coordination costs a local file
  /// nothing, so nothing is asked.
  static Future<bool> touchFileCoordinated(String path) {
    final override = debugCoordinatedToucher;
    return _askCoordinator(
      'touchFileCoordinated',
      {'sourcePath': path},
      override == null ? null : () => override(path),
    );
  }

  /// Test seam for [replaceFileCoordinated] — the channel is unreachable
  /// from a Dart test the same way every picker above is.
  /// ⚠️Reset in `test/flutter_test_config.dart`.
  static Future<bool> Function({
    required String sourcePath,
    required String destinationPath,
  })?
  debugCoordinatedReplacer;

  /// Overwrites [destinationPath] with [sourcePath]'s bytes through the
  /// platform's file COORDINATION (NSFileCoordinator) — the access
  /// discipline File Provider documents actually honour for outside
  /// writers. The save fallback for providers that refuse plain in-place
  /// writes (실측 08-26, iPhone + Google Drive). Answers whether the
  /// replace landed; false on the platforms that have no coordinator.
  static Future<bool> replaceFileCoordinated({
    required String sourcePath,
    required String destinationPath,
  }) async {
    return _coordinated(
      'replaceFileCoordinated',
      debugCoordinatedReplacer,
      sourcePath: sourcePath,
      destinationPath: destinationPath,
    );
  }

  /// Test seam for [readFileCoordinated], for the same reason as the
  /// replacer's. ⚠️Reset in `test/flutter_test_config.dart`.
  static Future<bool> Function({
    required String sourcePath,
    required String destinationPath,
  })?
  debugCoordinatedReader;

  /// Stages [sourcePath]'s bytes into [destinationPath] through the
  /// platform's file COORDINATION — the read twin of
  /// [replaceFileCoordinated]. A File Provider document (Drive,
  /// Dropbox…) can be a non-materialised placeholder that a plain
  /// `dart:io` read refuses even inside an open security scope (실측
  /// 08-26, iPhone + Google Drive .tvpp); coordinated reading is what
  /// makes the provider download it. False on the platforms that have
  /// no coordinator — callers fall back to nothing, their direct read
  /// already failed.
  static Future<bool> readFileCoordinated({
    required String sourcePath,
    required String destinationPath,
  }) async {
    return _coordinated(
      'readFileCoordinated',
      debugCoordinatedReader,
      sourcePath: sourcePath,
      destinationPath: destinationPath,
    );
  }

  /// ONE law for every user-picked file the app opens, whatever its
  /// format and whatever platform it came from: hand back a path a plain
  /// read will actually serve.
  ///
  /// 🚨IT ASKS AND WAITS — IT DOES NOT COPY. A File Provider document
  /// (Drive, Dropbox…) can be a placeholder that exists and refuses the
  /// first read while the fetch it just triggered runs on (실측 08-27,
  /// iPhone: the first open said 「잠시 후 다시 시도해 주세요」, the second
  /// opened the same file). One-shot code turns that into a notice, and
  /// the notice makes the USER the retry loop. So this asks the platform
  /// to bring the bytes down ([requestFileDownload]) and then re-probes
  /// THE PICK ITSELF until it reads.
  ///
  /// ⛔It used to stage a local copy instead, and that was the wrong
  /// shape twice over (유저 2026-08-27: 「사본은 왠만하면 만들고싶지
  /// 않아」). The cloud client is already keeping a local copy — ours
  /// would be the same bytes a second time, 10GB for a 5GB project — and
  /// nobody owned its lifetime: the `.anicel` door left it in the system
  /// temp for the OS to sweep while every cel ref pointed inside it.
  ///
  /// The staged road survives as an ALARMED last resort: `staged: true`
  /// is the caller's cue to say so on screen, so a build that still
  /// needs it is visible rather than quietly slower. If it never fires
  /// in the field, it comes out.
  ///
  /// ⚠️A pick with NO ENTRY gets no wait and no ask — nothing is on its
  /// way to a path that does not exist — but it does get the one staged
  /// attempt, because 「exists」 is the platform answering about a
  /// placeholder and a wrong answer there must cost an attempt rather
  /// than the whole road.
  ///
  /// 🚨THE WAIT HAS NO DEADLINE WHEN SOMEONE CAN STOP IT (유저
  /// 2026-08-27: 「상한을 두는 게 아니라 … 유저가 보고 판단해서 취소
  /// 버튼을 누르게 하는 게 자연스럽고 공개적이지 않을까」). A clock cannot
  /// tell a slow line from a dead one — it only guesses, and every guess
  /// either kills a download that would have finished or keeps a dead one
  /// on screen. The person watching can tell, so [onWaiting] keeps them
  /// informed and [isCancelled] is the escape.
  ///
  /// [within] is therefore a BACKSTOP, not the mechanism: null means no
  /// deadline, and it is REFUSED without [isCancelled], because a wait
  /// nobody can stop and no clock ends is a hang with a nice name. A door
  /// with a window passes null; a door without one keeps the default.
  ///
  /// [step] is the PROBE spacing, named so tests can compress it — how
  /// often the file is asked, which backs off. What [onWaiting] reports is
  /// the elapsed time and what has ARRIVED, on its own steady beat.
  static Future<({String path, bool staged})> materializeOpenedFile(
    String path, {
    Duration? within = const Duration(minutes: 10),
    Duration step = const Duration(milliseconds: 250),
    void Function(Duration waited, FileArrival arrival)? onWaiting,
    bool Function()? isCancelled,
  }) async {
    if (within == null && isCancelled == null) {
      throw ArgumentError.value(
        within,
        'within',
        'a wait with no deadline needs a way to be cancelled',
      );
    }
    // 🚨★★★ONE WAIT, ONE CLOCK, ONE CANCEL (F-135, 유저 2026-09-15: 「우선
    // 프로젝트 열 때 여는중 이라고만뜨는데」). The provider's fetch and the
    // pick becoming readable are ONE wait to the person watching. The fetch
    // used to be awaited bare, before the clock existed — and on an iPad it
    // IS the long part (a 94MB project on Drive): the window said only
    // 「여는 중…」, never that it was waiting for the cloud, and Cancel did
    // nothing until the provider let go. Every wait in here goes through
    // [tick]: stopped when the person stops it, reported as it grows, and
    // bounded only by [within]. 🧪Measured the same day: once the bytes are
    // local, the app's own read and apply of that project take ~160ms — this
    // wait is what the window is for.
    //
    // ⚠️No percent for the fetch: iOS gives an app no progress for another
    // app's File Provider download (the subscriber API is macOS-only), so the
    // line says what is being waited for and for how long — never a number
    // it cannot know.
    // 🚨★★★TWO QUESTIONS, TWO VALUES (F-141, 유저 2026-09-16: 「클라우드에서
    // 내려받는중 표시가 1,2,3초가 아니라 1,3,5초마다? 보임」).
    //
    // 「얼마나 자주 물어볼까」와 「얼마나 지났나」는 다른 질문인데, 누적치
    // 하나가 둘 다에 답하고 있었다: the probe spacing doubles so a slow fetch
    // is not asked a hundred times a minute, and the window was shown that
    // spacing's running total — so the line it drew skipped seconds (0 · 0 ·
    // 1 · 3 · 5 · 7) as the spacing grew. The clock is the clock now, and
    // the backoff is only the backoff.
    final clock = Stopwatch()..start();
    var pause = step;
    // What the last probe SAW, so the wait's sentence can be true instead of
    // guessed from the clock ([cloudWaitLine]).
    var seen = FileArrival.nothing;
    // One tick of the wait; false once [within] has passed. A wait that has
    // something to finish passes it as [sooner] and ends the tick early when
    // it does — and a tick ended that way reports nothing, because an
    // instant answer is not a wait. The timer goes with it, so nothing is
    // left ticking behind an answered question.
    //
    // ⚠️It sleeps in [_reportEvery] slices and reports each one, so the beat
    // the window draws stays steady while [pause] backs off. A [sooner] that
    // wins is the caller's [settled] to notice — the one caller raises its
    // flag before that future completes, so the slice loop cannot spin on an
    // already-finished future.
    Future<bool> tick({Future<void>? sooner, bool Function()? settled}) async {
      var slept = Duration.zero;
      while (true) {
        if (isCancelled?.call() ?? false) {
          throw const MaterializeCancelled();
        }
        if (within != null && clock.elapsed >= within) {
          return false;
        }
        final left = pause - slept;
        final slice = left < _reportEvery ? left : _reportEvery;
        final elapsed = Completer<void>();
        final timer = Timer(slice, elapsed.complete);
        await (sooner == null
            ? elapsed.future
            : Future.any<void>([sooner, elapsed.future]));
        timer.cancel();
        if (settled?.call() ?? false) {
          return true;
        }
        slept += slice;
        onWaiting?.call(clock.elapsed, seen);
        if (slept >= pause) {
          // Doubling, capped: the common case lands within a second or two.
          pause = pause * 2;
          if (pause > _materializeMaxStep) {
            pause = _materializeMaxStep;
          }
          return true;
        }
      }
    }

    // 🎯THE PROVIDER IS ASKED BEFORE THE FILE IS BELIEVED. A materialised
    // item reads at once — and it may be the copy the provider cached last
    // time, not what the cloud holds now (2026-09-13: twelve cuts on the
    // desktop, one on the iPad, same path). The coordinated read is what
    // makes the provider bring the current item; it copies nothing, and
    // where there is no coordinator it is not asked at all.
    // ⚠️A Cancel here leaves the native coordination to finish on its own
    // thread: its block only opens the item and closes it again, so there is
    // nothing to undo — only nothing left to wait for.
    if (hasFileCoordinator) {
      var answered = false;
      final ask = readInPlaceCoordinated(path)
          .then<void>((_) {}, onError: (Object _) {})
          .whenComplete(() => answered = true);
      while (!answered) {
        if (!await tick(sooner: ask, settled: () => answered)) {
          break;
        }
      }
    }
    seen = await arrivalOf(path);
    if (seen == FileArrival.whole) {
      return (path: path, staged: false);
    }
    if (await File(path).exists()) {
      // Ask the platform to fetch it, then wait for the PICK to be ALL here
      // — no copy anywhere in this wait.
      await requestFileDownload(path);
      while (await tick()) {
        seen = await arrivalOf(path);
        if (seen == FileArrival.whole) {
          return (path: path, staged: false);
        }
      }
    }
    final dot = path.lastIndexOf('.');
    final extension = dot > path.lastIndexOf(Platform.pathSeparator)
        ? path.substring(dot)
        : '';
    final staged =
        '${Directory.systemTemp.path}${Platform.pathSeparator}'
        'anicel-open-${DateTime.now().microsecondsSinceEpoch}$extension';
    if (await readFileCoordinated(sourcePath: path, destinationPath: staged) &&
        await arrivalOf(staged) == FileArrival.whole) {
      return (path: staged, staged: true);
    }
    throw FileSystemException('파일을 읽지 못했습니다', path);
  }

  static const Duration _materializeMaxStep = Duration(seconds: 2);

  /// How often a waiting window is told the time. ⛔It does NOT back off
  /// with [_materializeMaxStep]: a clock that skipped seconds is exactly
  /// what F-141 reported.
  static const Duration _reportEvery = Duration(seconds: 1);

  /// Test seam for [requestFileDownload]. ⚠️Reset in
  /// `test/flutter_test_config.dart`.
  static Future<void> Function(String path)? debugDownloadRequester;

  /// Asks the platform to bring [path]'s bytes down, copying nothing.
  ///
  /// Best-effort and deliberately answer-less: the platforms that have
  /// this request answer it asynchronously anyway, and the only signal
  /// worth acting on is the one every platform shares — whether the file
  /// reads yet. Silent everywhere else, where there was nothing to
  /// fetch.
  static Future<void> requestFileDownload(String path) async {
    final override = debugDownloadRequester;
    if (override != null) {
      return override(path);
    }
    if (!hasFileCoordinator) {
      return;
    }
    await _invoke('requestFileDownload', {'sourcePath': path}, GrantKind.file);
  }

  /// How much of [path] has actually ARRIVED.
  ///
  /// 🚨★★★「바이트가 하나 있다」와 「이 파일이 다 왔다」는 다른 질문이다
  /// (F-142, 유저 2026-09-16: 「드라이브프로그램에서 아직 다운로드가
  /// 안됬는데 … 그냥 열어버린 느낌이 있음. 제대로 확인」).
  ///
  /// This asked the FIRST byte and called that readable. A cloud
  /// placeholder fills from the FRONT, so the first byte lands early and
  /// the open believed a file whose tail was still in the cloud — and on
  /// Windows there is no coordinator to appeal to ([hasFileCoordinator] is
  /// Apple's only), so this probe is the WHOLE answer there.
  ///
  /// Both ends are asked now: the front says something is arriving, the
  /// LAST byte says all of it has. ⚠️Existence was already known to answer
  /// the wrong question; so did one byte.
  static Future<FileArrival> arrivalOf(String path) async {
    final override = debugArrival;
    if (override != null) {
      return override(path);
    }
    var front = false;
    RandomAccessFile? file;
    try {
      final open = file = await File(path).open();
      return await arrivalFrom(
        length: open.length,
        byteAt: (offset) async {
          await open.setPosition(offset);
          final byte = await open.read(1);
          if (offset == 0 && byte.isNotEmpty) {
            front = true;
          }
          return byte.isNotEmpty;
        },
      );
    } on FileSystemException {
      // The refusal came from the tail, so something IS here.
      return front ? FileArrival.partway : FileArrival.nothing;
    } finally {
      await file?.close();
    }
  }

  /// The two-ended question itself, over whatever can answer it.
  ///
  /// 🚨Split out so the LAW can be pinned. A placeholder that holds its
  /// front and refuses its tail is the platform's behaviour and no local
  /// filesystem can be made to imitate it — a test that goes through
  /// [debugArrival] proves only that the seam works, and a probe that
  /// quietly stopped asking the last byte would sail through it.
  static Future<FileArrival> arrivalFrom({
    required Future<int> Function() length,
    required Future<bool> Function(int offset) byteAt,
  }) async {
    if (!await byteAt(0)) {
      return FileArrival.nothing;
    }
    // The LAST byte, because a placeholder fills from the FRONT.
    return await byteAt(await length() - 1)
        ? FileArrival.whole
        : FileArrival.partway;
  }

  /// Test seam for [arrivalOf]. A placeholder's refusal is the platform's
  /// answer and no local filesystem can be made to give it — the same
  /// reason [debugCoordinatedInPlaceReader] exists.
  /// ⚠️Reset in `test/flutter_test_config.dart`.
  static Future<FileArrival> Function(String path)? debugArrival;

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

/// How much of a picked file is HERE — the three answers a cloud pick can
/// give, and the reason 「읽을 수 있다」 was never the right question
/// (F-142).
///
/// ⚠️[partway] is not a failure: it is a file on its way, and the wait's
/// sentence keeps counting for it rather than claiming nothing arrived
/// ([cloudWaitLine], F-141).
enum FileArrival {
  /// Not a byte of it. The placeholder exists and refuses the read it has
  /// just started.
  nothing,

  /// The front reads and the end does not — it is coming down.
  partway,

  /// Both ends read, so what lies between them is here too.
  whole,
}
