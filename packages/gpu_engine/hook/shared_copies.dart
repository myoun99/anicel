import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import 'build_inputs.dart';

/// What a checkout's hook built, kept in the trunk's hook folder by the
/// contents of every file the build read — so a checkout whose files read
/// the same takes a copy, and neither the hook folder's turn nor cargo.
///
/// 🚨THE SAME FILES, NOT THE SAME CHECKOUT (card
/// a-batch-is-cut-silent-while-it-waits-for-the-hook-turn, 2026-11-14):
/// every checkout's build of the engine is its own (`QA_CHECKOUT`,
/// build.dart), so after a turn another checkout held the hook built the
/// engine's crates again — 45–212 s under the turn, over eleven runs that
/// night, while other runs waited up to 15 minutes behind it. `QA_CHECKOUT`
/// is only the library's fingerprint, and nothing else that differs between
/// checkouts changes what it does (브러시/렌더링, that card, 00:48). The key
/// is what the build read ([readByTheBuild] — every file of the
/// workspace, vendor's among them, which the dep-info does not name), the
/// hook's own
/// files, and the hook's config, which the caller keeps apart
/// ([forConfig]): files byte for byte the same build the same library.
/// The DXC library goes with it — rust/build.rs puts it beside the hook's
/// output, and with no cargo nothing would.
final class SharedCopies {
  SharedCopies(this.folder);

  /// The copies kept for one [config] of the hook, under [hookFolder].
  factory SharedCopies.forConfig(
    String hookFolder,
    Map<String, Object?> config,
  ) {
    final key = sha256.convert(utf8.encode(jsonEncode(config))).toString();
    return SharedCopies(
      Directory(
        '$hookFolder${Platform.pathSeparator}copies'
        '${Platform.pathSeparator}${key.substring(0, 16)}',
      ),
    );
  }

  final Directory folder;

  /// The kept copy whose files read in [checkout] hash as they did where it
  /// was built, last taken first; null when none does.
  KeptCopy? find(Uri checkout) {
    final hashes = <String, String?>{};
    for (final entry in _entries()) {
      final kept = KeptCopy._read(entry);
      if (kept == null) continue;
      if (_digest(checkout, kept.read, hashes) == _name(entry)) return kept;
    }
    return null;
  }

  /// Keeps what the build at [checkout] made — [made], relative to
  /// [outputDirectory], [library] among them — by the contents of what it
  /// [read] and of the hook's files under [hook]. ⛔Not when a read file
  /// changed after the build [started], or lies outside the checkout: the
  /// copy would not be what those files build. What lies under
  /// [outputDirectory] the hook made, and is no key.
  void keep({
    required Uri checkout,
    required Uri outputDirectory,
    required Iterable<Uri> read,
    required Uri hook,
    required String library,
    required List<String> made,
    required DateTime started,
  }) {
    final root = checkout.toFilePath();
    final listed = <String>{};
    for (final uri in [...read, ..._hookFiles(hook)]) {
      if (lies(uri, under: outputDirectory)) continue;
      if (!lies(uri, under: checkout)) return;
      final file = File.fromUri(uri);
      if (!file.existsSync() || file.lastModifiedSync().isAfter(started)) {
        return;
      }
      listed.add(uri.toFilePath().substring(root.length).replaceAll(r'\', '/'));
    }
    final sorted = listed.toList()..sort();
    final digest = _digest(checkout, sorted, {});
    if (digest == null) return;
    final kept = Directory('${folder.path}/$digest');
    if (kept.existsSync()) return;
    final part = Directory('${folder.path}/$digest.part-$pid')
      ..createSync(recursive: true);
    for (final name in made) {
      final to = File('${part.path}/$name')..parent.createSync(recursive: true);
      File.fromUri(outputDirectory.resolve(name)).copySync(to.path);
    }
    File('${part.path}/$_entryFile').writeAsStringSync(
      jsonEncode({'library': library, 'made': made, 'read': sorted}),
    );
    try {
      part.renameSync(kept.path);
    } on FileSystemException {
      // Another checkout kept the same files first.
      part.deleteSync(recursive: true);
      return;
    }
    _letTheLastTakenGo();
  }

  /// Last taken first.
  List<Directory> _entries() {
    if (!folder.existsSync()) return const [];
    final found = [
      for (final entity in folder.listSync(followLinks: false))
        if (entity is Directory &&
            !_name(entity).contains('.part-') &&
            File('${entity.path}/$_entryFile').existsSync())
          entity,
    ];
    DateTime taken(Directory entry) =>
        File('${entry.path}/$_entryFile').lastModifiedSync();
    return found..sort((a, b) => taken(b).compareTo(taken(a)));
  }

  void _letTheLastTakenGo() {
    for (final entry in _entries().skip(kKeptCopies)) {
      try {
        entry.deleteSync(recursive: true);
      } on FileSystemException {
        // Being copied from: the next keep lets it go.
      }
    }
  }
}

/// How many copies one config keeps: the library and DXC are 46 MB on
/// Windows, and C: was at 97 % the night this was written.
const kKeptCopies = 8;

const _entryFile = 'entry.json';

/// A kept build: its files, and what it read, relative to a checkout.
final class KeptCopy {
  KeptCopy._(this.where, this.library, this.made, this.read);

  static KeptCopy? _read(Directory folder) {
    try {
      final json =
          jsonDecode(File('${folder.path}/$_entryFile').readAsStringSync())
              as Map<String, Object?>;
      return KeptCopy._(
        folder,
        json['library']! as String,
        (json['made']! as List).cast<String>(),
        (json['read']! as List).cast<String>(),
      );
    } on Object {
      return null;
    }
  }

  final Directory where;
  final String library;
  final List<String> made;
  final List<String> read;

  /// Copies [made] into [outputDirectory] and marks the copy taken; false
  /// when it went meanwhile — another checkout let it go.
  bool copyTo(Uri outputDirectory) {
    try {
      for (final name in made) {
        final to = File.fromUri(outputDirectory.resolve(name))
          ..parent.createSync(recursive: true);
        File('${where.path}/$name').copySync(to.path);
      }
      File('${where.path}/$_entryFile').setLastModifiedSync(DateTime.now());
      return true;
    } on FileSystemException {
      return false;
    }
  }

  /// What it read, in [checkout].
  List<Uri> readIn(Uri checkout) => [
    for (final path in read) _in(checkout, path),
  ];
}

/// A [relative] path of files in [checkout] — as a path, not a URI
/// reference that a `#` or `%` in a name would cut.
Uri _in(Uri checkout, String relative) =>
    checkout.resolveUri(Uri(path: relative));

Iterable<Uri> _hookFiles(Uri hook) => [
  for (final entity in Directory.fromUri(hook).listSync())
    if (entity is File && entity.path.endsWith('.dart')) entity.uri,
];

/// The hash of [listed] files' paths and contents in [checkout]; null when
/// one is missing. [hashes] keeps each file's for the next copy's list.
String? _digest(
  Uri checkout,
  List<String> listed,
  Map<String, String?> hashes,
) {
  final lines = StringBuffer();
  for (final path in listed) {
    final hash = hashes.putIfAbsent(path, () {
      final file = File.fromUri(_in(checkout, path));
      return file.existsSync()
          ? sha256.convert(file.readAsBytesSync()).toString()
          : null;
    });
    if (hash == null) return null;
    lines.writeln('$path $hash');
  }
  return sha256.convert(utf8.encode(lines.toString())).toString();
}

String _name(Directory entry) =>
    entry.uri.pathSegments.lastWhere((s) => s.isNotEmpty);
