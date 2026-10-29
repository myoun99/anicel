import 'dart:convert';
import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'qa_engine_abi.dart';

/// `qa_fx_picture` (qa_fx_plugin.h): premultiplied RGBA8 rows, its first
/// pixel at (left, top) on the canvas.
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

/// `qa_fx_render_job` (qa_fx_plugin.h).
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

/// A picture a plugin is handed or gives back: premultiplied RGBA8, rows
/// [width] × 4 bytes apart, its first pixel at ([left], [top]) on the
/// canvas.
typedef FxPluginPicture = ({
  Uint8List pixels,
  int width,
  int height,
  int left,
  int top,
});

/// When a plugin is asked: the frame's index from the cut's first, its
/// time in seconds, the frames a second, and the output pixels a canvas
/// pixel is drawn at (below 1 in a draft).
typedef FxPluginMoment = ({
  int frameIndex,
  double time,
  double frameRate,
  double scale,
});

/// What opening a plugin gives: the plugin, or what the host said of why
/// not.
typedef FxPluginOpened = ({QaFxPlugin? plugin, String? error});

/// The engine's fx plugin host (qa_fx_plugin.c) — one plugin opened from a
/// native library or a WebAssembly module, asked the same four questions
/// either way (anicel_fx_plugin.h; 🗣️I-132-Q5 「a + 데스크톱은 같은
/// 규격의 네이티브(.dll · .dylib)도」).
final class QaFxPluginHost {
  QaFxPluginHost._(DynamicLibrary library)
    : _openNative = library
          .lookupFunction<
            Pointer<Void> Function(Pointer<Utf8>, Pointer<Utf8>, Int32),
            Pointer<Void> Function(Pointer<Utf8>, Pointer<Utf8>, int)
          >('qa_fx_plugin_open_native'),
      _openWasm = library
          .lookupFunction<
            Pointer<Void> Function(
              Pointer<Uint8>,
              Int64,
              Pointer<Utf8>,
              Int32,
            ),
            Pointer<Void> Function(Pointer<Uint8>, int, Pointer<Utf8>, int)
          >('qa_fx_plugin_open_wasm'),
      _calls = (
        describe: library
            .lookupFunction<
              Int32 Function(Pointer<Void>, Pointer<Uint8>, Int32),
              int Function(Pointer<Void>, Pointer<Uint8>, int)
            >('qa_fx_plugin_describe'),
        reach: library
            .lookupFunction<
              Int32 Function(
                Pointer<Void>,
                Pointer<Double>,
                Int32,
                Int32,
                Double,
                Double,
                Double,
              ),
              int Function(
                Pointer<Void>,
                Pointer<Double>,
                int,
                int,
                double,
                double,
                double,
              )
            >('qa_fx_plugin_reach'),
        render: library
            .lookupFunction<
              Int32 Function(Pointer<Void>, Pointer<QaFxRenderJobStruct>),
              int Function(Pointer<Void>, Pointer<QaFxRenderJobStruct>)
            >('qa_fx_plugin_render'),
        close: library
            .lookupFunction<
              Void Function(Pointer<Void>),
              void Function(Pointer<Void>)
            >('qa_fx_plugin_close'),
      );

  static QaFxPluginHost? _instance;
  static bool _tried = false;

  static void debugResetForTests() {
    _instance = null;
    _tried = false;
  }

  /// The host, or null where there is no engine — or one whose structs are
  /// laid out otherwise than these (a plugin is then not asked at all,
  /// never asked with fields read wrong).
  static QaFxPluginHost? get instance {
    if (!_tried) {
      _tried = true;
      final library = openQaEngineLibrary();
      _instance =
          library != null &&
              qaStructSizeMatches(
                library,
                'qa_fx_render_job_sizeof',
                sizeOf<QaFxRenderJobStruct>(),
              ) &&
              qaStructSizeMatches(
                library,
                'qa_fx_picture_sizeof',
                sizeOf<QaFxPictureStruct>(),
              )
          ? QaFxPluginHost._(library)
          : null;
    }
    return _instance;
  }

  final Pointer<Void> Function(Pointer<Utf8>, Pointer<Utf8>, int) _openNative;
  final Pointer<Void> Function(Pointer<Uint8>, int, Pointer<Utf8>, int)
  _openWasm;
  final _PluginCalls _calls;

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
      : (plugin: QaFxPlugin._(handle, _calls), error: null);
}

typedef _PluginCalls = ({
  int Function(Pointer<Void>, Pointer<Uint8>, int) describe,
  int Function(
    Pointer<Void>,
    Pointer<Double>,
    int,
    int,
    double,
    double,
    double,
  )
  reach,
  int Function(Pointer<Void>, Pointer<QaFxRenderJobStruct>) render,
  void Function(Pointer<Void>) close,
});

/// One open plugin. ⚠️Asked by one thread at a time; [close] lets it go.
final class QaFxPlugin {
  QaFxPlugin._(this._handle, this._calls);

  Pointer<Void> _handle;
  final _PluginCalls _calls;

  /// The plugin's description (anicel_fx_plugin.h, UTF-8 JSON), or null
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
    final length = _calls.describe(_handle, out, room);
    if (length < 0 || length > room) {
      return (length: length, text: null);
    }
    try {
      return (length: length, text: utf8.decode(out.asTypedList(length)));
    } on FormatException {
      return (length: -1, text: null);
    }
  });

  /// How far past its input the effect reaches for [values] (four doubles
  /// a parameter, anicel_fx_value) at [moment], in output pixels — or null
  /// where the plugin failed to say.
  int? reach(Float64List values, FxPluginMoment moment) => using((arena) {
    final at = arena<Double>(values.isEmpty ? 1 : values.length);
    at.asTypedList(values.length).setAll(0, values);
    final reach = _calls.reach(
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

  /// [input] as the effect draws it, its size and place — or null where the
  /// plugin failed (the row is then drawn as if the effect were off).
  /// [layers] are the rows its layer parameters name, in the places the
  /// values give them.
  Uint8List? render({
    required FxPluginPicture input,
    required Float64List values,
    required List<FxPluginPicture> layers,
    required FxPluginMoment moment,
  }) => using((arena) {
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
    if (_calls.render(_handle, job) != 0) {
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

  /// Lets the plugin go; nothing may be asked of it after.
  void close() {
    if (_handle == nullptr) {
      return;
    }
    _calls.close(_handle);
    _handle = nullptr;
  }
}
