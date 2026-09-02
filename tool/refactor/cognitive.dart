// ignore_for_file: avoid_print
// The audit's cognitive-complexity meter (2026-09-02): the warning line is
// 15 (CLAUDE.md), and this is what measures it.
//
//   dart run tool/refactor/cognitive.dart lib            # the summary
//   dart run tool/refactor/cognitive.dart lib --list 15  # every function above 15
//
// under a directory — so the ceiling's NUMBER comes out of the real code.
//
//   dart --packages=<pkg>/.dart_tool/package_config.json cognitive.dart lib
//
// Cognitive, as implemented here:
//   +1 for if / else-if / else / ternary / switch (whole) / loop / catch /
//      collection-if / collection-for, and for each SEQUENCE of && or ||
//      (a run of the same operator is one increment);
//   + the nesting level, for every one of those that nests (else-if and
//     else take +1 without the nesting add-on, per the spec);
//   nesting rises inside if/else/ternary/switch/loops/catch AND inside a
//   lambda or local function body.
// McCabe, as tool/code_map.dart counts it: 1 + if/for/while/do/case/catch/
//   ?: / && / || / ?? / collection if / collection for.
import 'dart:io';

import 'package:analyzer/dart/analysis/features.dart';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/token.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/source/line_info.dart';

class Fn {
  Fn(this.file, this.name, this.mccabe, this.cognitive, this.hasSwitch,
      this.line, this.endLine);
  final int line;
  final int endLine;
  final String file;
  final String name;
  final int mccabe;
  final int cognitive;
  final bool hasSwitch;
}

class _Cognitive extends RecursiveAstVisitor<void> {
  int score = 0;
  int nesting = 0;
  bool hasSwitch = false;

  void _nest(void Function() body) {
    nesting++;
    body();
    nesting--;
  }

  @override
  void visitIfStatement(IfStatement node) {
    score += 1 + nesting;
    node.expression.accept(this);
    _nest(() => node.thenStatement.accept(this));
    final elseS = node.elseStatement;
    if (elseS == null) return;
    if (elseS is IfStatement) {
      _elseIf(elseS);
    } else {
      score += 1;
      _nest(() => elseS.accept(this));
    }
  }

  void _elseIf(IfStatement node) {
    score += 1;
    node.expression.accept(this);
    _nest(() => node.thenStatement.accept(this));
    final elseS = node.elseStatement;
    if (elseS == null) return;
    if (elseS is IfStatement) {
      _elseIf(elseS);
    } else {
      score += 1;
      _nest(() => elseS.accept(this));
    }
  }

  @override
  void visitConditionalExpression(ConditionalExpression node) {
    score += 1 + nesting;
    node.condition.accept(this);
    _nest(() {
      node.thenExpression.accept(this);
      node.elseExpression.accept(this);
    });
  }

  @override
  void visitSwitchStatement(SwitchStatement node) {
    hasSwitch = true;
    score += 1 + nesting;
    node.expression.accept(this);
    _nest(() {
      for (final m in node.members) {
        m.accept(this);
      }
    });
  }

  @override
  void visitSwitchExpression(SwitchExpression node) {
    hasSwitch = true;
    score += 1 + nesting;
    node.expression.accept(this);
    _nest(() {
      for (final c in node.cases) {
        c.accept(this);
      }
    });
  }

  void _loop(AstNode body, List<AstNode?> heads) {
    score += 1 + nesting;
    for (final h in heads) {
      h?.accept(this);
    }
    _nest(() => body.accept(this));
  }

  @override
  void visitForStatement(ForStatement node) =>
      _loop(node.body, [node.forLoopParts]);
  @override
  void visitWhileStatement(WhileStatement node) =>
      _loop(node.body, [node.condition]);
  @override
  void visitDoStatement(DoStatement node) =>
      _loop(node.body, [node.condition]);

  @override
  void visitCatchClause(CatchClause node) {
    score += 1 + nesting;
    _nest(() => node.body.accept(this));
  }

