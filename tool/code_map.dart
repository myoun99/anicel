// A generated map of every declaration in `lib/`, and the import graph
// between the files that hold them.
//
// 🚨★★★IT IS GENERATED, NEVER MAINTAINED.
//
// Why that matters more than what it measures: the obvious way to "understand
// every function" is to read them all and write the answers into a file. That
// file is a SECOND COPY OF THE CODE — it is right the day it is written and
// drifts every day after, and nothing tells you when it has drifted. The
// board in this repo already works the other way round (`board.jsonl` is the
// record, the screen is drawn every time it opens), and so does this: run it
// again and the map is current by construction.
//
// So the deliverable is THIS FILE, not its output. Do not check the output in
// and do not hand-edit it.
//
// ## It is an instrument, so here is what it looks like when it lies
//
//   - A FILE THAT DID NOT PARSE is a hole in the map. Every count would be
//     quietly too low and nothing on screen would say so. ⇒ parse failures
//     are printed FIRST, counted, and make the process exit non-zero. A map
//     that cannot say 「I did not read 3 files」 is worse than no map.
//   - COMPLEXITY IS A COUNT OF DECISION POINTS, not a judgement. A 400-line
//     function of straight-line code scores 1. That is not a bug in the
//     number, it is the number's meaning — read `lines` beside it.
//   - COGNITIVE COMPLEXITY IS THE OTHER NUMBER, and the one the ratchet
//     reads (유저 2026-09-02: 「스위치문이 부당하게 늘어나니까 인지복잡도」).
//     SonarSource's rules: +1 for each if / else-if / else / ?: / switch (the
//     WHOLE switch, not each case) / loop / catch / collection-if / -for, +1
//     per run of `&&` or `||`, and + the nesting depth for each of those that
//     nests — a lambda body nests too. 🧪Measured the day it was added: of
//     1,214 functions McCabe put over 6, 310 were switch-driven and read at
//     6 or under; 167 deeply nested ones McCabe put UNDER 6 read over it.
//     McCabe stays in the map for what it is good at — a path count.
//   - FAN-IN COUNTS IMPORT EDGES, not calls. A file imported for one constant
//     ranks as high as one imported for a god object. It answers 「how many
//     files would notice if this moved」, which is the question a boundary
//     refactor asks, and it does not answer 「how hot is this」.
//   - PARTS ARE PARSED ON THEIR OWN. A `part` file's declarations are counted
//     under its own path, not folded into the library. There are none in
//     `lib/` today; if that changes, this comment is where to look.
//   - A METHOD'S `startLine` IS ITS FIRST TOKEN — which for an `@override`
//     method is the annotation, one line ABOVE the signature. 🧪Two
//     extraction scripts asserted `Widget build(` at the reported line and
//     both refused before writing; the line count (`lines`) is right either
//     way, the anchor is just where the declaration begins.
//
// ## Usage
//
//   dart run tool/code_map.dart                 # ranked tables for a human
//   dart run tool/code_map.dart --json          # the whole map, for a tool
//   dart run tool/code_map.dart --top 40        # how many rows per table
//   dart run tool/code_map.dart --root lib      # what to walk (default lib)
import 'dart:convert';
import 'dart:io';

import 'package:analyzer/dart/analysis/features.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/diagnostic/diagnostic.dart';

import 'import_graph.dart';

void main(List<String> args) {
  final root = _flagValue(args, '--root') ?? 'lib';
  final top = int.tryParse(_flagValue(args, '--top') ?? '') ?? 25;
  final wantsJson = args.contains('--json');

  final map = CodeMap.walk(root);

  // ⛔UNREADABLE FILES FIRST, ALWAYS. See the header: a silent hole makes
  // every other number on this page too small.
  if (map.unreadable.isNotEmpty) {
    stderr.writeln(
      '⛔${map.unreadable.length} FILE(S) DID NOT PARSE — every '
      'count below is missing them:',
    );
    for (final entry in map.unreadable.entries) {
      stderr.writeln('  ${entry.key}: ${entry.value}');
    }
  }

  if (wantsJson) {
    stdout.writeln(const JsonEncoder.withIndent('  ').convert(map.toJson()));
  } else {
    _report(map, top);
  }
  if (map.unreadable.isNotEmpty) exit(1);
}

