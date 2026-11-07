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
// is a download, and a download is asked for first. A crate that ships no
// file is listed under its repository's own, pinned in tool/crate_licences/
// ([pinnedLicences]).
//
// 관제 2026-11-07 (connection-round-checklist A 📜): four notice rows did
// the same thing crate by crate (symphonia's, cpal's, the letters', and
// Wasmtime's), and wgpu's crates had no row at all. This one list replaces
// them; test/every_crate_the_engine_ships_is_noticed_test.dart holds it to
// the lock.
import 'dart:convert';
import 'dart:io';

import 'crates_for_host.dart';

/// A shipped crate's licence as its manifest declares it, the repository
/// the manifest names, and the files it ships it in, by name — empty where
/// it ships none.
typedef CrateLicence = ({
  String? expression,
  String? repository,
  Map<String, String> files,
});

/// The licence files a repository keeps for crates of it that ship none, by
/// the `repository` their manifests name: each file's name under
/// [pinnedFolder], and where it was taken from, word for word.
///
/// 캔버스 베이스 패널 2026-11-07 (gpu-engine-skeleton, 관제 13:53 「어떻게
/// 고지할지 네가 정하라 … 한 법으로」 · 유저 Q12 「원본 저장소의 원문을 받아
/// 고정한다」): objc2's crates ship no licence file and their repository
/// keeps no MIT text either — one LICENSE.md saying which licence each crate
/// is under. That file is what the repository says, so its crates are listed
/// under it: by repository, so a crate of it that joins the lock
/// (objc2-av-foundation and objc2-core-media are on their way) is listed
/// without a line here. Ahead of [borrowedText], which lends a sibling's
/// text where the repository says nothing.
const pinnedLicences = <String, Map<String, String>>{
  'https://github.com/madsmtm/objc2': {
    // Alike at every commit the shipped crates were cut from (their
    // .cargo_vcs_info.json: b4167b58 block2 0.6.2, d7d2fa23 objc2 0.6.5,
    // 8d214f54 objc2-encode 4.1.0, 7b1abfd7 the 0.3.2 crates) — git's id of
    // it 540ae4c8 at each.
    'LICENSE.md': 'https://raw.githubusercontent.com/madsmtm/objc2/'
        'd7d2fa23ceaa5e6096c923b081040e5d81b3b9df/LICENSE.md',
    // The MIT terms LICENSE.md links, its four paragraphs a blank line
    // apart (the page breaks no line within one), 2026-11-07: MIT asks for
    // this notice in every copy, and the repository keeps none (유저 Q13
    // 「MIT 문구도 받아 같이 싣는다」). Its first line's blanks stay as the
    // page has them — the repository names no holder to put there.
    'MIT.txt': 'https://opensource.org/license/MIT',
  },
};

/// The folder [pinnedLicences] keeps [repository]'s files in.
String pinnedFolder(String repository) =>
    'tool/crate_licences/${repository.replaceFirst('https://', '')}';

/// The texts of [pinnedLicences], by repository, read from [pinnedFolder]s.
Map<String, List<String>> pinnedTexts() => {
  for (final MapEntry(key: repository, value: files) in pinnedLicences.entries)
    repository: [
      for (final name in files.keys)
        File('${pinnedFolder(repository)}/$name').readAsStringSync().trim(),
    ],
};

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
/// `license` and `repository`, and the licence files beside the manifest.
CrateLicence licenceIn(Directory folder) {
  final manifest = File('${folder.path}/Cargo.toml').readAsStringSync();
  String? field(String key) => RegExp(
    '^$key\\s*=\\s*"([^"]*)"',
    multiLine: true,
  ).firstMatch(manifest)?.group(1);
  final files = <String, String>{
    for (final file in folder.listSync().whereType<File>())
      if (isLicenceFile(file.uri.pathSegments.last))
        file.uri.pathSegments.last: file.readAsStringSync(),
  };
  return (
    expression: field('license'),
    repository: field('repository'),
    files: Map.fromEntries(
      files.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
    ),
  );
}

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
    if (apache.isNotEmpty) return apache.first.value.trim();
  }
  return null;
}

/// The notices: one entry a licence text, naming every crate of [shipped]
/// that ships it — a crate with two files (its MIT and its Apache) under
/// each, so a text many crates ship is listed once, as the app's licence
/// screen lists a package under each of its texts. A crate that ships none
/// is listed under its repository's texts of [pinned] (by [pinnedTexts]),
/// else under the text [borrowedText] lends it. The crates of an entry
/// sorted, the entries by their first crate and then their text.
List<({List<String> crates, String text})> noticesOf(
  Map<String, CrateLicence> shipped, {
  Map<String, List<String>> pinned = const {},
}) {
  final byText = <String, Set<String>>{};
  final unread = <String>[];
  for (final MapEntry(key: crate, value: licence) in shipped.entries) {
    final texts = licence.files.isNotEmpty
        ? [for (final text in licence.files.values) text.trim()]
        : pinned[licence.repository] ??
            [?borrowedText(licence.expression, shipped)];
    if (texts.isEmpty) unread.add('$crate (${licence.expression})');
    for (final text in texts) {
      (byText[text] ??= {}).add(crate);
    }
  }
  if (unread.isNotEmpty) {
    throw StateError('no licence text for: ${unread.join(', ')}');
  }
  return [
    for (final MapEntry(key: text, value: crates) in byText.entries)
      (crates: crates.toList()..sort(), text: text),
  ]..sort((a, b) {
      final first = a.crates.first.compareTo(b.crates.first);
      return first != 0 ? first : a.text.compareTo(b.text);
    });
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

/// What a notices file accounts for: the targets it was made for, the
/// crates it lists — each once, however many texts it is under — and the
/// lock's crates it found no target ships.
({List<String> targets, List<String> noticed, List<String> unshipped})
noticedCrates(Map<String, dynamic> file) => (
  targets: (file['targets'] as List).cast<String>(),
  noticed: {
    for (final notice in (file['notices'] as List).cast<Map<String, dynamic>>())
      ...(notice['crates'] as List).cast<String>(),
  }.toList()..sort(),
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
  final notices = noticesOf(read, pinned: pinnedTexts());
  final file = noticesFile(targets, notices, unshipped);
  File(args[1]).writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(file)}\n',
  );
  stdout.writeln('${read.length} crates under ${notices.length} texts · '
      '${unshipped.length} not shipped');
}
