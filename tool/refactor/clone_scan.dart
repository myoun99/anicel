// Structural clone candidates across lib/: the token streams of every
// function body, with identifiers and literals normalised, compared for
// runs of at least `minTokens` tokens that occur in two places. A run is a
// CANDIDATE — connascence (the same algorithm, whatever the text) is the
// judgment, and it is made by reading, not here. The audit's Round 1
// (2026-09-03) worked the list from the top; the architecture ratchet
// keeps the count from growing back. A run with no control flow and no
// operators in it (an argument list, a field list) is a shape, not a law,
// and is not counted — see [_carriesAnAlgorithm].
import 'dart:io';

import 'package:analyzer/dart/analysis/features.dart';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/token.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/source/line_info.dart';

import 'app_sources.dart';

/// One normalised token and where it sits in its file.
class CloneToken {
  CloneToken(this.norm, this.offset);
  final String norm;
  final int offset;
}

/// One function body: its owner (`Class.method` or a top-level name) and
/// its normalised tokens.
class CloneBody {
  CloneBody(this.file, this.owner, this.tokens, this.lineInfo);
  final String file;
  final String owner;
  final List<CloneToken> tokens;
  final LineInfo lineInfo;

  int lineAt(int tokenIndex) =>
      lineInfo.getLocation(tokens[tokenIndex].offset).lineNumber;
}

/// A run of [length] normalised tokens shared by [a] (from [aStart]) and
/// [b] (from [bStart]).
class CloneCandidate {
  CloneCandidate(this.a, this.aStart, this.b, this.bStart, this.length);
  final CloneBody a;
  final int aStart;
  final CloneBody b;
  final int bStart;
  final int length;

  String describe() {
    String where(CloneBody body, int start) =>
        '${body.file}:${body.lineAt(start)}-'
        '${body.lineAt(start + length - 1)}  ${body.owner}';
    return '$length tokens\n    ${where(a, aStart)}\n    ${where(b, bStart)}';
  }
}

class _Bodies extends RecursiveAstVisitor<void> {
  _Bodies(this.file, this.lineInfo, this.allTokens);
  final String file;
  final LineInfo lineInfo;
  final List<Token> allTokens;
  final out = <CloneBody>[];
  String? owner;

  // Generated-shape members: their text is the class's field list, not an
  // algorithm, so two of them agreeing says nothing.
  static const skipNames = {
    '==',
    'hashCode',
    'toString',
    'copyWith',
    'toJson',
    'fromJson',
    'debugFillProperties',
    'createState',
  };

  void _body(String name, FunctionBody body) {
    if (skipNames.contains(name)) return;
    final toks = <CloneToken>[];
    for (final t in allTokens) {
      if (t.offset < body.offset) continue;
      if (t.offset >= body.end) break;
      toks.add(CloneToken(_norm(t), t.offset));
    }
    if (toks.length >= 8) {
      out.add(
        CloneBody(file, owner == null ? name : '$owner.$name', toks, lineInfo),
      );
    }
  }

  static String _norm(Token t) {
    if (t.type == TokenType.IDENTIFIER) return 'I';
    if (t.type == TokenType.STRING ||
        t.type == TokenType.INT ||
        t.type == TokenType.DOUBLE ||
        t.type == TokenType.HEXADECIMAL) {
      return 'L';
    }
    return t.lexeme;
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
    _body(node.name.lexeme, node.body);
  }

  @override
  void visitFunctionDeclaration(FunctionDeclaration node) {
    if (node.parent is FunctionDeclarationStatement) return;
    _body(node.name.lexeme, node.functionExpression.body);
  }

  @override
  void visitConstructorDeclaration(ConstructorDeclaration node) {
    _body(node.name?.lexeme ?? 'new', node.body);
  }
}

/// Every function body under [libRoot] ([appDartFiles]: `lib/dev/`
/// excluded), as normalised token streams.
List<CloneBody> cloneBodies(String libRoot) {
  final bodies = <CloneBody>[];
  for (final path in appDartFiles(libRoot)) {
    final result = parseString(
      content: File(path).readAsStringSync(),
      path: path,
      featureSet: FeatureSet.latestLanguageVersion(),
      throwIfDiagnostics: false,
    );
    final toks = <Token>[];
    for (var t = result.unit.beginToken; !t.isEof; t = t.next!) {
      toks.add(t);
    }
    final shown = path.substring(path.indexOf('lib/'));
    final visitor = _Bodies(shown, result.lineInfo, toks);
    result.unit.accept(visitor);
    bodies.addAll(visitor.out);
  }
  return bodies;
}

