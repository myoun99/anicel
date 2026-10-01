// 🚨AN OPTIONAL PARAMETER IS READ BY ITS BODY (board
// `a-brush-picked-wears-the-texture-of-the-one-before`, 2026-10-01).
//
// `BrushToolState.copyWith` declared `textureMaskSource` and the texture's
// three levels and read none of them: G5 renamed the argument, and the
// body's `textureMask` went on compiling as the GETTER of that name — the
// texture of the brush being left. Every brush picked after a textured one
// wore its paper, and a library reset took it up again (유저: 「사본인가
// 설마?」). The analyzer has no warning for a parameter of a public method
// that nobody reads; this is that warning, for every function, method and
// constructor under lib/.
//
// It is an instrument, so here is what it looks like when it lies:
//   - it matches NAMES: a parameter read only through a local or a member of
//     the same name counts as read — the very shape of the copyWith bug when
//     the parameter's old name is the one still read, which is why this asks
//     about the parameter and not about the getter
//   - an `@override` is skipped (an interface can hand over more than one
//     implementation needs), and so are `this.x` and `super.x`, which the
//     declaration itself reads
//   - only OPTIONAL parameters are asked about: a caller has to pass a
//     required one, so one nobody reads is dead weight, not a value dropped
//     on the floor
@TestOn('vm')
library;

import 'package:analyzer/dart/analysis/features.dart';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/dart_sources.dart';

/// Unread today, each with why it is still here. An entry that no longer
/// matches FAILS: a ledger that keeps paid debts on it stops being read.
///
/// EMPTY from the day it was written (2026-10-01): the scan found four more
/// beside the texture's, and each was a value its callers passed and nobody
/// had read since the decision that retired it — an added layer's name
/// (the cel letters name it), the SE tags' row offset (#903: the tag sits
/// where its row's Transform puts it), the ffmpeg container (the output
/// path's extension is the container) and the lane drag's head lane (#1381:
/// the rail hands over the span it drew). All four went.
const _unread = <String, String>{};

void main() {
  test('every optional parameter under lib/ is read by its body', () {
    final found = <String>{
      for (final file in dartFilesUnder('lib'))
        ...unreadParameters(file.path, file.readAsStringSync()),
    };
    expect(
      found.difference(_unread.keys.toSet()),
      isEmpty,
      reason: 'These declare an optional parameter their body never reads: '
          'a caller that passes one has it dropped without a word — '
          'BrushToolState.copyWith dressed every brush in the texture of '
          'the one before that way. Read it, or remove it.',
    );
    expect(
      _unread.keys.toSet().difference(found),
      isEmpty,
      reason: 'Paid: take these off the ledger.',
    );
  });

  test('the reading finds the copyWith shape, and nothing a body reads', () {
    const source = '''
class State {
  Object? get texture => null;
  State copyWith({Object? textureSource, bool? invert, int? size}) {
    return make(texture, size);
  }
  State.named({this.kept, int? used}) : other = used;
  State.dropping({int? dropped}) : other = 1;
  factory State.handing({int? on}) = State.named;
  @override
  void handed({int? spare}) {}
  void abstractly({int? later});
}
''';
    expect(unreadParameters('x.dart', source), {
      'x.dart copyWith textureSource',
      'x.dart copyWith invert',
      'x.dart dropping dropped',
    });
  });
}

/// `'<path> <function> <parameter>'` for every optional parameter in
/// [source] that its body never names.
Set<String> unreadParameters(String path, String source) {
  final unit = parseString(
    content: source,
    featureSet: FeatureSet.latestLanguageVersion(),
    throwIfDiagnostics: false,
  ).unit;
  final visitor = _Unread(path.replaceAll(r'\', '/'));
  unit.accept(visitor);
  return visitor.found;
}

class _Unread extends RecursiveAstVisitor<void> {
  _Unread(this.path);

  final String path;
  final Set<String> found = {};

  /// [alsoReading] is a constructor's initializers; a constructor with
  /// those and no body is asked like any other, where a method with no body
  /// is abstract and has nothing to ask.
  void _ask(
    String name,
    FormalParameterList? parameters,
    FunctionBody? body,
    NodeList<Annotation> metadata, {
    List<AstNode>? alsoReading,
  }) {
    if (parameters == null ||
        body == null ||
        (body is EmptyFunctionBody && alsoReading == null) ||
        body is NativeFunctionBody ||
        metadata.any((annotation) => annotation.name.name == 'override')) {
      return;
    }
    final named = <String>{};
    for (final node in [body, ...?alsoReading]) {
      node.accept(_Names(named));
    }
    for (final parameter in parameters.parameters) {
      if (!parameter.isOptional ||
          parameter is FieldFormalParameter ||
          parameter is SuperFormalParameter) {
        continue;
      }
      final id = parameter.name?.lexeme;
      if (id != null && !id.startsWith('_') && !named.contains(id)) {
        found.add('$path $name $id');
      }
    }
  }

  @override
  void visitMethodDeclaration(MethodDeclaration node) {
    _ask(node.name.lexeme, node.parameters, node.body, node.metadata);
    super.visitMethodDeclaration(node);
  }

  @override
  void visitFunctionDeclaration(FunctionDeclaration node) {
    _ask(
      node.name.lexeme,
      node.functionExpression.parameters,
      node.functionExpression.body,
      node.metadata,
    );
    super.visitFunctionDeclaration(node);
  }

  @override
  void visitConstructorDeclaration(ConstructorDeclaration node) {
    // A redirecting factory hands every parameter on without naming one.
    if (node.redirectedConstructor == null) {
      _ask(
        node.name?.lexeme ?? 'new',
        node.parameters,
        node.body,
        node.metadata,
        alsoReading: node.initializers,
      );
    }
    super.visitConstructorDeclaration(node);
  }
}

class _Names extends RecursiveAstVisitor<void> {
  _Names(this.into);

  final Set<String> into;

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    into.add(node.name);
    super.visitSimpleIdentifier(node);
  }
}
