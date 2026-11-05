import 'package:hooks/hooks.dart';
import 'package:native_toolchain_rust/native_toolchain_rust.dart';

// Builds rust/ with the toolchain pinned in rust/rust-toolchain.toml and
// ships it as the code asset that lib/src/engine_ffi.dart binds to.
void main(List<String> args) async {
  await build(args, (input, output) async {
    await const RustBuilder(
      assetName: 'src/engine_ffi.dart',
    ).run(input: input, output: output);
  });
}
