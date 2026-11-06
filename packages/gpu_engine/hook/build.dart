import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';
import 'package:native_toolchain_rust/native_toolchain_rust.dart';

// Builds rust/ with the toolchain pinned in rust/rust-toolchain.toml and
// ships it as the code asset that lib/src/engine_ffi.dart binds to.
//
// On Windows it also ships the dxcompiler.dll the engine compiles its DX12
// shaders with (gpu-engine-feasibility-Q4 · Q5): rust/build.rs fetches it,
// checks it against its pin and copies it where this hook asks, and Flutter
// installs every bundled code asset in one folder
// (windows/CMakeLists.txt, NATIVE_ASSETS_DIR) — beside the engine, which
// looks for it there.
void main(List<String> args) async {
  await build(args, (input, output) async {
    final windows = input.config.buildCodeAssets &&
        input.config.code.targetOS == OS.windows;
    final dxc = input.outputDirectory.resolve('dxc/');
    await RustBuilder(
      assetName: 'src/engine_ffi.dart',
      extraCargoEnvironmentVariables: {
        if (windows) 'GPU_ENGINE_DXC_OUT': dxc.toFilePath(),
      },
    ).run(input: input, output: output);
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
