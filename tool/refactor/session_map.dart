// ignore_for_file: avoid_print
// The god-object map (round 8, 2026-09-06): what every part of the
// EditorSessionManager library touches of the host, measured by the AST
// instead of read by eye. A `part` splits a FILE, not a class — the 40
// parts are one class in more files, and this is the evidence: for each
// collaborator/extension member, which host fields it reads and writes and
// which host methods it calls; and the inverse, for each host field, which
// parts own it. A field written by exactly one part belongs to that part's
// future class; a field written from many is shared state that needs an
// owner before anything can move.
//
//   dart run tool/refactor/session_map.dart <repoRoot> [out.json]
//
// Resolution is by NAME (the library is one namespace, so a private name
// is unambiguous across the host and its parts); locals and parameters
// declared inside a member shadow host names and are subtracted.

import 'dart:convert';
import 'dart:io';

import 'package:analyzer/dart/analysis/features.dart';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/source/line_info.dart';

const _hostPath = 'lib/src/ui/editor_session_manager.dart';
const _hostClass = 'EditorSessionManager';

void main(List<String> args) {
  final root = args.isEmpty ? '.' : args[0];
  final hostFile = File('$root/$_hostPath');
  final hostUnit = _parse(hostFile);
  final host = hostUnit.unit.declarations
      .whereType<ClassDeclaration>()
      .firstWhere((c) => c.namePart.typeName.lexeme == _hostClass);

  final hostFields = <String, Map<String, Object?>>{};
  final hostMethods = <String, Map<String, Object?>>{};
  for (final m in host.body.members) {
    if (m is FieldDeclaration) {
      for (final v in m.fields.variables) {
        hostFields[v.name.lexeme] = {
          'name': v.name.lexeme,
          'type': m.fields.type?.toSource() ?? 'var',
          'final': m.fields.isFinal,
          'late': m.fields.isLate,
          'static': m.isStatic,
          'line': hostUnit.lineInfo.getLocation(v.offset).lineNumber,
          'private': v.name.lexeme.startsWith('_'),
        };
      }
    } else if (m is MethodDeclaration) {
      hostMethods[m.name.lexeme] = {
        'name': m.name.lexeme,
        'kind': m.isGetter
            ? 'getter'
            : m.isSetter
            ? 'setter'
            : 'method',
        'from': hostUnit.lineInfo.getLocation(m.offset).lineNumber,
        'to': hostUnit.lineInfo.getLocation(m.end).lineNumber,
        'private': m.name.lexeme.startsWith('_'),
      };
    }
  }
  final hostNames = {...hostFields.keys, ...hostMethods.keys};

  // The host's own members count as one more "part": the host itself.
  final parts = <Map<String, Object?>>[];
  final fieldUse = <String, Map<String, Map<String, int>>>{};
  void note(String part, String field, String how) {
    final byPart = fieldUse.putIfAbsent(field, () => {});
    final counts = byPart.putIfAbsent(part, () => {'reads': 0, 'writes': 0});
    counts[how] = (counts[how] ?? 0) + 1;
  }

  parts.add(
    _mapDeclaration(
      'host',
      _hostPath,
      host,
      hostUnit.lineInfo,
      hostNames,
      hostFields,
      note,
    ),
  );

  for (final d in hostUnit.unit.directives.whereType<PartDirective>()) {
    final rel = d.uri.stringValue!;
    final partPath = 'lib/src/ui/$rel';
    final unit = _parse(File('$root/$partPath'));
    for (final decl in unit.unit.declarations) {
      parts.add(
        _mapDeclaration(
          rel.replaceAll('session/', '').replaceAll('.dart', ''),
          partPath,
          decl,
          unit.lineInfo,
          hostNames,
          hostFields,
          note,
        ),
      );
    }
  }

  final ownership = <String, Object?>{};
  for (final e in fieldUse.entries) {
    final writers = e.value.entries
        .where((p) => (p.value['writes'] ?? 0) > 0)
        .map((p) => p.key)
        .toList();
    final readers = e.value.entries
        .where((p) => (p.value['reads'] ?? 0) > 0)
        .map((p) => p.key)
        .toList();
    ownership[e.key] = {
      'writers': writers,
      'readers': readers,
      'byPart': e.value,
    };
  }

  final out = {
    'host': {
      'fields': hostFields.values.toList(),
      'methods': hostMethods.values.toList(),
      'lines': hostUnit.lineInfo.lineCount,
    },
    'parts': parts,
    'fieldOwnership': ownership,
  };
  final json = const JsonEncoder.withIndent(' ').convert(out);
  if (args.length > 1) {
    File(args[1]).writeAsStringSync(json);
  } else {
    print(json);
  }

  // A human summary on stderr so the JSON stays machine-clean.
  stderr.writeln(
    'host: ${hostFields.length} fields, '
    '${hostMethods.length} methods, ${hostUnit.lineInfo.lineCount} lines',
  );
  final sorted = parts.toList()
    ..sort(
      (a, b) => ((b['hostTouched']! as Map).length).compareTo(
        (a['hostTouched']! as Map).length,
      ),
    );
  for (final p in sorted) {
    final touched = p['hostTouched'] as Map;
    final writes = p['hostWritten'] as List;
    stderr.writeln(
      '${(p['part']! as String).padRight(28)} '
      '${(p['kind']! as String).padRight(12)} '
      '${(p['name']! as String).padRight(32)} '
      'members=${(p['members']! as List).length.toString().padLeft(3)} '
      'touches=${touched.length.toString().padLeft(3)} '
      'writes=${writes.length.toString().padLeft(2)}',
    );
  }
  final multiWriters = ownership.entries
      .where((e) => ((e.value! as Map)['writers'] as List).length > 1)
      .toList();
  stderr.writeln(
    'fields written from more than one part: '
    '${multiWriters.length}',
  );
  for (final e in multiWriters) {
    stderr.writeln('  ${e.key}: ${(e.value! as Map)['writers']}');
  }
}

