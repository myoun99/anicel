import 'dart:io';

import 'package:flutter/material.dart';

import '../../services/media/media_relink_matcher.dart';
import '../dialogs/app_confirm_dialog.dart';
import '../dialogs/folder_pick_flow.dart';
import '../editor_session_manager.dart';
import '../text/app_strings.dart';
import '../widgets/app_window.dart';

/// RELINK-2: "find them all under this folder".
///
/// The banner counts what is missing; this is the verb behind its button.
/// Point it at the folder the work moved to and it relinks everything it
/// can be SURE about, in one undo step.
///
/// The preview is not decoration. A folder that matches almost nothing is
/// exactly how "I picked the wrong folder" looks, and the moment to say so
/// is before the pool is rewritten rather than after.
Future<void> runMediaRelinkFlow(
  BuildContext context,
  EditorSessionManager session,
) async {
  // Read the pool, not the cache: a removed asset can linger in the cache
  // until the next refresh, and hunting for a file nobody references any
  // more would pad the "of N" with ghosts.
  final missing = <String>[
    for (final asset in session.mediaAssets)
      if (session.missingMediaPaths.contains(asset.path)) asset.path,
  ];
  if (missing.isEmpty) {
    return;
  }
  final folder = await pickFolderForUser(context);
  if (folder == null || !context.mounted) {
    return;
  }
  final candidates = await filesUnder(folder);
  if (!context.mounted) {
    return;
  }
  final plan = planMediaRelink(
    missingPaths: missing,
    candidatePaths: candidates,
  );
  final apply = await _confirm(
    context,
    found: plan.matched.length,
    total: missing.length,
  );
  if (apply != true) {
    return;
  }
  session.relinkMediaAssets(plan.matched);
}

/// Every file under [root], recursively.
///
/// Recursive because a production folder splits by cut — the drawing being
/// hunted is almost never at the top. ASYNC rather than `listSync` because
/// a shot folder holds thousands of files and this runs on the UI isolate.
///
/// A folder that vanishes mid-walk yields what was found so far: a partial
/// candidate list makes for a smaller match, which the preview reports
/// honestly, and that beats failing the whole pass.
@visibleForTesting
Future<List<String>> filesUnder(String root) async {
  final paths = <String>[];
  try {
    await for (final entity in Directory(
      root,
    ).list(recursive: true, followLinks: false)) {
      if (entity is File) {
        paths.add(entity.path);
      }
    }
  } on Object {
    // Permission, a race with the user, a vanished mount.
  }
  return paths;
}

Future<bool?> _confirm(
  BuildContext context, {
  required int found,
  required int total,
}) {
  final strings = AppText.strings;
  return showDialog<bool>(
    context: context,
    builder: (context) => AppConfirmDialog(
      windowKey: const ValueKey<String>('media-relink-preview'),
      title: strings.mediaFindInFolder,
      titleIcon: Icons.link_outlined,
      message: strings.mediaRelinkFound
          .replaceAll('{m}', '$found')
          .replaceAll('{n}', '$total'),
      actions: [
        AppWindowAction(
          label: strings.commonCancel,
          actionKey: const ValueKey<String>('media-relink-cancel'),
          onPressed: () => Navigator.of(context).pop(false),
        ),
        // Nothing to apply is not an error and not a question — the window
        // still says what it found, but offering "Relink" for zero files
        // would be offering a no-op.
        if (found > 0)
          AppWindowAction(
            label: strings.mediaRelink,
            actionKey: const ValueKey<String>('media-relink-apply'),
            emphasis: AppWindowActionEmphasis.primary,
            onPressed: () => Navigator.of(context).pop(true),
          ),
      ],
    ),
  );
}
