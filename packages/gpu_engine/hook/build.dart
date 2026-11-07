import 'dart:convert';
import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';
import 'package:native_toolchain_rust/native_toolchain_rust.dart';

import '../../../tool/bash_executable.dart';

// Builds rust/ with the toolchain pinned in rust/rust-toolchain.toml and
// ships it as the code asset that lib/src/engine_ffi.dart binds to.
//
// On Windows it also ships the dxcompiler.dll the engine compiles its DX12
// shaders with (gpu-engine-feasibility-Q4 · Q5): rust/build.rs fetches it,
// checks it against its pin and copies it where this hook asks, and Flutter
// installs every bundled code asset in one folder
// (windows/CMakeLists.txt, NATIVE_ASSETS_DIR) — beside the engine, which
// looks for it there.
//
// THE TRUNK'S ONE HOOK FOLDER (관제 · 브러시/렌더링 2026-11-07,
// connection-round-checklist (나)): the hook built into a folder of each
// checkout's own, and the app's tests run it — so every lane's first test
// built wgpu once more (485 MB and 110 s, measured that day). Every
// checkout's hook builds in the trunk's rust/target-hook instead, under
// that folder's turn (tool/cargo_turn.sh --folder hook --hold) — ⛔not the
// crate gate's folder and turn (관제 2026-11-08 00:24, the card's 00:21):
// under them a lane's first test waited for a gate's whole run, 445 s
// against 19 s, and after a gate the hook built 14 of its shared host
// build scripts and 30 crates again, 45 s. It builds there as each
// checkout's own build: cargo does not read rust/.cargo/config.toml from
// here (the run's folder is not rust/ — measured 2026-11-07, QA_CHECKOUT
// was unset in the build's fingerprint), so the hook hands it QA_CHECKOUT
// itself. ⛔Without it a lane's files, older than another checkout's build,
// read as fresh and the lane's tests run that checkout's engine
// (src/kernels/shared/one_checkout.rs) — measured for a target the hook
// hands no other checkout's own value for, as it hands every one but
// Windows (tool/engine_hook_checkout_test.sh). The library is copied out
// of the folder before the turn is let go, and the copy is the asset:
// another checkout may build there again before Flutter installs it.
// ⚠️With no bash to take the turn it builds into a folder of its own, as
// before (관제 22:55: a fork of the machine's, not a convenience rule —
// it builds as correctly as before). That is a build started outside a
// shell, as from Android Studio: the main PC's PATH has Git's folder of
// commands, not its shell (measured 2026-11-07). The user's own builds are
// the trunk's, one checkout, which a shared folder saves nothing for.
const _asset = 'src/engine_ffi.dart';

void main(List<String> args) async {
  await build(args, (input, output) async {
    final windows = input.config.buildCodeAssets &&
        input.config.code.targetOS == OS.windows;
    final dxc = input.outputDirectory.resolve('dxc/');
    final turn = await _Turn.take(
      input.packageRoot.resolve('../../tool/cargo_turn.sh'),
    );
    try {
      final folder =
          turn.folder ?? input.outputDirectory.resolve('own_target/');
      // Which way it built, in the log the hooks runner keeps (stdout.txt
      // beside the hook's input) — never a silent second way (관제 22:55).
      print(
        turn.folder == null
            ? "gpu_engine: ${turn.why} — built in this checkout's own target, "
                '${folder.toFilePath()}'
            : "gpu_engine: built in the trunk's hook folder, "
                '${folder.toFilePath()}, under its turn',
      );
      _aimTarget(input.outputDirectory, folder);
      final built = BuildOutputBuilder();
      await RustBuilder(
        assetName: _asset,
        extraCargoEnvironmentVariables: {
          'QA_CHECKOUT': input.packageRoot.resolve('rust/').toFilePath(),
          if (windows) 'GPU_ENGINE_DXC_OUT': dxc.toFilePath(),
        },
      ).run(input: input, output: built);
      _shipCopies(built.build(), input, output);
    } finally {
      await turn.release();
    }
    if (!windows) return;
    final dll = dxc.resolve('dxcompiler.dll');
    // ⛔No FXC behind a missing file: the engine would open no adapter.
    if (!File.fromUri(dll).existsSync()) {
      throw StateError('rust/build.rs left no dxcompiler.dll in $dxc');
    }
    output.assets.code.add(
      CodeAsset(
        package: input.packageName,
        name: 'dxcompiler',
        linkMode: DynamicLoadingBundled(),
        file: dll,
      ),
    );
  });
}

