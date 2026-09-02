// Deletes named TOP-LEVEL declarations from a Dart file, doc comment and
// all, by the AST — the sweep's other half (2026-09-03).
//
//   dart run tool/refactor/delete_decl.dart <file> <name> [<name> ...]
import 'dart:io';

import 'package:analyzer/dart/analysis/features.dart';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';

void main(List<String> args) {
  final file = File(args[0]);
  final names = args.sublist(1).toSet();
  var src = file.readAsStringSync();
  final unit = parseString(
    content: src,
    featureSet: FeatureSet.latestLanguageVersion(),
    throwIfDiagnostics: false,
  ).unit;
  final spans = <(int, int, String)>[];
  for (final d in unit.declarations) {
    final name = switch (d) {
      FunctionDeclaration() => d.name.lexeme,
      ClassDeclaration() => d.namePart.typeName.lexeme,
      TopLevelVariableDeclaration() => d.variables.variables.single.name.lexeme,
      _ => null,
    };
    if (name == null || !names.contains(name)) continue;
    final start = d.documentationComment?.offset ?? d.offset;
    spans.add((start, d.end, name));
  }
  final missing = names.difference(spans.map((s) => s.$3).toSet());
  if (missing.isNotEmpty) {
    stderr.writeln('not found: ${missing.join(', ')}');
    exit(1);
  }
  spans.sort((a, b) => b.$1.compareTo(a.$1));
  for (final (start, end, name) in spans) {
    // Take the trailing line break and one blank line before, so no double
    // blank is left behind.
    var from = start;
    var to = end;
    while (to < src.length && (src[to] == '\r' || src[to] == '\n')) {
      to++;
    }
    var back = from;
    var breaks = 0;
    while (back > 0 && (src[back - 1] == '\r' || src[back - 1] == '\n')) {
      if (src[back - 1] == '\n') breaks++;
      if (breaks > 1) break;
      back--;
    }
    if (breaks > 1) from = back;
    src = src.replaceRange(from, to, breaks > 1 ? (src.contains('\r\n') ? '\r\n' : '\n') : '');
    stdout.writeln('deleted $name');
  }
  file.writeAsStringSync(src);
}
