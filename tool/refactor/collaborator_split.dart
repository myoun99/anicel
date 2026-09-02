// Carves ONE family of members out of a god class into a collaborator
// class in a part file (same library — private seams stay private). The
// generalised form of range_move_split.dart, driven by a JSON spec:
//
//   {
//     "mainPath":   "lib/src/ui/editor_session_manager.dart",
//     "className":  "EditorSessionManager",
//     "partPath":   "lib/src/ui/session/edge_drag.dart",
//     "partOf":     "../editor_session_manager.dart",
//     "collaborator": "_EdgeDrag",
//     "field":      "_edgeDrag",
//     "family":     ["beginExposureEdgeDrag", ...],   // methods that move
//     "statePrefixes": ["_edgeDrag", ...],            // fields/accessors that move by name
//     "doc":        ["/// ...", ...],                 // the collaborator's class doc
//     "door":       ["// ...", ...]                   // the comment over the session's field
//   }
//
// Mechanics (analyzer-driven, unresolved AST):
//   · a member MOVES if it is in `family` or its name starts with a state
//     prefix;
//   · inside a moved body, a bare identifier that names a session member
//     which is NOT moved becomes `_session.<name>` — unless that method
//     declares a local or parameter of the same name;
//   · inside a kept body, a bare identifier that names a MOVED member
//     becomes `<field>.<name>`;
//   · `notifyListeners()` in moved bodies becomes `_session._notifyChanged()`
//     — the door the session grew for its first collaborator (added here
//     only if absent);
//   · public methods in `family` keep a one-line forwarder on the session.
//
// Usage: dart run <this> <spec.json> [--dry]
import 'dart:convert';
import 'dart:io';

import 'package:analyzer/dart/analysis/features.dart';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';

void must(bool ok, String what) {
  if (!ok) {
    stderr.writeln('REFUSED: $what');
    exit(3);
  }
}

String _formatted(String members) {
  final tmp = File('${Directory.systemTemp.path}/_door_fmt.dart');
  tmp.writeAsStringSync('class _Door {\n$members}\n');
  final r = Process.runSync('dart', ['format', tmp.path]);
  must(r.exitCode == 0, 'dart format: ${r.stderr}');
  final lines = tmp.readAsStringSync().replaceAll('\r\n', '\n').split('\n');
  must(lines.first == 'class _Door {', 'formatted scratch shape');
  final end = lines.lastIndexOf('}');
  return '${lines.sublist(1, end).join('\n')}\n\n';
}

class _Locals extends RecursiveAstVisitor<void> {
  _Locals(FormalParameterList? params) {
    _params(params);
  }
  final names = <String>{};

  void _params(FormalParameterList? params) {
    if (params == null) return;
    for (final p in params.parameters) {
      final n = p.name?.lexeme;
      if (n != null) names.add(n);
    }
  }

  // A lambda's parameters shadow only INSIDE the lambda — `(context) =>`
  // in one builder must not hide the State's `context` elsewhere in the
  // method — so they are resolved by the enclosing-function walk in _Refs,
  // not by this method-wide set (which is why there is no
  // visitFunctionExpression here).

  @override
  void visitVariableDeclaration(VariableDeclaration node) {
    names.add(node.name.lexeme);
    super.visitVariableDeclaration(node);
  }

  @override
  void visitDeclaredIdentifier(DeclaredIdentifier node) {
    names.add(node.name.lexeme);
    super.visitDeclaredIdentifier(node);
  }

  @override
  void visitCatchClause(CatchClause node) {
    final e = node.exceptionParameter?.name.lexeme;
    final s = node.stackTraceParameter?.name.lexeme;
    if (e != null) names.add(e);
    if (s != null) names.add(s);
    super.visitCatchClause(node);
  }

  @override
  void visitFunctionDeclarationStatement(FunctionDeclarationStatement node) {
    names.add(node.functionDeclaration.name.lexeme);
    super.visitFunctionDeclarationStatement(node);
  }

