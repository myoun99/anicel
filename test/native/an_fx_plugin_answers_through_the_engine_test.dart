@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/native/qa_engine_abi.dart';
import 'package:anicel/src/native/qa_fx_plugin_host.dart';

import '../helpers/native_engine_path.dart';

/// The fx plugin host as Dart asks it: the sample plugin the engine's build
/// makes beside it (qa_fx_plugin_sample.c) opened through
/// [QaFxPluginHost], its description, reach and render read back through
/// the structs — held to answers worked out here, so a field the Dart
/// struct lays where the C one does not shows as a wrong picture.
///
/// The WebAssembly side is the engine's own test's (qa_fx_plugin_test.c):
/// it writes its twin module from text, which Dart cannot.
void main() {
  final libraryPath = nativeEngineLibraryPathOrNull();
  final samplePath = libraryPath == null ? null : _sampleBeside(libraryPath);
  final skip = libraryPath == null
      ? nativeEngineMissingSkipReason
      : samplePath == null
      ? 'the engine at $libraryPath has no sample plugin beside it'
      : false;

  setUp(() {
    QaFxPluginHost.debugResetForTests();
    debugQaEngineLibraryPathOverride = libraryPath;
  });

  tearDown(() {
    QaFxPluginHost.debugResetForTests();
    debugQaEngineLibraryPathOverride = null;
  });

  QaFxPlugin openSample() {
    final host = QaFxPluginHost.instance;
    expect(host, isNotNull, reason: 'the engine at $libraryPath loaded '
        'but its plugin structs are laid out otherwise');
    final opened = host!.openNative(samplePath!);
    expect(opened.error, isNull);
    return opened.plugin!;
  }

  // The input: 5×3 at canvas (−1, −2); the map 2×2 at (0, −2), its alpha a
  // checkerboard. Premultiplied: no colour above its alpha.
  final input = Uint8List(5 * 3 * 4);
  for (var y = 0; y < 3; y += 1) {
    for (var x = 0; x < 5; x += 1) {
      final at = (y * 5 + x) * 4;
      input
        ..[at] = x * 30
        ..[at + 1] = y * 40
        ..[at + 2] = 7 + x + y
        ..[at + 3] = 160 + x * 10 + y * 3;
    }
  }
  final map = Uint8List(2 * 2 * 4);
  for (var y = 0; y < 2; y += 1) {
    for (var x = 0; x < 2; x += 1) {
      map[(y * 2 + x) * 4 + 3] = (x + y).isEven ? 255 : 0;
    }
  }
  const moment = (frameIndex: 3, time: 3 / 24, frameRate: 24.0, scale: 1.0);

  // What the sample gives, worked out here on its own.
  Uint8List expected({required double amount, required bool withMap}) {
    final out = Uint8List(input.length);
    for (var y = 0; y < 3; y += 1) {
      for (var x = 0; x < 5; x += 1) {
        final at = (y * 5 + x) * 4;
        var inverts = amount >= 50;
        if (inverts && withMap) {
          // The input's canvas place, less the map's.
          final mx = (x - 1) - 0;
          final my = (y - 2) - (-2);
          inverts =
              mx >= 0 &&
              my >= 0 &&
              mx < 2 &&
              my < 2 &&
              map[(my * 2 + mx) * 4 + 3] > 127;
        }
        for (var c = 0; c < 3; c += 1) {
          out[at + c] = inverts ? input[at + 3] - input[at + c] : input[at + c];
        }
        out[at + 3] = input[at + 3];
      }
    }
    return out;
  }

  Uint8List? render(
    QaFxPlugin plugin, {
    required double amount,
    bool? mapOn,
  }) => plugin.render(
        input: (pixels: input, width: 5, height: 3, left: -1, top: -2),
        values: Float64List.fromList([
          amount, 0, 0, 0, //
          if (mapOn ?? true) 0 else -1, 0, 0, 0,
        ]),
        layers: [(pixels: map, width: 2, height: 2, left: 0, top: -2)],
        moment: moment,
      );

  test('the sample says who it is', () {
    final plugin = openSample();
    final description =
        jsonDecode(plugin.describe()!) as Map<String, dynamic>;
    expect(description['spec'], 1);
    expect(description['id'], 'app.anicel.test.invert');
    expect([
      for (final parameter in description['params'] as List<dynamic>)
        (parameter as Map<String, dynamic>)['kind'],
    ], ['number', 'layer']);
    plugin.close();
  }, skip: skip);

  test('its reach reads the values and every number of the moment', () {
    final plugin = openSample();
    final values = Float64List.fromList([80, 0, 0, 0, 0, 0, 0, 0]);
    expect(plugin.reach(values, moment), 80 ~/ 10 + 3 + 3);
    expect(
      plugin.reach(values, (
        frameIndex: 5,
        time: 7 / 24,
        frameRate: 24.0,
        scale: 0.5,
      )),
      4 + 5 + 7,
    );
    plugin.close();
  }, skip: skip);

  test('a render reads the map where the canvas puts it', () {
    final plugin = openSample();
    expect(
      render(plugin, amount: 80),
      expected(amount: 80, withMap: true),
    );
    expect(
      render(plugin, amount: 80, mapOn: false),
      expected(amount: 80, withMap: false),
    );
    expect(
      render(plugin, amount: 30),
      expected(amount: 30, withMap: true),
    );
    plugin.close();
  }, skip: skip);

  test("a plugin's failure is no picture", () {
    final plugin = openSample();
    expect(render(plugin, amount: -5), isNull);
    plugin.close();
  }, skip: skip);

  test('what is no plugin is said so', () {
    final host = QaFxPluginHost.instance!;
    final missing = host.openNative('${samplePath!}.missing');
    expect(missing.plugin, isNull);
    expect(missing.error, isNotEmpty);
    final garbage = host.openWasm(Uint8List.fromList([1, 2, 3, 4]));
    expect(garbage.plugin, isNull);
    expect(garbage.error, isNotEmpty);
  }, skip: skip);
}

/// The sample plugin the engine's build makes in its own folder — where
/// QA_ENGINE_PATH points ([nativeEngineLibraryPathOrNull]).
String? _sampleBeside(String libraryPath) {
  final folder = File(libraryPath).parent.path;
  final name = Platform.isWindows
      ? 'qa_fx_plugin_sample.dll'
      : Platform.isMacOS
      ? 'libqa_fx_plugin_sample.dylib'
      : 'libqa_fx_plugin_sample.so';
  final path = '$folder${Platform.pathSeparator}$name';
  if (File(path).existsSync()) {
    return path;
  }
  if (nativeEngineRequired) {
    fail('QA_REQUIRE_NATIVE=1 but no sample plugin beside the engine: $path');
  }
  return null;
}
