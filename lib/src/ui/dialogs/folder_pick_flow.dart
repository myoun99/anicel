import 'dart:async';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../../services/persistence/app_documents.dart';
import '../../services/persistence/folder_grant.dart';
import '../../services/persistence/move_into_folder.dart';
import '../../services/persistence/provider_documents.dart';
import '../text/app_strings.dart';
import '../widgets/app_window.dart';
import 'open_file_flow.dart';
import 'app_confirm_dialog.dart';

/// PICK-2: the folder request with its failures spoken out loud.
///
/// [FolderPicker.pick] deliberately reports four distinct outcomes; this is
/// where three of them become words. It exists because the alternative —
/// every caller writing `if (path == null) return;` — turns a Drive folder
/// with no filesystem path, a missing storage permission and a broken
/// channel into the same nothing-happened, which is precisely the failure
/// mode the old `on Object { safe default }` habit produced.
///
/// Returns a real directory path, or null when the user backed out or was
/// told why they cannot use what they chose.
Future<String?> pickFolderForUser(
  BuildContext context, {
  String? initialDirectory,
}) async => (await pickFolderGrantForUser(
  context,
  initialDirectory: initialDirectory,
))?.path;

/// Whether a folder pick has to clear a storage grant before it may even
/// open the picker.
///
/// Android alone: everywhere else the OS either attaches no permission to
/// a path (Windows, Linux) or grants one with the pick itself (iOS,
/// macOS). Pure over the OS name so BOTH answers can be pinned from the
/// Windows workstation this app is written on — the same seam
/// `FolderPicker.scopedForPlatform` uses, and for the same reason: a test
/// asserting `Platform.isAndroid` here would be asserting `false == false`.
bool folderPickNeedsStorageGrant(String operatingSystem) =>
    operatingSystem == 'android';

/// PICK-6: whether a CANCELLED folder pick might really be a person looking
/// for Google Drive, which no folder window can give them.
///
/// On Apple the Open button is DEAD in Drive: the delegate never fires, so
/// the app receives a plain cancel and cannot tell the two apart. On
/// Android Drive is not even LISTED — the system's folder window shows only
/// the providers that can hand over a folder, and Drive's cannot (Google's
/// own tracker, issue 135636079) — so a person looking for it can only
/// cancel. 🪦Android was left out until 2026-09-27 on the belief that its
/// window lists Drive and answers `noFilesystemPath` for it; that answer
/// only ever comes from a provider that DOES hand over a folder with no
/// path behind it, and it keeps its own notice.
///
/// Its own predicate, not borrowed from one that names the same platforms
/// for another reason — that would leave this silently wrong the day either
/// answer moves.
bool folderPickCancelMayBeDrive(String operatingSystem) =>
    operatingSystem == 'ios' ||
    operatingSystem == 'macos' ||
    operatingSystem == 'android';

/// What the Drive notice tells a person on [operatingSystem] to use instead:
/// where a folder CAN come from there — iCloud Drive and Dropbox on Apple
/// (실측 2026-08-13, iPhone), this device on Android, where a sync app can
/// keep a Drive folder.
String folderPickDriveNoticeFor(String operatingSystem) =>
    operatingSystem == 'android'
    ? AppText.strings.folderPickDriveNoticeAndroid
    : AppText.strings.folderPickDriveNotice;

/// Test seam for the OS the flow branches on.
///
/// The gate's whole job is to keep an Android user out of a picker that
/// would refuse every folder, and the notice it raises had NO coverage
/// after the in-app browser (its only test consumer) was deleted. Reset in
/// `test/flutter_test_config.dart` — a top-level left set by one file
/// would hand its answer to every file after it.
@visibleForTesting
String? debugOperatingSystemOverride;

String get _operatingSystem =>
    debugOperatingSystemOverride ?? Platform.operatingSystem;