String? _flagValue(List<String> args, String flag) {
  final i = args.indexOf(flag);
  return i < 0 || i + 1 >= args.length ? null : args[i + 1];
}

// ─────────────────────────────────────────────────────────────────────────
// What the map holds
// ─────────────────────────────────────────────────────────────────────────

/// One function, method, getter, setter or constructor.
class FunctionFact {
  FunctionFact({
    required this.file,
    required this.owner,
    required this.name,
    required this.kind,
    required this.startLine,
    required this.endLine,
    required this.complexity,
    required this.cognitive,
    required this.parameters,
    required this.isPrivate,
  });

  final String file;

  /// The class/mixin/extension it belongs to, or null for a top-level one.
  final String? owner;
  final String name;

  /// `function` · `method` · `getter` · `setter` · `constructor`.
  final String kind;
  final int startLine;
  final int endLine;

  /// McCabe: 1 + decision points. See the header for what it does NOT say.
  final int complexity;

  /// Cognitive complexity (SonarSource) — how hard the body is to READ. The
  /// ratchet's number; see the header for the rules.
  final int cognitive;
  final int parameters;
  final bool isPrivate;

  int get lines => endLine - startLine + 1;

  /// `Owner.name`, or `name` for a top-level function.
  String get qualified => owner == null ? name : '$owner.$name';

  Map<String, dynamic> toJson() => {
    'file': file,
    if (owner != null) 'owner': owner,
    'name': name,
    'kind': kind,
    'startLine': startLine,
    'endLine': endLine,
    'lines': lines,
    'complexity': complexity,
    'cognitive': cognitive,
    'parameters': parameters,
    'isPrivate': isPrivate,
  };
}

/// One class, mixin, enum, extension or typedef.
class TypeFact {
  TypeFact({
    required this.file,
    required this.name,
    required this.kind,
    required this.startLine,
    required this.endLine,
    required this.fields,
    required this.methods,
    required this.publicMembers,
    this.constants = 0,
  });

  final String file;
  final String name;

  /// `class` · `mixin` · `enum` · `extension` · `typedef`.
  final String kind;
  final int startLine;
  final int endLine;

  /// Declared fields. ⚠️Counted separately from methods because a god object
  /// is recognised by its STATE first — 11 mid-drag fields on one session
  /// object is the shape the audit is looking for, and a method count alone
  /// would have missed it.
  final int fields;
  final int methods;
  final int publicMembers;

  /// An enum's cases. ⛔A SEPARATE NUMBER FROM [fields], because they answer
  /// different questions: [fields] is 「how much state does this hold」, which
  /// is what makes a god object, and a case list is 「how many things can this
  /// be」, which makes a wide switch instead. Folding them together would rank
  /// a 40-case enum above a session object on the state table and answer
  /// neither question — 「한 플래그가 두 질문에 답하는 것도 발명이다」.
  final int constants;

  int get lines => endLine - startLine + 1;

  Map<String, dynamic> toJson() => {
    'file': file,
    'name': name,
    'kind': kind,
    'startLine': startLine,
    'endLine': endLine,
    'lines': lines,
    'fields': fields,
    'methods': methods,
    'publicMembers': publicMembers,
    'constants': constants,
  };
}

/// One file in the walked tree.
class FileFact {
  FileFact({required this.path, required this.lines, required this.imports});

  final String path;
  final int lines;

  /// Repo-relative paths this file imports, resolved from relative URIs.
  /// ⚠️`package:` imports of OTHER packages are dropped — the map is about
  /// this tree, and an edge to `package:flutter/material.dart` would swamp
  /// every ranking without answering anything the audit asks.
  final List<String> imports;

