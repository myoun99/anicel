import 'dart:io';

import 'package:anicel/src/services/persistence/session_scratch.dart';
import 'package:flutter_test/flutter_test.dart';

/// The run's room made to refuse every park until the test ends: a FILE
/// where its folder has to go, so nothing can be created under it — the
/// shape of a revoked scope or a full disk. Answers that file; deleting it
/// opens the room again.
///
/// ⚠️The folder's delete is the PREMISE, not a cleanup: a delete that failed
/// quietly would be a refusal that silently did not happen
/// (`a_temp_dir_cleans_itself_up_in_one_place_test`).
///
/// 🚨One premise, asked three times — a cooled cel, a wall's cut, a copy laid
/// to another size (card
/// `a-kept-cel-copied-to-another-canvas-size-is-rewritten-on-the-ui-thread`,
/// 2026-11-14) — so it is said here, once.
File refuseTheRoom() {
  final room = Directory(SessionScratch.stagedFolder());
  if (room.existsSync()) {
    room.deleteSync(recursive: true);
  }
  final blocker = File(SessionScratch.stagedFolder())
    ..createSync(recursive: true)
    ..writeAsBytesSync(const [0]);
  addTearDown(() {
    if (blocker.existsSync()) {
      blocker.deleteSync();
    }
  });
  return blocker;
}
