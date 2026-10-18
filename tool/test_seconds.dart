// How long each test file took on this machine — so a run hands its longest
// files out first.
//
// 🆕2026-10-18 (card tests-crowd-the-machine). A batch ends when its slowest
// file ends, and `flutter test` starts files in the order it is given them.
// Measured on the main PC: 60 timeline files at four at a time took 205s
// while their run times summed to 697s — 174s of work per slot — because
// the 75s file started near the end and ran alone. Handed out longest
// first, the long ones run beside the many short ones and the tail goes.
// That is the classic longest-processing-time-first rule; what it needs is
// the time, and a run leaves it in a JSON report beside its console
// (`--file-reporter`), so the console a session reads is unchanged.
//
// WHERE: the machine's own cache, beside `tool/run.sh`'s exes —
// `%LOCALAPPDATA%\anicel` on Windows, `~/.cache/anicel` elsewhere. ⛔The
// same place spelled twice (here and in run.sh): change both or neither.
// Per machine on purpose: a file's time is this machine's, and every
// worktree on it shares the one record.
import 'dart:convert';

/// This machine's folder for what the tools keep between runs, or null if
/// the environment names none.
String? machineCacheFolder(Map<String, String> environment) {
  final local = environment['LOCALAPPDATA'];
  if (local != null && local.isNotEmpty) {
    return '${local.replaceAll('\\', '/')}/anicel';
  }
  final xdg = environment['XDG_CACHE_HOME'];
  if (xdg != null && xdg.isNotEmpty) return '$xdg/anicel';
  final home = environment['HOME'];
  return home == null || home.isEmpty ? null : '$home/.cache/anicel';
}

/// `<path>\t<milliseconds>` per line. A line that is not one is skipped —
/// two runs that wrote at once leave, at worst, a time to measure again.
Map<String, int> readTimes(String text) => {
  for (final line in const LineSplitter().convert(text))
    if (line.split('\t') case [final path, final ms]
        when path.isNotEmpty && int.tryParse(ms) != null)
      path: int.parse(ms),
};

String writeTimes(Map<String, int> times) => [
  for (final path in (times.keys.toList()..sort())) '$path\t${times[path]}\n',
].join();

/// Each test file's time in a `json` report: from its loading to its last
/// test, keyed by its path from the repository's root ([root]) with `/`.
Map<String, int> fileTimes(String report, {required String root}) {
  final prefix = '${root.replaceAll('\\', '/')}/'.toLowerCase();
  final path = <int, String>{};
  final first = <int, int>{};
  final last = <int, int>{};
  final suiteOf = <int, int>{};
  for (final line in const LineSplitter().convert(report)) {
    final Object? event;
    try {
      event = jsonDecode(line);
    } on FormatException {
      continue;
    }
    if (event is! Map<String, dynamic>) continue;
    final time = event['time'];
    if (time is! int) continue;
    switch (event['type']) {
      case 'suite':
        final suite = event['suite'] as Map<String, dynamic>;
        final p = (suite['path'] as String?)?.replaceAll('\\', '/');
        if (p != null) path[suite['id'] as int] = p;
      case 'testStart':
        final test = event['test'] as Map<String, dynamic>;
        final suite = test['suiteID'] as int;
        suiteOf[test['id'] as int] = suite;
        first.putIfAbsent(suite, () => time);
      case 'testDone':
        final suite = suiteOf[event['testID'] as int];
        if (suite != null) last[suite] = time;
    }
  }
  return {
    for (final MapEntry(key: suite, value: p) in path.entries)
      if (first[suite] != null && last[suite] != null)
        (p.toLowerCase().startsWith(prefix) ? p.substring(prefix.length) : p):
            last[suite]! - first[suite]!,
  };
}

/// [known] with [measured] laid over it: a file measured again keeps the
/// mean of the two, so one slow run on a crowded machine moves it halfway.
Map<String, int> merged(Map<String, int> known, Map<String, int> measured) => {
  ...known,
  for (final MapEntry(key: path, value: ms) in measured.entries)
    path: known[path] == null ? ms : (known[path]! + ms) ~/ 2,
};

/// [files] with the longest first by [known]. A file never timed goes ahead
/// of all of them: it may be the longest, and running it early times it.
/// Equal times keep their order, so the same record gives the same run.
List<String> longestFirst(List<String> files, Map<String, int> known) {
  final order = [for (var i = 0; i < files.length; i++) i];
  int rank(String file) => known[file] ?? 1 << 30;
  order.sort((a, b) {
    final byTime = rank(files[b]).compareTo(rank(files[a]));
    return byTime != 0 ? byTime : a.compareTo(b);
  });
  return [for (final i in order) files[i]];
}