  /// How many files in the tree import this one. Filled after the walk.
  int fanIn = 0;

  /// Which layer the path puts it in: `core` · `models` · `services` ·
  /// `controllers` · `ui` · `native` · `other`. The dependency-direction rule
  /// is stated in these words, so the map speaks them too.
  String get layer {
    for (final name in const [
      'core',
      'models',
      'services',
      'controllers',
      'ui',
      'native',
    ]) {
      if (path.contains('/$name/')) return name;
    }
    return 'other';
  }

  Map<String, dynamic> toJson() => {
    'path': path,
    'lines': lines,
    'layer': layer,
    'fanIn': fanIn,
    'imports': imports,
  };
}

/// Every fact the walk collected, plus what it could not read.
class CodeMap {
  CodeMap._();

  final files = <String, FileFact>{};
  final types = <TypeFact>[];
  final functions = <FunctionFact>[];

  /// path → why it could not be parsed. ⛔Never empty-and-ignored: `main`
  /// prints this first and exits non-zero.
  final unreadable = <String, String>{};

  static CodeMap walk(String root) {
    final map = CodeMap._();
    final dir = Directory(root);
    if (!dir.existsSync()) {
      stderr.writeln('code_map: no such directory — $root');
      exit(2);
    }
    final paths = <String>[
      for (final e in dir.listSync(recursive: true))
        if (e is File && e.path.endsWith('.dart')) _rel(e.path),
    ]..sort();

    for (final path in paths) {
      map._scan(path);
    }
    map._fillFanIn();
    return map;
  }

  void _scan(String path) {
    // ⛔READ THE FILE HERE, then `parseString`. `parseFile` looks convenient
    // but it goes through `PhysicalResourceProvider`, which demands a
    // NATIVE NORMALIZED absolute path and throws 「Path must be normalized」
    // on anything else — including the forward-slash absolute path this walk
    // produces on Windows. 🧪It failed on every file of a temp-directory
    // fixture while passing on `lib/`, which is the worst shape a path bug
    // can have: correct where it is exercised, broken where it is tested.
    // `parseString`'s `path` is only the name errors are reported under, so
    // nothing is lost.
    final String content;
    try {
      content = File(path).readAsStringSync();
    } catch (e) {
      unreadable[path] = 'could not read: $e';
      return;
    }
    final ParseStringResult parsed;
    try {
      parsed = parseString(
        content: content,
        path: path,
        featureSet: FeatureSet.latestLanguageVersion(),
        throwIfDiagnostics: false,
      );
    } catch (e) {
      unreadable[path] = '$e';
      return;
    }
    // ⚠️A syntax error does not throw with `throwIfDiagnostics: false`; it
    // comes back as a diagnostic over a PARTIAL tree. Counting a partial tree
    // is the silent hole this file exists to refuse.
    //
    // 🚨★★★COMPARE THE ENUM, NEVER ITS NAME. This line first read
    // `d.severity.name == 'ERROR'` and the real name is lowercase `error`, so
    // it matched NOTHING: the tool ran over 809 files, reported 「0 unreadable」
    // and could not have reported anything else. A green that was measuring
    // an empty set — and only a test with a deliberately broken fixture told
    // the difference.
    final fatal = parsed.errors.where((d) => d.severity == Severity.error);
    if (fatal.isNotEmpty) {
      unreadable[path] = fatal.first.message;
      return;
    }

    final lineInfo = parsed.lineInfo;
    int lineOf(int offset) => lineInfo.getLocation(offset).lineNumber;

    files[path] = FileFact(
      path: path,
      // ⚠️`lineInfo.lineCount` counts the EMPTY POSITION after a trailing
      // newline as a line, so it reads one higher than `wc -l` on every file
      // that ends properly. 🧪Measured on `lib/`: the totals differed by 809,
      // which was exactly the file count — the shape of an off-by-one-per-file
      // rather than of a real disagreement.
      lines: lineInfo.lineCount - (parsed.content.endsWith('\n') ? 1 : 0),
      // ⛔THE SHARED LAW, not a second opinion — see `import_graph.dart`.
      imports: importsOf(path, content).toList()..sort(),
    );

    parsed.unit.accept(_DeclarationVisitor(this, path, lineOf));
  }

