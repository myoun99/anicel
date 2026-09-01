// Does any test notice when this file stops doing what it says?
//
// 🚨★★★THIS EDITS REAL SOURCE FILES. Read the safety section before changing
// anything in it.
//
// `tool/audit_rank.dart` answers the cheap half — 117 lib files are named by
// no test at all, and those need no run to be judged. This answers the other
// half for the 692 that ARE named: it turns a line off with
// `tool/mutations.dart` and runs the tests that name the file.
//
//   KILLED     a test went red. The behaviour is pinned.
//   SURVIVED   nobody noticed. ⚠️A QUESTION, not a verdict — the line may be
//              unreachable, or genuinely not worth pinning.
//   UNBUILT    the edit did not compile, so the suite says nothing about it.
//              ⛔NEVER counted as killed: a compile error turns everything
//              red and looks exactly like success.
//   TIMEOUT    the suite stopped finishing. Probably a loop the mutation
//              made infinite; recorded rather than guessed at.
//   UNNAMED    no test names this file, so there was nothing to run.
//
// ## Safety
//
// Three rules, and the first two are why this can be pointed at `lib/`:
//
//   1. IT REFUSES A DIRTY FILE. If the target has uncommitted changes, a
//      crash mid-run would take them with it. `git status` decides, not a
//      flag.
//   2. IT RESTORES IN `finally`, AND THEN CHECKS. Writing the bytes back is
//      not the same as having written them back; the run exits non-zero and
//      says the path out loud if the file does not match what it saved.
//   3. ONE MUTATION AT A TIME. The file is whole between runs, so an
//      interrupt at any point leaves at most one edit to undo, and rule 2
//      has already undone it.
//
// ## Usage
//
//   dart run tool/mutation_run.dart lib/src/services/x.dart
//   dart run tool/mutation_run.dart lib/src/services/x.dart --sample 6
//   dart run tool/mutation_run.dart --out results.jsonl lib/a.dart lib/b.dart
//   dart run tool/mutation_run.dart --plan lib/a.dart   # say what it would do
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'import_graph.dart';
import 'mutations.dart';

/// How long one suite may take before the run is called a timeout.
///
/// ⚠️Generous on purpose: a cold `flutter test` on this repo pays a compiler
/// start, and calling that a timeout would report the toolchain as a finding.
const _suiteTimeout = Duration(minutes: 8);

/// What one mutation run concluded.
enum Verdict { killed, survived, unbuilt, timeout, unnamed }

/// What a finished `flutter test` says about the mutation it ran under.
///
/// ⛔PURE, so a test can drive it. The distinction that matters is between a
/// red suite and a suite that never ran: `flutter test` reports 「Failed to
/// load」 when a file will not compile, and a caller that only looked at the
/// exit code would file every compile error as a kill.
Verdict classifyRun({required int exitCode, required String output}) {
  if (output.contains('Failed to load') ||
      output.contains('Compilation failed')) {
    return Verdict.unbuilt;
  }
  return exitCode == 0 ? Verdict.survived : Verdict.killed;
}

/// Whether `dart analyze`'s output says the mutated file will not build.
///
/// 🚨★★★THIS IS NOT AN OPTIMISATION, IT IS THE FIX FOR A WRONG PREMISE.
///
/// `tool/mutations.dart` claimed every operator it emits compiles, because
/// the swaps are interchangeable to the type system. 🧪The first real file
/// measured 3 UNBUILT out of 6, and the reason is Dart's flow analysis rather
/// than the operators:
///
///   · `blockStart == null` → `!= null` inverts which branch promotes, so
///     three lines down an `int?` lands in an `int`.
///   · `x != null && f(x)` → `||` drops the promotion the right operand was
///     relying on.
///
/// Null checks are everywhere in null-safe Dart, so this is common rather
/// than a corner. Running a whole suite to discover it costs ~40s a time;
/// `dart analyze` on the one file costs ~3s and says the same thing.
///
/// ⚠️A clean analyze does NOT promise the suite builds — a single file is
/// analysed in isolation. It is a cheap NO, not an expensive YES, so
/// [classifyRun] still watches for 「Failed to load」 afterwards.
///
/// ⛔Matches ` error - ` and not the exit code: `dart analyze` exits non-zero
/// for infos and warnings too, and a file carrying a pre-existing lint would
/// otherwise report every mutation as unbuilt.
bool analyzeReportsError(String output) => output.contains(' error - ');