  @override
  void visitIfElement(IfElement node) {
    score += 1 + nesting;
    node.expression.accept(this);
    _nest(() {
      node.thenElement.accept(this);
      node.elseElement?.accept(this);
    });
  }

  @override
  void visitForElement(ForElement node) {
    score += 1 + nesting;
    node.forLoopParts.accept(this);
    _nest(() => node.body.accept(this));
  }

  @override
  void visitBinaryExpression(BinaryExpression node) {
    final op = node.operator.type;
    if (op == TokenType.AMPERSAND_AMPERSAND || op == TokenType.BAR_BAR) {
      final parent = node.parent;
      final sameRun =
          parent is BinaryExpression && parent.operator.type == op;
      if (!sameRun) score += 1;
    }
    super.visitBinaryExpression(node);
  }

  @override
  void visitFunctionExpression(FunctionExpression node) {
    // A lambda's body nests; a function DECLARATION's own body is visited
    // at nesting 0 by the caller (it enters through its FunctionExpression
    // too, hence the parent check).
    if (node.parent is FunctionDeclaration && nesting == 0 && score == 0) {
      super.visitFunctionExpression(node);
      return;
    }
    _nest(() => super.visitFunctionExpression(node));
  }
}

class _McCabe extends RecursiveAstVisitor<void> {
  int forks = 0;
  @override
  void visitIfStatement(IfStatement n) { forks++; super.visitIfStatement(n); }
  @override
  void visitForStatement(ForStatement n) { forks++; super.visitForStatement(n); }
  @override
  void visitWhileStatement(WhileStatement n) { forks++; super.visitWhileStatement(n); }
  @override
  void visitDoStatement(DoStatement n) { forks++; super.visitDoStatement(n); }
  @override
  void visitSwitchCase(SwitchCase n) { forks++; super.visitSwitchCase(n); }
  @override
  void visitSwitchPatternCase(SwitchPatternCase n) { forks++; super.visitSwitchPatternCase(n); }
  @override
  void visitSwitchExpressionCase(SwitchExpressionCase n) { forks++; super.visitSwitchExpressionCase(n); }
  @override
  void visitCatchClause(CatchClause n) { forks++; super.visitCatchClause(n); }
  @override
  void visitConditionalExpression(ConditionalExpression n) { forks++; super.visitConditionalExpression(n); }
  @override
  void visitIfElement(IfElement n) { forks++; super.visitIfElement(n); }
  @override
  void visitForElement(ForElement n) { forks++; super.visitForElement(n); }
  @override
  void visitBinaryExpression(BinaryExpression n) {
    final op = n.operator.type;
    if (op == TokenType.AMPERSAND_AMPERSAND || op == TokenType.BAR_BAR || op == TokenType.QUESTION_QUESTION) forks++;
    super.visitBinaryExpression(n);
  }
}

class _Functions extends RecursiveAstVisitor<void> {
  _Functions(this.file, this.lineInfo);
  final LineInfo lineInfo;
  final String file;
  final out = <Fn>[];
  String? owner;

  void _score(String name, AstNode body) {
    final c = _Cognitive()..nesting = 0;
    body.accept(c);
    final m = _McCabe();
    body.accept(m);
    final owned = owner == null ? name : '$owner.$name';
    final span = body.parent ?? body;
    out.add(Fn(file, owned, 1 + m.forks, c.score, c.hasSwitch,
        lineInfo.getLocation(span.offset).lineNumber,
        lineInfo.getLocation(span.end).lineNumber));
  }

  @override
  void visitClassDeclaration(ClassDeclaration node) {
    owner = node.namePart.typeName.lexeme;
    super.visitClassDeclaration(node);
    owner = null;
  }

  @override
  void visitMixinDeclaration(MixinDeclaration node) {
    owner = node.name.lexeme;
    super.visitMixinDeclaration(node);
    owner = null;
  }

  @override
  void visitMethodDeclaration(MethodDeclaration node) {
    _score(node.name.lexeme, node.body);
  }

