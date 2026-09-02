// Candidate edits that change what a file DOES, so a test suite can be asked
// whether it would notice.
//
// 🚨★★★A GREEN TEST IS NOT EVIDENCE. The repo's own rule: 「제품 코드를 껐을
// 때 빨개지는지」가 증거다. `tool/audit_rank.dart` can say a file is named by
// no test, which is certain; for everything else — 692 files that ARE named —
// only turning the code off answers it. This generates the "off".
//
// ## Every mutation here compiles, on purpose
//
// The outcome that ruins a mutation run is a change that does not build: the
// suite goes red for the whole file, which reads exactly like a kill and is
// the opposite of one. So the operators are token swaps between forms that
// are interchangeable to the type system:
//
//   `<` ↔ `<=`   `>` ↔ `>=`   `==` ↔ `!=`   `&&` ↔ `||`   `true` ↔ `false`
//
// ⚠️Even these can fail to build in one narrow case: a class that overloads
// `<` and not `<=`. That is why the RUNNER records "did not compile" as its
// own outcome and never counts it as killed — a rule that has to hold for
// every operator is a rule that will be broken, so the runner does not
// depend on it holding.
//
// ⛔ARITHMETIC IS DELIBERATELY ABSENT. `+` ↔ `-` is the classic mutation and
// it does not compile over `String` or `List`, which this codebase uses `+`
// on constantly. Adding it means either resolving types (a whole analysis
// session per file) or accepting a pile of uninterpretable results. It is
// worth doing later, on its own, with the type information — not smuggled in
// beside operators that are safe.
//
// ## What a surviving mutation means
//
//   KILLED    → some test asserts on this behaviour. The line is pinned.
//   SURVIVED  → no test noticed the code doing something else. ⚠️Not always a
//               defect: the line may be unreachable, or genuinely not worth
//               pinning. It is a QUESTION, and the audit's job is to ask it.
import 'package:analyzer/dart/analysis/features.dart';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/diagnostic/diagnostic.dart';

/// One candidate edit: replace [length] characters at [offset] with
/// [replacement].
class Mutation {
  const Mutation({
    required this.offset,
    required this.length,
    required this.was,
    required this.replacement,
    required this.line,
    required this.kind,
  });

  final int offset;
  final int length;

  /// The text being replaced, kept so a report can show the edit without
  /// re-reading the file, and so [applyTo] can refuse a stale mutation.
  final String was;
  final String replacement;
  final int line;

  /// `comparison` · `equality` · `logic` · `boolean`.
  final String kind;

  /// [source] with this edit made.
  ///
  /// ⛔Throws if [source] no longer has [was] at [offset]. A mutation applied
  /// to the wrong text produces a file nobody predicted, and the run would
  /// report its result against the mutation it MEANT to make.
  String applyTo(String source) {
    // 🚨★★★READ THE WHOLE TOKEN, NOT [length] CHARACTERS.
    //
    // 🧪Two measured failures, and they pull in opposite directions, which is
    // why neither a prefix check nor a length check can serve alone:
    //   · `<` → `<=` applied twice. A guard comparing one character reads the
    //     `<` of `<=`, matches, and writes 「a <== 3」. Reported nothing.
    //   · `>=` → `>`. A guard asking 「does it already start with `>`」 sees
    //     that `>=` does and refuses a mutation that had never been made.
    // The operator at an offset is a TOKEN. Comparing tokens answers both.
    // ⛔ONE CHECK, NOT TWO. A separate 「already applied」 branch sat here and
    // 🧪a mutation proved it dead: turning it off changed nothing, because a
    // site that already holds the replacement fails this comparison anyway.
    // Its only contribution was a nicer message, which this one now carries.
    final token = _tokenAt(source, offset);
    if (token != was) {
      throw StateError(
        'mutation at $offset expected 「$was」 and found 「$token」 — '
        '${token == replacement ? "it has already been applied" : "the source changed under it"}',
      );
    }
    return source.replaceRange(offset, offset + length, replacement);
  }

  @override
  String toString() => 'L$line $kind 「$was」→「$replacement」';
}

final _wordChar = RegExp('[A-Za-z0-9_]');

/// The whole token starting at [offset] — an operator run or a word.
///
/// ⚠️`-` and the other arithmetic characters are deliberately NOT operator
/// characters here. Nothing in [_swaps] contains them, and including them
/// would read `>= -1` as the token `>=-`.
String _tokenAt(String source, int offset) {
  if (offset >= source.length) return '';
  final first = source[offset];
  final isWord = _wordChar.hasMatch(first);
  var end = offset;
  while (end < source.length) {
    final c = source[end];
    final continues = isWord ? _wordChar.hasMatch(c) : '<>=!&|'.contains(c);
    if (!continues) break;
    end += 1;
  }
  return source.substring(offset, end);
}

/// Which token swaps are available, and what each is called.
const _swaps = <String, ({String to, String kind})>{
  '<': (to: '<=', kind: 'comparison'),
  '<=': (to: '<', kind: 'comparison'),
  '>': (to: '>=', kind: 'comparison'),
  '>=': (to: '>', kind: 'comparison'),
  '==': (to: '!=', kind: 'equality'),
  '!=': (to: '==', kind: 'equality'),
  '&&': (to: '||', kind: 'logic'),
  '||': (to: '&&', kind: 'logic'),
};

/// Every candidate edit in [source], in source order.
///
/// Returns empty for a file that does not parse — a caller cannot mutate what
/// it could not read, and pretending there were no candidates is the honest
/// answer to 「what can I change here」. ⚠️The runner reports unreadable files
/// separately, from `code_map`, so this silence is not the only word on it.
List<Mutation> mutationsIn(String source) {
  final parsed = parseString(
    content: source,
    featureSet: FeatureSet.latestLanguageVersion(),
    throwIfDiagnostics: false,
  );
  if (parsed.errors.any((d) => d.severity == Severity.error)) return const [];

  final found = <Mutation>[];
  final lineInfo = parsed.lineInfo;
  parsed.unit.accept(_MutationVisitor(found, (offset) {
    return lineInfo.getLocation(offset).lineNumber;
  }));
  found.sort((a, b) => a.offset.compareTo(b.offset));
  return found;
}

class _MutationVisitor extends RecursiveAstVisitor<void> {
  _MutationVisitor(this.found, this.lineOf);

  final List<Mutation> found;
  final int Function(int offset) lineOf;

  @override
  void visitBinaryExpression(BinaryExpression node) {
    final lexeme = node.operator.lexeme;
    final swap = _swaps[lexeme];
    if (swap != null) {
      found.add(Mutation(
        offset: node.operator.offset,
        length: lexeme.length,
        was: lexeme,
        replacement: swap.to,
        line: lineOf(node.operator.offset),
        kind: swap.kind,
      ));
    }
    super.visitBinaryExpression(node);
  }

  @override
  void visitBooleanLiteral(BooleanLiteral node) {
    // ⚠️A `const` context is still mutable text — `const x = true` becoming
    // `const x = false` compiles and changes behaviour, which is the point.
    final lexeme = node.literal.lexeme;
    found.add(Mutation(
      offset: node.literal.offset,
      length: lexeme.length,
      was: lexeme,
      replacement: lexeme == 'true' ? 'false' : 'true',
      line: lineOf(node.literal.offset),
      kind: 'boolean',
    ));
    super.visitBooleanLiteral(node);
  }
}