/// Whether the Drive notice has already been shown this session.
///
/// Once, not once per picker: it is the same fact wherever folder mode
/// survives, and a user who has read it does not need it again on the next
/// import.
///
/// ⚠️Reset in `test/flutter_test_config.dart` — a top-level left true by one
/// test would silence the notice for every file after it.
@visibleForTesting
bool debugDriveNoticeShown = false;

bool get _driveNoticeShown => debugDriveNoticeShown;
set _driveNoticeShown(bool value) => debugDriveNoticeShown = value;

/// The same flow, keeping the whole grant.
///
/// The project open and Save-As paths need the BOOKMARK as well as the path:
/// on Apple platforms a recent-projects entry is refused after relaunch
/// unless the app can produce the security-scoped token it was granted. Every
/// other caller only ever wants somewhere to write, so [pickFolderForUser]
/// stays the short spelling.
Future<FolderGrant?> pickFolderGrantForUser(
  BuildContext context, {
  String? initialDirectory,
}) async {
  // Android resolves the system tree back to a real path, and that probe
  // fails without the All-Files grant — which would surface as "this
  // location has no folder path" and send the user hunting for a different
  // folder when the folder was never the problem. Ask first.
  if (!await _storageGrantCleared(context)) {
    return null;
  }
  final grant = await FolderPicker.pick(initialDirectory: initialDirectory);
  if (!context.mounted) {
    return null;
  }
  return _spokenFor(context, grant, folderMode: true);
}

/// PICK-5: the same flow for FILES, keeping the grants whole.
///
/// Every caller here used to reach `file_selector` directly, and on both
/// mobile platforms that plugin COPIES the chosen file — into the iOS
/// sandbox (`.import` mode) or into `getCacheDir()` on Android — and hands
/// back the copy. An asset imported "by reference" therefore referenced a
/// temporary duplicate that the next cache sweep removes. Routing through
/// [FolderPicker.pickFiles] is what makes a reference reference the file
/// the user actually chose.
///
/// 🚨 The GRANT is the difference between a reference that survives a
/// relaunch and one that does not. `pickFiles` mints a security-scoped
/// bookmark on Apple platforms, and a path-only spelling of this call
/// threw it away at the door — so an asset imported by REFERENCE recorded
/// a path, and a recorded path on iOS or macOS is refused the next time
/// the app starts. Every piece of the machine existed; the answer simply
/// never reached the code that could write it down. ⚠️That spelling is
/// GONE (2026-09-10: nothing in the app called it, and a door that drops
/// the token is a door someone reaches for by accident) — there is one
/// file door and it hands back what it was granted, paths included.
///
/// Opening a PROJECT wants it for the same reason: a recent-projects entry
/// is refused after relaunch unless the app can produce the token it was
/// granted.
///
/// [acceptsDocuments] answers ONE question — can the caller work from a
/// file with no filesystem path (PICK-7, Drive on Android)? The media
/// import can: it reads one through a copy of its own and carries it
/// (유저 2026-09-27: 「안한것 다 해줘. 임포트 드라이브로 할때라던가」). A
/// relink cannot — a reference has to point at a file that is still there
/// next time — and is told what a Drive folder is told.
///
/// Empty when the user backed out or was told why they cannot use what
/// they chose.
Future<List<FolderGrant>> pickFileGrantsForUser(
  BuildContext context, {
  required List<String> supportedExtensions,
  bool allowMultiple = false,
  bool acceptsDocuments = false,
}) async {
  final grants = await _pickedFileGrants(
    context,
    allowMultiple: allowMultiple,
  );
  if (grants == null || !context.mounted) {
    return const [];
  }
  return _grantsTheCallerTakes(
    context,
    grants,
    supportedExtensions,
    acceptsDocuments: acceptsDocuments,
  );
}