/// Up to [count] mutations spread across [all], rather than the first [count].
///
/// ⚠️The first N are all in the same function — usually the first one in the
/// file — and would report that function's coverage as the file's. Even
/// spacing is deterministic, which a random sample would not be: a run has to
/// be repeatable to be worth arguing with.
List<Mutation> sampleOf(List<Mutation> all, int count) {
  if (all.length <= count || count <= 0) return all;
  final step = all.length / count;
  return [for (var i = 0; i < count; i += 1) all[(i * step).floor()]];
}

Future<void> main(List<String> args) async {
  final sample = int.tryParse(_flag(args, '--sample') ?? '') ?? 5;
  final outPath = _flag(args, '--out');
  final planOnly = args.contains('--plan');
  final targets = args
      .where((a) => a.endsWith('.dart') && !a.startsWith('--'))
      .toList();

  if (targets.isEmpty) {
    stderr.writeln('usage: mutation_run.dart <lib/...dart> [more] '
        '[--sample N] [--out results.jsonl] [--plan]');
    exit(2);
  }

  final graph = buildImportGraph(roots: ['lib', 'test']);
  final namersOf = <String, List<String>>{};
  for (final entry in graph.entries) {
    if (!entry.key.startsWith('test/')) continue;
    for (final target in entry.value) {
      namersOf.putIfAbsent(target, () => []).add(entry.key);
    }
  }

  final sink = outPath == null
      ? null
      : (File(outPath)..createSync(recursive: true)).openWrite(
          mode: FileMode.append,
        );

  var killed = 0, survived = 0, unbuilt = 0, timedOut = 0;
  try {
    for (final target in targets) {
      final namers = (namersOf[target] ?? const <String>[]).toList()..sort();
      final file = File(target);
      if (!file.existsSync()) {
        stderr.writeln('⛔no such file: $target');
        exit(2);
      }
      if (namers.isEmpty) {
        _say(target, 'UNNAMED — no test names this file, nothing to run');
        sink?.writeln(jsonEncode({
          'file': target,
          'verdict': Verdict.unnamed.name,
          'namers': 0,
        }));
        continue;
      }

      final original = file.readAsStringSync();
      final candidates = sampleOf(mutationsIn(original), sample);
      _say(target, '${namers.length} namer(s), ${candidates.length} mutation(s)'
          '${planOnly ? ' — plan only' : ''}');
      for (final namer in namers) {
        _say(target, '  namer: $namer');
      }
      if (planOnly) {
        for (final m in candidates) {
          _say(target, '  would try: $m');
        }
        continue;
      }

      _refuseIfDirty(target);

      for (final m in candidates) {
        final verdict = await _runOne(file, original, m, namers);
        switch (verdict) {
          case Verdict.killed:
            killed += 1;
          case Verdict.survived:
            survived += 1;
          case Verdict.unbuilt:
            unbuilt += 1;
          case Verdict.timeout:
            timedOut += 1;
          case Verdict.unnamed:
            break;
        }
        _say(target, '  ${verdict.name.toUpperCase().padRight(9)} $m');
        sink?.writeln(jsonEncode({
          'file': target,
          'line': m.line,
          'kind': m.kind,
          'was': m.was,
          'became': m.replacement,
          'verdict': verdict.name,
          'namers': namers.length,
        }));
      }
    }
  } finally {
    await sink?.flush();
    await sink?.close();
  }

  stdout.writeln('');
  stdout.writeln('killed $killed · survived $survived · unbuilt $unbuilt · '
      'timeout $timedOut');
  // ⚠️Exit 0 whatever the verdicts. A surviving mutation is a FINDING, not a
  // failure of this run — a non-zero exit would make a report indistinguishable
  // from a crash to whatever called it.
}

void _say(String target, String message) {
  stdout.writeln('[${target.split('/').last}] $message');
}