  void _fillFanIn() {
    for (final file in files.values) {
      for (final target in file.imports) {
        files[target]?.fanIn += 1;
      }
    }
  }

  Map<String, dynamic> toJson() => {
    'files': [
      for (final path in files.keys.toList()..sort()) files[path]!.toJson(),
    ],
    'types': [for (final t in types) t.toJson()],
    'functions': [for (final f in functions) f.toJson()],
    'unreadable': unreadable,
    'totals': {
      'files': files.length,
      'types': types.length,
      'functions': functions.length,
      'lines': files.values.fold<int>(0, (a, f) => a + f.lines),
    },
  };
}

// ─────────────────────────────────────────────────────────────────────────
// Reading one file
// ─────────────────────────────────────────────────────────────────────────

/// Collects one file's declarations.
///
/// ⚠️Tracks the enclosing type by hand rather than walking up `parent`,
/// because a method's owner is the thing every ranking groups by and a null
/// there is indistinguishable from a top-level function.
class _DeclarationVisitor extends RecursiveAstVisitor<void> {
  _DeclarationVisitor(this.map, this.path, this.lineOf);

  final CodeMap map;
  final String path;
  final int Function(int offset) lineOf;

  String? _owner;

  void _inType(String name, void Function() body) {
    final previous = _owner;
    _owner = name;
    body();
    _owner = previous;
  }

  void _addType(
    String name,
    String kind,
    AstNode node,
    List<ClassMember> members, {
    int constants = 0,
  }) {
    var fields = 0;
    var methods = 0;
    var public = 0;
    for (final member in members) {
      if (member is FieldDeclaration) {
        for (final v in member.fields.variables) {
          fields += 1;
          if (!v.name.lexeme.startsWith('_')) public += 1;
        }
      } else if (member is MethodDeclaration) {
        methods += 1;
        if (!member.name.lexeme.startsWith('_')) public += 1;
      } else if (member is ConstructorDeclaration) {
        methods += 1;
        if (!(member.name?.lexeme ?? '').startsWith('_')) public += 1;
      }
    }
    map.types.add(
      TypeFact(
        file: path,
        name: name,
        kind: kind,
        startLine: lineOf(node.offset),
        endLine: lineOf(node.end),
        fields: fields,
        methods: methods,
        publicMembers: public,
        constants: constants,
      ),
    );
  }

  void _addFunction(
    String name,
    String kind,
    AstNode node,
    FormalParameterList? params,
    AstNode? body,
  ) {
    map.functions.add(
      FunctionFact(
        file: path,
        owner: _owner,
        name: name,
        kind: kind,
        startLine: lineOf(node.offset),
        endLine: lineOf(node.end),
        complexity: _complexityOf(body),
        cognitive: _cognitiveOf(body),
        parameters: params?.parameters.length ?? 0,
        isPrivate: name.startsWith('_'),
      ),
    );
  }

  // ⚠️analyzer 13 spells the name and the member list DIFFERENTLY per
  // declaration — `ClassDeclaration` and `EnumDeclaration` carry a
  // `namePart.typeName`, while `MixinDeclaration` and `ExtensionDeclaration`
  // still carry a plain `name`. All four hold their members under `body`.
  // Read from the package before changing these; guessing produced four
  // wrong spellings on the first attempt.

  @override
  void visitClassDeclaration(ClassDeclaration node) {
    final name = node.namePart.typeName.lexeme;
    _addType(name, 'class', node, node.body.members);
    _inType(name, () => super.visitClassDeclaration(node));
  }

