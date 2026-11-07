// The registry crates ONE PLATFORM's build of a cargo workspace takes,
// worked out from what this machine already holds — for refusal 8's list of
// what is not downloaded here (tool/lane.sh, crates_not_here).
//
//   dart tool/crates_for_host.dart <Cargo.lock> <members.json> <cfg> \
//       <triple> <index folder>
//
//   <members.json>   `cargo metadata --no-deps --format-version 1`
//   <cfg>            `rustc --print cfg`
//   <triple>         the `host:` of `rustc -vV`
//   <index folder>   $CARGO_HOME/registry/index
//
// Prints one `name-version` a line, the way the registry cache names its
// files.
//
// 관제 2026-11-07 (native-memory-safety): the lock names every platform's
// crates, and the Surface was told to fetch them all — 29 crates for Linux,
// the Mac and Android came down with the four its build needed, and nobody
// had allowed those. The list is this platform's alone.
// WHY NOT CARGO: `cargo metadata --filter-platform`, `cargo tree --target`
// and `cargo fetch --target` all download what they walk before they answer;
// offline, each stops at the first crate missing and names that one alone
// (measured 2026-11-07, with cpal and zeno both gone: metadata named cpal,
// fetch named zeno) — and a list is wanted exactly when one is missing.
// What they walk is here without a download: the lock's edges, the members'
// manifests (`--no-deps` opens no crate) and, for every registry crate, the
// index entry it was resolved from, whose dependencies carry their `target`.
// Measured on master the same day: this list was `cargo metadata
// --filter-platform x86_64-pc-windows-msvc`'s 256 of the lock's 330, crate
// for crate.
import 'dart:convert';
import 'dart:io';

import 'source_brackets.dart';

/// One `[[package]]` of a Cargo.lock.
typedef LockPackage = ({
  String name,
  String version,
  bool fromRegistry,
  List<String> dependencies,
});

/// A dependency as a manifest declares it: the crate it names (not its
/// rename), of which kind (`normal` · `dev` · `build`), and for which
/// platform (`null` for every one).
typedef Declared = ({String crate, String kind, String? target});

List<LockPackage> lockPackages(String lock) {
  final packages = <LockPackage>[];
  for (final block in lock.split('[[package]]').skip(1)) {
    String? field(String key) => RegExp(
      '^$key = "([^"]*)"',
      multiLine: true,
    ).firstMatch(block)?.group(1);
    final list = RegExp(
      r'^dependencies = \[(.*?)\]',
      multiLine: true,
      dotAll: true,
    ).firstMatch(block)?.group(1);
    packages.add((
      name: field('name')!,
      version: field('version')!,
      fromRegistry: field('source')?.startsWith('registry+') ?? false,
      dependencies: [
        for (final entry in RegExp('"([^"]*)"').allMatches(list ?? ''))
          entry.group(1)!,
      ],
    ));
  }
  return packages;
}

typedef _Json = Map<String, dynamic>;

/// [dependency] as `cargo metadata` and the index both write one; [crate]
/// is the field that holds the crate's own name.
Declared _declared(_Json dependency, String crate) => (
  crate: dependency[crate] as String,
  kind: dependency['kind'] as String? ?? 'normal',
  target: dependency['target'] as String?,
);

/// The workspace members' own dependencies, by `name version`.
Map<String, List<Declared>> memberDependencies(String metadata) => {
  for (final package
      in ((jsonDecode(metadata) as _Json)['packages'] as List).cast<_Json>())
    '${package['name']} ${package['version']}': [
      for (final dependency
          in (package['dependencies'] as List).cast<_Json>())
        _declared(dependency, 'name'),
    ],
};

/// The dependencies the index entry of [name] [version] declares, or null
/// when this machine's index holds no entry for it.
List<Declared>? indexDependencies(
  Directory index,
  String name,
  String version,
) {
  final lower = name.toLowerCase();
  final at = switch (lower.length) {
    1 => '1/$lower',
    2 => '2/$lower',
    3 => '3/${lower[0]}/$lower',
    _ => '${lower.substring(0, 2)}/${lower.substring(2, 4)}/$lower',
  };
  for (final registry in index.listSync().whereType<Directory>()) {
    final file = File('${registry.path}/.cache/$at');
    if (!file.existsSync()) continue;
    // A header, then `version \0 json \0` for every version the registry
    // has: the JSON is what counts, the rest never starts with a brace.
    final text = utf8.decode(file.readAsBytesSync(), allowMalformed: true);
    for (final part in text.split('\u0000')) {
      if (!part.startsWith('{')) continue;
      final entry = jsonDecode(part) as _Json;
      if (entry['vers'] != version) continue;
      return [
        for (final dependency in (entry['deps'] as List).cast<_Json>())
          // A renamed dependency keeps the crate's own name in `package`.
          _declared(
            dependency,
            dependency.containsKey('package') ? 'package' : 'name',
          ),
      ];
    }
  }
  return null;
}

