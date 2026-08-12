import 'dart:io';

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
  if (folderPickNeedsStorageGrant(_operatingSystem) &&
      !await AppStorage.isAllFilesAccessGranted()) {
    if (!context.mounted) {
      return null;
    }
    await _showStorageGrantNotice(context);
    return null;
  }
  final grant = await FolderPicker.pick(initialDirectory: initialDirectory);
  if (!context.mounted) {
    return null;
  }
  switch (grant.status) {
    case FolderPickStatus.granted:
      return grant;
    case FolderPickStatus.cancelled:
      // Backing out is not an event. Say nothing.
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
