import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../packages/gpu_engine/hook/shared_copies.dart';
import '../helpers/temp_dir.dart';

/// A CHECKOUT WHOSE FILES READ THE SAME TAKES A COPY OF THEIR BUILD
/// (a-batch-is-cut-silent-while-it-waits-for-the-hook-turn, 2026-11-14).
///
/// Every checkout's build of the engine is its own, so after another
/// checkout's turn the hook built the engine's crates again — 45–212 s
/// under the turn while other runs waited behind it. What a build made is
/// kept by the contents of what it read and the hook's own files, and a
/// checkout whose files hash the same takes a copy: neither the turn nor
/// cargo. Measured once by hand in the lane (the hook's 「a copy of the
/// build of the same files」 line, and no turn taken).
void main() {
  late Directory root;
  late SharedCopies copies;
  late DateTime before;

  Uri checkout(String name) => Directory('${root.path}/$name/').uri;

  File write(String path, String text) =>
      File('${root.path}/$path')
        ..createSync(recursive: true)
        ..writeAsStringSync(text);

  void lay(String name, {String lib = 'fn main() {}', String hook = 'a'}) {
    write('$name/rust/src/lib.rs', lib);
    write('$name/rust/Cargo.toml', '[package]');
    write('$name/hook/build.dart', hook);
    write('$name/out/engine.dll', 'built from $lib');
    write('$name/out/dxc/dxcompiler.dll', 'dxc');
  }

  // As the hook's reads are: DXC beside its output among them, which it
  // made and is no key.
  List<Uri> readIn(String name) => [
    checkout(name).resolve('rust/src/lib.rs'),
    checkout(name).resolve('rust/Cargo.toml'),
    checkout(name).resolve('out/dxc/dxcompiler.dll'),
  ];

  void keepFrom(String name, {DateTime? started}) => copies.keep(
    checkout: checkout(name),
    outputDirectory: checkout(name).resolve('out/'),
    read: readIn(name),
    hook: checkout(name).resolve('hook/'),
    library: 'engine.dll',
    made: const ['engine.dll', 'dxc/dxcompiler.dll'],
    started: started ?? DateTime.now().add(const Duration(seconds: 5)),
  );

  setUp(() {
    root = Directory.systemTemp.createTempSync('shared-copies');
    root = Directory(root.resolveSymbolicLinksSync().replaceAll(r'\', '/'));
    copies = SharedCopies(Directory('${root.path}/copies/config'));
    before = DateTime.now().subtract(const Duration(minutes: 1));
  });
  tearDown(() => deleteTempQuietly(root));

  test('another checkout with the same files takes the copy, and what it '
      'read is its own', () {
    lay('a');
    lay('b');
    File('${root.path}/b/out/engine.dll').deleteSync();
    File('${root.path}/b/out/dxc/dxcompiler.dll').deleteSync();
    keepFrom('a');
    final kept = copies.find(checkout('b'));
    expect(kept, isNotNull);
    expect(kept!.copyTo(checkout('b').resolve('out/')), isTrue);
    expect(
      File('${root.path}/b/out/engine.dll').readAsStringSync(),
      'built from fn main() {}',
    );
    expect(
      File('${root.path}/b/out/dxc/dxcompiler.dll').readAsStringSync(),
      'dxc',
    );
    expect(kept.library, 'engine.dll');
    expect(
      kept.readIn(checkout('b')).map((u) => u.toFilePath()).toSet(),
      {
        for (final path in [
          'b/hook/build.dart',
          'b/rust/Cargo.toml',
          'b/rust/src/lib.rs',
        ])
          File('${root.path}/$path').uri.toFilePath(),
      },
    );
  });

  test('a read file that differs, or is missing, takes no copy', () {
    lay('a');
    lay('b', lib: 'fn main() { 1; }');
    lay('c');
    File('${root.path}/c/rust/Cargo.toml').deleteSync();
    keepFrom('a');
    expect(copies.find(checkout('b')), isNull);
    expect(copies.find(checkout('c')), isNull);
  });

  test('the hook\'s own files are in the key', () {
    lay('a');
    lay('b', hook: 'b');
    keepFrom('a');
    expect(copies.find(checkout('b')), isNull);
  });

  test('a build whose read file changed after it started is not kept', () {
    lay('a');
    lay('b');
    keepFrom('a', started: before);
    expect(copies.find(checkout('b')), isNull);
  });

  test('a read file outside the checkout keeps nothing', () {
    lay('a');
    lay('b');
    final outside = write('elsewhere/lib.rs', 'x');
    copies.keep(
      checkout: checkout('a'),
      outputDirectory: checkout('a').resolve('out/'),
      read: [...readIn('a'), outside.uri],
      hook: checkout('a').resolve('hook/'),
      library: 'engine.dll',
      made: const ['engine.dll'],
      started: DateTime.now().add(const Duration(seconds: 5)),
    );
    expect(copies.find(checkout('b')), isNull);
  });

  test('of more copies than it keeps, the one taken longest ago goes', () {
    final long = DateTime.now().subtract(const Duration(hours: 1));
    for (var i = 0; i < kKeptCopies; i++) {
      lay('c$i', lib: 'fn main() { $i; }');
      keepFrom('c$i');
      final kept = copies.find(checkout('c$i'))!;
      // Taken an hour ago and on: the order is the test's, not the clock's.
      for (final file in kept.where.listSync().whereType<File>()) {
        file.setLastModifiedSync(long.add(Duration(seconds: i)));
      }
    }
    lay('c$kKeptCopies', lib: 'fn main() { $kKeptCopies; }');
    keepFrom('c$kKeptCopies');
    expect(copies.find(checkout('c0')), isNull);
    expect(copies.find(checkout('c1')), isNotNull);
    expect(copies.find(checkout('c$kKeptCopies')), isNotNull);
  });
}
