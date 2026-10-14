// 🚨A VALUE CHECKED INSIDE A LOOP IS READ THROUGH A LOCAL OF THAT FUNCTION
// (I-57, 2026-10-14).
//
// Dart 3.13's AOT compiler hoists loads out of a loop ABOVE the check that
// guards them when the checked value is not a local of the loop's own
// function — a variable a closure captured, a promoted private field, or a
// local promoted through a `bool` — and a null receiver is then read
// through: the release build dies on a null object read (dart-lang/sdk
// #63413, #64528, #64530; fixed upstream 2026-10-02, in no 3.13 stable).
// The JIT never does this, so debug runs and every test stay green. The
// session's SE rows, memoised behind a closure on 10-14, killed every
// release and profile build at start (`preview != null && preview.id ==
// layer.id`, with `preview` captured) — the user found it by running the
// release build. A local the loop's function checks itself is safe: the
// check pins the loads below it.
//
// It is an instrument, so here is what it looks like when it lies:
//   - it reads SOURCE, not types: a check of a name and a member read
//     through the same name in the same loop is the shape, whatever the
//     name's type — a non-null value checked anyway is reported too
//   - a name is a local when the loop's function declares it; anything
//     else (a capture, a field, a top-level) is not
//   - `?.`, `!` and a check outside the loop are what make a read safe
//     here; a local copied from the capture inside the closure is too
//   - a field read as `other._f` (another object's private field) is not
//     asked about — none sat in a loop on the day this was written
@TestOn('vm')
library;

import 'package:analyzer/dart/analysis/features.dart';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/token.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/dart_sources.dart';