/// The PROJECT door's pick (PICK-7): one file — and a file with no
/// filesystem path is taken too, as the provider document it is. A project
/// opens one through a working copy ([ProviderDocuments]).
///
/// Null when the user backed out or was told why they cannot use what
/// they chose.
Future<FolderGrant?> pickProjectGrantForUser(
  BuildContext context, {
  required List<String> supportedExtensions,
  String? initialDirectory,
}) async {
  final grants = await _pickedFileGrants(
    context,
    allowMultiple: false,
    initialDirectory: initialDirectory,
  );
  if (grants == null || !context.mounted) {
    return null;
  }
  final taken = await _grantsTheCallerTakes(
    context,
    grants,
    supportedExtensions,
    acceptsDocuments: true,
  );
  return taken.isEmpty ? null : taken.first;
}

/// The pick itself, behind the storage gate, with a failure that answers
/// for the whole batch said out loud — null when there is nothing to take.
Future<List<FolderGrant>?> _pickedFileGrants(
  BuildContext context, {
  required bool allowMultiple,
  String? initialDirectory,
}) async {
  // The same gate as the folder flow, for the same reason: Android resolves
  // the system document back to a real path, and that probe fails without
  // the All-Files grant.
  if (!await _storageGrantCleared(context)) {
    return null;
  }
  // 🚨★★★**NO TYPE FILTER — the dialog shows everything.** 유저 2026-08-29:
  // 「픽커는 어떤플랫폼이든 어떤 확장자던 선택할수 있게하고, 대응만
  // 지원안되는 확장자면 그 때 해당 파일 지원안된다고 안내창 띄우게」.
  //
  // ⛔`acceptedTypeGroups` used to come in from every caller, and it
  // answered TWO questions with one value: what the dialog SHOWS and what
  // the caller ACCEPTS. Those are different questions and the user has
  // separated them — a greyed-out file is a wall with no explanation,
  // while a notice can name the file and the formats.
  final grants = await FolderPicker.pickFiles(
    acceptedTypeGroups: const [],
    allowMultiple: allowMultiple,
    initialDirectory: initialDirectory,
  );
  if (!context.mounted) {
    return null;
  }
  // Never empty, and a failure arrives as ONE grant carrying the status —
  // so the first entry answers for the batch. A document answers for
  // itself ([_grantsTheCallerTakes]): a batch can hold real files beside it.
  if (grants.first.document == null &&
      await _spokenFor(context, grants.first) == null) {
    return null;
  }
  return grants;
}

/// What the caller takes of [grants]: the files of a kind it supports —
/// judged by NAME, a document's own, since its URI says nothing of what it
/// is — and the documents only where [acceptsDocuments]. What it turns away
/// is said once for the documents and once for the unsupported files.
///
/// A document taken is REMEMBERED here, by its name: every step after the
/// pick has only its URI, and the copy it is read from is named after it
/// ([ProviderDocuments.copyIn]) — an asset or a tab called by a URI's id
/// would be the result of a caller forgetting.
Future<List<FolderGrant>> _grantsTheCallerTakes(
  BuildContext context,
  List<FolderGrant> grants,
  List<String> supportedExtensions, {
  required bool acceptsDocuments,
}) async {
  final accepted = <FolderGrant>[];
  final refused = <String>[];
  var documentsRefused = false;
  for (final grant in grants) {
    final document = grant.document;
    if (document != null && !acceptsDocuments) {
      documentsRefused = true;
      continue;
    }
    final name = grant.path ?? document?.name;
    if (name == null) {
      continue;
    }
    if (fileIsSupported(name, supportedExtensions)) {
      if (document != null) {
        ProviderDocuments.remember(document);
      }
      accepted.add(grant);
    } else {
      refused.add(name);
    }
  }
  if (documentsRefused) {
    await _showNoFilesystemPathNotice(context);
    if (!context.mounted) {
      return const [];
    }
  }
  if (refused.isNotEmpty) {
    await noticeUnsupportedFiles(context, refused, supportedExtensions);
  }
  return accepted;
}