/// What `rustc --print cfg` says of a platform, and its triple.
class TargetPlatform {
  TargetPlatform(this.triple, Iterable<String> cfgLines)
    : _cfg = {for (final line in cfgLines) line.trim()}..remove('');

  final String triple;
  final Set<String> _cfg;

  /// Whether a dependency declared for [target] is built for this platform.
  bool takes(String? target) {
    if (target == null) return true;
    if (!target.startsWith('cfg(')) return target == triple;
    return _holds(target.trim(), target);
  }

  /// Whether [predicate] holds here: `cfg`, `all`, `any` and `not` over
  /// the predicates their call passes — cut where `tool/source_brackets.dart`
  /// cuts a call's arguments — or a `key = "value"` or a bare name, as
  /// `rustc --print cfg` spells them.
  bool _holds(String predicate, String target) {
    final call = RegExp(r'^(\w+)\s*\(').firstMatch(predicate);
    if (call == null) {
      final pair = RegExp(r'^(\w+)\s*=\s*("[^"]*")$').firstMatch(predicate);
      return _cfg.contains(pair == null ? predicate : '${pair[1]}=${pair[2]}');
    }
    final arguments = callArguments(predicate, call.end - 1);
    if (arguments == null) throw FormatException('never closes', target);
    final held = [
      for (final argument in arguments) _holds(argument.trim(), target),
    ];
    return switch (call[1]) {
      'cfg' || 'all' => held.every((one) => one),
      'any' => held.any((one) => one),
      'not' => !held.single,
      _ => throw FormatException('not a cfg predicate: ${call[1]}', target),
    };
  }
}

/// Which of the lock's edges a walk takes — the one question two lists ask
/// of the same walk (관제 2026-11-07, connection-round-checklist: "what a
/// build takes is not what the binary carries").
enum Walk {
  /// What a build downloads and compiles: a member's dependencies of every
  /// kind, any other crate's but its dev-dependencies (cargo builds no
  /// dependency's tests) — refusal 8's list.
  build,

  /// What the built library carries: normal dependencies alone, a member's
  /// as any other crate's — a build script's crates and a test's run on the
  /// machine that builds, never in what ships. The notices' list
  /// (tool/crate_notices.dart).
  binary;

  bool follows(String kind, {required bool fromMember}) => switch (this) {
    Walk.build => fromMember || kind != 'dev',
    Walk.binary => kind == 'normal',
  };
}

/// The registry crates, `name-version`, that [walk] reaches from every
/// member of the workspace on [platform].
///
/// An edge of the lock is walked when the crate it leaves declares, for this
/// platform and of a kind [walk] follows, the crate it reaches. Where a
/// declaration cannot be read — a crate this machine's index never saw, a
/// path crate that is not a member — every edge is walked: what cannot be
/// ruled out is listed.
Set<String> cratesFor(
  List<LockPackage> lock,
  Map<String, List<Declared>> members,
  List<Declared>? Function(LockPackage) declaredOf,
  TargetPlatform platform, {
  required Walk walk,
}) {
  LockPackage named(String dependency) {
    final words = dependency.split(' ');
    return lock.singleWhere(
      (package) =>
          package.name == words[0] &&
          (words.length == 1 || package.version == words[1]),
    );
  }

  final reached = <LockPackage>{
    for (final package in lock)
      if (members.containsKey('${package.name} ${package.version}')) package,
  };
  final queue = [...reached];
  while (queue.isNotEmpty) {
    final package = queue.removeLast();
    final member = members['${package.name} ${package.version}'];
    final declared = member ??
        (package.fromRegistry ? declaredOf(package) : null);
    for (final dependency in package.dependencies.map(named)) {
      final asNamed =
          declared?.where((d) => d.crate == dependency.name) ?? const [];
      final walked = asNamed.isEmpty ||
          asNamed.any(
            (d) =>
                walk.follows(d.kind, fromMember: member != null) &&
                platform.takes(d.target),
          );
      if (walked && reached.add(dependency)) queue.add(dependency);
    }
  }
  return {
    for (final package in reached)
      if (package.fromRegistry) '${package.name}-${package.version}',
  };
}

void main(List<String> args) {
  if (args.length != 5) {
    stderr.writeln(
      'usage: dart tool/crates_for_host.dart <Cargo.lock> <members.json> '
      '<cfg> <triple> <index folder>',
    );
    exit(2);
  }
  final index = Directory(args[4]);
  final crates = cratesFor(
    lockPackages(File(args[0]).readAsStringSync()),
    memberDependencies(File(args[1]).readAsStringSync()),
    (package) => indexDependencies(index, package.name, package.version),
    TargetPlatform(args[3], File(args[2]).readAsLinesSync()),
    walk: Walk.build,
  ).toList()..sort();
  stdout.write(crates.map((crate) => '$crate\n').join());
}