void main() {
  test('no loop under lib/ reads a checked value past its check', () {
    final hits = <String>[];
    for (final file in dartFilesUnder('lib')) {
      hits.addAll(
        checkedReadsInLoops(libPath(file), file.readAsStringSync()),
      );
    }
    expect(
      hits,
      isEmpty,
      reason:
          'copy the value into a local of the function that runs the loop '
          '(or pass it in as a parameter) and check THAT — a capture, a '
          'field or a bool-promoted local is hoisted past its check by the '
          'AOT compiler and read through when it is null',
    );
  });

  test('the scan sees the three shapes, and none of the safe ones', () {
    const planted = '''
class Host {
  final Layer? _preview;
  List<Layer> captured(List<Layer> layers, Layer? preview) {
    final build = () => [
      for (final layer in layers)
        preview != null && preview.id == layer.id ? preview : layer,
    ];
    return build();
  }
  List<Layer> field(List<Layer> layers) => [
    for (final layer in layers)
      _preview != null && _preview.id == layer.id ? _preview : layer,
  ];
  List<Layer> viaBool(List<Layer> layers, Layer? preview) {
    final has = preview != null;
    final out = <Layer>[];
    for (final layer in layers) {
      out.add(has && preview.id == layer.id ? preview : layer);
    }
    return out;
  }
  List<Layer> local(List<Layer> layers, Layer? preview) => [
    for (final layer in layers)
      preview != null && preview.id == layer.id ? preview : layer,
  ];
  List<Layer> checkedBefore(List<Layer> layers, Layer? preview) {
    final build = () {
      if (preview == null) return layers;
      return [for (final layer in layers) preview.id == layer.id ? preview : layer];
    };
    return build();
  }
  List<Layer> nullAware(List<Layer> layers, Layer? preview) {
    final build = () => [
      for (final layer in layers) preview?.id == layer.id ? preview! : layer,
    ];
    return build();
  }
  List<Layer> copied(List<Layer> layers, Layer? preview) {
    final build = () {
      final shown = preview;
      return [
        for (final layer in layers)
          shown != null && shown.id == layer.id ? shown : layer,
      ];
    };
    return build();
  }
  List<Layer> perItem(List<Layer?> layers) => [
    for (final layer in layers)
      if (layer != null && layer.id.isNotEmpty) layer,
  ];
}
''';
    expect(checkedReadsInLoops('x.dart', planted), {
      'x.dart captured preview',
      'x.dart field _preview',
      'x.dart viaBool preview',
    });
  });

  test('every way of reading through a value is seen, in every loop', () {
    const planted = '''
class Host {
  final Object? _shape;
  int indexed(Pass pass) {
    final (:mask, :size) = pass;
    return rewrite((view) {
      var sum = 0;
      for (var i = 0; i < size; i += 1) {
        sum += mask == null ? 255 : mask[i];
      }
      return sum;
    });
  }
  void called(Rows? rows, List<Node> nodes) {
    void each() {
      var i = 0;
      while (i < nodes.length) {
        if (rows != null) rows.keep(nodes[i]);
        i += 1;
      }
    }
    each();
  }
  bool compared(Id? id, List<Id> ids) {
    bool any() {
      var i = 0;
      do {
        if (id != null && id == ids[i]) return true;
        i += 1;
      } while (i < ids.length);
      return false;
    }
    return any();
  }
  int typed(List<int> xs) {
    var sum = 0;
    for (final x in xs) {
      if (this._shape is Circle) sum += this._shape.radius.round();
    }
    return sum;
  }
  int negated(List<Layer> layers, Layer? preview) {
    final has = !(preview == null);
    var n = 0;
    for (final layer in layers) {
      if (has) n += preview.id.length;
    }
    return n;
  }
  int viaIs(List<int> xs, Object? shape) {
    final round = shape is Circle;
    var n = 0;
    for (final x in xs) {
      if (round) n += shape.radius.round();
    }
    return n;
  }
  int viaJoinedBool(List<Layer> layers, Layer? preview, bool on) {
    final has = preview != null && on;
    var n = 0;
    for (final layer in layers) {
      if (has) n += preview.id.length;
    }
    return n;
  }
}
''';
    expect(checkedReadsInLoops('y.dart', planted), {
      'y.dart indexed mask',
      'y.dart called rows',
      'y.dart compared id',
      'y.dart typed _shape',
      'y.dart negated preview',
      'y.dart viaIs shape',
      'y.dart viaJoinedBool preview',
    });
  });

  test('a value the loop changes, or checks outside it, is not asked', () {
    const planted = '''
class Host {
  final Layer? _preview;
  int byItem(List<Layer?> layers) {
    var n = 0;
    for (final layer in layers) {
      if (layer != null) n += layer.id.length;
    }
    return n;
  }
  int rewritten(List<Layer> layers, Layer? last) {
    var n = 0;
    for (final layer in layers) {
      if (last != null) n += last.id.length;
      last = layer;
    }
    return n;
  }
  int fieldCheckedBefore(List<Layer> layers) {
    if (_preview == null) return 0;
    var n = 0;
    for (final layer in layers) {
      n += _preview.id == layer.id ? 1 : 0;
    }
    return n;
  }
  int boolButGuardedToo(List<Layer> layers, Layer? preview) {
    final has = preview != null;
    var n = 0;
    for (final layer in layers) {
      if (has && preview != null && preview.id == layer.id) n += 1;
    }
    return n;
  }
  int boolPerItem(List<Layer?> layers) {
    var n = 0;
    for (final maybe in layers) {
      final layer = maybe;
      final has = layer != null;
      if (has) n += layer.id.length;
    }
    return n;
  }
  int boolOnARewritten(List<Layer> layers, Layer? last) {
    final has = last != null;
    var n = 0;
    for (final layer in layers) {
      if (has) n += last.id.length;
      last = layer;
    }
    return n;
  }
  int destructuredHere(Pass pass, List<int> xs) {
    final (:mask, :size) = pass;
    var n = 0;
    for (final x in xs) {
      n += mask == null ? 0 : mask[x];
    }
    return n;
  }
}
''';
    expect(checkedReadsInLoops('z.dart', planted), isEmpty);
  });
}