  @override
  void visitMixinDeclaration(MixinDeclaration node) {
    _addType(node.name.lexeme, 'mixin', node, node.body.members);
    _inType(node.name.lexeme, () => super.visitMixinDeclaration(node));
  }

  @override
  void visitEnumDeclaration(EnumDeclaration node) {
    final name = node.namePart.typeName.lexeme;
    _addType(
      name,
      'enum',
      node,
      node.body.members,
      constants: node.body.constants.length,
    );
    _inType(name, () => super.visitEnumDeclaration(node));
  }

  @override
  void visitExtensionDeclaration(ExtensionDeclaration node) {
    final name = node.name?.lexeme ?? '(unnamed extension)';
    _addType(name, 'extension', node, node.body.members);
    _inType(name, () => super.visitExtensionDeclaration(node));
  }

  @override
  void visitGenericTypeAlias(GenericTypeAlias node) {
    _addType(node.name.lexeme, 'typedef', node, const []);
    super.visitGenericTypeAlias(node);
  }

  @override
  void visitFunctionDeclaration(FunctionDeclaration node) {
    // ⚠️Only TOP-LEVEL ones land here as functions; a local function inside a
    // body also visits here, and its complexity is already counted inside its
    // enclosing member. Guarding on the parent keeps it from being counted
    // twice — once as itself and once inside its owner.
    if (node.parent is CompilationUnit) {
      _addFunction(
        node.name.lexeme,
        node.isGetter
            ? 'getter'
            : node.isSetter
            ? 'setter'
            : 'function',
        node,
        node.functionExpression.parameters,
        node.functionExpression.body,
      );
    }
    super.visitFunctionDeclaration(node);
  }

  @override
  void visitMethodDeclaration(MethodDeclaration node) {
    _addFunction(
      node.name.lexeme,
      node.isGetter
          ? 'getter'
          : node.isSetter
          ? 'setter'
          : 'method',
      node,
      node.parameters,
      node.body,
    );
    super.visitMethodDeclaration(node);
  }

  @override
  void visitConstructorDeclaration(ConstructorDeclaration node) {
    _addFunction(
      node.name?.lexeme ?? '(default)',
      'constructor',
      node,
      node.parameters,
      node.body,
    );
    super.visitConstructorDeclaration(node);
  }
}

/// McCabe complexity of one body: 1 + every point the control flow forks.
///
/// ⚠️`&&`, `||` and `??` count. A condition with three `&&` is three more
/// ways through the function, and a version that only counted statements
/// would score the app's guard-heavy predicates at 1.
int _complexityOf(AstNode? body) {
  if (body == null) return 1;
  final counter = _ComplexityVisitor();
  body.accept(counter);
  return 1 + counter.points;
}

class _ComplexityVisitor extends RecursiveAstVisitor<void> {
  int points = 0;

  @override
  void visitIfStatement(IfStatement node) {
    points += 1;
    super.visitIfStatement(node);
  }

  @override
  void visitConditionalExpression(ConditionalExpression node) {
    points += 1;
    super.visitConditionalExpression(node);
  }

  @override
  void visitForStatement(ForStatement node) {
    points += 1;
    super.visitForStatement(node);
  }

  @override
  void visitForElement(ForElement node) {
    points += 1;
    super.visitForElement(node);
  }

  @override
  void visitIfElement(IfElement node) {
    points += 1;
    super.visitIfElement(node);
  }

  @override
  void visitWhileStatement(WhileStatement node) {
    points += 1;
    super.visitWhileStatement(node);
  }

  @override
  void visitDoStatement(DoStatement node) {
    points += 1;
    super.visitDoStatement(node);
  }

  @override
  void visitCatchClause(CatchClause node) {
    points += 1;
    super.visitCatchClause(node);
  }

  @override
  void visitSwitchCase(SwitchCase node) {
    points += 1;
    super.visitSwitchCase(node);
  }

  @override
  void visitSwitchPatternCase(SwitchPatternCase node) {
    points += 1;
    super.visitSwitchPatternCase(node);
  }

