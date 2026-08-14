import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../models/media_identity.dart';
import '../../services/import/media_identity_reader.dart';
import '../../services/media/media_relink_matcher.dart';
import '../../services/persistence/anicel_incremental_writer.dart'
    show anicelCrc32Finish, anicelCrc32Start, anicelCrc32Update;
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
  final read = <String, MediaIdentity?>{};
  final plan = planMediaRelink(
    missingPaths: missing,
    candidatePaths: candidates,
    recordedIdentity: session.recordedMediaIdentity,
    candidateIdentity: (candidate, wanted) =>
        readCandidateIdentity(candidate, wanted, memo: read),
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

/// What the file at [candidate] is, doing the least work that can still
/// change the answer about [wanted].
///
/// The IO half of the content check, kept out here because the matcher is
/// pure. Two early exits carry the whole cost story:
///
/// - a **length** that already differs is a decisive no from `stat` alone,
///   so the file is never opened;
/// - a [wanted] with **no recorded CRC** means reading these bytes could
///   only ever produce `unknown`, so reading them buys nothing.
///
/// What is left is the case that earns its read: same size, and something
/// to compare a hash against.
MediaIdentity? readCandidateIdentity(
  String candidate,
  MediaIdentity wanted, {
  Map<String, MediaIdentity?>? memo,
}) {
  final onDisk = readMediaIdentity(candidate);
  if (onDisk == null ||
      onDisk.lengthBytes != wanted.lengthBytes ||
      wanted.crc32 == null) {
    return onDisk;
  }
  // Every missing asset with the same file name reaches the same
  // candidates, so without this a folder holding N ambiguous `A1.png`s
  // reads each of them N times. Keyed by path alone because a file's hash
  // does not depend on who is asking.
  final cached = memo?[candidate];
  if (cached != null) {
    return cached;
  }
  try {
    final found = MediaIdentity(
      lengthBytes: onDisk.lengthBytes,
      crc32: _crc32OfFile(candidate),
    );
    memo?[candidate] = found;
    return found;
  } on Object {
    // Unreadable is not "different" — a permission error must not make the
    // matcher rule a file out that may be exactly the one.
    return onDisk;
  }
}

/// CRC-32 of the file at [path], a chunk at a time.
///
/// ⚠️ Chunked rather than `readAsBytesSync`. The candidates here are the
/// ones a tie survived to, and a tie is decided by SIZE — so every file
/// this opens is exactly as big as the asset being hunted, which on this
/// app's material means a video or a multi-hundred-megabyte plate. Pulling
/// one whole into memory to hash it is the allocation that gets the app
/// killed on the devices this project refuses to abandon.
int _crc32OfFile(String path) {
  final handle = File(path).openSync();
  try {
    var running = anicelCrc32Start;
    final buffer = Uint8List(256 * 1024);
    while (true) {
      final read = handle.readIntoSync(buffer);
      if (read <= 0) {
        break;
      }
      running = anicelCrc32Update(running, buffer, read);
    }
    return anicelCrc32Finish(running);
  } finally {
    handle.closeSync();
  }
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
