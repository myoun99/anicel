// Bindings to the texture shim, which every platform whose engine makes
// the texture Flutter shows exports by the same names: the Windows plugin
// DLL Flutter loads beside the runner (windows/gpu_engine_plugin_c_api.cpp),
// the iOS and macOS pod compiled into the app (darwin/Classes/
// GpuEnginePlugin.m) and the Linux plugin library the runner links
// (linux/gpu_engine_plugin.cc).
import 'dart:ffi';
import 'dart:io';

final DynamicLibrary _shim = Platform.isWindows
    ? DynamicLibrary.open('gpu_engine_plugin.dll')
    : Platform.isLinux
    ? DynamicLibrary.open('libgpu_engine_plugin.so')
    : DynamicLibrary.process();

/// Windows' alone: Flutter names its adapter by LUID only there.
final int Function() flutterAdapterLuid = _shim
    .lookupFunction<Uint64 Function(), int Function()>(
      'gpu_engine_flutter_adapter_luid',
    );

final int Function(Pointer<Void>, Pointer<Void>, int, int, bool)
textureRegister = _shim
    .lookupFunction<
      Int64 Function(Pointer<Void>, Pointer<Void>, Uint32, Uint32, Bool),
      int Function(Pointer<Void>, Pointer<Void>, int, int, bool)
    >('gpu_engine_texture_register');

final bool Function(int, int) textureShow = _shim
    .lookupFunction<Bool Function(Int64, Int32), bool Function(int, int)>(
      'gpu_engine_texture_show',
    );

final void Function(int) textureUnregister = _shim
    .lookupFunction<Void Function(Int64), void Function(int)>(
      'gpu_engine_texture_unregister',
    );

/// Windows' alone: what ANGLE's D3D11 sees of a shared handle.
final bool Function(
  Pointer<Void>,
  Pointer<Uint32>,
  Pointer<Uint32>,
  Pointer<Uint32>,
)
inspectShared = _shim
    .lookupFunction<
      Bool Function(
        Pointer<Void>,
        Pointer<Uint32>,
        Pointer<Uint32>,
        Pointer<Uint32>,
      ),
      bool Function(
        Pointer<Void>,
        Pointer<Uint32>,
        Pointer<Uint32>,
        Pointer<Uint32>,
      )
    >('gpu_engine_inspect_shared');