  @override
  void visitSwitchExpressionCase(SwitchExpressionCase node) {
    points += 1;
    super.visitSwitchExpressionCase(node);
  }

  @override
  void visitBinaryExpression(BinaryExpression node) {
    const forks = {'&&', '||', '??'};
    if (forks.contains(node.operator.lexeme)) points += 1;
    super.visitBinaryExpression(node);
  }
}

/// Cognitive complexity (SonarSource, 2017) of one body — see the header.
int _cognitiveOf(AstNode? body) {
  if (body == null) return 0;
  final counter = _CognitiveVisitor();
  body.accept(counter);
  return counter.score;
}

class _CognitiveVisitor extends RecursiveAstVisitor<void> {
  int score = 0;
  int _nesting = 0;

  void _nested(void Function() body) {
    _nesting++;
    body();
    _nesting--;
  }

  /// A structure that nests: +1, plus the depth it sits at.
  void _structure() => score += 1 + _nesting;

  @override
  void visitIfStatement(IfStatement node) {
    _structure();
    node.expression.accept(this);
    _nested(() => node.thenStatement.accept(this));
    _else(node.elseStatement);
  }

  /// `else if` and `else` are +1 each WITHOUT the nesting add-on — the
  /// reader is already inside the if.
  void _else(Statement? elseStatement) {
    if (elseStatement == null) return;
    score += 1;
    if (elseStatement is IfStatement) {
      elseStatement.expression.accept(this);
      _nested(() => elseStatement.thenStatement.accept(this));
      _else(elseStatement.elseStatement);
      return;
    }
    _nested(() => elseStatement.accept(this));
  }

  @override
  void visitConditionalExpression(ConditionalExpression node) {
    _structure();
    node.condition.accept(this);
    _nested(() {
      node.thenExpression.accept(this);
      node.elseExpression.accept(this);
    });
  }

  @override
  void visitSwitchStatement(SwitchStatement node) {
    _structure();
    node.expression.accept(this);
    _nested(() => node.members.accept(this));
  }

  @override
  void visitSwitchExpression(SwitchExpression node) {
    _structure();
    node.expression.accept(this);
    _nested(() => node.cases.accept(this));
  }

  @override
  void visitForStatement(ForStatement node) {
    _structure();
    node.forLoopParts.accept(this);
    _nested(() => node.body.accept(this));
  }

  @override
  void visitWhileStatement(WhileStatement node) {
    _structure();
    node.condition.accept(this);
    _nested(() => node.body.accept(this));
  }

  @override
  void visitDoStatement(DoStatement node) {
    _structure();
    node.condition.accept(this);
    _nested(() => node.body.accept(this));
  }

  @override
  void visitCatchClause(CatchClause node) {
    _structure();
    _nested(() => node.body.accept(this));
  }

  @override
  void visitIfElement(IfElement node) {
    _structure();
    node.expression.accept(this);
    _nested(() {
      node.thenElement.accept(this);
      node.elseElement?.accept(this);
    });
  }

  @override
  void visitForElement(ForElement node) {
    _structure();
    node.forLoopParts.accept(this);
    _nested(() => node.body.accept(this));
  }

  /// A run of the same boolean operator is one increment; `a && b && c` is
  /// one thought, `a && b || c` is two.
  @override
  void visitBinaryExpression(BinaryExpression node) {
    final op = node.operator.lexeme;
    if (op == '&&' || op == '||') {
      final parent = node.parent;
      final continuesRun =
          parent is BinaryExpression && parent.operator.lexeme == op;
      if (!continuesRun) score += 1;
    }
    super.visitBinaryExpression(node);
  }