  @override
  void visitDeclaredVariablePattern(DeclaredVariablePattern node) {
    names.add(node.name.lexeme);
    super.visitDeclaredVariablePattern(node);
  }
}

class _Refs extends RecursiveAstVisitor<void> {
  _Refs(this.targets, this.locals);
  final Set<String> targets;
  final Set<String> locals;
  final hits = <SimpleIdentifier>[];
  final thisNodes = <ThisExpression>[];

  @override
  void visitThisExpression(ThisExpression node) {
    thisNodes.add(node);
    super.visitThisExpression(node);
  }

  bool _shadowedByAnEnclosingLambda(SimpleIdentifier node) {
    for (var a = node.parent; a != null; a = a.parent) {
      if (a is FunctionExpression) {
        final params = a.parameters?.parameters ?? const [];
        if (params.any((p) => p.name?.lexeme == node.name)) return true;
      }
    }
    return false;
  }

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    final name = node.name;
    if (!targets.contains(name) || locals.contains(name)) return;
    if (_shadowedByAnEnclosingLambda(node)) return;
    final p = node.parent;
    if (p is PrefixedIdentifier && p.identifier == node) return;
    if (p is PropertyAccess && p.propertyName == node) return;
    if (p is MethodInvocation &&
        p.methodName == node &&
        (p.target != null || p.isCascaded)) {
      return;
    }
    if (p is Label) return;
    if (p is NamedType) return;
    hits.add(node);
  }
}

class _Member {
  _Member(
    this.name,
    this.node,
    this.start,
    this.end,
    this.isField,
    this.isStatic,
  );
  final String name;
  final ClassMember node;
  final int start;
  final int end;
  final bool isField;
  // A static member is reached through its CLASS, not through the host or
  // the collaborator field — on either side of the cut.
  final bool isStatic;
}

