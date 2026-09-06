// ignore_for_file: avoid_print
// The sibling promotion (round 8, G0-2): a `SessionInternals` member the
// host answers by forwarding to one of its OWN collaborators is not an
// internal — it is a sibling, and the collaborator that asks for it should
// hold that sibling by constructor.
//
//   dart run tool/refactor/session_siblings.dart <repoRoot> [--apply]
//
// ⚠️The host builds its collaborators with `late final X _x = X(…)`, so
// the graph must stay ACYCLIC: two objects that name each other cannot be
// built at all (a stack overflow on first touch — measured 2026-09-06,
// StoryboardRows↔Standing). So each candidate edge is added only if it
// does not close a cycle in the graph built so far; the ones that would
// are printed as REFUSED and stay on SessionInternals with a ⛔ comment.
//
// What it rewrites, per accepted edge (user U asks the host for member m,
// which the host forwards to collaborator field `_p` of class P):
//   - `_internals.m` becomes `_<p>.m` in U's file
//   - U gains `required P <p>` / `final P _<p>;` and the import
//   - the host's `U(…)` construction gains `<p>: _p`
// Members left with no asker at all are printed as DEAD.

import 'dart:io';

const _hostPath = 'lib/src/ui/editor_session_manager.dart';
const _rolesPath = 'lib/src/ui/session/session_roles.dart';
const _sessionDir = 'lib/src/ui/session';

