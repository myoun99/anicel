// HOIST LOCAL FUNCTIONS — Fowler's "Replace Method with Method Object", the
// half a tool can do: every function declared directly inside one method's
// body becomes a private method of the class, and the locals those
// functions captured become fields the method assigns.
//
//   dart run tool/refactor/hoist_local_functions.dart <file> <Class> <method>
//       [local=Type ...] [--dry]
//
// `local=Type` names a captured local and the field type it becomes:
// `Rect` → `late final Rect _local;`, `Rect!` → `late Rect _local;` (the
// method reassigns it), `Rect?` → `Rect? _local;` (a memo). The local's
// declaration inside the method turns into an assignment (or, for a memo,
// disappears), and every use — in the method and in the hoisted functions —
// is renamed to the field.
//
// What it does NOT do: decide which locals are captured (read the method;
// the analyzer flags any you missed as undefined names), or move the method
// itself out of its class — `collaborator_split.dart` does that, and the
// two compose: split first, hoist inside the part.
//
// Hoisted names get a `_` prefix; labels (`name:`) and member accesses
// (`x.name`) are left alone. Doc comments travel with their function.
import 'dart:io';

import 'package:analyzer/dart/analysis/features.dart';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';

void main(List<String> rawArgs) {
  // `@file` splices the file's non-empty lines in as arguments: a field
  // type like `Map<TileCoord, BitmapTile?>?` cannot survive the Windows
  // `dart.bat` wrapper (`<` and `>` are redirections to cmd.exe).
  final args = <String>[
    for (final arg in rawArgs)
      if (arg.startsWith('@'))
        ...File(arg.substring(1))
            .readAsLinesSync()
            .map((line) => line.trim())
            .where((line) => line.isNotEmpty)
      else
        arg,
  ];
  final dry = args.contains('--dry');
  final positional = args.where((a) => !a.startsWith('--')).toList();
  if (positional.length < 3) {
    stderr.writeln(
      'usage: hoist_local_functions.dart <file> <Class> <method> '
      '[local=Type ...] [--dry]',
    );
    exit(2);
  }
  final path = positional[0];
  final className = positional[1];
  final methodName = positional[2];
  final fieldSpecs = <String, String>{
    for (final spec in positional.skip(3))
      spec.split('=')[0]: spec.split('=')[1],
  };

  final source = File(path).readAsStringSync();
  final unit = parseString(
    content: source,
    path: path,
    featureSet: FeatureSet.latestLanguageVersion(),
  ).unit;
  ClassDeclaration? cls;
  for (final d in unit.declarations) {
    if (d is ClassDeclaration && d.namePart.typeName.lexeme == className) {
      cls = d;
    }
  }
  if (cls == null) {
    stderr.writeln('no class $className in $path');
    exit(1);
  }
  MethodDeclaration? method;
  for (final m in cls.body.members) {
    if (m is MethodDeclaration && m.name.lexeme == methodName) {
      method = m;
    }
  }
  if (method == null) {
    stderr.writeln('no method $methodName in $className');
    exit(1);
  }
  final body = method.body;
  if (body is! BlockFunctionBody) {
    stderr.writeln('$methodName has no block body');
    exit(1);
  }
  final locals = body.block.statements
      .whereType<FunctionDeclarationStatement>()
      .toList();
  // No local functions but captured locals named: the method is being
  // prepared for a range cut (its locals become fields first, so the
  // ranges moved out afterwards have nothing to capture).
  if (locals.isEmpty && fieldSpecs.isEmpty) {
    stderr.writeln('$methodName declares no local functions');
    exit(1);
  }

  // The rename map: hoisted functions and captured locals both gain `_`.
  final renames = <String, String>{
    for (final f in locals)
      f.functionDeclaration.name.lexeme:
          '_${f.functionDeclaration.name.lexeme}',
    for (final name in fieldSpecs.keys) name: '_$name',
  };

  // Cut the local functions out of the method text, remembering each one's
  // source (with its doc comment) for the class-level copy.
  final methodStart = method.offset;
  final methodEnd = method.end;
  var methodText = source.substring(methodStart, methodEnd);
  final hoisted = <String>[];
  for (final f in locals.reversed) {
    final doc = f.functionDeclaration.documentationComment;
    final from = (doc?.offset ?? f.offset) - methodStart;
    final to = f.end - methodStart;
    final lineStart = methodText.lastIndexOf('\n', from) + 1;
    var lineEnd = methodText.indexOf('\n', to);
    lineEnd = lineEnd < 0 ? methodText.length : lineEnd + 1;
    // Swallow ONE blank line after the function so the body does not keep
    // a double gap where the declaration was.
    if (methodText.startsWith('\n', lineEnd)) {
      lineEnd += 1;
    }
    hoisted.insert(0, _dedent(methodText.substring(lineStart, lineEnd)));
    methodText =
        methodText.substring(0, lineStart) + methodText.substring(lineEnd);
  }

  methodText = _rename(methodText, renames);
  final fieldLines = <String>[];
  for (final entry in fieldSpecs.entries) {
    final name = '_${entry.key}';
    final type = entry.value;
    final memoDeclaration = RegExp(
      '^[ \\t]*${RegExp.escape(type)} $name;[ \\t]*\\n',
      multiLine: true,
    );
    if (type.endsWith('?') && methodText.contains(memoDeclaration)) {
      fieldLines.add('  $type $name;');
      // A memo: its declaration line goes; the field is the memo now.
      // (`Rect?` escaped — a bare `?` is a quantifier, and the first run
      // left the local behind.)
      methodText = methodText.replaceAll(memoDeclaration, '');
    } else if (type.endsWith('?')) {
      // A nullable local assigned once (`final x = maybe;`): a late final
      // nullable field, assigned where the local was.
      fieldLines.add('  late final $type $name;');
      methodText = methodText.replaceAll(
        // `=(?=\s)`: the initializer may start on the next line.
        RegExp('\\b(?:var|final) $name =(?=\\s)'),
        '$name = ',
      );
    } else if (type.endsWith('!')) {
      fieldLines.add('  late ${type.substring(0, type.length - 1)} $name;');
      methodText = methodText.replaceAll(
        // `=(?=\s)`: the initializer may start on the next line.
        RegExp('\\b(?:var|final) $name =(?=\\s)'),
        '$name = ',
      );
    } else {
      fieldLines.add('  late final $type $name;');
      methodText = methodText.replaceAll(
        // `=(?=\s)`: the initializer may start on the next line.
        RegExp('\\b(?:var|final) $name =(?=\\s)'),
        '$name = ',
      );
    }
  }
  final hoistedText = hoisted.map((h) => _rename(h, renames)).join('\n');

  final fieldsBlock = fieldLines.isEmpty ? '' : '${fieldLines.join('\n')}\n\n';
  final rebuilt =
      '${source.substring(0, methodStart)}$fieldsBlock$methodText\n\n'
      '$hoistedText${source.substring(methodEnd).replaceFirst(RegExp(r'^\n*'), '')}';

  stdout.writeln(
    'hoist $className.$methodName: ${locals.length} local functions → '
    'methods (${locals.map((f) => f.functionDeclaration.name.lexeme).join(', ')}); '
    '${fieldSpecs.length} captured locals → fields',
  );
  if (dry) {
    stdout.writeln('--dry: ${rebuilt.split('\n').length} lines would result');
    return;
  }
  File(path).writeAsStringSync(rebuilt);
  stdout.writeln('OK $path written');
}

/// Removes two columns of indentation — a method-body statement sits two
/// deeper than a class member — from every line that has them.
String _dedent(String text) => text
    .split('\n')
    .map((line) => line.startsWith('  ') ? line.substring(2) : line)
    .join('\n');

/// Renames whole identifiers, leaving labels (`name:`) and member accesses
/// (`.name`) untouched.
String _rename(String text, Map<String, String> renames) {
  var out = text;
  for (final entry in renames.entries) {
    out = out.replaceAllMapped(
      // `$name` in an interpolation IS a use and is renamed with the rest;
      // only a member access (`x.name`, but not a spread `...name`) or a
      // longer identifier is left alone. A label is `name:` with the colon
      // attached — `a ? name : b` is a use (the first cut of the
      // layer-stack paint lost two ternaries to a looser guard, and the
      // bottom bar's `...joined(` to a guard that took a spread for a dot).
      RegExp('(?<!\\w)(?<!\\.(?<!\\.\\.))${entry.key}\\b(?!:(?!:))'),
      (_) => entry.value,
    );
  }
  return out;
}