/// The builder builds into `target` of the hook's output folder, and the
/// folder is fixed on its command line — so `target` is a link to [folder].
void _aimTarget(Uri outputDirectory, Uri folder) {
  final target = outputDirectory.resolve('target').toFilePath();
  final was = FileSystemEntity.typeSync(target, followLinks: false);
  // ⛔The link itself, never through it: it is the trunk's target.
  if (was == FileSystemEntityType.link) Link(target).deleteSync();
  // A hook from before the link built there itself.
  if (was == FileSystemEntityType.directory) {
    Directory(target).deleteSync(recursive: true);
  }
  Directory.fromUri(folder).createSync(recursive: true);
  if (!Platform.isWindows) {
    Link(target).createSync(folder.toFilePath());
    return;
  }
  // ⛔A junction, not the symbolic link Dart's Link makes on Windows:
  // rust/build.rs unpacks the DXC zip into its OUT_DIR, inside this
  // folder, with Windows' tar, which will not unpack through a symbolic
  // link ("too many symbolic link levels") and does through a junction
  // (measured 2026-11-07). A junction needs no privilege either.
  final made = Process.runSync('cmd', [
    '/c',
    'mklink',
    '/J',
    target,
    folder.toFilePath(),
  ]);
  if (made.exitCode != 0) {
    throw StateError('mklink /J $target: ${made.stdout}${made.stderr}');
  }
}

/// The builder's library, copied beside the hook's output and shipped
/// from there.
void _shipCopies(
  BuildOutput built,
  BuildInput input,
  BuildOutputBuilder output,
) {
  for (final asset in built.assets.code) {
    final library = File.fromUri(asset.file!);
    final copy = input.outputDirectory.resolve(library.uri.pathSegments.last);
    library.copySync(copy.toFilePath());
    output.assets.code.add(
      CodeAsset(
        package: input.packageName,
        name: _asset,
        linkMode: asset.linkMode,
        file: copy,
      ),
    );
  }
  output.dependencies.addAll(built.dependencies);
}

/// The trunk's hook folder's turn, held by `tool/cargo_turn.sh --folder
/// hook --hold` until [release] — or, when it could not be taken, why.
final class _Turn {
  _Turn._(this._holder, this.folder, this.why);

  final Process? _holder;

  /// The hook folder, as the turn says it; null when not held.
  final Uri? folder;

  final String why;

  static Future<_Turn> take(Uri script) async {
    final Process holder;
    try {
      holder = await Process.start(bashExecutable, [
        script.toFilePath(),
        '--folder',
        'hook',
        '--hold',
      ]);
    } on ProcessException catch (error) {
      return _Turn._(null, null, "no bash to take the hook folder's turn "
          '(${error.executable}: ${error.message.trim()})');
    }
    holder.stderr.listen(stderr.add);
    final said = await holder.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .firstWhere((_) => true, orElse: () => '');
    if (said.isEmpty) {
      return _Turn._(null, null, '${script.toFilePath()} --hold said no '
          'folder (exit ${await holder.exitCode})');
    }
    return _Turn._(holder, Directory(said).uri, 'held');
  }

  Future<void> release() async {
    final holder = _holder;
    if (holder == null) return;
    await holder.stdin.close();
    await holder.exitCode;
  }
}
