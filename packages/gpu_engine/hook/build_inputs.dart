import 'dart:io';

/// What the hook reports its build read, out of what the builder [named]:
/// those outside the build's [target] folder, and the workspace's
/// manifests under [rust] ([manifestsOf]).
///
/// 🚨WHAT THE BUILD MADE IS NOT WHAT IT READ (card
/// a-batch-is-cut-silent-while-it-waits-for-the-hook-turn, 2026-11-13):
/// the library's dep-info names `out/dxcompiler.dll` under [target] as
/// well — rust/build.rs asks to be run again when it changes — and that
/// path goes through the link `withTargetAimed` takes down when the build
/// ends. The hooks runner found it changed every time and ran the hook
/// again for every `flutter test`, so every run took the hook folder's turn
/// and waited behind whoever held it: 9 minutes of a run's 13 once, for a
/// cargo that then had nothing to build (0.8 s).
///
/// ⚠️THE MANIFESTS ARE NOT IN THE DEP-INFO: cargo names the sources it
/// compiled. A lane that changed a version in a Cargo.toml and the lock and
/// nothing else would be run on its old engine once the hook no longer ran
/// every time.
List<Uri> readByTheBuild(Iterable<Uri> named, Uri target, Uri rust) {
  final made = _comparable(target.toFilePath());
  return [
    for (final dependency in named)
      if (!_comparable(dependency.toFilePath()).startsWith(made)) dependency,
    ...manifestsOf(rust),
  ];
}

/// Every `Cargo.toml`, `Cargo.lock` and `rust-toolchain.toml` under [rust],
/// past no folder named `target…` — the trunk's hook folder lies there, its
/// builds holding copies of the registry's manifests — nor a hidden one.
List<Uri> manifestsOf(Uri rust) {
  final found = <Uri>[];
  void walk(Directory folder) {
    for (final entity in folder.listSync(followLinks: false)) {
      final name = entity.uri.pathSegments.lastWhere((s) => s.isNotEmpty);
      if (entity is Directory) {
        if (!name.startsWith('target') && !name.startsWith('.')) walk(entity);
      } else if (_manifests.contains(name)) {
        found.add(entity.uri);
      }
    }
  }

  walk(Directory.fromUri(rust));
  return found;
}

const _manifests = {'Cargo.toml', 'Cargo.lock', 'rust-toolchain.toml'};

String _comparable(String path) =>
    Platform.isWindows ? path.toLowerCase() : path;