String? _flag(List<String> args, String name) {
  final i = args.indexOf(name);
  return i < 0 || i + 1 >= args.length ? null : args[i + 1];
}

/// ⛔Refuses to mutate a file with uncommitted changes. See Safety #1.
void _refuseIfDirty(String path) {
  final status = Process.runSync('git', ['status', '--porcelain', '--', path]);
  final out = (status.stdout as String).trim();
  if (out.isNotEmpty) {
    stderr.writeln('⛔$path has uncommitted changes:\n  $out\n'
        '  This tool rewrites the file and puts it back. Commit or revert '
        'first — a crash mid-run would take your edits with it.');
    exit(3);
  }
}

/// Applies [m], runs [namers], and puts the file back whatever happens.
Future<Verdict> _runOne(
  File file,
  String original,
  Mutation m,
  List<String> namers,
) async {
  file.writeAsStringSync(m.applyTo(original));
  try {
    // The cheap NO first — see [analyzeReportsError].
    final pre = Process.runSync(
      'dart',
      ['analyze', file.path],
      runInShell: true,
    );
    if (analyzeReportsError('${pre.stdout}${pre.stderr}')) {
      return Verdict.unbuilt;
    }
    return await _runNamers(namers);
  } finally {
    file.writeAsStringSync(original);
    // Safety #2: having written is not having written.
    final now = file.readAsStringSync();
    if (now != original) {
      stderr.writeln('🚨COULD NOT RESTORE ${file.path} — it is still '
          'mutated. Fix it before anything else runs.');
      exit(4);
    }
  }
}

/// Runs [namers] one at a time, cheapest first, stopping at the first red.
///
/// 🧪MEASURED, AND IT IS THE WHOLE COST OF A CAMPAIGN. One informative
/// mutation on `onion_skin_plan.dart` took ~2.7 minutes because every
/// `flutter test` pays a cold compiler start; at that rate the 692 named
/// files would be ~155 hours at five mutations each.
///
/// Two things follow, and only one of them is code:
///   · A KILL needs one red suite, not all of them. Stopping there turns the
///     common case from N runs into 1.
///   · A widget test costs several times what a service test costs, so the
///     order is 「anything that is not `test/ui/`」 first. ⚠️A heuristic, and
///     a wrong guess costs time rather than correctness — the verdict is the
///     same either way.
///
/// ⛔A SURVIVOR STILL PAYS FULL PRICE, by definition: 「nobody noticed」 is
/// only true once every namer has failed to notice. That is the answer the
/// audit most wants, and it is the expensive one.
Future<Verdict> _runNamers(List<String> namers) async {
  final ordered = namers.toList()
    ..sort((a, b) {
      final aUi = a.startsWith('test/ui/') ? 1 : 0;
      final bUi = b.startsWith('test/ui/') ? 1 : 0;
      return aUi != bUi ? aUi - bUi : a.compareTo(b);
    });
  var worst = Verdict.survived;
  for (final namer in ordered) {
    final verdict = await _runSuite([namer]);
    if (verdict == Verdict.killed) return Verdict.killed;
    // An unbuilt or timed-out suite is not a survivor; keep it and carry on,
    // because another namer may still go red and answer the question.
    if (verdict != Verdict.survived) worst = verdict;
  }
  return worst;
}

Future<Verdict> _runSuite(List<String> namers) async {
  final process = await Process.start(
    'flutter',
    ['test', ...namers],
    runInShell: true,
  );
  final buffer = StringBuffer();
  final done = Completer<int>();
  unawaited(process.stdout
      .transform(utf8.decoder)
      .forEach(buffer.write)
      .catchError((_) {}));
  unawaited(process.stderr
      .transform(utf8.decoder)
      .forEach(buffer.write)
      .catchError((_) {}));
  unawaited(process.exitCode.then((code) {
    if (!done.isCompleted) done.complete(code);
  }));

  Timer(_suiteTimeout, () {
    if (done.isCompleted) return;
    process.kill(ProcessSignal.sigkill);
    done.complete(-1);
  });

  final code = await done.future;
  if (code == -1) return Verdict.timeout;
  return classifyRun(exitCode: code, output: buffer.toString());
}
