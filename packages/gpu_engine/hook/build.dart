import 'dart:convert';
import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';
import 'package:native_toolchain_rust/native_toolchain_rust.dart';

import '../../../tool/bash_executable.dart';
import '../../../tool/machine_variables.dart';
import 'build_inputs.dart';
import 'shared_copies.dart';
import 'target_link.dart';

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
//
// A BUILD OF THE SAME FILES IS COPIED, NOT BUILT AGAIN (card
// a-batch-is-cut-silent-while-it-waits-for-the-hook-turn, 2026-11-14):
// before it asks for the turn, and again once it has it, the hook looks
// among the folder's copies for what another checkout built from files
// that read the same as its own, and after a build it keeps what it made
// there (hook/shared_copies.dart). With no bash to say where the folder
// is, it neither looks nor keeps.
const _asset = 'src/engine_ffi.dart';

void main(List<String> args) async {
  if (await _againWithThisMachinesRustHomes(args) case final code?) {
    exit(code);
  }
  await build(args, (input, output) async {
    final windows = input.config.buildCodeAssets &&
        input.config.code.targetOS == OS.windows;
    final dxc = input.outputDirectory.resolve('dxc/');
    final script = input.packageRoot.resolve('../../tool/cargo_turn.sh');
    final copies = await _copiesFor(script, input);
    if (copies == null || !_shipKept(copies, input, output)) {
      await _buildUnderTheTurn(
        script,
        copies,
        input,
        output,
        windows: windows,
        dxc: dxc,
      );
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

/// Builds the engine under the hook folder's turn — unless another
/// checkout kept a build of the same files while this one waited — and
/// keeps what it made in [copies].
Future<void> _buildUnderTheTurn(
  Uri script,
  SharedCopies? copies,
  BuildInput input,
  BuildOutputBuilder output, {
  required bool windows,
  required Uri dxc,
}) async {
  final turn = await _Turn.take(script);
  try {
    if (copies != null && _shipKept(copies, input, output)) return;
    final folder = turn.folder ?? input.outputDirectory.resolve('own_target/');
    final homes = [
      for (final name in kMachineVariables)
        '$name=${Platform.environment[name] ?? 'the default'}',
    ].join(' ');
    // Which way it built and with which Rust, in the log the hooks runner
    // keeps (stdout.txt beside the hook's input) — never a silent second
    // way (관제 22:55). ⚠️In one write: the runner appends each piece of
    // output to that file without waiting for the one before, and of two
    // lines written at once one was lost, either one (2026-11-08).
    stdout.writeln(
      turn.folder == null
          ? "gpu_engine: ${turn.why} — built in this checkout's own target, "
              '${folder.toFilePath()}, with Rust from $homes'
          : "gpu_engine: built in the trunk's hook folder, "
              '${folder.toFilePath()}, under its turn, '
              'with Rust from $homes',
    );
    await withTargetAimed(input.outputDirectory, folder, () async {
      final started = DateTime.now();
      final built = BuildOutputBuilder();
      await RustBuilder(
        assetName: _asset,
        // ⛔NOT A LOCK OF CARGO'S CHOOSING (관제 2026-11-13, card
        // the-engine-hook-builds-without-locked-and-rewrites-the-lock):
        // the builder runs a plain `cargo build`, which mends a lock that
        // is out of step with the manifests and builds what it chose — a
        // mutant of the lock's names was rewritten before the test that
        // read it ran. Every build of the app is the lock's, as the
        // land's crate gate and gpu-engine.yml already build. Not
        // `--offline`: a CI runner fetches the crates.
        extraCargoBuildArgs: const ['--locked'],
        extraCargoEnvironmentVariables: {
          'QA_CHECKOUT': input.packageRoot.resolve('rust/').toFilePath(),
          if (windows) 'GPU_ENGINE_DXC_OUT': dxc.toFilePath(),
        },
      ).run(input: input, output: built);
      final made = built.build();
      final read = _shipCopies(made, input, output);
      if (copies != null) {
        _keep(copies, made, read, input, started, windows: windows);
      }
    });
  } finally {
    await turn.release();
  }
}

/// The trunk's copies for this hook's config — null with no bash to say
/// where the hook folder is.
Future<SharedCopies?> _copiesFor(Uri script, BuildInput input) async {
  final ProcessResult said;
  try {
    said = await Process.run(bashExecutable, [
      script.toFilePath(),
      '--folder',
      'hook',
      '--where',
    ]);
  } on ProcessException {
    return null;
  }
  final folder = (said.stdout as String).trim();
  if (said.exitCode != 0 || folder.isEmpty) return null;
  return SharedCopies.forConfig(folder, input.config.json);
}

/// Ships the copy a build of the same files kept; false when there is
/// none, or when it went while this one took it.
bool _shipKept(
  SharedCopies copies,
  BuildInput input,
  BuildOutputBuilder output,
) {
  final checkout = input.packageRoot.resolve('../../');
  final KeptCopy? kept;
  try {
    kept = copies.find(checkout);
  } on FileSystemException {
    return false;
  }
  if (kept == null || !kept.copyTo(input.outputDirectory)) return false;
  // In one write, as the line of a build (above).
  stdout.writeln(
    'gpu_engine: a copy of the build of the same files, ${kept.where.path}',
  );
  output.assets.code.add(
    CodeAsset(
      package: input.packageName,
      name: _asset,
      linkMode: DynamicLoadingBundled(),
      file: input.outputDirectory.resolve(kept.library),
    ),
  );
  output.dependencies.addAll(kept.readIn(checkout));
  return true;
}

/// Keeps the library the build made — with DXC beside it on Windows — for
/// a checkout whose files read the same. ⛔Only a library loaded at run
/// time, which is what [_shipKept] ships; and a copy it could not keep
/// fails no build, as the build it would save was made.
void _keep(
  SharedCopies copies,
  BuildOutput built,
  List<Uri> read,
  BuildInput input,
  DateTime started, {
  required bool windows,
}) {
  if (built.assets.code case [final asset]
      when asset.linkMode is DynamicLoadingBundled) {
    final library = asset.file!.pathSegments.last;
    try {
      copies.keep(
        checkout: input.packageRoot.resolve('../../'),
        outputDirectory: input.outputDirectory,
        read: read,
        hook: input.packageRoot.resolve('hook/'),
        library: library,
        made: [library, if (windows) 'dxc/dxcompiler.dll'],
        started: started,
      );
    } on FileSystemException catch (error) {
      stderr.writeln('gpu_engine: kept no copy of this build — $error');
    }
  }
}

/// ⛔THIS MACHINE'S RUST HOMES, WHICH THE HOOKS RUNNER TAKES AWAY (관제
/// 2026-11-08, the-engine-hook-builds-with-the-c-drive-rust-homes): it hands
/// a hook only the variables it lists (hooks_runner 1.5.0,
/// `includeHookEnvironmentVariable`), and CARGO_HOME and RUSTUP_HOME are not
/// among them — so on the main PC, whose homes are on D:, the builder's
/// rustup installed the pinned toolchain into the default home on C:
/// (1.7 GB, 2026-11-07) and cargo kept a registry there. Handing them to
/// cargo alone is not enough: the builder asks `rustup show
/// active-toolchain` first, with no environment of ours, and that installs
/// the toolchain into the home it sees (measured 2026-11-08). So the hook
/// runs itself once more with them, read where a session's are
/// (tool/machine_variables.dart) — none off Windows, and none where the
/// user set none in their own settings. It does so before it asks for the
/// hook folder's turn, which the run it starts takes. Null when it has
/// them already.
Future<int?> _againWithThisMachinesRustHomes(List<String> args) async {
  final missing = {
    for (final MapEntry(:key, :value) in thisMachinesVariables().entries)
      if (Platform.environment[key] != value) key: value,
  };
  if (missing.isEmpty) return null;
  final again = await Process.start(
    Platform.resolvedExecutable,
    [...Platform.executableArguments, Platform.script.toFilePath(), ...args],
    environment: missing,
    mode: ProcessStartMode.inheritStdio,
  );
  return again.exitCode;
}

/// The builder's library, copied beside the hook's output and shipped
/// from there, and what the build read ([readByTheBuild]), which it
/// returns.
List<Uri> _shipCopies(
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
  final read = readByTheBuild(
    built.dependencies,
    target: input.outputDirectory.resolve('target/'),
    rust: input.packageRoot.resolve('rust/'),
    checkout: input.packageRoot.resolve('../../'),
  );
  output.dependencies.addAll(read);
  return read;
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
