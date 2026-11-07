// The notices of the registry crates a cargo workspace's library carries:
// one list, every crate under its licence text, written for the app's
// About ▸ licenses screen (lib/main.dart registers it).
//
//   dart tool/crate_notices.dart <workspace folder> <out.json>
//
// The platforms are the workspace's `rust-toolchain.toml` targets — what the
// engine is built for, and so what ships; a target that joins there joins
// here the next time this runs. What each platform's library carries is
// tool/crates_for_host.dart's walk over the binary's edges (one walk for
// both lists, 관제 2026-11-07). The texts are the files each crate ships
// beside its manifest, read from this machine's registry sources; a crate
// whose source is not here is named, and nothing is written — fetching it
// is a download, and a download is asked for first.
//
// 관제 2026-11-07 (connection-round-checklist A 📜): four notice rows did
// the same thing crate by crate (symphonia's, cpal's, the letters', and
// Wasmtime's), and wgpu's crates had no row at all. This one list replaces
// them; test/every_crate_the_engine_ships_is_noticed_test.dart holds it to
// the lock.
import 'dart:convert';
import 'dart:io';

import 'crates_for_host.dart';

/// A shipped crate's licence as its manifest declares it, and the files it
/// ships it in, by name — empty where it ships none.
typedef CrateLicence = ({String? expression, Map<String, String> files});

/// The registry folder cargo keeps its index and sources under.
Directory registryHome() {
  final env = Platform.environment;
  final home = env['CARGO_HOME'] ??
      '${env['USERPROFILE'] ?? env['HOME']}${Platform.pathSeparator}.cargo';
  return Directory('$home${Platform.pathSeparator}registry');
}

/// The `targets` of a `rust-toolchain.toml`.
List<String> toolchainTargets(String toml) {
  final list = RegExp(
    r'^targets\s*=\s*\[(.*?)\]',
    multiLine: true,
    dotAll: true,
  ).firstMatch(toml);
  if (list == null) throw const FormatException('no targets');
  return [
    for (final target in RegExp('"([^"]*)"').allMatches(list.group(1)!))
      target.group(1)!,
  ];
}

/// Whether [name] is a licence file's, as crates name them.
bool isLicenceFile(String name) => RegExp(
  '^(LICEN[CS]E|COPYING|COPYRIGHT|NOTICE|UNLICENSE)',
  caseSensitive: false,
).hasMatch(name);

/// The licence of the crate whose source is [folder]: its manifest's
/// `license`, and the licence files beside the manifest.
CrateLicence licenceIn(Directory folder) {
  final manifest = File('${folder.path}/Cargo.toml').readAsStringSync();
  final expression = RegExp(
    r'^license\s*=\s*"([^"]*)"',
    multiLine: true,
  ).firstMatch(manifest)?.group(1);
  final files = <String, String>{
    for (final file in folder.listSync().whereType<File>())
      if (isLicenceFile(file.uri.pathSegments.last))
        file.uri.pathSegments.last: file.readAsStringSync(),
  };
  return (expression: expression, files: Map.fromEntries(
    files.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
  ));
}

/// A crate's notice text: its files, one after another, each under its
/// name where there are more than one.
String textOf(Map<String, String> files) => files.length == 1
    ? files.values.single.trim()
    : [
        for (final MapEntry(:key, :value) in files.entries)
          '$key\n\n${value.trim()}',
      ].join('\n\n');

/// The text a crate that ships no licence file is listed under: the
/// Apache-2.0 text of the first crate (by name) declaring the same licence
/// — its APACHE file, or its one file where the licence is Apache's alone.
/// ⚠️Null for any licence that offers no Apache-2.0: an MIT or BSD text
/// carries its own crate's copyright line, and lending one would name the
/// wrong owner — such a crate stops the list for a person to look at.
String? borrowedText(
  String? expression,
  Map<String, CrateLicence> shipped,
) {
  if (expression == null || !expression.contains('Apache-2.0')) return null;
  final alone = !expression.contains(' OR ') && !expression.contains('/');
  final siblings = shipped.entries
      .where((e) => e.value.expression == expression && e.value.files.isNotEmpty)
      .toList()
    ..sort((a, b) => a.key.compareTo(b.key));
  for (final sibling in siblings) {
    final files = sibling.value.files;
    final apache = files.entries.where(
      (file) =>
          file.key.toUpperCase().contains('APACHE') ||
          (alone && files.length == 1),
    );
    if (apache.isNotEmpty) return textOf(Map.fromEntries([apache.first]));
  }
  return null;
}

/// The notices: every crate of [shipped] under its text, one entry a text,
/// the crates of an entry sorted, the entries by their first crate.
List<({List<String> crates, String text})> noticesOf(
  Map<String, CrateLicence> shipped,
) {
  final byText = <String, List<String>>{};
  final unread = <String>[];
  for (final MapEntry(key: crate, value: licence) in shipped.entries) {
    final text = licence.files.isEmpty
        ? borrowedText(licence.expression, shipped)
        : textOf(licence.files);
    if (text == null) {
      unread.add('$crate (${licence.expression})');
      continue;
    }
    (byText[text] ??= []).add(crate);
  }
  if (unread.isNotEmpty) {
    throw StateError('no licence text for: ${unread.join(', ')}');
  }
  final notices = [
    for (final MapEntry(key: text, value: crates) in byText.entries)
      (crates: crates..sort(), text: text),
  ]..sort((a, b) => a.crates.first.compareTo(b.crates.first));
  return notices;
}

