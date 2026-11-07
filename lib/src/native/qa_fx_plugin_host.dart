// The engine's Rust library carries the host (rust/src/lib.rs), and its
// names are found in that code asset — no library opened, no path named.
@DefaultAsset(gpuEngineAsset)
library;

import 'dart:convert';
import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:gpu_engine/gpu_engine.dart' show gpuEngineAsset;

import '../models/fx_plugin_run.dart';

/// The host's `Picture` (native/fx_plugin/src/job.rs): premultiplied RGBA8
/// rows, its first pixel at (left, top) on the canvas.
final class QaFxPictureStruct extends Struct {
  external Pointer<Uint8> pixels;
  @Int32()
  external int width;
  @Int32()
  external int height;
  @Int32()
  external int stride;
  @Int32()
  external int left;
  @Int32()
  external int top;
}

/// The host's `RenderJob` (native/fx_plugin/src/job.rs).
final class QaFxRenderJobStruct extends Struct {
  external QaFxPictureStruct input;
  external Pointer<Uint8> output;
  @Int32()
  external int outputStride;
  @Int32()
  external int valueCount;
  external Pointer<Double> values;
  external Pointer<QaFxPictureStruct> layers;
  @Int32()
  external int layerCount;
  @Int32()
  external int frameIndex;
  @Double()
  external double time;
  @Double()
  external double frameRate;
  @Double()
  external double scale;
}

/// What opening a plugin gives: the plugin, or what the host said of why
/// not.
typedef FxPluginOpened = ({QaFxPlugin? plugin, String? error});

@Native<Pointer<Void> Function(Pointer<Utf8>, Pointer<Utf8>, Int32)>(
  symbol: 'qa_fx_plugin_open_native',
)
external Pointer<Void> _openNative(
  Pointer<Utf8> path,
  Pointer<Utf8> error,
  int errorCapacity,
);

@Native<Pointer<Void> Function(Pointer<Uint8>, Int64, Pointer<Utf8>, Int32)>(
  symbol: 'qa_fx_plugin_open_wasm',
)
external Pointer<Void> _openWasm(
  Pointer<Uint8> bytes,
  int length,
  Pointer<Utf8> error,
  int errorCapacity,
);

@Native<Int32 Function(Pointer<Void>, Pointer<Uint8>, Int32)>(
  symbol: 'qa_fx_plugin_describe',
)
external int _describe(
  Pointer<Void> plugin,
  Pointer<Uint8> out,
  int capacity,
);

@Native<
  Int32 Function(
    Pointer<Void>,
    Pointer<Double>,
    Int32,
    Int32,
    Double,
    Double,
    Double,
  )
>(symbol: 'qa_fx_plugin_reach')
external int _reach(
  Pointer<Void> plugin,
  Pointer<Double> values,
  int valueCount,
  int frameIndex,
  double time,
  double frameRate,
  double scale,
);

@Native<Int32 Function(Pointer<Void>, Pointer<QaFxRenderJobStruct>)>(
  symbol: 'qa_fx_plugin_render',
)
external int _render(
  Pointer<Void> plugin,
  Pointer<QaFxRenderJobStruct> job,
);

@Native<Void Function(Pointer<Void>)>(symbol: 'qa_fx_plugin_close')
external void _close(Pointer<Void> plugin);

@Native<Int32 Function()>(symbol: 'qa_fx_render_job_sizeof')
external int _renderJobSize();

@Native<Int32 Function()>(symbol: 'qa_fx_picture_sizeof')
external int _pictureSize();

/// The engine's fx plugin host (native/fx_plugin) — one plugin opened from
/// a native library or a WebAssembly module, asked the same four questions
/// either way (sdk/fx/anicel-fx; 🗣️I-132-Q5 「a + 데스크톱은 같은
/// 규격의 네이티브(.dll · .dylib)도」).
final class QaFxPluginHost {
  QaFxPluginHost._();

  /// The host, or null where its structs are laid out otherwise than these
  /// (a plugin is then not asked at all, never asked with fields read
  /// wrong).
  static final QaFxPluginHost? instance =
      _renderJobSize() == sizeOf<QaFxRenderJobStruct>() &&
          _pictureSize() == sizeOf<QaFxPictureStruct>()
      ? QaFxPluginHost._()
      : null;

  static const int _errorRoom = 512;

