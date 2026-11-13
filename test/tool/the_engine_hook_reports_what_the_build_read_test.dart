import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../packages/gpu_engine/hook/build_inputs.dart';
import '../helpers/temp_dir.dart';

/// THE ENGINE'S BUILD HOOK REPORTS WHAT ITS BUILD READ, NOT WHAT IT MADE
/// (a-batch-is-cut-silent-while-it-waits-for-the-hook-turn, 2026-11-13).
///
/// The library's dep-info named `out/dxcompiler.dll` under the build's
/// target folder, which goes when the hook ends, and the hooks runner ran
/// the hook again for every `flutter test` — every run took the hook
/// folder's turn, for a cargo with nothing to build. The manifests, which
/// cargo reads and its dep-info does not name, take its place: a lane that
/// changes only a version is built again. Measured once by hand with
/// `flutter test -v` (the runner's 「Skipping build for gpu_engine」 on a
/// second run, 「Rerunning」 after a Cargo.toml changed).
void main() {
  late Directory root;
  late Uri rust;

  File made(String path) =>
      File('${root.path}/$path')
        ..createSync(recursive: true)
        ..writeAsStringSync(path);

  Set<String> names(Iterable<Uri> uris) => {
    for (final uri in uris)
      uri.toFilePath().replaceAll(r'\', '/').substring(root.path.length + 1),
  };

  setUp(() {
    root = Directory.systemTemp.createTempSync('hook-inputs');
    root = Directory(root.resolveSymbolicLinksSync().replaceAll(r'\', '/'));
    rust = Directory('${root.path}/rust').uri;
    for (final path in [
      'rust/Cargo.toml',
      'rust/Cargo.lock',
      'rust/rust-toolchain.toml',
      'rust/src/lib.rs',
      'rust/native/audio/Cargo.toml',
      'rust/vendor/wgpu-hal/Cargo.toml',
      'rust/.cargo/config.toml',
      'rust/target-hook/release/build/x/Cargo.toml',
      'rust/target/debug/build/y/Cargo.toml',
    ]) {
      made(path);
    }
  });
  tearDown(() => deleteTempQuietly(root));

  test('the manifests are every Cargo.toml, the lock and the toolchain, '
      'past no target folder', () {
    expect(names(manifestsOf(rust)), {
      'rust/Cargo.toml',
      'rust/Cargo.lock',
      'rust/rust-toolchain.toml',
      'rust/native/audio/Cargo.toml',
      'rust/vendor/wgpu-hal/Cargo.toml',
    });
  });

  test('what lies under the build\'s target folder is left out, and the '
      'manifests join the sources', () {
    final source = made('rust/src/lib.rs').uri;
    final built = made('out/target/release/build/g/out/dxcompiler.dll').uri;
    final shipped = made('out/dxc/dxcompiler.dll').uri;
    final read = readByTheBuild(
      [source, built, shipped],
      Directory('${root.path}/out/target').uri,
      rust,
    );
    expect(names(read), {
      'rust/src/lib.rs',
      'out/dxc/dxcompiler.dll',
      'rust/Cargo.toml',
      'rust/Cargo.lock',
      'rust/rust-toolchain.toml',
      'rust/native/audio/Cargo.toml',
      'rust/vendor/wgpu-hal/Cargo.toml',
    });
  });
}