({CompilationUnit unit, LineInfo lineInfo}) _parse(File file) {
  final result = parseString(
    content: file.readAsStringSync(),
    path: file.path,
    featureSet: FeatureSet.latestLanguageVersion(),
    throwIfDiagnostics: false,
  );
  return (unit: result.unit, lineInfo: result.lineInfo);
}

Map<String, Object?> _mapDeclaration(
  String part,
  String path,
  CompilationUnitMember decl,
  LineInfo lineInfo,
  Set<String> hostNames,
  Map<String, Map<String, Object?>> hostFields,
  void Function(String part, String field, String how) note,
) {
  final String kind;
  final String name;
  final List<ClassMember> members;
  final bool viaSession;
  if (decl is ClassDeclaration) {
    kind = decl.namePart.typeName.lexeme == _hostClass
        ? 'host'
        : 'collaborator';
    name = decl.namePart.typeName.lexeme;
    members = decl.body.members;
    viaSession = kind != 'host';
  } else if (decl is ExtensionDeclaration) {
    kind = 'extension';
    name = decl.name?.lexeme ?? '<unnamed>';
    members = decl.body.members;
    viaSession = false;
  } else if (decl is MixinDeclaration) {
    kind = 'mixin';
    name = decl.name.lexeme;
    members = decl.body.members;
    viaSession = false;
  } else {
    kind = decl is FunctionDeclaration
        ? 'function'
        : decl.runtimeType.toString();
    name = decl is FunctionDeclaration
        ? decl.name.lexeme
        : decl is TopLevelVariableDeclaration
        ? decl.variables.variables.first.name.lexeme
        : '<${decl.runtimeType}>';
    members = const [];
    viaSession = false;
  }

  final touched = <String, int>{};
  final written = <String>{};
  final mapped = <Map<String, Object?>>[];
  for (final m in members) {
    final visitor = _HostUseVisitor(hostNames, viaSession);
    m.accept(visitor);
    final reads =
        visitor.reads.keys.where((n) => !visitor.locals.contains(n)).toList()
          ..sort();
    final writes =
        visitor.writes.keys.where((n) => !visitor.locals.contains(n)).toList()
          ..sort();
    final calls =
        visitor.calls.keys.where((n) => !visitor.locals.contains(n)).toList()
          ..sort();
    for (final r in reads) {
      touched[r] = (touched[r] ?? 0) + visitor.reads[r]!;
      if (hostFields.containsKey(r)) note(part, r, 'reads');
    }
    for (final w in writes) {
      touched[w] = (touched[w] ?? 0) + visitor.writes[w]!;
      written.add(w);
      if (hostFields.containsKey(w)) note(part, w, 'writes');
    }
    final String memberName;
    final String memberKind;
    if (m is MethodDeclaration) {
      memberName = m.name.lexeme;
      memberKind = m.isGetter
          ? 'getter'
          : m.isSetter
          ? 'setter'
          : 'method';
    } else if (m is FieldDeclaration) {
      memberName = m.fields.variables.map((v) => v.name.lexeme).join(',');
      memberKind = 'field';
    } else if (m is ConstructorDeclaration) {
      memberName = m.name?.lexeme ?? '<ctor>';
      memberKind = 'constructor';
    } else {
      memberName = '<${m.runtimeType}>';
      memberKind = 'other';
    }
    mapped.add({
      'name': memberName,
      'kind': memberKind,
      'from': lineInfo.getLocation(m.offset).lineNumber,
      'to': lineInfo.getLocation(m.end).lineNumber,
      'reads': reads,
      'writes': writes,
      'calls': calls,
    });
  }
  return {
    'part': part,
    'file': path,
    'kind': kind,
    'name': name,
    'from': lineInfo.getLocation(decl.offset).lineNumber,
    'to': lineInfo.getLocation(decl.end).lineNumber,
    'members': mapped,
    'hostTouched': touched,
    'hostWritten': written.toList()..sort(),
  };
}