void main(List<String> args) {
  final root = args.isEmpty ? '.' : args[0];
  final apply = args.contains('--apply');
  final hostFile = File('$root/$_hostPath');
  var host = hostFile.readAsStringSync();

  // --- the host's collaborator fields, and how each one is built ---------
  final fieldClass = <String, String>{}; // _camera -> Camera
  for (final m in RegExp(
    'late final ([A-Z][A-Za-z0-9_]*) (_[a-zA-Z0-9_]+) =',
  ).allMatches(host)) {
    fieldClass[m.group(2)!] = m.group(1)!;
  }
  final classField = {for (final e in fieldClass.entries) e.value: e.key};

  // --- the graph as it stands: which collaborator names which ------------
  final edges = <String, Set<String>>{
    for (final c in fieldClass.values) c: <String>{},
  };
  for (final e in fieldClass.entries) {
    final ctor = _ctorArgsOf(host, e.key);
    for (final other in fieldClass.entries) {
      if (other.key == e.key) {
        continue;
      }
      if (RegExp(
            ': ${other.key}\\s*[,)]?\\s*\$',
            multiLine: true,
          ).hasMatch(ctor) ||
          RegExp(': ${other.key}[,)]').hasMatch(ctor) ||
          ctor.trimRight().endsWith(': ${other.key}')) {
        edges[e.value]!.add(other.value);
      }
    }
  }

  // --- the candidates: SessionInternals members the host forwards --------
  final roles = File('$root/$_rolesPath').readAsLinesSync();
  final start = roles.indexWhere(
    (l) => l.startsWith('abstract interface class SessionInternals'),
  );
  final memberLine = <String, List<int>>{};
  for (var i = start + 1; i < roles.length && roles[i] != '}'; i += 1) {
    // A property says `get x` / `set x`; a method's name is the identifier
    // before the LAST `(` on the line, because a `Function(` in the return
    // type sits before it and would otherwise win.
    final accessor = RegExp(
      r'\b(?:get|set)\s+([a-zA-Z_][a-zA-Z0-9_]*)',
    ).firstMatch(roles[i]);
    final calls = RegExp(
      r'([a-zA-Z_][a-zA-Z0-9_]*)\s*\(',
    ).allMatches(roles[i]).toList();
    final name =
        accessor?.group(1) ?? (calls.isEmpty ? null : calls.last.group(1));
    if (name != null) {
      memberLine.putIfAbsent(name, () => []).add(i);
    }
  }

  final files = <String, File>{};
  for (final f in Directory(
    '$root/$_sessionDir',
  ).listSync().whereType<File>()) {
    if (f.path.endsWith('.dart')) {
      files[f.uri.pathSegments.last] = f;
    }
  }
  final classOfFile = <String, String>{};
  final sources = <String, String>{};
  for (final e in files.entries) {
    final src = e.value.readAsStringSync();
    sources[e.key] = src;
    final c = RegExp(
      '^class ([A-Z][A-Za-z0-9_]*)',
      multiLine: true,
    ).firstMatch(src);
    if (c != null) {
      classOfFile[e.key] = c.group(1)!;
    }
  }

  final accepted =
      <String, Map<String, Set<String>>>{}; // file -> field -> members
  final refused = <String>[];
  final dead = <String>[];
  final removable = <String>[];

  for (final member in memberLine.keys) {
    final fwd = RegExp(
      '(?:get |set |\\b)$member(?:\\([^)]*\\))?[^;{]*=>\\s*(_[a-zA-Z0-9_]+)\\.',
      dotAll: true,
    ).firstMatch(host);
    final providerField = fwd?.group(1);
    if (providerField == null || !fieldClass.containsKey(providerField)) {
      continue;
    }
    final provider = fieldClass[providerField]!;
    final askers = <String>[
      for (final e in sources.entries)
        if (RegExp('_internals\\.$member\\b').hasMatch(e.value)) e.key,
    ];
    if (askers.isEmpty) {
      dead.add(member);
      removable.add(member);
      continue;
    }
    var allMoved = true;
    for (final askerFile in askers) {
      final asker = classOfFile[askerFile];
      if (asker == null || asker == provider) {
        allMoved = false;
        continue;
      }
      if (_reaches(edges, provider, asker)) {
        refused.add(
          '$asker -> $provider ($member): $provider already needs $asker',
        );
        allMoved = false;
        continue;
      }
      edges[asker]!.add(provider);
      accepted
          .putIfAbsent(askerFile, () => {})
          .putIfAbsent(providerField, () => {})
          .add(member);
    }
    if (allMoved) {
      removable.add(member);
    }
  }

  for (final d in dead) {
    print('DEAD    $d');
  }
  for (final r in refused) {
    print('REFUSED $r');
  }
  var edgeCount = 0;
  var memberCount = 0;
  for (final e in accepted.entries) {
    for (final f in e.value.entries) {
      edgeCount += 1;
      memberCount += f.value.length;
      print('ACCEPT  ${e.key} <- ${f.key}: ${f.value.join(", ")}');
    }
  }
  print('REMOVABLE ${removable.length}: ${removable.join(", ")}');
  print(
    'edges=$edgeCount members=$memberCount dead=${dead.length} '
    'refused=${refused.length} removable=${removable.length} '
    'internalsWas=${memberLine.length}',
  );
  if (!apply) {
    return;
  }

  // --- rewrite ------------------------------------------------------------
  for (final e in accepted.entries) {
    final file = files[e.key]!;
    var src = sources[e.key]!;
    final params = <String>[];
    final fields = <String>[];
    final inits = <String>[];
    final imports = <String>[];
    final added = <String>[]; // only the fields this run introduced
    for (final f in e.value.entries) {
      final field = f.key;
      final cls = fieldClass[field]!;
      final param = field.substring(1);
      for (final m in f.value) {
        src = src.replaceAll(RegExp('_internals\\.$m\\b'), '$field.$m');
      }
      if (!RegExp('final $cls $field;').hasMatch(src)) {
        params.add('required $cls $param');
        fields.add('  final $cls $field;');
        inits.add('$field = $param');
        added.add(field);
        final importPath = '${_snake(cls)}.dart';
        if (File('$root/$_sessionDir/$importPath').existsSync() &&
            !src.contains("import '$importPath';")) {
          imports.add("import '$importPath';");
        }
      }
    }
    if (params.isNotEmpty) {
      final cls = classOfFile[e.key]!;
      // ⛔`replaceFirst` takes the replacement LITERALLY — `$1` is the two
      // characters, not the group. Only the *Mapped forms see the match.
      src = src.replaceFirstMapped(
        RegExp('($cls\\(\\{[^}]*)\\}\\)'),
        (m) => '${m[1]}, ${params.join(", ")}})',
      );
      src = src.replaceFirstMapped(
        RegExp(
          '(: _[a-zA-Z0-9_]+ = [a-zA-Z0-9_]+(?:, _[a-zA-Z0-9_]+ = [a-zA-Z0-9_]+)*);',
        ),
        (m) => '${m[1]}, ${inits.join(", ")};',
      );
      // The fields go straight under the constructor — the one anchor
      // every one of these files has (a `final` field list may be typed
      // with parentheses or generics that no simple pattern spans).
      final ctorAt = src.indexOf('\n  $cls({');
      final ctorEnd = ctorAt < 0 ? -1 : src.indexOf('\n', ctorAt + 1);
      if (ctorEnd < 0) {
        throw StateError('no constructor line found in ${e.key}');
      }
      src = src.replaceRange(
        ctorEnd + 1,
        ctorEnd + 1,
        '\n${fields.join("\n")}\n',
      );
      if (imports.isNotEmpty) {
        final lastImport = RegExp("import '[^']+';").allMatches(src).last;
        src = src.replaceRange(
          lastImport.end,
          lastImport.end,
          '\n${imports.join("\n")}',
        );
      }
      // The host builds this collaborator: hand it the sibling fields.
      final askerField = classField[cls]!;
      // ⛔Only the fields this run ADDED: a collaborator that already held
      // the sibling is already handed it, and naming it twice is an error.
      final ctorArgs = added.map((f) => '${f.substring(1)}: $f').join(', ');
      host = host.replaceFirstMapped(
        RegExp('(late final $cls $askerField = $cls\\([^;]*?)\\);'),
        (m) => '${m[1]}, $ctorArgs);',
      );
    }
    file.writeAsStringSync(src);
  }
  // The remainder shrinks: every member whose askers all took the sibling
  // (and every member nobody asks for) leaves SessionInternals.
  final drop = <int>{for (final m in removable) ...?memberLine[m]};
  final kept = [
    for (var i = 0; i < roles.length; i += 1)
      if (!drop.contains(i)) roles[i],
  ];
  File('$root/$_rolesPath').writeAsStringSync('${kept.join("\n")}\n');
  hostFile.writeAsStringSync(host);
  print('applied; dropped ${drop.length} lines from SessionInternals');
}

String _ctorArgsOf(String host, String field) {
  final m = RegExp(
    'late final [A-Za-z0-9_]+ $field = [A-Za-z0-9_]+\\(([^;]*)\\);',
  ).firstMatch(host);
  return m?.group(1) ?? '';
}

bool _reaches(Map<String, Set<String>> edges, String from, String to) {
  final seen = <String>{};
  final stack = <String>[from];
  while (stack.isNotEmpty) {
    final n = stack.removeLast();
    if (n == to) {
      return true;
    }
    if (!seen.add(n)) {
      continue;
    }
    stack.addAll(edges[n] ?? const <String>{});
  }
  return false;
}

String _snake(String name) => name
    .replaceAllMapped(
      RegExp('([a-z0-9])([A-Z])'),
      (m) => '${m.group(1)}_${m.group(2)}',
    )
    .toLowerCase();