void main(List<String> args) {
  must(args.isNotEmpty, 'usage: <spec.json> [--dry]');
  final dry = args.contains('--dry');
  final spec =
      jsonDecode(File(args[0]).readAsStringSync()) as Map<String, dynamic>;
  final mainPath = spec['mainPath'] as String;
  final className = spec['className'] as String;
  final partPath = spec['partPath'] as String;
  final partOf = spec['partOf'] as String;
  final collaborator = spec['collaborator'] as String;
  final field = spec['field'] as String;
  final family = (spec['family'] as List).cast<String>().toSet();
  final prefixes = (spec['statePrefixes'] as List).cast<String>();
  final doc = (spec['doc'] as List).cast<String>();
  final doorLines = (spec['door'] as List).cast<String>();
  final hostRef = (spec['hostRef'] as String?) ?? '_session';
  final protectedMap =
      ((spec['protected'] as Map?) ?? {'notifyListeners': '_notifyChanged'})
          .cast<String, String>();
  final inherited = ((spec['inherited'] as List?) ?? const []).cast<String>();
  final doorMethod =
      ((spec['doorMethod'] as List?) ??
              const [
                '  /// The door a collaborator announces through - notifyListeners is',
                '  /// protected, and a collaborator is not a subclass.',
                '  void _notifyChanged() => notifyListeners();',
              ])
          .cast<String>();
  // The directive is relative to the HOST's directory, wherever that is.
  final hostDir = mainPath.substring(0, mainPath.lastIndexOf('/') + 1);
  must(partPath.startsWith(hostDir), 'the part must live under the host\'s directory: $hostDir');
  final partDirective = "part '${partPath.substring(hostDir.length)}';";

  final raw = File(mainPath).readAsStringSync();
  final crlf = raw.contains('\r\n');
  final src = crlf ? raw.replaceAll('\r\n', '\n') : raw;
  final unit = parseString(
    content: src,
    path: mainPath,
    featureSet: FeatureSet.latestLanguageVersion(),
    throwIfDiagnostics: false,
  ).unit;
  // --append: the collaborator already exists; move MORE private members
  // into it (the orphan check found helpers only the family reads).
  final append = args.contains('--append');
  must(
    append == src.contains(partDirective),
    append
        ? 'append needs the split: $partDirective'
        : 'already split: $partDirective',
  );
  must(
    append == File(partPath).existsSync(),
    '$partPath ${append ? 'missing' : 'exists'}',
  );
  must(
    !append || family.every((n) => n.startsWith('_')),
    'append mode moves private members only',
  );
  ClassDeclaration? cls;
  for (final d in unit.declarations) {
    if (d is ClassDeclaration && d.namePart.typeName.lexeme == className) {
      cls = d;
    }
  }
  must(cls != null, '$className not found');

  final all = <_Member>[];
  for (final m in cls!.body.members) {
    final start =
        m.documentationComment?.offset ??
        m.firstTokenAfterCommentAndMetadata.offset;
    if (m is MethodDeclaration) {
      all.add(_Member(m.name.lexeme, m, start, m.end, false, m.isStatic));
    } else if (m is FieldDeclaration) {
      must(
        m.fields.variables.length == 1,
        'multi-variable field at ${m.offset}',
      );
      final n = m.fields.variables.first.name.lexeme;
      all.add(_Member(n, m, start, m.end, true, m.isStatic));
    }
  }
  final names = {for (final m in all) m.name};
  final statics = {
    for (final m in all)
      if (m.isStatic) m.name,
  };
  final moved = <String>{
    for (final n in names)
      if (family.contains(n) || prefixes.any(n.startsWith)) n,
  };
  for (final f in family) {
    must(names.contains(f), 'family member $f not found');
  }
  final kept = names.difference(moved);
  final movedMembers = all.where((m) => moved.contains(m.name)).toList();
  stdout.writeln(
    'members ${all.length}; moving ${movedMembers.length} '
    '(${movedMembers.where((m) => m.isField).length} fields, '
    '${movedMembers.where((m) => !m.isField).length} methods/accessors)',
  );
  stdout.writeln('  moved: ${moved.join(' ')}');

  final edits = <(int, int, String)>[];
  final partPieces = <String>[];
  var sessionRefs = 0;
  var notifies = 0;
  for (final m in movedMembers) {
    // (name kept in m.name)
    var text = src.substring(m.start, m.end);
    if (m.isField) {
      // A moved FIELD's initialiser may name session members (an enforcer
      // built over the session's caches). Those become `_session.x`, which
      // needs `this` — so the field becomes `late` if it was not.
      final fields = (m.node as FieldDeclaration).fields;
      final refs = _Refs({...kept, ...inherited}, const {});
      fields.accept(refs);
      if (refs.hits.isNotEmpty) {
        final local = <(int, int, String)>[];
        for (final id in refs.hits) {
          final rel = id.offset - m.start;
          local.add((
            rel,
            rel,
            statics.contains(id.name) ? '$className.' : '$hostRef.',
          ));
          sessionRefs++;
        }
        if (fields.lateKeyword == null &&
            refs.hits.any((id) => !statics.contains(id.name))) {
          final rel = fields.offset - m.start;
          local.add((rel, rel, 'late '));
        }
        local.sort((a, b) => b.$1.compareTo(a.$1));
        for (final (a, b, r) in local) {
          text = text.replaceRange(a, b, r);
        }
      }
    }
    if (!m.isField) {
      final locals = _Locals((m.node as MethodDeclaration).parameters);
      m.node.accept(locals);
      final refs = _Refs({
        ...kept,
        ...protectedMap.keys,
        ...inherited,
      }, locals.names);
      m.node.accept(refs);
      final local = <(int, int, String)>[];
      // `this` in a session method IS the session — the collaborator hands
      // `_session` where the session handed itself.
      for (final t in refs.thisNodes) {
        final rel = t.offset - m.start;
        local.add((rel, rel + 4, hostRef));
        sessionRefs++;
      }
      for (final id in refs.hits) {
        final name = id.name;
        final rel = id.offset - m.start;
        if (protectedMap.containsKey(name)) {
          local.add((rel, rel + name.length, '$hostRef.${protectedMap[name]}'));
          notifies++;
        } else {
          local.add((
            rel,
            rel,
            statics.contains(name) ? '$className.' : '$hostRef.',
          ));
          sessionRefs++;
        }
      }
      local.sort((a, b) => b.$1.compareTo(a.$1));
      for (final (a, b, r) in local) {
        text = text.replaceRange(a, b, r);
      }
    }
    partPieces.add(text);
    var end = m.end;
    if (end < src.length && src[end] == '\n') end++;
    if (end < src.length && src[end] == '\n') end++;
    final lineStart = src.lastIndexOf('\n', m.start - 1) + 1;
    edits.add((lineStart, end, ''));
  }
  stdout.writeln(
    'session refs prefixed: $sessionRefs; notifyListeners → _notifyChanged: $notifies',
  );

  // Kept bodies: a PUBLIC family member keeps its forwarder, so a bare call
  // still works; a PRIVATE one is reached through the field — and a private
  // METHOD the rest calls is the collaborator's interface, so it loses its
  // underscore (the class itself is library-private).
  var backRefs = 0;
  final readers = <String, int>{};
  final privateMoved = moved.where((n) => n.startsWith('_')).toSet();
  final renames = <String, String>{};
  final backHits = <(SimpleIdentifier, String)>[];
  void backRefsIn(AstNode node, FormalParameterList? params, String owner) {
    final locals = _Locals(params);
    node.accept(locals);
    final refs = _Refs(privateMoved, locals.names);
    node.accept(refs);
    for (final id in refs.hits) {
      backHits.add((id, owner));
      final target = all.firstWhere((x) => x.name == id.name);
      final candidate = id.name.substring(1);
      // The public name must be free: not a member, and not a name the
      // file already uses bare (a top-level function of the same name —
      // `railSwipeColumns` — would be shadowed inside the collaborator).
      final usedBare = RegExp(
        '(?<![A-Za-z0-9_.])${RegExp.escape(candidate)}(?![A-Za-z0-9_])',
      ).hasMatch(src);
      if (!target.isField && !names.contains(candidate) && !usedBare) {
        renames[id.name] = candidate;
      }
    }
  }

  for (final m in all.where((m) => kept.contains(m.name))) {
    // A kept FIELD's initialiser can name a moved member too (a callback
    // handed to a helper object) — walk it like a body.
    if (m.isField) {
      backRefsIn(
        (m.node as FieldDeclaration).fields,
        null,
        '${m.name} (field)',
      );
      continue;
    }
    backRefsIn(m.node, (m.node as MethodDeclaration).parameters, m.name);
  }
  for (final c in cls.body.members.whereType<ConstructorDeclaration>()) {
    backRefsIn(c, c.parameters, '${c.name?.lexeme ?? className} (constructor)');
  }
  for (final (id, reader) in backHits) {
    final via = statics.contains(id.name) ? collaborator : field;
    edits.add((id.offset, id.end, '$via.${renames[id.name] ?? id.name}'));
    backRefs++;
    readers[reader] = (readers[reader] ?? 0) + 1;
  }
  if (renames.isNotEmpty) {
    for (var i = 0; i < partPieces.length; i++) {
      var text = partPieces[i];
      for (final e in renames.entries) {
        text = text.replaceAll(
          RegExp('(?<![A-Za-z0-9_.])${RegExp.escape(e.key)}(?![A-Za-z0-9_])'),
          e.value,
        );
      }
      partPieces[i] = text;
    }
    stdout.writeln(
      'interface (private methods the rest calls, made public on the collaborator): '
      '${renames.entries.map((e) => '${e.key}→${e.value}').join(' ')}',
    );
  }
  stdout.writeln(
    'kept bodies now read the family through $field: $backRefs '
    '${readers.isEmpty ? '' : readers.toString()}',
  );

  // A moved STATIC that the code reached as `Host._name` is now
  // `Collaborator.name` outside the collaborator and bare inside it —
  // the parser sees `Host._name` as a prefixed identifier, not a bare
  // reference, so the visitor above never met it.
  final movedStatics = {
    for (final n in moved)
      if (statics.contains(n)) n,
  };
  String requalify(String text, {required bool inside}) {
    for (final n in movedStatics) {
      final re = RegExp(
        '${RegExp.escape(className)}\\s*\\.\\s*${RegExp.escape(n)}(?![A-Za-z0-9_])',
      );
      final to = renames[n] ?? n;
      text = text.replaceAll(re, inside ? to : '$collaborator.$to');
    }
    return text;
  }
  for (var i = 0; i < partPieces.length; i++) {
    partPieces[i] = requalify(partPieces[i], inside: true);
  }

  final forwarders = StringBuffer();
  for (final n in family) {
    if (n.startsWith('_')) continue;
    final m =
        all.firstWhere((m) => m.name == n && !m.isField).node
            as MethodDeclaration;
    final retType = m.returnType == null
        ? ''
        : '${src.substring(m.returnType!.offset, m.returnType!.end)} ';
    if (m.isGetter) {
      forwarders.writeln('  ${retType}get $n => $field.$n;');
      continue;
    }
    if (m.isSetter) {
      final p = m.parameters!.parameters.single;
      forwarders.writeln(
        '  set $n(${src.substring(p.offset, p.end)}) => $field.$n = ${p.name!.lexeme};',
      );
      continue;
    }
    final params = m.parameters!;
    final args = <String>[];
    for (final p in params.parameters) {
      final name = p.name!.lexeme;
      args.add(p.isNamed ? '$name: $name' : name);
    }
    final ret = m.returnType == null
        ? ''
        : '${src.substring(m.returnType!.offset, m.returnType!.end)} ';
    final sig = src.substring(params.offset, params.end);
    // A static stays static — reached through the collaborator's CLASS.
    if (m.isStatic) {
      forwarders.writeln(
        '  static $ret$n$sig => $collaborator.$n(${args.join(', ')});',
      );
      continue;
    }
    forwarders.writeln('  $ret$n$sig => $field.$n(${args.join(', ')});');
  }
  final hasDoor = src.contains(doorMethod.last.trim());
  final doorRaw = StringBuffer();
  for (final l in doorLines) {
    doorRaw.writeln('  $l');
  }
  // A host with a const constructor cannot hold a late field; a stateless
  // collaborator (no fields moved) is then handed out by a getter, built
  // per call — nothing of it outlives the call.
  final fieldAsGetter = spec['fieldAsGetter'] == true;
  if (fieldAsGetter) {
    must(
      movedMembers.every((m) => !m.isField),
      'fieldAsGetter needs a stateless collaborator (no fields move)',
    );
    doorRaw.writeln('  $collaborator get $field => $collaborator(this);');
  } else {
    doorRaw.writeln(
      '  late final $collaborator $field = $collaborator(this);',
    );
  }
  doorRaw.writeln();
  // The door is grown the first time a family actually announces through
  // it — an unused door is an unused_element warning.
  if (!hasDoor && notifies > 0) {
    for (final l in doorMethod) {
      doorRaw.writeln(l);
    }
    doorRaw.writeln();
  }
  doorRaw.write(forwarders);
  if (!append) {
    final door = _formatted(doorRaw.toString());
    final firstMoved = movedMembers
        .map((m) => m.start)
        .reduce((a, b) => a < b ? a : b);
    final firstLine = src.lastIndexOf('\n', firstMoved - 1) + 1;
    edits.add((firstLine, firstLine, door));

    final lastPart = unit.directives.whereType<PartDirective>().lastOrNull;
    final lastHeader = unit.directives
        .where((d) => d is ImportDirective || d is ExportDirective)
        .last;
    final anchor = lastPart?.end ?? lastHeader.end;
    edits.add((
      anchor,
      anchor,
      lastPart == null ? '\n\n$partDirective' : '\n$partDirective',
    ));
  }

  edits.sort(
    (a, b) => a.$1 != b.$1 ? b.$1.compareTo(a.$1) : b.$2.compareTo(a.$2),
  );
  var out = src;
  int? last;
  for (final (a, b, r) in edits) {
    must(last == null || b <= last, 'overlapping edits at $a..$b');
    out = out.replaceRange(a, b, r);
    last = a;
  }
  out = requalify(out, inside: false);

  final part = StringBuffer();
  if (append) {
    var existing = File(partPath).readAsStringSync().replaceAll('\r\n', '\n');
    // The collaborator used to reach these through the session; now they
    // are its own. Other collaborators reach them through the session's
    // field for this one (private, same library).
    for (final n in moved) {
      final re = RegExp(
        '${RegExp.escape(hostRef)}\\.${RegExp.escape(n)}(?![A-Za-z0-9_])',
      );
      existing = existing.replaceAll(re, n);
      for (final f in File(partPath).parent.listSync().whereType<File>()) {
        if (f.path.replaceAll(r'\', '/') == partPath.replaceAll(r'\', '/')) {
          continue;
        }
        if (!f.path.endsWith('.dart')) continue;
        final other = f.readAsStringSync();
        if (!re.hasMatch(other)) continue;
        f.writeAsStringSync(other.replaceAll(re, '$hostRef.$field.$n'));
        stdout.writeln('  ${f.path}: $hostRef.$n → $hostRef.$field.$n');
      }
    }
    final close = existing.lastIndexOf('\n}');
    must(close > 0, 'part file has no closing brace');
    part.write(existing.substring(0, close + 1));
    part.writeln();
    for (final piece in partPieces) {
      part.writeln(piece);
      part.writeln();
    }
    part.writeln('}');
  } else {
    part
      ..writeln("part of '$partOf';")
      ..writeln();
    for (final l in doc) {
      part.writeln(l);
    }
    part
      ..writeln('class $collaborator {')
      ..writeln('  $collaborator(this.$hostRef);')
      ..writeln()
      ..writeln('  final $className $hostRef;')
      ..writeln();
    for (final piece in partPieces) {
      part.writeln(piece);
      part.writeln();
    }
    part.writeln('}');
  }

  // The OTHER collaborators reach a moved private member through the
  // session's field for this one (a public one keeps its forwarder).
  final otherEdits = <String, String>{};
  if (!append) {
    final dir = File(partPath).parent;
    if (dir.existsSync()) {
      for (final f in dir.listSync().whereType<File>()) {
        if (!f.path.endsWith('.dart')) continue;
        var text = f.readAsStringSync();
        final original = text;
        for (final n in privateMoved) {
          // The formatter may have wrapped `_session\n    .member(` — match
          // across the whitespace; the batch reformats the file after.
          final re = RegExp(
            '${RegExp.escape(hostRef)}\\s*\\.\\s*${RegExp.escape(n)}(?![A-Za-z0-9_])',
          );
          if (!re.hasMatch(text)) continue;
          text = text.replaceAll(re, '$hostRef.$field.${renames[n] ?? n}');
          stdout.writeln(
            '  ${f.path.split(RegExp(r'[\\/]')).last}: $hostRef.$n → $hostRef.$field.${renames[n] ?? n}',
          );
        }
        text = requalify(text, inside: false);
        if (text != original) otherEdits[f.path] = text;
      }
    }
  }

  if (dry) {
    stdout.writeln(
      'DRY — main ${out.split('\n').length} lines (was ${src.split('\n').length}); part ${part.toString().split('\n').length} lines',
    );
    File(
      '${Directory.systemTemp.path}/collab_part_dry.dart',
    ).writeAsStringSync(part.toString());
    return;
  }
  for (final e in otherEdits.entries) {
    File(e.key).writeAsStringSync(e.value);
  }
  File(partPath).parent.createSync(recursive: true);
  File(mainPath).writeAsStringSync(crlf ? out.replaceAll('\n', '\r\n') : out);
  File(partPath).writeAsStringSync(
    crlf ? part.toString().replaceAll('\n', '\r\n') : part.toString(),
  );
  stdout.writeln(
    'OK collaborator_split — main ${out.split('\n').length} lines; $partPath written',
  );
}