/// Counts uses of host names inside one member. In a collaborator the host
/// is reached through `_session.<name>`; in the host and its extensions the
/// name is bare. Locals and parameters are collected so bare names they
/// shadow can be subtracted afterwards.
class _HostUseVisitor extends RecursiveAstVisitor<void> {
  _HostUseVisitor(this.hostNames, this.viaSession);

  final Set<String> hostNames;
  final bool viaSession;
  final reads = <String, int>{};
  final writes = <String, int>{};
  final calls = <String, int>{};
  final locals = <String>{};

  void _bump(Map<String, int> m, String n) => m[n] = (m[n] ?? 0) + 1;

  bool _isSession(Expression? target) =>
      target is SimpleIdentifier && target.name == '_session';

  @override
  void visitVariableDeclaration(VariableDeclaration node) {
    locals.add(node.name.lexeme);
    super.visitVariableDeclaration(node);
  }

  @override
  void visitFormalParameterList(FormalParameterList node) {
    for (final p in node.parameters) {
      final n = p.name?.lexeme;
      if (n != null) locals.add(n);
    }
    super.visitFormalParameterList(node);
  }

  @override
  void visitAssignmentExpression(AssignmentExpression node) {
    final left = node.leftHandSide;
    final target = _hostTarget(left);
    if (target != null) _bump(writes, target);
    // The right side and any index/target expressions are reads.
    if (left is PrefixedIdentifier ||
        left is PropertyAccess ||
        left is SimpleIdentifier) {
      node.rightHandSide.accept(this);
      if (left is PropertyAccess) left.target?.accept(this);
      return;
    }
    super.visitAssignmentExpression(node);
  }

  String? _hostTarget(Expression e) {
    if (viaSession) {
      if (e is PrefixedIdentifier && _isSession(e.prefix)) {
        return e.identifier.name;
      }
      if (e is PropertyAccess && _isSession(e.target)) {
        return e.propertyName.name;
      }
      return null;
    }
    if (e is SimpleIdentifier && hostNames.contains(e.name)) {
      return e.name;
    }
    if (e is PropertyAccess && e.target is ThisExpression) {
      return e.propertyName.name;
    }
    return null;
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    if (viaSession) {
      if (_isSession(node.target)) _bump(calls, node.methodName.name);
    } else if (node.target == null &&
        hostNames.contains(node.methodName.name)) {
      _bump(calls, node.methodName.name);
    }
    super.visitMethodInvocation(node);
  }

  @override
  void visitPrefixedIdentifier(PrefixedIdentifier node) {
    if (viaSession && _isSession(node.prefix)) {
      _bump(reads, node.identifier.name);
      return;
    }
    super.visitPrefixedIdentifier(node);
  }

  @override
  void visitPropertyAccess(PropertyAccess node) {
    if (viaSession && _isSession(node.target)) {
      _bump(reads, node.propertyName.name);
      return;
    }
    super.visitPropertyAccess(node);
  }

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    if (!viaSession && hostNames.contains(node.name)) {
      final parent = node.parent;
      final isDeclaration =
          parent is VariableDeclaration && parent.name == node.token;
      final isMethodName =
          parent is MethodInvocation && parent.methodName == node;
      final isLabel = parent is Label;
      if (!isDeclaration && !isMethodName && !isLabel) _bump(reads, node.name);
    }
    super.visitSimpleIdentifier(node);
  }
}