  /// Opens the native library at [path].
  ///
  /// ⚠️Loading a native library runs its code: only a plugin a person has
  /// installed is opened this way (the WebAssembly one answers whatever is
  /// asked before that — it runs in a sandbox).
  FxPluginOpened openNative(String path) => using((arena) {
    final error = arena<Uint8>(_errorRoom).cast<Utf8>();
    final named = path.toNativeUtf8(allocator: arena);
    return _opened(_openNative(named, error, _errorRoom), error);
  });

  /// Opens the WebAssembly module [bytes] — in a sandbox: no folder, no
  /// network, no environment.
  FxPluginOpened openWasm(Uint8List bytes) => using((arena) {
    final module = arena<Uint8>(bytes.isEmpty ? 1 : bytes.length);
    module.asTypedList(bytes.length).setAll(0, bytes);
    final error = arena<Uint8>(_errorRoom).cast<Utf8>();
    final handle = _openWasm(module, bytes.length, error, _errorRoom);
    return _opened(handle, error);
  });

  FxPluginOpened _opened(Pointer<Void> handle, Pointer<Utf8> error) =>
      handle == nullptr
      ? (plugin: null, error: error.toDartString())
      : (plugin: QaFxPlugin._(handle), error: null);
}

/// One open plugin. ⚠️Asked by one thread at a time; [close] lets it go.
final class QaFxPlugin implements FxPluginRunner {
  QaFxPlugin._(this._handle);

  Pointer<Void> _handle;

  /// The plugin's description (sdk/fx/anicel-fx, UTF-8 JSON), or null
  /// where it would not say — or said what is no UTF-8.
  String? describe() {
    const room = 4096;
    final first = _describeIn(room);
    // A longer one is asked again in the room it named — once: a plugin
    // that names more each time is not asked for ever.
    return first.length <= room ? first.text : _describeIn(first.length).text;
  }

  ({int length, String? text}) _describeIn(int room) => using((arena) {
    final out = arena<Uint8>(room);
    final length = _describe(_handle, out, room);
    if (length < 0 || length > room) {
      return (length: length, text: null);
    }
    try {
      return (length: length, text: utf8.decode(out.asTypedList(length)));
    } on FormatException {
      return (length: -1, text: null);
    }
  });

  @override
  int? reach(Float64List values, FxPluginMoment moment) => using((arena) {
    if (_handle == nullptr) {
      return null;
    }
    final at = arena<Double>(values.isEmpty ? 1 : values.length);
    at.asTypedList(values.length).setAll(0, values);
    final reach = _reach(
      _handle,
      at,
      values.length ~/ 4,
      moment.frameIndex,
      moment.time,
      moment.frameRate,
      moment.scale,
    );
    return reach < 0 ? null : reach;
  });

  @override
  Uint8List? render({
    required FxPluginPicture input,
    required Float64List values,
    required List<FxPluginPicture> layers,
    required FxPluginMoment moment,
  }) => using((arena) {
    if (_handle == nullptr) {
      return null;
    }
    final job = arena<QaFxRenderJobStruct>();
    _lay(job.ref.input, input, arena);
    final bytes = input.width * input.height * 4;
    final output = arena<Uint8>(bytes == 0 ? 1 : bytes);
    job.ref
      ..output = output
      ..outputStride = input.width * 4
      ..valueCount = values.length ~/ 4
      ..values = arena<Double>(values.isEmpty ? 1 : values.length)
      ..layers = arena<QaFxPictureStruct>(layers.isEmpty ? 1 : layers.length)
      ..layerCount = layers.length
      ..frameIndex = moment.frameIndex
      ..time = moment.time
      ..frameRate = moment.frameRate
      ..scale = moment.scale;
    job.ref.values.asTypedList(values.length).setAll(0, values);
    for (final (index, layer) in layers.indexed) {
      _lay(job.ref.layers[index], layer, arena);
    }
    if (_render(_handle, job) != 0) {
      return null;
    }
    return Uint8List.fromList(output.asTypedList(bytes));
  });

  static void _lay(
    QaFxPictureStruct to,
    FxPluginPicture picture,
    Allocator arena,
  ) {
    final pixels = arena<Uint8>(
      picture.pixels.isEmpty ? 1 : picture.pixels.length,
    );
    pixels.asTypedList(picture.pixels.length).setAll(0, picture.pixels);
    to
      ..pixels = pixels
      ..width = picture.width
      ..height = picture.height
      ..stride = picture.width * 4
      ..left = picture.left
      ..top = picture.top;
  }

  @override
  void close() {
    if (_handle == nullptr) {
      return;
    }
    _close(_handle);
    _handle = nullptr;
  }
}
