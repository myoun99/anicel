// ignore_for_file: avoid_print
// G0-1 of the god-object decomposition (round 8, 2026-09-06): the roles.
//
//   dart run tool/refactor/session_roles_apply.dart <repoRoot> <session_map.json>
//
// What it does, mechanically and in one pass:
//   1. Every host name a collaborator reads or calls that belongs to a
//      role (the table in session_roles_gen.dart) and is PRIVATE is
//      renamed to its public spelling across the host and its 40 parts
//      (whole-identifier match; the library is one namespace so the
//      private name cannot mean anything else there). A public getter
//      that only forwarded to the field (`get repository => _repository`)
//      is deleted — the field now IS the member.
//   2. lib/src/ui/session/session_roles.dart is written: one abstract
//      interface per role, members copied from the host's own
//      declarations (a field becomes a getter; a setter too when a part
//      writes it).
//   3. The host class `implements` the roles, and each implementing
//      member gets `@override`.
// Collaborators still hold `_session` after this pass; G0-2 gives them
// the role fields and takes them out of `part`. This pass is the boundary
// the compiler will enforce then — read by eye, then the analyzer.

import 'dart:convert';
import 'dart:io';

import 'package:analyzer/dart/analysis/features.dart';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';

import 'session_roles_gen.dart' show roleOf, roleOrder;

const _hostPath = 'lib/src/ui/editor_session_manager.dart';
const _hostClass = 'EditorSessionManager';
const _rolesPath = 'lib/src/ui/session/session_roles.dart';