/// PICK-6: hands a finished file to the location the user picks — the
/// SCOPED platforms' Save As (iOS/Android have no save dialog, so the file
/// is staged first and the OS moves it).
///
/// ⚠️[sourcePath] is CONSUMED on success — the file is MOVED, not copied.
/// From then on the returned grant's path is the only copy.
///
/// The grant is returned whole rather than as a path, because Save As is
/// exactly the caller that needs the bookmark: it is what lets every later
/// save write there with no UI at all.
Future<FolderGrant?> exportFileForUser(
  BuildContext context, {
  required String sourcePath,
  String? suggestedName,
}) async {
  if (!await _storageGrantCleared(context)) {
    return null;
  }
  final grant = await FolderPicker.exportFile(
    sourcePath: sourcePath,
    suggestedName: suggestedName,
  );
  if (!context.mounted) {
    return null;
  }
  // A document is a place the bytes LANDED (PICK-7: poured in through the
  // provider), not a refusal.
  return _spokenFor(context, grant, acceptsDocuments: true);
}

/// What became of finished outputs handed to the user
/// ([handOverFilesForUser]).
enum HandOver {
  /// They stand where the user put them — moved there, or poured into the
  /// document a save window made. What was handed over is spent.
  placed,

  /// Another app was offered them (Android's share sheet) and reads them
  /// when it will, so what was handed over has to stay for this run.
  offered,

  /// The user backed out, or no window could open.
  declined,
}

/// The windows that can take finished outputs.
enum HandOverRoad {
  /// iOS's export picker: any number, files and folders alike, and the mode
  /// that reaches Google Drive (실측 2026-08-13 — folder mode does not).
  exportPicker,

  /// Android's save window: ONE file, anywhere a document can be made —
  /// Google Drive included.
  saveWindow,

  /// Android's share sheet: several files, offered to whichever app takes
  /// them (「드라이브에 저장」). No Android window places more than one.
  shareSheet,

  /// A folder window, and the outputs moved there — the desktops, where the
  /// folder window reaches every drive (Google Drive for desktop is one).
  folderWindow,
}

/// The road finished outputs take to the user on [operatingSystem] —
/// [oneFile] when they are a single file. Pure over the OS name so every
/// road can be pinned from the Windows workstation this is written on,
/// the seam [folderPickNeedsStorageGrant] uses for the same reason.
HandOverRoad handOverRoadFor(
  String operatingSystem, {
  required bool oneFile,
}) => switch (operatingSystem) {
  'ios' => HandOverRoad.exportPicker,
  'android' => oneFile ? HandOverRoad.saveWindow : HandOverRoad.shareSheet,
  _ => HandOverRoad.folderWindow,
};

/// Hands finished outputs — [paths], files or folders — to wherever the
/// user picks, AFTER they were made (drive-folder-windows-Q1, 유저
/// 2026-09-27: 「내보내기가 끝나면 드라이브로 넘긴다 — 파일 창을 거쳐」):
/// the one way an export reaches a place no folder window opens, Google
/// Drive above all. The road is [handOverRoadFor]'s.
///
/// The caller owns [paths] afterwards: gone when [HandOver.placed] (moved,
/// or poured and theirs to clear), still needed when [HandOver.offered].
Future<HandOver> handOverFilesForUser(
  BuildContext context, {
  required List<String> paths,
}) async {
  final oneFile =
      paths.length == 1 && FileSystemEntity.isFileSync(paths.single);
  switch (handOverRoadFor(_operatingSystem, oneFile: oneFile)) {
    case HandOverRoad.exportPicker:
      final grant = await FolderPicker.exportFiles(paths);
      if (!context.mounted) {
        return HandOver.declined;
      }
      return await _spokenFor(context, grant) == null
          ? HandOver.declined
          : HandOver.placed;
    case HandOverRoad.saveWindow:
      return await exportFileForUser(context, sourcePath: paths.single) ==
              null
          ? HandOver.declined
          : HandOver.placed;
    case HandOverRoad.shareSheet:
      return await FolderPicker.shareFiles(paths)
          ? HandOver.offered
          : HandOver.declined;
    case HandOverRoad.folderWindow:
      final folder = await pickFolderForUser(context);
      if (folder == null) {
        return HandOver.declined;
      }
      for (final path in paths) {
        moveIntoFolder(path, folder);
      }
      return HandOver.placed;
  }
}

