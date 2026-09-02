// Round 2's clean-code measurements as a library: parameter counts, body
// lengths and class lengths over a directory of Dart files, so the
// architecture warning ratchet and a report can read the same numbers.
import 'dart:io';

import 'package:analyzer/dart/analysis/features.dart';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/source/line_info.dart';

/// One measured declaration: where it is and what was measured.
class CleanCodeFinding {
  CleanCodeFinding(this.where, this.value);
  final String where;
  final int value;

  @override
  String toString() => '$value  $where';
}

/// The three counts the ratchet holds, plus the offenders behind each.
class CleanCodeScan {
  CleanCodeScan({
    required this.functions,
    required this.wideSignatures,
    required this.longBodies,
    required this.longClasses,
  });

  /// Every function, method and constructor body seen.
  final int functions;

  /// Functions and methods (constructors and `copyWith` excluded — a
  /// value object's field list is not an argument list) taking
  /// [wideSignatureAt] or more parameters.
  final List<CleanCodeFinding> wideSignatures;

  /// Bodies longer than [longBodyOver] lines.
  final List<CleanCodeFinding> longBodies;

  /// Classes longer than [longClassOver] lines.
  final List<CleanCodeFinding> longClasses;

  static const wideSignatureAt = 5;
  static const longBodyOver = 60;
  static const longClassOver = 600;
}

/// Scans every `.dart` file under [root] (`lib/dev/` excluded).
CleanCodeScan scanCleanCode(String root) {
  final files =
      Directory(root)
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));
  final visitor = _Visitor();
  for (final file in files) {
    final path = file.path.replaceAll('\\', '/');
    if (path.contains('/lib/dev/')) continue;
    final result = parseString(
      content: file.readAsStringSync(),
      path: path,
      featureSet: FeatureSet.latestLanguageVersion(),
      throwIfDiagnostics: false,
    );
    visitor.file = path.substring(path.indexOf('lib/'));
    visitor.lineInfo = result.lineInfo;
    result.unit.accept(visitor);
  }
  int byValue(CleanCodeFinding a, CleanCodeFinding b) =>
      b.value.compareTo(a.value);
  return CleanCodeScan(
    functions: visitor.functions,
    wideSignatures: visitor.wide..sort(byValue),
    longBodies: visitor.bodies..sort(byValue),
    longClasses: visitor.classes..sort(byValue),
  );
}

class _Visitor extends RecursiveAstVisitor<void> {
  late String file;
  late LineInfo lineInfo;
  int functions = 0;
  String? owner;
  final wide = <CleanCodeFinding>[];
  final bodies = <CleanCodeFinding>[];
  final classes = <CleanCodeFinding>[];

  int _line(int offset) => lineInfo.getLocation(offset).lineNumber;

  String _where(AstNode node, String name) =>
      '$file:${_line(node.offset)}  ${owner == null ? name : '$owner.$name'}';

  void _signature(AstNode node, String name, FormalParameterList? params) {
    if (params == null || name == 'copyWith') return;
    final count = params.parameters.length;
    if (count >= CleanCodeScan.wideSignatureAt) {
      wide.add(CleanCodeFinding(_where(node, name), count));
    }
  }

  void _body(AstNode node, String name, FunctionBody body) {
    functions += 1;
    final lines = _line(body.end) - _line(body.offset) + 1;
    if (lines > CleanCodeScan.longBodyOver) {
      bodies.add(CleanCodeFinding(_where(node, name), lines));
    }
  }

  @override
  void visitClassDeclaration(ClassDeclaration node) {
    owner = node.namePart.typeName.lexeme;
    final lines = _line(node.end) - _line(node.offset) + 1;
    if (lines > CleanCodeScan.longClassOver) {
      classes.add(
        CleanCodeFinding('$file:${_line(node.offset)}  $owner', lines),
      );
    }
    super.visitClassDeclaration(node);
    owner = null;
  }

  @override
  void visitMethodDeclaration(MethodDeclaration node) {
    final name = node.name.lexeme;
    _signature(node, name, node.parameters);
    _body(node, name, node.body);
    super.visitMethodDeclaration(node);
  }

  @override
  void visitFunctionDeclaration(FunctionDeclaration node) {
    if (node.parent is FunctionDeclarationStatement) {
      super.visitFunctionDeclaration(node);
      return;
    }
    final name = node.name.lexeme;
    _signature(node, name, node.functionExpression.parameters);
    _body(node, name, node.functionExpression.body);
    super.visitFunctionDeclaration(node);
  }

  @override
  void visitConstructorDeclaration(ConstructorDeclaration node) {
    _body(node, node.name?.lexeme ?? 'new', node.body);
    super.visitConstructorDeclaration(node);
  }
}
