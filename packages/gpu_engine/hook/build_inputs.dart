import 'dart:io';

/// What the hook reports its build read, out of what the builder [named]:
/// those outside the hook's [output] folder, every file of the [rust]
/// workspace ([workspaceFiles]), and the manifests beside each source up to
/// the [checkout] ([manifestsBeside]).
///
/// 🚨WHAT THE BUILD MADE IS NOT WHAT IT READ (card
/// a-batch-is-cut-silent-while-it-waits-for-the-hook-turn, 2026-11-13):
/// the library's dep-info names `out/dxcompiler.dll` under the build's
/// target folder as well — rust/build.rs asks to be run again when it
/// changes — and that path goes through the link `withTargetAimed` takes
/// down when the build ends. The hooks runner found it changed every time
/// and ran the hook again for every `flutter test`, so every run took the
/// hook folder's turn and waited behind whoever held it: 9 minutes of a
/// run's 13 once, for a cargo that then had nothing to build (0.8 s).
///
/// 🚨NOR WHAT IT SHIPS — THE WHOLE [output] FOLDER, NOT ONLY THE TARGET IN
/// IT (card a-second-release-build-loses-its-dxc, 2026-11-16): the dep-info
/// names the DXC copy rust/build.rs leaves in `dxc/` beside the library too,
/// and Flutter lists each file a hook ships as its build's output unless
/// the hook reported it read — and deletes a file it listed last build that
/// it no longer lists (flutter_tools build_system.dart, 「Delete outputs from
/// previous stages」). A build from a kept copy (shared_copies.dart) reported
/// no DXC read and a cargo build did, so a cargo build after a copy had
/// Flutter delete the DXC it had just shipped, and `install_code_assets`
/// failed to find it: every second Windows release build on the Surface
/// (2026-11-16 22:58 · 23:30), and the main PC's stamps of one config
/// flipped between the two (`build_hooks.stamp`, the DXC an input after a
/// cargo build and an output after a copy).
///
/// ⚠️THE DEP-INFO DOES NOT NAME ALL THE BUILD READS (measured 2026-11-14 in
/// a dep-info of 208 files): cargo names the sources of the path crates it
/// reaches through path crates — not those of rust/vendor, patched in for
/// registry crates (wgpu-hal, symphonia), nor any manifest. Once the hook
/// no longer ran every time, a lane that changed only those would have run
/// its tests on its old engine; hence the workspace's every file, and the
/// manifests of a crate outside it (sdk/fx/anicel-fx, read from rust/).
List<Uri> readByTheBuild(
  Iterable<Uri> named, {
  required Uri output,
  required Uri rust,
  required Uri checkout,
}) {
  final sources = [
    for (final dependency in named)
      if (!lies(dependency, under: output)) dependency,
  ];
  return {
    ...sources,
    ...workspaceFiles(rust),
    ...manifestsBeside(sources, checkout),
  }.toList();
}

/// Every file under [rust], past no folder named `target…` — the trunk's
/// hook folder lies there, its builds holding copies of the registry's
/// manifests — nor a hidden one: cargo, run from the package root, reads no
/// rust/.cargo (build.dart, QA_CHECKOUT).
List<Uri> workspaceFiles(Uri rust) {
  final found = <Uri>[];
  void walk(Directory folder) {
    for (final entity in folder.listSync(followLinks: false)) {
      final name = entity.uri.pathSegments.lastWhere((s) => s.isNotEmpty);
      if (entity is Directory) {
        if (!name.startsWith('target') && !name.startsWith('.')) walk(entity);
      } else if (entity is File) {
        found.add(entity.uri);
      }
    }
  }

  walk(Directory.fromUri(rust));
  return found;
}

/// The `Cargo.toml`, `Cargo.lock` and `rust-toolchain.toml` in every
/// folder from each of [sources] up to [checkout]: a crate's manifest, and
/// the workspace's a crate inherits from.
List<Uri> manifestsBeside(Iterable<Uri> sources, Uri checkout) {
  final found = <Uri>[];
  final seen = <String>{};
  for (final source in sources) {
    var folder = File.fromUri(source).parent;
    while (lies(folder.uri, under: checkout) && seen.add(folder.path)) {
      for (final name in _manifests) {
        final manifest = File('${folder.path}${Platform.pathSeparator}$name');
        if (manifest.existsSync()) found.add(manifest.uri);
      }
      folder = folder.parent;
    }
  }
  return found;
}

const _manifests = {'Cargo.toml', 'Cargo.lock', 'rust-toolchain.toml'};

/// Whether [path] is [under] that folder or is it.
bool lies(Uri path, {required Uri under}) {
  String comparable(Uri uri) {
    final text = uri.toFilePath();
    final trimmed = text.endsWith(Platform.pathSeparator)
        ? text.substring(0, text.length - 1)
        : text;
    return Platform.isWindows ? trimmed.toLowerCase() : trimmed;
  }

  final folder = comparable(under);
  final candidate = comparable(path);
  return candidate == folder ||
      candidate.startsWith('$folder${Platform.pathSeparator}');
}