/// The notices file's shape, written by [noticesFile] and read by
/// [noticedCrates] — the app (lib/main.dart) reads `notices` alone.
Map<String, Object> noticesFile(
  List<String> targets,
  List<({List<String> crates, String text})> notices,
  Iterable<String> unshipped,
) => {
  'about': "Written by tool/crate_notices.dart from the engine's Cargo.lock "
      '— run it again, do not edit.',
  'targets': targets,
  'notices': [
    for (final notice in notices) {'crates': notice.crates, 'text': notice.text},
  ],
  'unshipped': unshipped.toList()..sort(),
};

/// What a notices file accounts for: the targets it was made for, the crates
/// it lists under a text, and the lock's crates it found no target ships.
({List<String> targets, List<String> noticed, List<String> unshipped})
noticedCrates(Map<String, dynamic> file) => (
  targets: (file['targets'] as List).cast<String>(),
  noticed: [
    for (final notice in (file['notices'] as List).cast<Map<String, dynamic>>())
      ...(notice['crates'] as List).cast<String>(),
  ],
  unshipped: (file['unshipped'] as List).cast<String>(),
);

Future<String> _run(String executable, List<String> args, String folder) async {
  final result = await Process.run(executable, args, workingDirectory: folder);
  if (result.exitCode != 0) {
    throw ProcessException(executable, args, '${result.stderr}', result.exitCode);
  }
  return '${result.stdout}';
}

/// The targets each registry crate (`name version`) of the workspace's
/// library ships on.
Future<Map<String, List<String>>> shippedOn(
  String workspace,
  List<LockPackage> lock,
  List<String> targets,
  Directory index,
) async {
  final members = memberDependencies(await _run('cargo', [
    'metadata', '--locked', '--offline', '--no-deps', '--format-version', '1',
  ], workspace));
  // The walk names a crate as the registry names its folder; the lock's
  // name and version say where the name ends (a name may hold `-5`, a
  // version `-1.1.0` — toml_edit's `+spec-1.1.0`).
  final spacedOf = {
    for (final package in lock)
      '${package.name}-${package.version}': '${package.name} ${package.version}',
  };
  final on = <String, List<String>>{};
  for (final target in targets) {
    final cfg =
        await _run('rustc', ['--print', 'cfg', '--target', target], workspace);
    final crates = cratesFor(
      lock,
      members,
      (package) => indexDependencies(index, package.name, package.version),
      TargetPlatform(target, LineSplitter.split(cfg)),
      walk: Walk.binary,
    );
    for (final crate in crates) {
      (on[spacedOf[crate]!] ??= []).add(target);
    }
  }
  return on;
}

/// The registry's folder for the crate `name version`: a name holds no
/// space, so the first one is where the version starts.
String folderOf(String crate) => crate.replaceFirst(' ', '-');

/// The licence of every crate of [on] whose source is under one of
/// [sources], by `name version` — and, by target, how many it found none
/// for, each named on stderr.
({Map<String, CrateLicence> read, Map<String, int> missing}) licencesOf(
  Map<String, List<String>> on,
  List<Directory> sources,
) {
  final read = <String, CrateLicence>{};
  final missing = <String, int>{};
  for (final MapEntry(key: crate, value: targets) in on.entries) {
    final folder = sources
        .map((source) => Directory('${source.path}/${folderOf(crate)}'))
        .where((folder) => folder.existsSync())
        .firstOrNull;
    if (folder == null) {
      stderr.writeln('not here: $crate (${targets.join(', ')})');
      for (final target in targets) {
        missing[target] = (missing[target] ?? 0) + 1;
      }
    } else {
      read[crate] = licenceIn(folder);
    }
  }
  return (read: read, missing: missing);
}

Future<void> main(List<String> args) async {
  if (args.length != 2) {
    stderr.writeln('usage: dart tool/crate_notices.dart <workspace> <out.json>');
    exit(2);
  }
  final workspace = args[0];
  final registry = registryHome();
  final lock = lockPackages(File('$workspace/Cargo.lock').readAsStringSync());
  final targets = toolchainTargets(
    File('$workspace/rust-toolchain.toml').readAsStringSync(),
  );
  final on = await shippedOn(
    workspace,
    lock,
    targets,
    Directory('${registry.path}/index'),
  );
  final sources = Directory('${registry.path}/src').listSync().whereType<Directory>();
  final (:read, :missing) = licencesOf(on, sources.toList());
  if (missing.isNotEmpty) {
    stderr.writeln('crates whose source is not on this machine, by target: '
        '$missing — nothing written');
    exit(1);
  }
  final unshipped = {
    for (final package in lock)
      if (package.fromRegistry) '${package.name} ${package.version}',
  }.difference(read.keys.toSet());
  final notices = noticesOf(read);
  final file = noticesFile(targets, notices, unshipped);
  File(args[1]).writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(file)}\n',
  );
  stdout.writeln('${read.length} crates under ${notices.length} texts · '
      '${unshipped.length} not shipped');
}
