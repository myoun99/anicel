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
/// with that confusing one.
///
/// ↩️**It said 「The OS reaps its own temp」 until 2026-10-08, and Windows
/// does not**: one machine's temp held 696 folders of test runs older than
/// six hours. Every folder this is asked to remove is asked again when the
/// run ends ([whatTheRunLeftIn]), once nothing of the run is holding it.
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
  _askedToGo.add(_spelled(directory.path));
  try {
    directory.deleteSync(recursive: true);
  } on FileSystemException {
    // A leaked handle on Windows must not fail the suite.
  }
}

/// Every folder [deleteTempQuietly] was asked to remove — whether it went
/// or not, because one that went can come back ([whatTheRunLeftIn]).
final Set<String> _askedToGo = <String>{};

String _spelled(String path) => path.replaceAll(r'\', '/');

/// Points `Directory.systemTemp` at a folder of this run's own, and answers
/// that folder.
///
/// 🚨★★★**A TEST FILE IS ONE RUN, AND ITS TEMP IS ITS OWN** (2026-10-08).
/// `flutter test` runs every file in a process of its own, all of them in
/// ONE temp directory, and nothing in that directory said which run made
/// what: by the time anyone looked, one machine's temp held 1,135 folders
/// of test runs and 696 of them were older than six hours. Asked here, every
/// `Directory.systemTemp` of the run — asked by a test, a fixture, or the
/// product code a test drives — lands in one folder that belongs to this
/// run alone, so 「what did this file leave behind」 has an answer that no
/// other run's folders can blur ([whatTheRunLeftIn]).
///
/// ⚠️The folder is made at the first ask, not here: this runs while a file
/// is still DECLARING its tests, and a file whose tests are all skipped
/// (the benchmarks) never runs the `tearDownAll` that would remove it.
///
/// ⛔What it cannot reach: a worker isolate (`IOOverrides` is per isolate)
/// and the engine's own C++. Neither makes a temp folder of ours today.
Directory giveTheRunItsOwnTemp() {
  final own = Directory(
    '${Directory.systemTemp.path}${Platform.pathSeparator}'
    'qa_run_${pid}_${DateTime.now().microsecondsSinceEpoch}',
  );
  IOOverrides.global = _TheRunsTemp(own);
  return own;
}

final class _TheRunsTemp extends IOOverrides {
  _TheRunsTemp(this._own);

  final Directory _own;
  bool _made = false;

  @override
  Directory getSystemTempDirectory() {
    if (!_made) {
      _own.createSync(recursive: true);
      _made = true;
    }
    return _own;
  }
}

/// Whatever is still in [temp] when the run's own folders are gone, one
/// line each — empty when the run left nothing.
///
/// 🎯**Two answers, and only the second waits.** An entry nothing asked to
/// delete was left behind, full stop. One a test DID ask [deleteTempQuietly]
/// to remove is asked again now that every test is over, for as long as
/// [patience], and is left behind only if the run is STILL holding it — a
/// file opened and never closed. Either way it came to be there is a moment's
/// grip, not a folder left behind: the delete lost to a handle, or a write
/// still on its way made the folder again after it (a settings store saves
/// without waiting and makes its folder; the first runs of this check met
/// it in a different suite each time, 2026-10-08).
Future<List<String>> whatTheRunLeftIn(
  Directory temp, {
  Duration patience = const Duration(seconds: 3),
}) async {
  if (!temp.existsSync()) {
    return const [];
  }
  final until = DateTime.now().add(patience);
  final left = <String>[];
  for (final entity in temp.listSync(followLinks: false)) {
    final path = _spelled(entity.path);
    final name = path.substring(path.lastIndexOf('/') + 1);
    if (!_askedToGo.contains(path)) {
      left.add('$name — nothing deleted it${_holding(entity)}');
    } else if (!await _goneBefore(entity, until)) {
      left.add('$name — still held when the run ended${_holding(entity)}');
    }
  }
  return left..sort();
}

/// Deletes [entity], asking again while something holds it and [until] has
/// not passed.
Future<bool> _goneBefore(FileSystemEntity entity, DateTime until) async {
  while (true) {
    try {
      entity.deleteSync(recursive: true);
      return true;
    } on FileSystemException {
      if (DateTime.now().isAfter(until)) {
        return false;
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  }
}

/// A few of the files inside [entity], so the line names its maker.
String _holding(FileSystemEntity entity) {
  if (entity is! Directory) {
    return '';
  }
  final root = _spelled(entity.path);
  final List<String> inside;
  try {
    inside = [
      for (final file in entity.listSync(recursive: true, followLinks: false))
        if (file is File) _spelled(file.path).substring(root.length + 1),
    ]..sort();
  } on FileSystemException {
    // The line is the report; a folder that will not be listed still is one.
    return '';
  }
  if (inside.isEmpty) {
    return ' (empty)';
  }
  final shown = inside.take(3).join(', ');
  return inside.length > 3 ? ' ($shown, …)' : ' ($shown)';
}
