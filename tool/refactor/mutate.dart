// Adversarial mutant, analyzer-driven so formatting cannot dodge it:
//   dart run mutate.dart <file> <Class> <method>
// A block-bodied method gets `return;` as its first statement (void) or its
// body replaced by `throw StateError('mutant')` (non-void); an expression
// body (`=> x`) becomes `{}` (void) or `=> throw StateError('mutant')`.
// Prints the mutated line so the change is visible. Restore with git or a
// backup copy — this script never restores.
import 'dart:io';

import 'package:analyzer/dart/analysis/features.dart';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';

void main(List<String> args) {
  final path = args[0];
  final className = args[1];
  final method = args[2];
  final raw = File(path).readAsStringSync();
  final crlf = raw.contains('\r\n');
  final src = crlf ? raw.replaceAll('\r\n', '\n') : raw;
  final unit = parseString(
    content: src,
    path: path,
    featureSet: FeatureSet.latestLanguageVersion(),
    throwIfDiagnostics: false,
  ).unit;
  final cls = unit.declarations
      .whereType<ClassDeclaration>()
      .firstWhere((c) => c.namePart.typeName.lexeme == className);
  final m = cls.body.members
      .whereType<MethodDeclaration>()
      .firstWhere((m) => m.name.lexeme == method);
  final isVoid = m.returnType?.toSource() == 'void';
  final body = m.body;
  late String out;
  if (body is BlockFunctionBody) {
    final open = body.block.leftBracket.end;
    final inject = isVoid ? ' return;' : " throw StateError('mutant');";
    out = src.replaceRange(open, open, inject);
  } else if (body is ExpressionFunctionBody) {
    final replacement = isVoid ? '{}' : "=> throw StateError('mutant');";
    out = src.replaceRange(body.offset, body.end, replacement);
  } else {
    stderr.writeln('unsupported body for $method');
    exit(3);
  }
  File(path).writeAsStringSync(crlf ? out.replaceAll('\n', '\r\n') : out);
  final line = src.substring(0, m.name.offset).split('\n').length;
  stdout.writeln('MUTATED $className.$method (${isVoid ? 'void' : 'non-void'}, '
      '${body is BlockFunctionBody ? 'block' : 'expression'} body) at $path:$line');
}