/// The clone candidates among [bodies]: the longest shared run per pair of
/// bodies, at least [minTokens] long, longest first. A body repeating
/// itself is not a copy of an algorithm, so same-body runs count only when
/// they do not overlap — or not at all with [crossOnly].
List<CloneCandidate> cloneCandidates(
  List<CloneBody> bodies, {
  int minTokens = 40,
  bool crossOnly = true,
}) {
  final index = <String, List<(int, int)>>{};
  for (var b = 0; b < bodies.length; b++) {
    final toks = bodies[b].tokens;
    for (var i = 0; i + minTokens <= toks.length; i++) {
      final key = toks.sublist(i, i + minTokens).map((t) => t.norm).join(' ');
      (index[key] ??= []).add((b, i));
    }
  }
  final seen = <String>{};
  final hits = <CloneCandidate>[];
  for (final places in index.values) {
    if (places.length < 2) continue;
    for (var x = 0; x < places.length; x++) {
      for (var y = x + 1; y < places.length; y++) {
        final (ba, ia) = places[x];
        final (bb, ib) = places[y];
        if (ba == bb && (ia - ib).abs() < minTokens) continue;
        // Only the leftmost window of a run starts a hit.
        if (ia > 0 &&
            ib > 0 &&
            bodies[ba].tokens[ia - 1].norm == bodies[bb].tokens[ib - 1].norm) {
          continue;
        }
        var len = minTokens;
        while (ia + len < bodies[ba].tokens.length &&
            ib + len < bodies[bb].tokens.length &&
            bodies[ba].tokens[ia + len].norm ==
                bodies[bb].tokens[ib + len].norm) {
          len++;
        }
        if (ba == bb && ia < ib + len && ib < ia + len) continue;
        if (!seen.add('$ba:$ia:$bb:$ib')) continue;
        if (!_carriesAnAlgorithm(bodies[ba].tokens, ia, len)) continue;
        hits.add(CloneCandidate(bodies[ba], ia, bodies[bb], ib, len));
      }
    }
  }
  hits.sort((p, q) => q.length.compareTo(p.length));
  // One hit per body pair: the longest run, dropping its shifted sub-runs.
  final longestPerStart = <String, CloneCandidate>{};
  for (final h in hits) {
    final key = '${h.a.file}#${h.a.owner}#${h.aStart}|${h.b.file}#${h.b.owner}';
    longestPerStart.putIfAbsent(key, () => h);
  }
  final byPair = <String, CloneCandidate>{};
  for (final h in longestPerStart.values) {
    final pair = '${h.a.file}#${h.a.owner}|${h.b.file}#${h.b.owner}';
    final held = byPair[pair];
    if (held == null || h.length > held.length) byPair[pair] = h;
  }
  final result = byPair.values.toList()
    ..sort((p, q) => q.length.compareTo(p.length));
  if (crossOnly) {
    result.removeWhere((h) => identical(h.a, h.b));
  }
  return result;
}

/// Tokens that make a run an ALGORITHM rather than a shape: control flow
/// and operators. Identifiers, literals, punctuation and type syntax are
/// what a named-argument list or a field list is made of.
const _algorithmTokens = {
  'if', 'else', 'for', 'while', 'do', 'switch', 'case', 'default',
  'return', 'break', 'continue', 'throw', 'try', 'catch', 'finally',
  'await', 'yield', 'in', 'is', 'as', //
  '=', '==', '!=', '+', '-', '*', '/', '%', '~/', '<=', '>=', '&&', '||',
  '!', '??', '?.', '..', '?..', '+=', '-=', '*=', '/=', '??=', '++', '--',
  '&', '|', '^', '~', '<<', '>>', '>>>',
};

/// Whether the run of [length] tokens from [start] carries an algorithm.
/// Round 6 (2026-09-04) found the scan counting the named-argument lists
/// of value-object constructions — `name: name,` forty tokens long — as
/// copies of one another across unrelated constructors, and the field
/// reset lists (`x = null;` over and over) of unrelated drags likewise. A
/// run with fewer than three DISTINCT control-flow or operator tokens is
/// a shape, not a law, and is not a candidate.
bool _carriesAnAlgorithm(List<CloneToken> tokens, int start, int length) {
  final kinds = <String>{};
  for (var i = start; i < start + length; i++) {
    final norm = tokens[i].norm;
    if (_algorithmTokens.contains(norm)) {
      kinds.add(norm);
      if (kinds.length >= 3) return true;
    }
  }
  return false;
}
