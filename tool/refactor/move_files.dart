// Moves Dart files with `git mv` and rewrites every import/export that
// reaches them: relative paths under lib/test/tool, `package:anicel/` paths
// anywhere, and the moved files' own relative imports (resolved against
// where the file WAS, then re-relativised from where it now is). CRLF is
// kept. Round 4 of the audit moved 21 files with this — the editing helper
// cluster and the ledgered 「type in the wrong folder」 files — and every
// importer followed without a hand edit.
//
//   dart run tool/refactor/move_files.dart <repoRoot> lib/a/x.dart=lib/b/x.dart ...
//
// Paths are repo-relative and `=` separates old from new. A `part` file is
// not rewritten (none of the moved files had one); `show`/`hide` clauses
// survive because only the quoted path is replaced.
import 'dart:io';

void main(List<String> args) {
  final root = args[0].replaceAll('\\', '/');
  final moves = <String, String>{
    for (final pair in args.sublist(1)) pair.split('=')[0]: pair.split('=')[1],
  };
  for (final entry in moves.entries) {
    Directory('$root/${entry.value}').parent.createSync(recursive: true);
    final r = Process.runSync('git', [
      'mv',
      entry.key,
      entry.value,
    ], workingDirectory: root);
    if (r.exitCode != 0) {
      stderr.writeln('git mv failed for ${entry.key}: ${r.stderr}');
      exit(2);
    }
  }
  final movedNewToOld = {for (final e in moves.entries) e.value: e.key};
  var rewritten = 0;
  final directive = RegExp(
    r"^(\s*(?:import|export)\s+')([^']+)(')",
    multiLine: true,
  );
  for (final dir in ['lib', 'test', 'tool']) {
    final d = Directory('$root/$dir');
    if (!d.existsSync()) continue;
    for (final entity in d.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final path = entity.path.replaceAll('\\', '/');
      final rel = path.substring(root.length + 1);
      final raw = entity.readAsStringSync();
      final crlf = raw.contains('\r\n');
      final importerDir = _dirOf(rel);
      // A moved file resolves its relative imports against where it WAS.
      final originalRel = movedNewToOld[rel] ?? rel;
      final originalDir = _dirOf(originalRel);
      final src = raw.replaceAllMapped(directive, (m) {
        final target = m.group(2)!;
        String? resolved;
        if (target.startsWith('package:anicel/')) {
          resolved = 'lib/${target.substring('package:anicel/'.length)}';
        } else if (!target.contains(':')) {
          resolved = _normalise('$originalDir/$target');
        }
        if (resolved == null) return m.group(0)!;
        final destination = moves[resolved] ?? resolved;
        final unchangedTarget = destination == resolved;
        if (unchangedTarget && originalDir == importerDir) return m.group(0)!;
        final written = target.startsWith('package:')
            ? 'package:anicel/${destination.substring('lib/'.length)}'
            : _relative(from: importerDir, to: destination);
        return '${m.group(1)}$written${m.group(3)}';
      });
      if (src != raw) {
        entity.writeAsStringSync(
          crlf ? src.replaceAll('\r\n', '\n').replaceAll('\n', '\r\n') : src,
        );
        rewritten += 1;
      }
    }
  }
  stdout.writeln(
    'moved ${moves.length} files, rewrote directives in $rewritten files',
  );
}

String _dirOf(String path) {
  final i = path.lastIndexOf('/');
  return i < 0 ? '.' : path.substring(0, i);
}

String _normalise(String path) {
  final out = <String>[];
  for (final part in path.split('/')) {
    if (part == '..') {
      out.removeLast();
    } else if (part != '.' && part.isNotEmpty) {
      out.add(part);
    }
  }
  return out.join('/');
}

String _relative({required String from, required String to}) {
  final a = from.split('/');
  final b = to.split('/');
  var i = 0;
  while (i < a.length && i < b.length && a[i] == b[i]) {
    i++;
  }
  return [...List.filled(a.length - i, '..'), ...b.sublist(i)].join('/');
}
