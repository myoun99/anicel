// The audit's "nobody calls it" sweep (2026-09-03): every public top-level
// declaration under lib/ against every Dart file in lib/, test/ and tool/.
//
//   dart run tool/refactor/unreferenced.dart <repoRoot>
//
import 'dart:io';

import 'package:analyzer/dart/analysis/features.dart';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';

import 'app_sources.dart';

class Decl {
  Decl(this.file, this.kind, this.name);
  final String file;
  final String kind;
  final String name;
}

List<File> dartFiles(String dir) => Directory(dir)
    .listSync(recursive: true)
    .whereType<File>()
    .where((f) => f.path.endsWith('.dart'))
    .toList();

void main(List<String> args) {
  final root = args[0].replaceAll('\\', '/');
  final decls = <Decl>[];
  for (final path in appDartFiles('$root/lib')) {
    final unit = parseString(
      content: File(path).readAsStringSync(),
      path: path,
      featureSet: FeatureSet.latestLanguageVersion(),
      throwIfDiagnostics: false,
    ).unit;
    for (final d in unit.declarations) {
      final String name;
      String kind;
      switch (d) {
        case FunctionDeclaration():
          name = d.name.lexeme;
          kind = 'function';
        case ClassDeclaration():
          name = d.namePart.typeName.lexeme;
          kind = 'class';
        case MixinDeclaration():
          name = d.name.lexeme;
          kind = 'mixin';
        case EnumDeclaration():
          name = d.namePart.typeName.lexeme;
          kind = 'enum';
        case ExtensionDeclaration():
          // An extension's members are used without naming it.
          continue;
        case TypeAlias():
          name = d.name.lexeme;
          kind = 'typedef';
        case TopLevelVariableDeclaration():
          for (final v in d.variables.variables) {
            final n = v.name.lexeme;
            if (!n.startsWith('_')) decls.add(Decl(path, 'variable', n));
          }
          continue;
        default:
          continue;
      }
      if (name.startsWith('_')) continue;
      decls.add(Decl(path, kind, name));
    }
  }
  // Every Dart file's text, once.
  final texts = <String, String>{};
  for (final dir in ['lib', 'test', 'tool']) {
    for (final f in dartFiles('$root/$dir')) {
      texts[f.path.replaceAll('\\', '/')] = f.readAsStringSync();
    }
  }
  final unreferenced = <Decl>[];
  final seamOnly = <Decl>[];
  for (final d in decls) {
    final re = RegExp('\\b${RegExp.escape(d.name)}\\b');
    // Its own file counts too — every hit past the declaration itself.
    if (re.allMatches(texts[d.file] ?? '').length > 1) continue;
    var inLib = false;
    var inOther = false;
    for (final entry in texts.entries) {
      if (entry.key == d.file) continue;
      if (!re.hasMatch(entry.value)) continue;
      if (entry.key.contains('/lib/')) {
        inLib = true;
        break;
      }
      inOther = true;
    }
    if (inLib) continue;
    (inOther ? seamOnly : unreferenced).add(d);
  }
  String rel(String p) => p.substring(p.indexOf('/lib/') + 1);
  stdout.writeln('public top-level declarations: ${decls.length}');
  stdout.writeln('\nUNREFERENCED ANYWHERE (${unreferenced.length}):');
  for (final d in unreferenced) {
    stdout.writeln('  ${d.kind.padRight(9)} ${d.name}  — ${rel(d.file)}');
  }
  stdout.writeln('\nREFERENCED BY test/ OR tool/ ONLY (${seamOnly.length}):');
  for (final d in seamOnly) {
    stdout.writeln('  ${d.kind.padRight(9)} ${d.name}  — ${rel(d.file)}');
  }
}
