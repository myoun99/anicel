import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../../services/persistence/app_documents.dart';
import '../../services/persistence/folder_grant.dart';
import '../text/app_strings.dart';
import '../widgets/app_window.dart';
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
}) async =>
    (await pickFolderGrantForUser(context, initialDirectory: initialDirectory))
        ?.path;

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

/// PICK-6: whether a CANCELLED folder pick might really be Google Drive's
/// greyed-out Open.
///
/// 🚨Apple only — and **not for the reason `referencesExpireForPlatform`
/// names the same two platforms.** There it is the sandbox; here it is that
/// Android answers `noFilesystemPath` for a Drive tree and raises its own
/// notice, while on Apple the Open button is simply DEAD: the delegate
/// never fires, so the app receives a plain cancel and cannot tell the two
/// apart.
///
/// Same tuple, different question — borrowing the other predicate would
/// leave this silently wrong the day either answer moves.
bool folderPickCancelMayBeDrive(String operatingSystem) =>
    operatingSystem == 'ios' || operatingSystem == 'macos';

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

/// PICK-5: the same flow for FILES.
///
/// Every caller here used to reach `file_selector` directly, and on both
/// mobile platforms that plugin COPIES the chosen file — into the iOS
/// sandbox (`.import` mode) or into `getCacheDir()` on Android — and hands
/// back the copy. An asset imported "by reference" therefore referenced a
/// temporary duplicate that the next cache sweep removes. Routing through
/// [FolderPicker.pickFiles] is what makes a reference reference the file
/// the user actually chose.
///
/// Returns the chosen paths; empty when the user backed out or was told why
/// they cannot use what they chose.
///
/// The short spelling, for the callers that only need somewhere to read
/// from. Anything that RECORDS what it picked wants
/// [pickFileGrantsForUser] instead — see there.
Future<List<String>> pickFilesForUser(
  BuildContext context, {
  required List<XTypeGroup> acceptedTypeGroups,
  bool allowMultiple = false,
}) async => [
  for (final grant in await pickFileGrantsForUser(
    context,
    acceptedTypeGroups: acceptedTypeGroups,
    allowMultiple: allowMultiple,
  ))
    ?grant.path,
];

/// The same flow, keeping the grants whole.
///
/// 🚨 This is the difference between a reference that survives a relaunch
/// and one that does not. `pickFiles` mints a security-scoped bookmark on
/// Apple platforms and the short spelling above threw it away at the door
/// — so an asset imported by REFERENCE recorded a path, and a recorded
/// path on iOS or macOS is refused the next time the app starts. Every
/// piece of the machine existed; the answer simply never reached the code
/// that could write it down.
///
/// Opening a PROJECT wants it for the same reason: a recent-projects entry
/// is refused after relaunch unless the app can produce the token it was
/// granted.
///
/// Empty when the user backed out or was told why they cannot use what
/// they chose.
Future<List<FolderGrant>> pickFileGrantsForUser(
  BuildContext context, {
  required List<XTypeGroup> acceptedTypeGroups,
  bool allowMultiple = false,
  String? initialDirectory,
}) async {
  // The same gate as the folder flow, for the same reason: Android resolves
  // the system document back to a real path, and that probe fails without
  // the All-Files grant.
  if (!await _storageGrantCleared(context)) {
    return const [];
  }
  final grants = await FolderPicker.pickFiles(
    acceptedTypeGroups: acceptedTypeGroups,
    allowMultiple: allowMultiple,
    initialDirectory: initialDirectory,
  );
  if (!context.mounted) {
    return const [];
  }
  // Never empty, and a failure arrives as ONE grant carrying the status —
  // so the first entry answers for the batch.
  if (await _spokenFor(context, grants.first) == null) {
    return const [];
  }
  return grants;
}

/// PICK-6: hands a finished file to the location the user picks.
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
  String? initialDirectory,
}) async {
  if (!await _storageGrantCleared(context)) {
    return null;
  }
  final grant = await FolderPicker.exportFile(
    sourcePath: sourcePath,
    suggestedName: suggestedName,
    initialDirectory: initialDirectory,
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
}) async {
  switch (grant.status) {
    case FolderPickStatus.granted:
      return grant;
    case FolderPickStatus.cancelled:
      // Backing out is not an event — except in the one case the app cannot
      // see. Google Drive greys out Open in FOLDER mode, and a greyed-out
      // button never calls the delegate, so a user who walked into Drive and
      // found Open dead arrives here looking exactly like someone who
      // changed their mind.
      //
      // Said ONCE per session, and only where it can happen: a real cancel
      // costs the user one line they can ignore, and the alternative is
      // never telling them at all.
      if (folderMode &&
          !_driveNoticeShown &&
          folderPickCancelMayBeDrive(_operatingSystem)) {
        _driveNoticeShown = true;
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(
            key: const ValueKey<String>('folder-pick-drive-notice'),
            content: Text(AppText.strings.folderPickDriveNotice),
          ),
        );
      }
      return null;
    case FolderPickStatus.noFilesystemPath:
      await _showNoFilesystemPathNotice(context);
      return null;
    case FolderPickStatus.unavailable:
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text(AppText.strings.folderPickUnavailable)),
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
            AppStorage.requestAllFilesAccess();
          },
        ),
      ],
    ),
  );
}
