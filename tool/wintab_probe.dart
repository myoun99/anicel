// Wintab bridge probe (pen program, PEN-2).
//
// Plain-VM FFI smoke against a REAL tablet driver:
//   dart tool/wintab_probe.dart [path/to/gpu_engine_core.dll]
//
// Prints the bridge ABI, whether wintab32 + a driver answer, and the
// driver's device name, from the GPU engine's library, which carries the
// pen (native/pen). qat_open needs the app's window, so a console run only
// exercises the query surface — the packet path is verified in-app (the
// input inspector's wintab line).
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

void main(List<String> args) {
  final path = args.isNotEmpty
      ? args.first
      : 'build/native_assets/windows/gpu_engine_core.dll';
  if (!File(path).existsSync()) {
    stderr.writeln('no library at $path — build the app first:');
    stderr.writeln('  flutter build windows');
    exit(2);
  }
  final lib = DynamicLibrary.open(path);
  final abi = lib.lookupFunction<Int32 Function(), int Function()>(
    'qat_abi_version',
  )();
  final available = lib.lookupFunction<Int32 Function(), int Function()>(
    'qat_available',
  )();
  stdout.writeln('pen abi=$abi available=$available');
  if (available == 0) {
    stdout.writeln(
      'no wintab driver answered (wintab32.dll missing or no '
      'tablet installed) — the graceful-absence path.',
    );
    return;
  }
  final name = malloc<Uint16>(64);
  final length = lib
      .lookupFunction<
        Int32 Function(Pointer<Uint16>, Int32),
        int Function(Pointer<Uint16>, int)
      >('qat_device_name')(name, 64);
  final chars = name.asTypedList(length);
  stdout.writeln('device: ${String.fromCharCodes(chars)}');
  malloc.free(name);
}
