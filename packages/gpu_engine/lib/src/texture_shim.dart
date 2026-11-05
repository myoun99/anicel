// Bindings to the Windows texture shim (windows/gpu_engine_plugin_c_api.cpp),
// the plugin DLL Flutter loads beside the runner.
import 'dart:ffi';

final DynamicLibrary _shim = DynamicLibrary.open('gpu_engine_plugin.dll');

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