  @override
  void visitFunctionDeclaration(FunctionDeclaration node) {
    if (node.parent is FunctionDeclarationStatement) return; // local: part of its owner
    _score(node.name.lexeme, node.functionExpression.body);
  }

  @override
  void visitConstructorDeclaration(ConstructorDeclaration node) {
    _score(node.name?.lexeme ?? 'new', node.body);
  }
}

void main(List<String> args) {
  final root = args.isEmpty ? 'lib' : args[0];
  final listAt = args.indexOf('--list');
  final ceiling = listAt < 0 ? null : int.parse(args[listAt + 1]);
  final fns = <Fn>[];
  for (final e in Directory(root).listSync(recursive: true)) {
    if (e is! File || !e.path.endsWith('.dart')) continue;
    final text = e.readAsStringSync();
    final unit = parseString(
      content: text,
      path: e.path,
      featureSet: FeatureSet.latestLanguageVersion(),
      throwIfDiagnostics: false,
    ).unit;
    final v = _Functions(e.path.replaceAll(r'\', '/'), unit.lineInfo);
    unit.accept(v);
    fns.addAll(v.out);
  }
  if (ceiling != null) {
    listAbove(fns, ceiling);
    return;
  }
  print('functions: ${fns.length}');
  int over(int ceiling, int Function(Fn) f) => fns.where((x) => f(x) > ceiling).length;
  print('\nCEILING   McCabe>c   Cognitive>c');
  for (final c in [3, 4, 6, 8, 10, 12, 15, 20]) {
    print('  ${c.toString().padLeft(2)}      ${over(c, (f) => f.mccabe).toString().padLeft(5)}       ${over(c, (f) => f.cognitive).toString().padLeft(5)}');
  }
  final mcOver = fns.where((f) => f.mccabe > 6).toList();
  final withSwitch = mcOver.where((f) => f.hasSwitch).length;
  print('\nMcCabe > 6: ${mcOver.length}; of those containing a switch: $withSwitch');
  for (final c in [6, 8, 10]) {
    final under = mcOver.where((f) => f.cognitive <= c).length;
    print('  ...that would be under cognitive $c: $under');
  }
  final cgOver6 = fns.where((f) => f.cognitive > 6 && f.mccabe <= 6).length;
  print('Cognitive > 6 but McCabe <= 6 (deep nesting the fork count misses): $cgOver6');
  print('\nTOP 15 by cognitive (cog  mc  name)');
  final byCog = [...fns]..sort((a, b) => b.cognitive.compareTo(a.cognitive));
  for (final f in byCog.take(15)) {
    print('  ${f.cognitive.toString().padLeft(3)}  ${f.mccabe.toString().padLeft(3)}  ${f.file.replaceFirst('lib/src/', '')}::${f.name}');
  }
  print('\nSWITCH-DRIVEN (mc > 6, cognitive <= 6, has switch) — first 15');
  for (final f in mcOver.where((f) => f.hasSwitch && f.cognitive <= 6).take(15)) {
    print('  mc ${f.mccabe.toString().padLeft(3)}  cog ${f.cognitive.toString().padLeft(2)}  ${f.file.replaceFirst('lib/src/', '')}::${f.name}');
  }
}

/// `cognitive.dart <root> --list <ceiling>`: every function above the
/// ceiling, highest first, with its line span — the warning line's list.
void listAbove(List<Fn> fns, int ceiling) {
  final over = fns.where((f) => f.cognitive > ceiling).toList()
    ..sort((a, b) => b.cognitive.compareTo(a.cognitive));
  print('functions above cognitive $ceiling: ${over.length}');
  for (final f in over) {
    final path = f.file.substring(f.file.indexOf('lib/'));
    print('${f.cognitive.toString().padLeft(3)} ${f.mccabe.toString().padLeft(3)} '
        '${(f.endLine - f.line + 1).toString().padLeft(4)}L  $path:${f.line}-${f.endLine}  ${f.name}');
  }
}
