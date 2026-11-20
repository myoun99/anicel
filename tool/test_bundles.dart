// A crowd batch's files run as bundles: entries that each import up to
// [kFilesPerBundle] test files and run each one's `main` as a group named by
// its path — one compile and one tester start for ten files.
//
// 🗣️유저 2026-11-20, card the-wide-check-takes-five-hours-Q3 「a 묶는다 —
// 혼자 서야 하는 파일만 따로」. `flutter test` compiles every file into a
// program of its own (92–108 MB of kernel, copied), starts a tester for it,
// loads and warms it. 🧪200 light files at eight suites (11-20): the
// compile 153 · 149 s → 27 · 29 s, each test 0.83–0.90 s → 0.46–0.52 s.
//
// ⚠️WHAT IT COSTS IS ISOLATION. The files of an entry share one isolate and
// one binding, and every file's `main` runs — declares its tests — before
// any test of any of them. A file that starts a binding of its own cannot
// stand beside another ([whyAlone]); a file that leans on what one before
// it left, or leaves what one after it trips on, goes red there and green
// alone — `affected_tests` runs every bundled red again alone, and names
// those ([kRunsAlone] is where the census puts them).

import 'source_brackets.dart';
import 'test_seconds.dart' show SuiteRun, isBundleEntry;

/// The most files one entry runs.
const kFilesPerBundle = 10;

/// The test config beside a batch's entries ([kBundleFolder]), from
/// [toRoot] — the way from their folder up to the checkout's root.
/// `flutter test` finds a file's config by walking up from it, so an entry
/// is wrapped as a test file is: the same `testExecutable`, once an entry.
String bundleConfigSource(String toRoot) =>
    "export '$toRoot/test/flutter_test_config.dart';\n";

/// The files that lose what they read in company — red in a bundle, green
/// alone — each with what it leans on. They run as files of their own.
/// 🧭The census fills it (전 파일을 묶어 정순 · 역순 두 번 + 파일별 대조,
/// 관제 11-20); a file leaves it when its test stops leaning.
const Map<String, String> kRunsAlone = {};

/// The test bindings flutter_test starts itself; any other is a file's own.
const _sharedBindings = {
  'TestWidgetsFlutterBinding',
  'AutomatedTestWidgetsFlutterBinding',
  'WidgetsFlutterBinding',
};

/// Why the test file [source] cannot share an isolate with others — or
/// null when it can.
String? whyAlone(String source) {
  final code = codeOnly(source);
  if (RegExp(r'\bclass\s+\w+\s+extends\s+\w*Binding\b').hasMatch(code)) {
    return 'it declares a test binding of its own, and an isolate holds one';
  }
  for (final start in RegExp(
    r'\b(\w+Binding)\.ensureInitialized\(',
  ).allMatches(code)) {
    if (!_sharedBindings.contains(start[1])) {
      return 'it starts ${start[1]}, and an isolate holds one binding';
    }
  }
  if (RegExp(r'\bmain\s*\([^)]*\)\s*async\b').hasMatch(code) ||
      RegExp(r'\bFuture<\w+>\s+main\s*\(').hasMatch(code)) {
    return 'its main is async, and a group is declared at once';
  }
  if (!RegExp(r'(^|\s)(void\s+)?main\s*\(\s*\)', multiLine: true)
      .hasMatch(code)) {
    return 'it has no main a group can call';
  }
  return null;
}

/// [source]'s library annotations, as written — what stands before its
/// `library;` — each on one line.
List<String> libraryAnnotations(String source) {
  final code = withoutComments(source);
  final found = <String>[];
  var at = 0;
  while (true) {
    while (at < code.length && code[at].trim().isEmpty) {
      at++;
    }
    if (at >= code.length || code[at] != '@') return found;
    final name = RegExp(r'[\w.]+').matchAsPrefix(code, at + 1);
    if (name == null) return found;
    final start = at;
    at = name.end;
    if (code.startsWith('(', at)) {
      final close = matchingClose(code, at);
      if (close == null) return found;
      at = close + 1;
    }
    found.add(code.substring(start, at).replaceAll(RegExp(r'\s+'), ' '));
  }
}

