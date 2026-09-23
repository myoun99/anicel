import 'dart:io';

/// Removes [directory] and lets the OS keep it if it will not let go.
///
/// 🚨**CLEANING UP IS NOT A TEST'S RESULT (2026-09-16).** Windows holds a
/// handle a moment longer than the last write — the store's own file, the
/// indexer, a scanner — and a `tearDown` that deleted the directory outright
/// turned that grip into a red test: an affected batch failed on
/// `PathAccessException … 別のプロセスが使用中です` (errno 32) in a test
/// that had nothing to do with the round, while other lanes were gating the
/// same machine. A test says nothing about the product by failing to remove
/// a folder, and a teardown that throws REPLACES the test's real failure
/// with that confusing one. The OS reaps its own temp.
///
/// ⛔This is not 「지우지 않는다」: the delete is still attempted, at the same
/// moment, and succeeds virtually always. Only the FAILURE is swallowed.
///
/// ↩️**Six suites retried the delete for 200 ms and then FAILED the test**
/// (「the brush-tip library's pattern」, for a fire-and-forget persist still
/// holding the file), and 75 wrapped it in a catch of their own. Both were
/// answers to the question this body answers — the retry the opposite
/// one — and were folded in here on 2026-09-23.
///
/// 🎯**One body, two seats.** A cleanup registered with `addTearDown` — from
/// a test body or a `setUp` alike — needs `deleteAfterSessionEnds` in
/// `project_scratch_folder.dart` instead: `addTearDown` callbacks run before
/// the corpus-wide release in `flutter_test_config.dart`, so that one ends
/// the session's hold on the project file first, and then calls this.
/// Nothing else in `test/` may write the delete by hand, and nothing may
/// call this from an `addTearDown`; the ratchet beside this file holds both.
void deleteTempQuietly(Directory directory) {
  try {
    directory.deleteSync(recursive: true);
  } on FileSystemException {
    // A leaked handle on Windows must not fail the suite.
  }
}