/// `'<path> <member> <name>'` for every read through [name] inside a loop
/// of [source] that a check inside the same loop guards, where the loop's
/// own function does not declare [name] — or declares it and promotes it
/// only through a `bool`.
Set<String> checkedReadsInLoops(String path, String source) {
  final unit = parseString(
    content: source,
    featureSet: FeatureSet.latestLanguageVersion(),
    throwIfDiagnostics: false,
  ).unit;
  final visitor = _Loops(path.replaceAll(r'\', '/'));
  unit.accept(visitor);
  return visitor.found;
}

class _Loops extends RecursiveAstVisitor<void> {
  _Loops(this.path);

  final String path;
  final Set<String> found = {};

  @override
  void visitForStatement(ForStatement node) {
    _ask(node);
    super.visitForStatement(node);
  }

  @override
  void visitForElement(ForElement node) {
    _ask(node);
    super.visitForElement(node);
  }

  @override
  void visitWhileStatement(WhileStatement node) {
    _ask(node);
    super.visitWhileStatement(node);
  }

  @override
  void visitDoStatement(DoStatement node) {
    _ask(node);
    super.visitDoStatement(node);
  }

  void _ask(AstNode loop) {
    final body = _bodyOf(loop);
    if (body == null) return;
    final inLoop = _Walk(body);
    loop.accept(inLoop);
    final locals = _declaredIn(body);
    for (final read in inLoop.reads) {
      final name = read.name;
      if (inLoop.declared.contains(name) || inLoop.written.contains(name)) {
        continue; // changes with the loop: nothing to hoist
      }
      final bool hazard;
      if (locals.contains(name)) {
        hazard =
            !_guardedByItsOwnCheck(read.node, name, loop) &&
            _promotedThroughABool(body, name, inLoop.names);
      } else {
        hazard = inLoop.checked.contains(name);
      }
      if (hazard) found.add('$path ${_memberOf(loop)} $name');
    }
  }
}

typedef _Read = ({String name, AstNode node});

/// One loop's reads, checks, declarations and writes — in the loop's own
/// function only: a closure inside the loop is compiled on its own.
class _Walk extends RecursiveAstVisitor<void> {
  _Walk(this.body);

  final FunctionBody body;
  final List<_Read> reads = [];
  final Set<String> names = {};
  final Set<String> checked = {};
  final Set<String> declared = {};
  final Set<String> written = {};

  bool _ours(AstNode node) => identical(_bodyOf(node), body);

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    if (_ours(node)) {
      names.add(node.name);
      if (_isReadThrough(node)) reads.add((name: node.name, node: node));
    }
    super.visitSimpleIdentifier(node);
  }

  @override
  void visitPropertyAccess(PropertyAccess node) {
    final target = node.target;
    if (target is PropertyAccess &&
        target.target is ThisExpression &&
        !node.isNullAware &&
        _ours(node)) {
      reads.add((name: target.propertyName.name, node: target));
    }
    super.visitPropertyAccess(node);
  }

  @override
  void visitBinaryExpression(BinaryExpression node) {
    final name = _nullChecked(node);
    if (name != null && _ours(node)) checked.add(name);
    super.visitBinaryExpression(node);
  }

  @override
  void visitIsExpression(IsExpression node) {
    final name = _nameOf(node.expression);
    if (name != null && _ours(node)) checked.add(name);
    super.visitIsExpression(node);
  }

  @override
  void visitVariableDeclaration(VariableDeclaration node) {
    if (_ours(node)) declared.add(node.name.lexeme);
    super.visitVariableDeclaration(node);
  }

  @override
  void visitDeclaredIdentifier(DeclaredIdentifier node) {
    if (_ours(node)) declared.add(node.name.lexeme);
    super.visitDeclaredIdentifier(node);
  }

  @override
  void visitDeclaredVariablePattern(DeclaredVariablePattern node) {
    if (_ours(node)) declared.add(node.name.lexeme);
    super.visitDeclaredVariablePattern(node);
  }

  @override
  void visitAssignmentExpression(AssignmentExpression node) {
    final name = _nameOf(node.leftHandSide);
    if (name != null && _ours(node)) written.add(name);
    super.visitAssignmentExpression(node);
  }

  @override
  void visitPostfixExpression(PostfixExpression node) {
    final name = _nameOf(node.operand);
    if (name != null && node.operator.type != TokenType.BANG && _ours(node)) {
      written.add(name);
    }
    super.visitPostfixExpression(node);
  }

  @override
  void visitPrefixExpression(PrefixExpression node) {
    final op = node.operator.type;
    final name = _nameOf(node.operand);
    if (name != null &&
        (op == TokenType.PLUS_PLUS || op == TokenType.MINUS_MINUS) &&
        _ours(node)) {
      written.add(name);
    }
    super.visitPrefixExpression(node);
  }
}

/// Whether [node] is the receiver a member is read through: `x.f`,
/// `x.m()`, `x[i]`, `x == y` — not `x?.f`, not `x!`, not `x == null`.
bool _isReadThrough(SimpleIdentifier node) {
  final parent = node.parent;
  // `x.f` parses as a PrefixedIdentifier; a PropertyAccess on a bare `x`
  // is only ever `x?.f`.
  if (parent is PrefixedIdentifier) return identical(parent.prefix, node);
  if (parent is MethodInvocation) {
    return identical(parent.target, node) && !parent.isNullAware;
  }
  if (parent is IndexExpression) {
    return identical(parent.target, node) && !parent.isNullAware;
  }
  if (parent is BinaryExpression) {
    return identical(parent.leftOperand, node) &&
        parent.operator.type.isUserDefinableOperator &&
        parent.rightOperand is! NullLiteral;
  }
  return false;
}

String? _nameOf(Expression e) {
  if (e is SimpleIdentifier) return e.name;
  if (e is PropertyAccess && e.target is ThisExpression) {
    return e.propertyName.name;
  }
  return null;
}

/// The name `x` of `x != null` / `x == null` / `null == x`.
String? _nullChecked(BinaryExpression node) {
  final op = node.operator.type;
  if (op != TokenType.BANG_EQ && op != TokenType.EQ_EQ) return null;
  if (node.rightOperand is NullLiteral) return _nameOf(node.leftOperand);
  if (node.leftOperand is NullLiteral) return _nameOf(node.rightOperand);
  return null;
}

/// Whether [e] checks [name]: `x != null`, `x == null`, `x is T`, or those
/// joined by `&&` / `||` / `!`.
bool _checks(Expression e, String name) {
  if (e is ParenthesizedExpression) return _checks(e.expression, name);
  if (e is PrefixExpression && e.operator.type == TokenType.BANG) {
    return _checks(e.operand, name);
  }
  if (e is IsExpression) return _nameOf(e.expression) == name;
  if (e is BinaryExpression) {
    final op = e.operator.type;
    if (op == TokenType.AMPERSAND_AMPERSAND || op == TokenType.BAR_BAR) {
      return _checks(e.leftOperand, name) || _checks(e.rightOperand, name);
    }
    return _nullChecked(e) == name;
  }
  return false;
}

/// Whether a condition between [read] and [loop] checks [name] itself —
/// the left of `&&` / `||`, the condition of `?:` or `if`.
bool _guardedByItsOwnCheck(AstNode read, String name, AstNode loop) {
  var child = read;
  for (var n = read.parent; n != null && !identical(n, loop); n = n.parent) {
    Expression? guard;
    if (n is BinaryExpression &&
        identical(n.rightOperand, child) &&
        (n.operator.type == TokenType.AMPERSAND_AMPERSAND ||
            n.operator.type == TokenType.BAR_BAR)) {
      guard = n.leftOperand;
    } else if (n is ConditionalExpression && !identical(n.condition, child)) {
      guard = n.condition;
    } else if (n is IfStatement && !identical(n.expression, child)) {
      guard = n.expression;
    } else if (n is IfElement && !identical(n.expression, child)) {
      guard = n.expression;
    }
    if (guard != null && _checks(guard, name)) return true;
    child = n;
  }
  return false;
}

/// Whether [body] declares a local that IS a check of [name] (`final has
/// = x != null;`) and the loop reads that local ([namesInLoop]).
bool _promotedThroughABool(
  FunctionBody body,
  String name,
  Set<String> namesInLoop,
) {
  final bools = <String>{};
  body.accept(_BoolsChecking(body, name, bools));
  return bools.any(namesInLoop.contains);
}

class _BoolsChecking extends RecursiveAstVisitor<void> {
  _BoolsChecking(this.body, this.name, this.bools);
  final FunctionBody body;
  final String name;
  final Set<String> bools;

  @override
  void visitVariableDeclaration(VariableDeclaration node) {
    final init = node.initializer;
    if (init != null &&
        identical(_bodyOf(node), body) &&
        _checks(init, name)) {
      bools.add(node.name.lexeme);
    }
    super.visitVariableDeclaration(node);
  }
}

/// The body of the function [node] sits in.
FunctionBody? _bodyOf(AstNode node) {
  for (var n = node.parent; n != null; n = n.parent) {
    if (n is FunctionBody) return n;
  }
  return null;
}

/// The names [body]'s function declares: its parameters and its locals,
/// not those of a closure inside it.
Set<String> _declaredIn(FunctionBody body) {
  final names = <String>{};
  final owner = body.parent;
  final parameters = switch (owner) {
    FunctionExpression(:final parameters) => parameters,
    MethodDeclaration(:final parameters) => parameters,
    ConstructorDeclaration(:final parameters) => parameters,
    _ => null,
  };
  for (final parameter in parameters?.parameters ?? <FormalParameter>[]) {
    final name = parameter.name?.lexeme;
    if (name != null) names.add(name);
  }
  final walk = _Walk(body);
  body.accept(walk);
  return names..addAll(walk.declared);
}

/// The member a loop sits in, by name — how the ledger and the failure
/// name a hit (line numbers move).
String _memberOf(AstNode node) {
  for (var n = node.parent; n != null; n = n.parent) {
    if (n is MethodDeclaration) return n.name.lexeme;
    if (n is FunctionDeclaration && n.parent is CompilationUnit) {
      return n.name.lexeme;
    }
    if (n is ConstructorDeclaration) return n.name?.lexeme ?? 'new';
  }
  return '<top>';
}
