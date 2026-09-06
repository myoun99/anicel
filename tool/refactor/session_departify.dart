// ignore_for_file: avoid_print
// G0-2 of the god-object decomposition (round 8, 2026-09-06): the
// collaborators leave `part` and take the roles by constructor.
//
//   dart run tool/refactor/session_departify.dart <repoRoot> <session_map.json>
//
// Run AFTER session_roles_apply.dart (the roles exist, the role members
// are public) and after session_map.dart was re-run on that tree. One
// pass, mechanical:
//   1. Every private top-level name declared in a part file (the
//      collaborator class, its typedefs, enums, consts) becomes public
//      across the library — it is about to be seen from other libraries.
//   2. Every host name a collaborator uses that belongs to NO role goes
//      into `SessionInternals` — the named, measured remainder of the
//      coupling. Private ones are made public the same way the roles'
//      were (a plain forwarding getter is deleted). The host implements
//      it; its members get @override. ⛔A host field that IS another
//      collaborator is not an internal but a SIBLING: it is injected by
//      constructor (the host passes its own late final field) and never
//      enters SessionInternals — the roles file names no collaborator.
//   3. Each collaborator's `_session` field is replaced by one field per
//      role it uses (and one per sibling), taken by a named constructor
//      parameter, and every `_session.<name>` is rewritten to
//      `_<role>.<name>` by the name's role, or to `_<sibling>` for a
//      sibling. A `_session` that survives (passed on as a value, or a
//      ChangeNotifier member the map does not know) is printed — that is
//      the hand-work left, and the analyzer will name it too.
//   4. The file stops being a part: it gets the host's imports one level
//      deeper (session_roles.dart among them; `dart fix` strips the unused
//      ones afterwards), the host's `part` line becomes an import placed
//      with the other imports, and `late final _X _x = _X(this)` becomes
//      `late final X _x = X(project: this, …, camera: _camera)` — the host
//      IS every role, and owns every sibling.
//
// What the analyzer names afterwards is by design hand-work, because it
// is semantic: a host member that wrote a collaborator's private field
// (the code moves INTO the collaborator as a named verb), a private type
// declared in the host that only a collaborator used (the declaration
// moves), a collaborator advancing the frame sequence itself (it mints).
//
// ⚠️Collaborators that do not hold `_session` (editing_stack_map,
// playback_cache_budget's `(this)` form, …) are left as parts and listed.

import 'dart:convert';
import 'dart:io';

import 'package:analyzer/dart/analysis/features.dart';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';

import 'session_roles_gen.dart' show roleOf, roleOrder;

const _hostPath = 'lib/src/ui/editor_session_manager.dart';
const _hostClass = 'EditorSessionManager';
const _rolesPath = 'lib/src/ui/session/session_roles.dart';

const _roleField = <String, String>{
  'ProjectAccess': '_project',
  'SelectionAccess': '_selection',
  'ChangeSink': '_changes',
  'FrameIds': '_frameIds',
  'TimelineAccess': '_timeline',
  'SessionInternals': '_internals',
};
const _roleParam = <String, String>{
  'ProjectAccess': 'project',
  'SelectionAccess': 'selection',
  'ChangeSink': 'changes',
  'FrameIds': 'frameIds',
  'TimelineAccess': 'timeline',
  'SessionInternals': 'internals',
};

/// Public spellings that cannot be the private name minus its underscore,
/// because that public name is already taken by something that is NOT the
/// same thing: `rowSelection` is the selection LISTENABLE, so the row
/// selection VERBS collaborator is named for what it is; `instructions` is
/// the map every instruction verb takes as a parameter, so the verbs
/// object says it is the verbs; and four collaborators share a name with
/// the drag STATE class under session/drags/ — the state keeps the noun,
/// the collaborator is the VERBS (the precedent: `_CutMoveDragVerbs`).
const _publicName = <String, String>{
  '_rowSelection': 'rowSelectionVerbs',
  '_instructions': 'instructionVerbs',
  '_MovieEndDrag': 'MovieEndDragVerbs',
  '_DrawingBlockMoveDrag': 'DrawingBlockMoveDragVerbs',
  '_LaneRangeMoveDrag': 'LaneRangeMoveDragVerbs',
  '_RunFramesAddDrag': 'RunFramesAddDragVerbs',
};

String _roleFor(String name) =>
    roleOf[name] ?? roleOf['_$name'] ?? 'SessionInternals';

