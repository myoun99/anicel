// Applies line-anchored edits from a JSON spec, in order, in one process.
//
// 🚨WHY A SPEC FILE AND NOT ARGUMENTS: on Windows `dart` is a batch wrapper
// (flutter/bin/dart.bat) that eats `^` and turns `\(` into `/(` on its way
// through argv, so a regex handed to a tool on the command line arrives
// altered and the tool reports the anchor missing. Every pattern therefore
// lives in the JSON and never touches a shell (decided 2026-09-02, after the
// same anchors failed twice through argv and worked from a file).
//
//   dart run tool/refactor/apply_spec.dart <spec.json>
//
// The spec is a JSON list of ops. Every pattern is a FULL-LINE regex (the
// tool wraps it in ^(?:...)$ after stripping CR). Paths are absolute or
// relative to the spec file's directory.
//   {"file": ..., "start": re, "end": re, "replacement": path | null,
//    "replaceText": text?, "occurrence": n?, "endOccurrence": n?,
//    "after": re?, "backLines": n?}
//       replace start..end (inclusive) with the file's lines, or with
//       "replaceText" split on \n, or delete when both are absent/null.
//       "occurrence"/"endOccurrence": the n-th match instead of the first.
//       "after": search only below the first line matching it.
//       "backLines": with no "start", start = end - backLines.
//   {"file": ..., "insertAfter": re, "text": line | "textFrom": path}
//   {"file": ..., "insertBefore": re, "text": line | "textFrom": path}
//   {"file": ..., "appendFrom": path}
// A deletion that leaves two blank lines at the seam keeps one. CRLF files
// stay CRLF. Exit 2 on the first missing anchor; later ops are not applied.
import 'dart:convert';
import 'dart:io';

void main(List<String> args) {
  final specFile = File(args[0]);
  final base = specFile.parent.path;
  final ops = (jsonDecode(specFile.readAsStringSync()) as List)
      .cast<Map<String, dynamic>>();
  String resolve(String p) =>
      p.startsWith('/') || RegExp('^[A-Za-z]:').hasMatch(p) ? p : '$base/$p';
  for (final op in ops) {
    final path = resolve(op['file'] as String);
    final file = File(path);
    final raw = file.readAsStringSync();
    final crlf = raw.contains('\r\n');
    final lines = raw.replaceAll('\r\n', '\n').split('\n');
    RegExp full(String p) => RegExp('^(?:$p)\$');
    var from = 0;
    if (op.containsKey('after')) {
      final after = full(op['after'] as String);
      final a = lines.indexWhere(after.hasMatch);
      if (a < 0) {
        stderr.writeln('AFTER MISSING ${after.pattern} in $path');
        exit(2);
      }
      from = a + 1;
    }
    List<String> out;
    if (op.containsKey('appendFrom')) {
      final extra = File(
        resolve(op['appendFrom'] as String),
      ).readAsStringSync().replaceAll('\r\n', '\n').split('\n');
      if (extra.isNotEmpty && extra.last.isEmpty) {
        extra.removeLast();
      }
      final body = lines.isNotEmpty && lines.last.isEmpty
          ? lines.sublist(0, lines.length - 1)
          : lines;
      out = [...body, ...extra, ''];
      stdout.writeln('APPENDED ${extra.length} line(s) to $path');
    } else if (op.containsKey('insertAfter') ||
        op.containsKey('insertBefore')) {
      final before = op.containsKey('insertBefore');
      final re = full((op[before ? 'insertBefore' : 'insertAfter']) as String);
      final i = lines.indexWhere(re.hasMatch, from);
      if (i < 0) {
        stderr.writeln('ANCHOR MISSING ${re.pattern} in $path');
        exit(2);
      }
      final at = before ? i : i + 1;
      final inserted = op.containsKey('textFrom')
          ? File(
              resolve(op['textFrom'] as String),
            ).readAsStringSync().replaceAll('\r', '').trimRight()
          : op['text'] as String;
      out = [...lines.sublist(0, at), inserted, ...lines.sublist(at)];
      stdout.writeln('INSERTED ${before ? 'before' : 'after'} $path:${i + 1}');
    } else {
      final end = full(op['end'] as String);
      int s;
      int e;
      if (op.containsKey('start')) {
        final start = full(op['start'] as String);
        final occurrence = (op['occurrence'] as int?) ?? 1;
        s = -1;
        var cursor = from;
        for (var n = 0; n < occurrence; n++) {
          s = lines.indexWhere(start.hasMatch, cursor);
          if (s < 0) {
            stderr.writeln(
              'START MISSING (occurrence $occurrence) ${start.pattern} in $path',
            );
            exit(2);
          }
          cursor = s + 1;
        }
        e = lines.indexWhere(end.hasMatch, s);
        final endOccurrence = (op['endOccurrence'] as int?) ?? 1;
        for (var n = 1; n < endOccurrence && e >= 0; n++) {
          e = lines.indexWhere(end.hasMatch, e + 1);
        }
      } else {
        e = lines.indexWhere(end.hasMatch, from);
        s = e - ((op['backLines'] as int?) ?? 0);
      }
      if (e < 0 || s < 0) {
        stderr.writeln(
          'END MISSING after line ${from + 1}: ${end.pattern} in $path',
        );
        exit(2);
      }
      final replacementPath = op['replacement'] as String?;
      final inline = op['replaceText'] as String?;
      final replacement = inline != null
          ? inline.split('\n')
          : replacementPath == null
          ? <String>[]
          : File(
              resolve(replacementPath),
            ).readAsStringSync().replaceAll('\r\n', '\n').split('\n');
      if (replacement.isNotEmpty && replacement.last.isEmpty) {
        replacement.removeLast();
      }
      out = [...lines.sublist(0, s), ...replacement, ...lines.sublist(e + 1)];
      if (replacement.isEmpty && s > 0 && s < out.length) {
        final beforeLine = out[s - 1].trim();
        final afterLine = out[s].trim();
        if (beforeLine.isEmpty && afterLine.isEmpty) {
          out.removeAt(s);
        } else if (beforeLine.isEmpty && afterLine == '}') {
          out.removeAt(s - 1);
        }
      }
      stdout.writeln(
        'REPLACED $path:${s + 1}-${e + 1} (${e - s + 1} lines) with ${replacement.length} line(s)',
      );
    }
    final text = out.join('\n');
    file.writeAsStringSync(crlf ? text.replaceAll('\n', '\r\n') : text);
  }
  stdout.writeln('SPEC OK (${ops.length} ops)');
}