/// A batch's [files] — longest first — as entries of at most
/// [kFilesPerBundle], dealt in turn so each starts on a heavy file and the
/// entries weigh about alike, a file only with files of its own library
/// annotations ([entrySource] makes them the entry's); and the files that
/// cannot share ([whyAlone], [kRunsAlone]) as they are. [reversed] runs
/// each entry's files the other way round — the census's second order.
({List<List<String>> bundles, List<String> alone}) bundlesOf(
  List<String> files, {
  required String Function(String path) read,
  bool reversed = false,
}) {
  final alone = <String>[];
  final alike = <String, List<String>>{};
  for (final file in files) {
    final source = read(file);
    if (kRunsAlone.containsKey(file) || whyAlone(source) != null) {
      alone.add(file);
    } else {
      (alike[libraryAnnotations(source).join('\n')] ??= []).add(file);
    }
  }
  return (
    bundles: [
      for (final shared in alike.values)
        for (final bundle in _dealt(shared))
          [if (reversed) ...bundle.reversed else ...bundle],
    ],
    alone: alone,
  );
}

/// [files] dealt in turn into as few entries of [kFilesPerBundle] as hold
/// them.
List<List<String>> _dealt(List<String> files) {
  final count = (files.length / kFilesPerBundle).ceil();
  final bundles = [for (var i = 0; i < count; i++) <String>[]];
  for (var i = 0; i < files.length; i++) {
    bundles[i % count].add(files[i]);
  }
  return bundles;
}

/// The source of an entry that runs [files] — paths from the checkout's
/// root, of one set of library annotations ([bundlesOf]) — each as a group
/// named by its path, from a folder [toRoot] below the root. [read] gives
/// each file's source; its annotations are the entry's.
///
/// 🪦THE ENTRY'S, NOT THE GROUP'S (census 11-20): under flutter_test a
/// group takes a skip and a retry and nothing else (`test_compat.dart`).
/// Each group was handed its file's time limit and platform, and 74
/// entries did not compile — their files ran alone, and were read as
/// having lost their isolation.
String entrySource(
  List<String> files,
  String Function(String path) read, {
  required String toRoot,
}) {
  final source = StringBuffer()
    ..writeln('// Written by tool/affected_tests.dart for one batch, and '
        'gone when it ends.');
  final annotations = files.isEmpty
      ? const <String>[]
      : libraryAnnotations(read(files.first));
  if (annotations.isNotEmpty) {
    source
      ..writeAll(annotations, '\n')
      ..writeln()
      ..writeln('library;');
  }
  source.writeln("import 'package:flutter_test/flutter_test.dart';");
  for (var i = 0; i < files.length; i++) {
    source.writeln("import '$toRoot/${files[i]}' as f$i;");
  }
  source.writeln('void main() {');
  for (var i = 0; i < files.length; i++) {
    source.writeln("  group('${files[i]}', f$i.main);");
  }
  source.writeln('}');
  return source.toString();
}

/// What each file of a bundled batch did, out of its report's [runs]
/// (`suiteRuns`) and the files each entry ran ([entries], by the entry's
/// path from the root). An entry's own run says what its files' groups
/// cannot: a red one — it failed to load, or its own tests failed — makes
/// every file of it red, to be run again alone; one that never ended leaves
/// what its files did unknown, but a red; a green one stands for a file
/// that declared no test, as a file of its own would.
List<SuiteRun> runsOfFiles(
  List<SuiteRun> runs,
  Map<String, List<String>> entries,
) {
  final byPath = {
    for (final run in runs)
      if (!isBundleEntry(run.path)) run.path: run,
  };
  for (final entry in runs.where((run) => isBundleEntry(run.path))) {
    for (final file in entries[entry.path] ?? const <String>[]) {
      final own = byPath[file];
      byPath[file] = switch (entry.green) {
        false => (path: file, ms: own?.ms, green: false),
        null => (
          path: file,
          ms: own?.ms,
          green: own?.green == false ? false : null,
        ),
        true => own ?? (path: file, ms: null, green: true),
      };
    }
  }
  return byPath.values.toList();
}