  /// A lambda's body nests (a local function's too): what happens inside a
  /// callback is one level further from the reader.
  @override
  void visitFunctionExpression(FunctionExpression node) {
    _nested(() => super.visitFunctionExpression(node));
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Paths
// ─────────────────────────────────────────────────────────────────────────

String _rel(String path) {
  final p = path.replaceAll(r'\', '/');
  final cwd = Directory.current.path.replaceAll(r'\', '/');
  return p.startsWith('$cwd/') ? p.substring(cwd.length + 1) : p;
}

// ─────────────────────────────────────────────────────────────────────────
// The human report
// ─────────────────────────────────────────────────────────────────────────

void _report(CodeMap map, int top) {
  final totalLines = map.files.values.fold<int>(0, (a, f) => a + f.lines);
  stdout.writeln('CODE MAP');
  stdout.writeln('  files      ${map.files.length}');
  stdout.writeln('  lines      $totalLines');
  stdout.writeln('  types      ${map.types.length}');
  stdout.writeln('  functions  ${map.functions.length}');
  stdout.writeln('');

  final byLayer = <String, List<FileFact>>{};
  for (final f in map.files.values) {
    byLayer.putIfAbsent(f.layer, () => []).add(f);
  }
  stdout.writeln('BY LAYER');
  for (final layer in byLayer.keys.toList()..sort()) {
    final group = byLayer[layer]!;
    final lines = group.fold<int>(0, (a, f) => a + f.lines);
    stdout.writeln(
      '  ${layer.padRight(12)}'
      '${group.length.toString().padLeft(5)} files'
      '${lines.toString().padLeft(9)} lines',
    );
  }
  stdout.writeln('');

  _table(
    'BIGGEST TYPES (lines)',
    (map.types.toList()..sort((a, b) => b.lines.compareTo(a.lines))).take(top),
    (t) =>
        '${t.lines.toString().padLeft(6)}  '
        '${t.fields.toString().padLeft(3)}f '
        '${t.methods.toString().padLeft(3)}m  '
        '${t.name}  (${t.file}:${t.startLine})',
  );

  _table(
    'MOST STATE (fields) — a god object is its state first',
    (map.types.toList()..sort((a, b) => b.fields.compareTo(a.fields))).take(
      top,
    ),
    (t) =>
        '${t.fields.toString().padLeft(6)}f '
        '${t.methods.toString().padLeft(4)}m  '
        '${t.name}  (${t.file}:${t.startLine})',
  );

  _table(
    'MOST COMPLEX FUNCTIONS (decision points)',
    (map.functions.toList()
          ..sort((a, b) => b.complexity.compareTo(a.complexity)))
        .take(top),
    (f) =>
        '${f.complexity.toString().padLeft(6)}  '
        '${f.lines.toString().padLeft(5)}L  '
        '${f.qualified}  (${f.file}:${f.startLine})',
  );

  _table(
    'HARDEST TO READ (cognitive complexity — the ratchet\'s number)',
    (map.functions.toList()..sort((a, b) => b.cognitive.compareTo(a.cognitive)))
        .take(top),
    (f) =>
        '${f.cognitive.toString().padLeft(6)}  '
        '${f.lines.toString().padLeft(5)}L  '
        '${f.qualified}  (${f.file}:${f.startLine})',
  );

  _table(
    'LONGEST FUNCTIONS (lines)',
    (map.functions.toList()..sort((a, b) => b.lines.compareTo(a.lines))).take(
      top,
    ),
    (f) =>
        '${f.lines.toString().padLeft(6)}L '
        '${f.complexity.toString().padLeft(5)}c  '
        '${f.qualified}  (${f.file}:${f.startLine})',
  );

  _table(
    'MOST DEPENDED ON (fan-in)',
    (map.files.values.toList()..sort((a, b) => b.fanIn.compareTo(a.fanIn)))
        .take(top),
    (f) =>
        '${f.fanIn.toString().padLeft(6)}  '
        '${f.lines.toString().padLeft(6)}L  ${f.path}',
  );
}

void _table<T>(String title, Iterable<T> rows, String Function(T) line) {
  stdout.writeln(title);
  for (final row in rows) {
    stdout.writeln('  ${line(row)}');
  }
  stdout.writeln('');
}