void main(List<String> args) {
  final root = args[0];
  final map =
      jsonDecode(File(args[1]).readAsStringSync()) as Map<String, dynamic>;
  final parts = (map['parts'] as List).cast<Map<String, dynamic>>();

  // The names collaborators touch, and which of them get written.
  final used = <String>{};
  final written = <String>{};
  final partFiles = <String>{};
  for (final p in parts) {
    if (p['kind'] != 'collaborator') continue;
    partFiles.add(p['file'] as String);
    for (final m in (p['members'] as List).cast<Map<String, dynamic>>()) {
      used.addAll(
        [...(m['reads'] as List), ...(m['calls'] as List)].cast<String>(),
      );
      written.addAll((m['writes'] as List).cast<String>());
    }
  }
  final roleMembers = <String, List<String>>{};
  for (final n in used.toList()..sort()) {
    final r = roleOf[n];
    if (r != null) roleMembers.putIfAbsent(r, () => []).add(n);
  }

  // 1. Rename privates to public across the library.
  final files = [_hostPath, ...partFiles.toList()..sort()];
  final renames = <String, String>{
    for (final r in roleMembers.values)
      for (final n in r)
        if (n.startsWith('_')) n: n.substring(1),
  };
  final hostSource = File('$root/$_hostPath').readAsStringSync();
  final hostUnit = parseString(
    content: hostSource,
    featureSet: FeatureSet.latestLanguageVersion(),
    throwIfDiagnostics: false,
  ).unit;
  final host = hostUnit.declarations.whereType<ClassDeclaration>().firstWhere(
    (c) => c.namePart.typeName.lexeme == _hostClass,
  );

  // Forwarding getters that the rename makes redundant, deleted by span.
  final deleteSpans = <(int, int)>[];
  for (final m in host.body.members) {
    if (m is! MethodDeclaration || !m.isGetter) continue;
    final target = renames.entries
        .where((e) => e.value == m.name.lexeme)
        .firstOrNull;
    if (target == null) continue;
    final body = m.body;
    if (body is ExpressionFunctionBody &&
        body.expression is SimpleIdentifier &&
        (body.expression as SimpleIdentifier).name == target.key) {
      final start = m.documentationComment?.offset ?? m.offset;
      deleteSpans.add((start, m.end));
      print('delete forwarder: ${m.name.lexeme} => ${target.key}');
    } else {
      throw StateError(
        'public ${m.name.lexeme} exists and is not a plain forwarder of ${target.key}',
      );
    }
  }

  String rewrite(String source, {List<(int, int)> drop = const []}) {
    var out = source;
    // Drop spans from the end so offsets stay valid.
    final spans = drop.toList()..sort((a, b) => b.$1.compareTo(a.$1));
    for (final (s, e) in spans) {
      // Take the trailing newline with the member.
      var end = e;
      while (end < out.length && (out[end] == '\r' || out[end] == '\n')) {
        end += 1;
      }
      out = out.substring(0, s) + out.substring(end);
    }
    for (final e in renames.entries) {
      out = out.replaceAllMapped(
        RegExp('(?<![A-Za-z0-9_])${RegExp.escape(e.key)}(?![A-Za-z0-9_])'),
        (_) => e.value,
      );
    }
    return out;
  }

  var newHost = rewrite(hostSource, drop: deleteSpans);
  for (final f in files) {
    if (f == _hostPath) continue;
    final path = '$root/$f';
    final src = File(path).readAsStringSync();
    final out = rewrite(src);
    if (out != src) File(path).writeAsStringSync(out);
  }

  // 2. The roles file.
  final eol = hostSource.contains('\r\n') ? '\r\n' : '\n';
  final unit2 = parseString(
    content: newHost,
    featureSet: FeatureSet.latestLanguageVersion(),
    throwIfDiagnostics: false,
  ).unit;
  final host2 = unit2.declarations.whereType<ClassDeclaration>().firstWhere(
    (c) => c.namePart.typeName.lexeme == _hostClass,
  );
  final decl = <String, ClassMember>{};
  final fieldType = <String, String>{};
  // A name with both a getter and a setter keeps the getter as its
  // declaration; the setter is remembered so the role carries both.
  final setters = <String>{};
  for (final m in host2.body.members) {
    if (m is MethodDeclaration) {
      if (m.isSetter) {
        setters.add(m.name.lexeme);
        decl.putIfAbsent(m.name.lexeme, () => m);
      } else {
        decl[m.name.lexeme] = m;
      }
    }
    if (m is FieldDeclaration) {
      for (final v in m.fields.variables) {
        decl[v.name.lexeme] = m;
        fieldType[v.name.lexeme] = m.fields.type?.toSource() ?? 'dynamic';
      }
    }
  }
  String pub(String n) => renames[n] ?? n;
  String memberSource(String n) {
    final m = decl[pub(n)];
    if (m == null) throw StateError('no host declaration for ${pub(n)}');
    if (m is FieldDeclaration) {
      final t = fieldType[pub(n)]!;
      final s = StringBuffer('  $t get ${pub(n)};');
      if (written.contains(n)) s.write('$eol  set ${pub(n)}($t value);');
      return s.toString();
    }
    final md = m as MethodDeclaration;
    final ret = md.returnType?.toSource() ?? 'void';
    if (md.isGetter) {
      final s = StringBuffer('  $ret get ${pub(n)};');
      if (written.contains(n) && setters.contains(pub(n))) {
        s.write('$eol  set ${pub(n)}($ret value);');
      }
      return s.toString();
    }
    if (md.isSetter) return '  set ${pub(n)}${md.parameters!.toSource()};';
    final tp = md.typeParameters?.toSource() ?? '';
    return '  $ret ${pub(n)}$tp${md.parameters!.toSource()};';
  }

  // The host's imports, one directory deeper: the roles file sits in
  // session/, so every relative URI gains a `../`; package: and dart:
  // stay. `dart fix --apply --code=unused_import` on the roles file
  // afterwards drops the ones no signature needs.
  final imports = <String>[];
  for (final d in hostUnit.directives.whereType<ImportDirective>()) {
    final uri = d.uri.stringValue!;
    if (uri.startsWith('session/')) continue;
    final deeper = uri.startsWith('package:') || uri.startsWith('dart:')
        ? uri
        : '../$uri';
    imports.add(d.toSource().replaceFirst("'$uri'", "'$deeper'"));
  }
  final roles = StringBuffer()
    ..write(
      '// The roles the editor session plays for its collaborators (round 8 of$eol',
    )
    ..write(
      '// the audit, 2026-09-06). A collaborator names the roles it needs in its$eol',
    )
    ..write(
      '// constructor and nothing else of the session is visible to it; the$eol',
    )
    ..write('// session is the one class that implements them all.$eol')
    ..write('//$eol')
    ..write(
      '// 🚨EVERY MEMBER HERE IS ONE A COLLABORATOR ALREADY READ OR CALLED when the$eol',
    )
    ..write(
      '// session was one class in 41 files (tool/refactor/session_map.dart$eol',
    )
    ..write(
      '// measured it). Adding a member is widening the seam; the direction of$eol',
    )
    ..write(
      '// travel is narrower roles, and a member no collaborator uses is deleted.$eol',
    )
    ..write(eol);
  // Imports are the host's, minus its parts; the analyzer strips the unused ones.
  for (final i in imports) {
    roles.write(i);
    roles.write(eol);
  }
  roles.write(eol);
  for (final role in roleOrder) {
    final names = roleMembers[role] ?? const <String>[];
    if (names.isEmpty) continue;
    roles.write('abstract interface class $role {$eol');
    for (final n in names) {
      roles.write(memberSource(n).replaceAll('\n', eol));
      roles.write(eol);
    }
    roles.write('}$eol$eol');
  }
  File('$root/$_rolesPath').writeAsStringSync(roles.toString());

  // 3. Host implements the roles; implementing members get @override.
  final implemented = roleOrder
      .where((r) => (roleMembers[r] ?? const []).isNotEmpty)
      .toList();
  final header = RegExp('class $_hostClass extends ChangeNotifier \\{');
  if (!header.hasMatch(newHost)) throw StateError('host header not found');
  newHost = newHost.replaceFirst(
    header,
    'class $_hostClass extends ChangeNotifier$eol    implements ${implemented.join(', ')} {',
  );
  // The roles file is imported right before the first part directive —
  // after every import, before the library's own files.
  newHost = newHost.replaceFirst(
    "part 'session/",
    "import 'session/session_roles.dart';${eol}part 'session/",
  );
  final unit3 = parseString(
    content: newHost,
    featureSet: FeatureSet.latestLanguageVersion(),
    throwIfDiagnostics: false,
  ).unit;
  final host3 = unit3.declarations.whereType<ClassDeclaration>().firstWhere(
    (c) => c.namePart.typeName.lexeme == _hostClass,
  );
  final wanted = {
    for (final r in roleMembers.values)
      for (final n in r) pub(n),
  };
  final inserts = <int>[];
  for (final m in host3.body.members) {
    final names = m is MethodDeclaration
        ? [m.name.lexeme]
        : m is FieldDeclaration
        ? m.fields.variables.map((v) => v.name.lexeme).toList()
        : const <String>[];
    if (!names.any(wanted.contains)) continue;
    if (m.metadata.any((a) => a.name.name == 'override')) continue;
    inserts.add(m.firstTokenAfterCommentAndMetadata.offset);
  }
  inserts.sort((a, b) => b.compareTo(a));
  for (final at in inserts) {
    newHost =
        '${newHost.substring(0, at)}@override$eol  ${newHost.substring(at)}';
  }
  File('$root/$_hostPath').writeAsStringSync(newHost);

  print('renamed ${renames.length} private names across ${files.length} files');
  print(
    'roles: ${implemented.map((r) => '$r(${roleMembers[r]!.length})').join(' ')}',
  );
  print(
    '@override added: ${inserts.length}; forwarders deleted: ${deleteSpans.length}',
  );
  final part = hostSource.contains("part 'session/") ? 'yes' : 'no';
  print('host still has parts: $part (G0-2 removes them)');
}