CompilationUnit _parse(String source) => parseString(
  content: source,
  featureSet: FeatureSet.latestLanguageVersion(),
  throwIfDiagnostics: false,
).unit;

String _renameAll(String source, Map<String, String> renames) {
  var out = source;
  for (final e in renames.entries) {
    out = out.replaceAllMapped(
      RegExp('(?<![A-Za-z0-9_])${RegExp.escape(e.key)}(?![A-Za-z0-9_])'),
      (_) => e.value,
    );
  }
  return out;
}

void main(List<String> args) {
  final root = args[0];
  final map =
      jsonDecode(File(args[1]).readAsStringSync()) as Map<String, dynamic>;
  final parts = (map['parts'] as List).cast<Map<String, dynamic>>();

  // Which collaborators hold `_session`, and what each uses of the host.
  final usesOf = <String, Set<String>>{}; // part file -> host names
  final writes = <String>{};
  final allUsed = <String>{};
  final classOf = <String, String>{}; // part file -> collaborator class
  for (final p in parts) {
    if (p['kind'] != 'collaborator') continue;
    final file = p['file'] as String;
    final src = File('$root/$file').readAsStringSync();
    if (!src.contains('final EditorSessionManager _session;')) continue;
    classOf[file] = p['name'] as String;
    final names = usesOf.putIfAbsent(file, () => {});
    for (final m in (p['members'] as List).cast<Map<String, dynamic>>()) {
      final used = [
        ...(m['reads'] as List),
        ...(m['calls'] as List),
        ...(m['writes'] as List),
      ].cast<String>();
      names.addAll(used);
      writes.addAll((m['writes'] as List).cast<String>());
    }
    allUsed.addAll(names);
  }

  // 1. Private top-level names in part files go public everywhere.
  final hostSource0 = File('$root/$_hostPath').readAsStringSync();
  final hostUnit0 = _parse(hostSource0);
  final partFiles = hostUnit0.directives
      .whereType<PartDirective>()
      .map((d) => 'lib/src/ui/${d.uri.stringValue!}')
      .toList();
  final renames = <String, String>{};
  for (final f in partFiles) {
    final unit = _parse(File('$root/$f').readAsStringSync());
    for (final d in unit.declarations) {
      final name = switch (d) {
        final ClassDeclaration c => c.namePart.typeName.lexeme,
        final MixinDeclaration m => m.name.lexeme,
        final EnumDeclaration e => e.namePart.typeName.lexeme,
        final ExtensionDeclaration e => e.name?.lexeme,
        final GenericTypeAlias t => t.name.lexeme,
        final FunctionTypeAlias t => t.name.lexeme,
        final FunctionDeclaration fn => fn.name.lexeme,
        final TopLevelVariableDeclaration v =>
          v.variables.variables.first.name.lexeme,
        _ => null,
      };
      if (name != null && name.startsWith('_')) {
        renames[name] = _publicName[name] ?? name.substring(1);
      }
    }
  }

  final hostDecl = hostUnit0.declarations
      .whereType<ClassDeclaration>()
      .firstWhere((c) => c.namePart.typeName.lexeme == _hostClass);
  final hostMembers = <String, ClassMember>{};
  final hostSetters = <String>{};
  final hostFieldType = <String, String>{};
  for (final m in hostDecl.body.members) {
    if (m is MethodDeclaration) {
      if (m.isSetter) {
        hostSetters.add(m.name.lexeme);
        hostMembers.putIfAbsent(m.name.lexeme, () => m);
      } else {
        hostMembers[m.name.lexeme] = m;
      }
    } else if (m is FieldDeclaration) {
      for (final v in m.fields.variables) {
        hostMembers[v.name.lexeme] = m;
        hostFieldType[v.name.lexeme] = m.fields.type?.toSource() ?? 'dynamic';
      }
    }
  }

  // Siblings: a host field whose type is another collaborator. A
  // collaborator that reads one is not reaching into the session, it is
  // talking to a peer — so the peer is injected by constructor (the host
  // passes its own late final field; late finals resolve lazily, so an
  // acyclic graph is safe) and the getter never enters SessionInternals.
  // The host field is not renamed: nothing outside the host needs it.
  final collaboratorClasses = classOf.values.toSet();
  final siblingOf = <String, String>{}; // host field -> collaborator class
  for (final n in allUsed) {
    final t = hostFieldType[n];
    if (t != null && collaboratorClasses.contains(t)) siblingOf[n] = t;
  }
  String siblingParam(String n) => _publicName[n] ?? n.substring(1);

  // 2. SessionInternals: every used name with no role. Private ones go
  //    public; a plain forwarding getter to such a field is deleted.
  final internals =
      allUsed
          .where(
            (n) =>
                _roleFor(n) == 'SessionInternals' && !siblingOf.containsKey(n),
          )
          .toList()
        ..sort();
  final deleteSpans = <(int, int)>[];
  for (final n in internals) {
    if (!n.startsWith('_')) continue;
    final public = _publicName[n] ?? n.substring(1);
    renames[n] = public;
    final twin = hostMembers[public];
    if (twin == null) continue;
    if (twin is MethodDeclaration && twin.isGetter) {
      final body = twin.body;
      if (body is ExpressionFunctionBody &&
          body.expression is SimpleIdentifier &&
          (body.expression as SimpleIdentifier).name == n) {
        deleteSpans.add((
          twin.documentationComment?.offset ?? twin.offset,
          twin.end,
        ));
        print('delete forwarder: $public => $n');
        continue;
      }
    }
    throw StateError(
      '$public already exists on the host and is not a plain forwarder of $n',
    );
  }

  String dropSpans(String source) {
    var out = source;
    final spans = deleteSpans.toList()..sort((a, b) => b.$1.compareTo(a.$1));
    for (final (s, e) in spans) {
      var end = e;
      while (end < out.length && (out[end] == '\r' || out[end] == '\n')) {
        end += 1;
      }
      out = out.substring(0, s) + out.substring(end);
    }
    return out;
  }

  var hostSource = _renameAll(dropSpans(hostSource0), renames);
  final eol = hostSource0.contains('\r\n') ? '\r\n' : '\n';
  String pub(String n) => renames[n] ?? n;

  // Signatures for SessionInternals, from the renamed host.
  final hostUnit1 = _parse(hostSource);
  final host1 = hostUnit1.declarations.whereType<ClassDeclaration>().firstWhere(
    (c) => c.namePart.typeName.lexeme == _hostClass,
  );
  final decl = <String, ClassMember>{};
  final fieldType = <String, String>{};
  final setters = <String>{};
  for (final m in host1.body.members) {
    if (m is MethodDeclaration) {
      if (m.isSetter) {
        setters.add(m.name.lexeme);
        decl.putIfAbsent(m.name.lexeme, () => m);
      } else {
        decl[m.name.lexeme] = m;
      }
    } else if (m is FieldDeclaration) {
      for (final v in m.fields.variables) {
        decl[v.name.lexeme] = m;
        fieldType[v.name.lexeme] = m.fields.type?.toSource() ?? 'dynamic';
      }
    }
  }
  String memberSource(String n) {
    final name = pub(n);
    final m = decl[name];
    if (m == null) throw StateError('no host declaration for $name');
    if (m is FieldDeclaration) {
      final t = fieldType[name]!;
      final s = StringBuffer('  $t get $name;');
      if (writes.contains(n)) s.write('$eol  set $name($t value);');
      return s.toString();
    }
    final md = m as MethodDeclaration;
    final ret = md.returnType?.toSource() ?? 'void';
    if (md.isGetter) {
      final s = StringBuffer('  $ret get $name;');
      if (writes.contains(n) && setters.contains(name)) {
        s.write('$eol  set $name($ret value);');
      }
      return s.toString();
    }
    if (md.isSetter) return '  set $name${md.parameters!.toSource()};';
    final tp = md.typeParameters?.toSource() ?? '';
    return '  $ret $name$tp${md.parameters!.toSource()};';
  }

  var roles = File('$root/$_rolesPath').readAsStringSync();
  final internalsBlock = StringBuffer()
    ..write(
      '/// What collaborators still reach into the session for beyond the$eol',
    )
    ..write(
      '/// roles above — the measured remainder of the coupling, and a list$eol',
    )
    ..write('/// that only shrinks: each member either moves into the one$eol')
    ..write(
      '/// collaborator that uses it, becomes a role, or is injected as the$eol',
    )
    ..write('/// sibling it really is. ⛔Nothing is added here.$eol')
    ..write('abstract interface class SessionInternals {$eol');
  for (final n in internals) {
    internalsBlock.write(memberSource(n));
    internalsBlock.write(eol);
  }
  internalsBlock.write('}$eol');
  final marker = RegExp(
    'abstract interface class SessionInternals \\{[\\s\\S]*?\\n\\}\\r?\\n',
  );
  roles = marker.hasMatch(roles)
      ? roles.replaceFirst(marker, internalsBlock.toString())
      : '$roles$eol${internalsBlock.toString()}';
  // The host's imports one level deeper — what every departed file and the
  // roles file start from (`dart fix` strips what each does not use).
  final hostImports = hostUnit0.directives
      .whereType<ImportDirective>()
      .toList();
  final deeperImports = StringBuffer();
  for (final d in hostImports) {
    final uri = d.uri.stringValue!;
    // Only the PART files are skipped (they are imported by name below); a
    // sibling library under session/ (drags/…) keeps its import, now
    // spelled from inside session/.
    if (partFiles.contains('lib/src/ui/$uri')) continue;
    final deeper = uri.startsWith('package:') || uri.startsWith('dart:')
        ? uri
        : uri.startsWith('session/')
        ? uri.substring('session/'.length)
        : '../$uri';
    deeperImports.write(d.toSource().replaceFirst("'$uri'", "'$deeper'"));
    deeperImports.write(eol);
  }

  // SessionInternals names host types the roles file never needed before:
  // its imports become the host's, deepened, and `dart fix` keeps the used.
  final rolesHead = roles.substring(0, roles.indexOf('${eol}import '));
  final rolesBody = roles.substring(roles.indexOf('abstract interface class'));
  roles =
      '$rolesHead$eol${deeperImports.toString().replaceFirst("import 'session_roles.dart';$eol", '')}$eol$rolesBody';
  File('$root/$_rolesPath').writeAsStringSync(roles);

  // Host: implements SessionInternals; @override on its members.
  hostSource = hostSource.replaceFirstMapped(
    RegExp(
      'implements ((?:ProjectAccess|SelectionAccess|ChangeSink|FrameIds|TimelineAccess)(?:, )?)+ \\{',
    ),
    (m) =>
        '${m.group(0)!.substring(0, m.group(0)!.length - 2)}, SessionInternals {',
  );

  // 3 + 4. Each collaborator: role fields, rewrites, and out of `part`.
  final importBlock = StringBuffer(deeperImports.toString());
  if (!importBlock.toString().contains("import 'session_roles.dart';")) {
    importBlock.write("import 'session_roles.dart';$eol");
  }
  for (final f in partFiles) {
    if (!classOf.containsKey(f)) continue;
    final rel = f.replaceFirst('lib/src/ui/session/', '');
    importBlock.write("import '$rel';$eol");
  }

  final leftovers = <String, List<String>>{};
  final newImportLines = <String>[];
  for (final f in partFiles) {
    final cls = classOf[f];
    if (cls == null) {
      print('left as part (no _session field): $f');
      continue;
    }
    var src = _renameAll(File('$root/$f').readAsStringSync(), renames);
    final publicCls = pub(cls);
    final siblings = usesOf[f]!.where(siblingOf.containsKey).toList()..sort();
    final rolesUsed = <String>{
      for (final n in usesOf[f]!)
        if (!siblingOf.containsKey(n)) _roleFor(n),
    };
    final ordered = [
      ...roleOrder,
      'SessionInternals',
    ].where(rolesUsed.contains).toList();

    // Constructor + fields: the roles first, then the sibling collaborators.
    final params = [
      for (final r in ordered) 'required $r ${_roleParam[r]}',
      for (final n in siblings)
        'required ${pub(siblingOf[n]!)} ${siblingParam(n)}',
    ].join(', ');
    final inits = [
      for (final r in ordered) '${_roleField[r]} = ${_roleParam[r]}',
      for (final n in siblings) '_${siblingParam(n)} = ${siblingParam(n)}',
    ].join(', ');
    final fields = [
      for (final r in ordered) '  final $r ${_roleField[r]};',
      for (final n in siblings)
        '  final ${pub(siblingOf[n]!)} _${siblingParam(n)};',
    ].join(eol);
    final ctorOld = '$publicCls(this._session);';
    if (!src.contains(ctorOld)) {
      throw StateError('$f: constructor `$ctorOld` not found');
    }
    src = src.replaceFirst(ctorOld, '$publicCls({$params}) : $inits;');
    src = src.replaceFirst(
      RegExp('  final EditorSessionManager _session;'),
      fields,
    );
    // `_session.<name>` by role; a sibling by its own field.
    // `_session\n    .name` — a member access split over lines is the same access.
    src = src.replaceAllMapped(
      RegExp('_session\\s*\\.([A-Za-z_][A-Za-z0-9_]*)'),
      (m) {
        final name = m.group(1)!;
        final original = usesOf[f]!.firstWhere(
          (n) => pub(n) == name || n == name,
          orElse: () => '',
        );
        if (original.isEmpty) {
          leftovers.putIfAbsent(f, () => []).add(name);
          return m.group(0)!;
        }
        if (siblingOf.containsKey(original)) {
          return '_${siblingParam(original)}';
        }
        return '${_roleField[_roleFor(original)]}.$name';
      },
    );
    for (final m in RegExp(
      '(?<![A-Za-z0-9_.])_session(?![A-Za-z0-9_])',
    ).allMatches(src)) {
      leftovers.putIfAbsent(f, () => []).add('<bare _session @${m.start}>');
    }
    // The generated class doc said how the collaborator reached the host;
    // that sentence is now false, so it says the new truth.
    src = src.replaceAll(
      'It reaches the session through `_session`.',
      'It names the roles it needs in its constructor.',
    );
    // Out of part.
    src = src.replaceFirst(RegExp("part of '[^']*';\\r?\\n(\\r?\\n)?"), '');
    // The file does not import itself.
    final ownImport =
        "import '${f.replaceFirst('lib/src/ui/session/', '')}';$eol";
    src = '${importBlock.toString().replaceFirst(ownImport, '')}$eol$src';
    File('$root/$f').writeAsStringSync(src);

    // Host wiring: `X(this)` — on one line or wrapped by the formatter —
    // becomes the roles (the host is every one of them) and the siblings
    // (the host's own fields for them).
    final wiringOld = RegExp(
      'late final $publicCls ([A-Za-z_][A-Za-z0-9_]*) = $publicCls\\(\\s*this,?\\s*\\);',
    );
    final wiring = wiringOld.firstMatch(hostSource);
    if (wiring == null) {
      leftovers
          .putIfAbsent(f, () => [])
          .add('<host wiring for $publicCls not found>');
    } else {
      final args = [
        for (final r in ordered) '${_roleParam[r]}: this',
        for (final n in siblings) '${siblingParam(n)}: $n',
      ].join(', ');
      hostSource = hostSource.replaceFirst(
        wiringOld,
        'late final $publicCls ${wiring.group(1)} = $publicCls($args);',
      );
    }
    final rel = f.replaceFirst('lib/src/ui/', '');
    hostSource = hostSource.replaceFirst(
      RegExp("part '${RegExp.escape(rel)}';\\r?\\n"),
      '',
    );
    newImportLines.add("import '$rel';");
  }
  // The new imports sit with the roles import, before the remaining parts.
  hostSource = hostSource.replaceFirst(
    "import 'session/session_roles.dart';",
    "import 'session/session_roles.dart';$eol${newImportLines.join(eol)}",
  );

  // @override for the internals members on the host.
  final hostUnit2 = _parse(hostSource);
  final host2 = hostUnit2.declarations.whereType<ClassDeclaration>().firstWhere(
    (c) => c.namePart.typeName.lexeme == _hostClass,
  );
  final wanted = internals.map(pub).toSet();
  final inserts = <int>[];
  for (final m in host2.body.members) {
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
    hostSource =
        '${hostSource.substring(0, at)}@override$eol  ${hostSource.substring(at)}';
  }
  File('$root/$_hostPath').writeAsStringSync(hostSource);

  // Other parts (still parts) see the renames too.
  for (final f in partFiles) {
    if (classOf.containsKey(f)) continue;
    final path = '$root/$f';
    final src = File(path).readAsStringSync();
    final out = _renameAll(src, renames);
    if (out != src) File(path).writeAsStringSync(out);
  }

  print(
    'departed: ${classOf.length} collaborators; renamed ${renames.length} names; '
    'SessionInternals: ${internals.length} members; @override added: ${inserts.length}',
  );
  for (final e in leftovers.entries) {
    print('LEFTOVER ${e.key}: ${e.value.toSet().join(', ')}');
  }
}