/// The DESKTOP half of Save As: the system save dialog answers with a
/// path, nothing is created, and the save that follows writes it. See
/// [FolderPicker.pickSaveDestination] for why desktop stopped staging a
/// file and moving it.
Future<FolderGrant?> pickSaveDestinationForUser(
  BuildContext context, {
  required String suggestedName,
  String? initialDirectory,
  List<XTypeGroup> acceptedTypeGroups = const [],
}) async {
  final grant = await FolderPicker.pickSaveDestination(
    suggestedName: suggestedName,
    initialDirectory: initialDirectory,
    acceptedTypeGroups: acceptedTypeGroups,
  );
  if (!context.mounted) {
    return null;
  }
  return _spokenFor(context, grant);
}

/// Android alone has to clear a storage grant before a picker is worth
/// opening — everywhere else the OS either attaches no permission to a path
/// (Windows, Linux) or grants one with the pick itself (iOS, macOS).
///
/// Returns false when the caller should stop (the user was told why).
Future<bool> _storageGrantCleared(BuildContext context) async {
  if (!folderPickNeedsStorageGrant(_operatingSystem) ||
      await AppStorage.isAllFilesAccessGranted()) {
    return true;
  }
  if (!context.mounted) {
    return false;
  }
  await _showStorageGrantNotice(context);
  return false;
}

/// The one place a pick's outcome becomes words.
///
/// Three entry points used to spell this switch out themselves, which is
/// how a fourth (export) would have quietly grown a fourth dialect of "the
/// user backed out" — and the whole reason [FolderGrant] reports four
/// distinct outcomes is that three of them deserve to be said out loud.
Future<FolderGrant?> _spokenFor(
  BuildContext context,
  FolderGrant grant, {
  bool folderMode = false,
  bool acceptsDocuments = false,
}) async {
  switch (grant.status) {
    case FolderPickStatus.granted:
      return grant;
    case FolderPickStatus.providerDocument:
      if (acceptsDocuments) {
        return grant;
      }
      await _showNoFilesystemPathNotice(context);
      return null;
    case FolderPickStatus.cancelled:
      // Backing out is not an event — except in the one case the app cannot
      // see. Google Drive gives no folder to any folder window — Open is
      // dead in it on Apple, and on Android it is not listed at all — so a
      // person who went looking for it arrives here looking exactly like
      // someone who changed their mind ([folderPickCancelMayBeDrive]).
      //
      // Said ONCE per session, and only where it can happen: a real cancel
      // costs the user one line they can ignore, and the alternative is
      // never telling them at all.
      if (folderMode &&
          !_driveNoticeShown &&
          folderPickCancelMayBeDrive(_operatingSystem)) {
        _driveNoticeShown = true;
        await showAppNotice(
          context,
          windowKey: const ValueKey<String>('folder-pick-drive-notice'),
          title: AppText.strings.commonNotice,
          message: folderPickDriveNoticeFor(_operatingSystem),
        );
      }
      return null;
    case FolderPickStatus.noFilesystemPath:
      await _showNoFilesystemPathNotice(context);
      return null;
    case FolderPickStatus.unavailable:
      await showAppNotice(
        context,
        title: AppText.strings.commonNotice,
        message: AppText.strings.folderPickUnavailable,
      );
      return null;
  }
}

