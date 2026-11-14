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
/// folder's turn, for a cargo with nothing to build. What the dep-info
/// does not name takes its place (2026-11-14): every file of the workspace
/// — rust/vendor's patched crates among them — and the manifests of a
/// crate outside it, so a lane that changes only those is built again.
/// Measured once by hand with `flutter test -v` (the runner's 「Skipping
/// build for gpu_engine」 on a second run, 「Rerunning」 after a vendored
/// source or the fx SDK's manifest changed).
void main() {
  late Directory root;
  late Uri checkout;
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
    checkout = Directory('${root.path}/checkout').uri;
    rust = Directory('${root.path}/checkout/rust').uri;
    for (final path in [
      'checkout/rust/Cargo.toml',
      'checkout/rust/Cargo.lock',
      'checkout/rust/src/lib.rs',
      'checkout/rust/vendor/wgpu-hal/src/lib.rs',
      'checkout/rust/.cargo/config.toml',
      'checkout/rust/target-hook/release/build/x/Cargo.toml',
      'checkout/rust/target/debug/build/y/Cargo.toml',
      'checkout/sdk/Cargo.toml',
      'checkout/sdk/fx/src/lib.rs',
      'checkout/sdk/fx/Cargo.toml',
      'checkout/sdk/example/Cargo.toml',
      'Cargo.toml',
    ]) {
      made(path);
    }
  });
  tearDown(() => deleteTempQuietly(root));

  test('the workspace is its every file, past no target folder nor a '
      'hidden one', () {
    expect(names(workspaceFiles(rust)), {
      'checkout/rust/Cargo.toml',
      'checkout/rust/Cargo.lock',
      'checkout/rust/src/lib.rs',
      'checkout/rust/vendor/wgpu-hal/src/lib.rs',
    });
  });

  test('beside a source, the manifests of every folder up to the checkout '
      'and none past it', () {
    final source = File('${root.path}/checkout/sdk/fx/src/lib.rs').uri;
    expect(names(manifestsBeside([source], checkout)), {
      'checkout/sdk/fx/Cargo.toml',
      'checkout/sdk/Cargo.toml',
    });
  });

  test('what lies under the build\'s target folder is left out, and the '
      'workspace and the manifests join the sources', () {
    final source = made('checkout/sdk/fx/src/lib.rs').uri;
    final built = made('out/target/release/build/g/out/dxcompiler.dll').uri;
    final shipped = made('out/dxc/dxcompiler.dll').uri;
    final beside = made('out/targeted/notes.txt').uri;
    final read = readByTheBuild(
      [source, built, shipped, beside],
      target: Directory('${root.path}/out/target').uri,
      rust: rust,
      checkout: checkout,
    );
    expect(names(read), {
      'checkout/sdk/fx/src/lib.rs',
      'out/dxc/dxcompiler.dll',
      'out/targeted/notes.txt',
      'checkout/rust/Cargo.toml',
      'checkout/rust/Cargo.lock',
      'checkout/rust/src/lib.rs',
      'checkout/rust/vendor/wgpu-hal/src/lib.rs',
      'checkout/sdk/fx/Cargo.toml',
      'checkout/sdk/Cargo.toml',
    });
  });

  test('on Windows a path lies under its folder whatever their case', () {
    final built = made('out/target/release/lib.d').uri;
    final upper = Uri.file(
      '${root.path}/out/target'.replaceAll('/', r'\').toUpperCase(),
      windows: true,
    );
    expect(lies(built, under: upper), isTrue);
  }, skip: Platform.isWindows ? false : 'paths there are one case');
}
