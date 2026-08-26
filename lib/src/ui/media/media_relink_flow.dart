import 'dart:isolate';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../models/media_identity.dart';
import '../../services/import/media_identity_reader.dart';
import '../../services/media/media_relink_matcher.dart';
import '../../services/persistence/anicel_incremental_writer.dart'
    show anicelCrc32Finish, anicelCrc32Start, anicelCrc32Update;
import '../dialogs/app_confirm_dialog.dart';
import '../dialogs/app_progress_dialog.dart';
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
  // The GRANT flavour, not the path shorthand: the paths this flow writes
  // into the project are read again at the NEXT launch, and on iOS/macOS a
  // recorded path without its security-scoped token is refused there. The
  // short spelling threw the token away, so relink — the feature that
  // exists to make broken references work again — healed them for exactly
  // one session and they died again at the next start.
  final regrant = await pickFolderGrantForUser(context);
  final folder = regrant?.path;
  if (folder == null || !context.mounted) {
    return;
  }
  final candidates = await filesUnder(folder);
  if (!context.mounted) {
    return;
  }
  // 🚨READ OFF THE UI ISOLATE, and behind a window that says so.
  //
  // Every candidate a tie survives to gets hashed, and a tie is decided by
  // SIZE — so each file opened here is exactly as big as the asset being
  // hunted, which on this app's material means a video or a
  // multi-hundred-megabyte plate. Doing that synchronously on the UI
  // isolate froze the app for as long as the disk took; over a cloud
  // folder it also HYDRATES every one of them, which is minutes of a
  // screen that does not repaint. The reads are the same reads — they
  // just happen where a frozen thread costs nothing.
  final wanted = [
    for (final path in missing) ?session.recordedMediaIdentity(path),
  ];
  final read = await runWithAppProgress<Map<String, MediaIdentity?>>(
    context: context,
    title: AppText.strings.mediaRelink,
    titleIcon: Icons.link_outlined,
    runningLabel: AppText.strings.mediaRelinkScanning,
    doneLabel: AppText.strings.mediaRelinkScanned,
    windowKey: const ValueKey<String>('relink-scan-progress'),
    task: (_) => Isolate.run(() => _identitiesOf(candidates, wanted)),
  );
  if (!context.mounted) {
    return;
  }
  final plan = planMediaRelink(
    missingPaths: missing,
    candidatePaths: candidates,
    recordedIdentity: session.recordedMediaIdentity,
    // Already read, and read once: the matcher gets a lookup rather than
    // a file handle.
    candidateIdentity: (candidate, _) => read[candidate],
  );
  final apply = await _confirm(
    context,
    found: plan.matched.length,
    total: missing.length,
  );
  if (apply != true) {
    return;
  }
  // The token first, the move second — the same order the import commit
  // uses, so the undoable path rewrite never exists without the grant
  // that makes it readable after a relaunch.
  session.rememberMediaGrants([regrant!]);
  session.relinkMediaAssets(plan.matched);
}

/// How many candidates this ISOLATE has read.
///
/// A static does not cross an isolate, which is exactly what makes it an
/// instrument: after a relink the UI isolate's copy is still zero, and it
/// stops being zero the moment somebody calls [_identitiesOf] here
/// instead of inside the worker. That is the whole property this file
/// exists to hold — the reads are the same reads, done where a frozen
/// thread costs nothing — and it is otherwise invisible to a test.
@visibleForTesting
int debugIdentityReadsOnThisIsolate = 0;

/// Every candidate's identity, read in one pass inside a worker.
///
/// The IO half of the content check, kept out of the matcher because the
/// matcher is pure. Two exits carry the whole cost story, and they are
/// the ones the lazy per-lookup version had — stated up front now
/// instead of discovered one candidate at a time:
///
/// - a **length** that differs from everything being hunted is a decisive
///   no from `stat` alone, so the file is never opened;
/// - a wanted asset with **no recorded CRC** has nothing a hash could
///   answer, so its size does not make anything worth reading.
///
/// What is left is the case that earns its read: same size, and something
/// to compare a hash against. Reading them all in one pass also drops the
/// memo the old shape needed — a folder of N ambiguous `A1.png`s used to
/// be read N times over, once per asking asset.
///
/// Top-level and taking only plain data, because it has to cross into an
/// isolate — which is also why the matcher is handed a finished map
/// rather than the closure it used to call.
Map<String, MediaIdentity?> _identitiesOf(
  List<String> candidates,
  List<MediaIdentity> wanted,
) {
  debugIdentityReadsOnThisIsolate += candidates.length;
  final hashableLengths = <int>{
    for (final identity in wanted)
      if (identity.crc32 != null) identity.lengthBytes,
  };
  final read = <String, MediaIdentity?>{};
  for (final candidate in candidates) {
    final onDisk = readMediaIdentity(candidate);
    if (onDisk == null || !hashableLengths.contains(onDisk.lengthBytes)) {
      read[candidate] = onDisk;
      continue;
    }
    try {
      read[candidate] = MediaIdentity(
        lengthBytes: onDisk.lengthBytes,
        crc32: _crc32OfFile(candidate),
      );
    } on Object {
      // Unreadable is not "different" — a permission error must not make
      // the matcher rule out a file that may be exactly the one.
      read[candidate] = onDisk;
    }
  }
  return read;
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