/// Only reachable on Android: iOS and macOS grant a real path through the
/// security scope, so a document provider there is a working folder rather
/// than a dead end. The wording is the sync-app guidance the in-app browser
/// used to carry in its footer, promoted to the moment it actually applies.
Future<void> _showNoFilesystemPathNotice(BuildContext context) {
  final strings = AppText.strings;
  return showDialog<void>(
    context: context,
    builder: (context) => AppConfirmDialog(
      windowKey: const ValueKey<String>('folder-no-path-dialog'),
      title: strings.folderNoPathTitle,
      titleIcon: Icons.cloud_off_outlined,
      message: strings.fileCloudNoticeOpen,
      actions: [
        AppWindowAction(
          label: strings.commonClose,
          actionKey: const ValueKey<String>('folder-no-path-close'),
          emphasis: AppWindowActionEmphasis.primary,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    ),
  );
}

/// The All-Files grant, which the in-app browser used to own. Deleting that
/// browser without moving this would have left Android users with a picker
/// that silently refuses every folder outside the app's own directory.
Future<void> _showStorageGrantNotice(BuildContext context) {
  final strings = AppText.strings;
  return showDialog<void>(
    context: context,
    builder: (context) => AppConfirmDialog(
      windowKey: const ValueKey<String>('storage-grant-dialog'),
      // `fileStorageOffNotice` is a two-clause sentence, authored as a BODY
      // — it was the browser's banner text. Using it as a heading and then
      // filling the body with the cloud-sync notice made the one dialog
      // whose job is "grant storage access" answer a different question.
      title: strings.folderStorageOffTitle,
      titleIcon: Icons.folder_off_outlined,
      message: strings.fileStorageOffNotice,
      actions: [
        AppWindowAction(
          label: strings.commonCancel,
          actionKey: const ValueKey<String>('storage-grant-cancel'),
          onPressed: () => Navigator.of(context).pop(),
        ),
        AppWindowAction(
          label: strings.fileOpenSettings,
          actionKey: const ValueKey<String>('storage-grant-settings'),
          emphasis: AppWindowActionEmphasis.primary,
          onPressed: () {
            Navigator.of(context).pop();
            unawaited(AppStorage.requestAllFilesAccess());
          },
        ),
      ],
    ),
  );
}

/// Hands the user a file called [suggestedName], written by [write], and
/// answers where it landed — or null when they cancelled or it failed.
///
/// 🚨★★★**THE SAME TWO HALVES AS SAVE AS, WITHOUT THE PROJECT.** Save As
/// grew both roads and then wrapped them in project-specific work — staging
/// the archive, adopting the placed path, minting a bookmark for later
/// saves. An export has none of that: the file leaves and is never written
/// to again.
///
/// So the roads are the same and the reasons are the ones already written
/// down: desktop has a save panel, so [pickSaveDestinationForUser] answers
/// with a path and this writes there. iOS has none — Apple never built one
/// — so the file is written into the app container FIRST and
/// [exportFileForUser] moves it where the picker says.
///
/// ⛔The container copy is deleted on the desktop road and MOVED on the
/// scoped one, so neither leaves a second copy behind (유저 08-27: 「사본
/// 남으면 진짜 용서안할게」) — the scoped half IS
/// [placeStagedFileForUser] now, shared with Save As, which is what the
/// heading above always claimed and this used to re-implement by hand.
///
/// ⚠️No bookmark comes back on purpose. A caller that wanted to write there
/// again would be a caller that should have used Save As.
///
/// 🚨**[write] takes a PATH, not bytes.** Some exports are hundreds of
/// megabytes — an hour of dialogue is 691MB of PCM — and a signature that
/// took a `Uint8List` would have re-created, in a brand new place, exactly
/// the whole-file allocation the carry and staging rounds spent themselves
/// removing. It answers false when it could not produce a real file, and
/// then nothing is handed over.
Future<String?> handWrittenFileToUser(
  BuildContext context, {
  required String suggestedName,
  required Future<bool> Function(String path) write,
  List<XTypeGroup> acceptedTypeGroups = const [],
}) async {
  if (!FolderPicker.grantsAreScoped) {
    final grant = await pickSaveDestinationForUser(
      context,
      suggestedName: suggestedName,
      acceptedTypeGroups: acceptedTypeGroups,
    );
    final picked = grant?.path;
    if (picked == null) {
      return null;
    }
    // Straight to the destination — the desktop law, and the reason Save
    // As stopped staging and moving (a cross-volume rename cannot work).
    if (await write(picked)) {
      return picked;
    }
    _discardQuietly(File(picked));
    return null;
  }
  final grant = await placeStagedFileForUser(
    context,
    suggestedName: suggestedName,
    write: write,
  );
  // A document (PICK-7) is where it landed too — by its URI, having no
  // path.
  return grant?.path ?? grant?.document?.uri;
}

/// THE SCOPED ROAD: writes a file called [suggestedName] into a staging
/// directory of its own via [write], hands it to the OS picker, and
/// answers the grant for wherever it landed — or null when [write] failed,
/// the window went away, or the user cancelled.
///
/// ⛔The staged copy is deleted on the desktop road and MOVED on this one,
/// so neither leaves a second copy behind (유저 08-27: 「사본 남으면 진짜
/// 용서안할게」).
///
/// 🚨**[write] takes a PATH, not bytes.** Some exports are hundreds of
/// megabytes — an hour of dialogue is 691MB of PCM — and a signature that
/// took a `Uint8List` would have re-created, in a brand new place, exactly
/// the whole-file allocation the carry and staging rounds spent themselves
/// removing. It answers false when it could not produce a real file, and
/// then nothing is handed over.
///
/// ⚠️The DESKTOP halves are deliberately NOT here. Save As desktop answers
/// with a path for the later atomic temp+rename save and asks the F-14
/// replace question; an export desktop writes immediately. Two laws, and a
/// flag choosing between them would be the invented kind.
///
/// [keepsSavingThere] answers ONE question — will the caller go on saving
/// into what it placed? Only Save As does. Where the picker answered with a
/// document that has no filesystem path (PICK-7, Drive on Android), the
/// staged file is poured into it and then either becomes that document's
/// working copy — moved, never copied, and answered as a path — or goes
/// with the staging folder like any other placed file.
Future<FolderGrant?> placeStagedFileForUser(
  BuildContext context, {
  required String suggestedName,
  required Future<bool> Function(String stagingPath) write,
  bool keepsSavingThere = false,
}) async {
  // Its own directory so the cleanup below cannot reach anything else.
  final stagingDirectory = Directory.systemTemp.createTempSync(
    'anicel_stage_',
  );
  final staged = File('${stagingDirectory.path}/$suggestedName');
  if (!await write(staged.path)) {
    _discardStaging(stagingDirectory);
    return null;
  }
  if (!context.mounted) {
    _discardStaging(stagingDirectory);
    return null;
  }
  final grant = await exportFileForUser(
    context,
    sourcePath: staged.path,
    suggestedName: suggestedName,
  );
  final document = grant?.document;
  final placed = keepsSavingThere && document != null
      ? FolderGrant.granted(
          path: ProviderDocuments.adoptAsWorkingCopy(document, staged.path),
          kind: GrantKind.file,
        )
      : grant;
  // On success the staged file was MOVED out and only the empty directory
  // is left; on cancel it is still in it — and poured into a document it
  // is still in it too, unless it became the working copy. Same cleanup.
  _discardStaging(stagingDirectory);
  return placed;
}

/// A leaked file must never fail an export — or a cancel, which is the path
/// that reaches it most often. The DESKTOP road's cleanup: it writes
/// straight to the destination, so what it sweeps is one file it created
/// there, never a directory.
void _discardQuietly(File file) {
  try {
    if (file.existsSync()) {
      file.deleteSync();
    }
  } on Object {
    // The container is the app's to sweep if this ever loses the race.
  }
}

/// Removes the staging directory. A leak here must never fail a save — or a
/// cancel, which is the path that reaches it most often.
void _discardStaging(Directory directory) {
  try {
    directory.deleteSync(recursive: true);
  } on Object {
    // Temp is the OS's to reclaim if this ever loses the race.
  }
}
