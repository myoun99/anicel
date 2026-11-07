@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/effect_parameter_spec.dart';
import 'package:anicel/src/models/fx_plugin_description.dart';
import 'package:anicel/src/models/fx_plugin_run.dart';
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
///
/// The SDK's example is the plugin a maker starts from (sdk/fx/example);
/// its C build (qa_fx_sdk_example.c, the key the Rust one is held to) is
/// made beside the engine: what it says of itself is held to the app's own
/// reading of a description, and its pictures to answers worked out here.
/// ⏳The connection round deletes the C builds; this then opens the Rust
/// ones the spec crate's tests build (native/fx_plugin/examples).
void main() {
  final libraryPath = nativeEngineLibraryPathOrNull();
  final samplePath = libraryPath == null
      ? null
      : _builtBeside(libraryPath, 'qa_fx_plugin_sample');
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

  group('the SDK example', () {
    final examplePath = libraryPath == null
        ? null
        : _builtBeside(libraryPath, 'qa_fx_sdk_example');
    final skipExample = libraryPath == null
        ? nativeEngineMissingSkipReason
        : examplePath == null
        ? 'the engine at $libraryPath has no SDK example beside it'
        : false;

    QaFxPlugin openExample() {
      final opened = QaFxPluginHost.instance!.openNative(examplePath!);
      expect(opened.error, isNull);
      return opened.plugin!;
    }

    // A 3×2 block of picture in a 7×5 input, its colour no more than its
    // alpha; the shadow's colour as its parameter says it, 0 to 1.
    const width = 7;
    const height = 5;
    final picture = Uint8List(width * height * 4);
    for (var y = 1; y <= 2; y += 1) {
      for (var x = 2; x <= 4; x += 1) {
        final at = (y * width + x) * 4;
        final alpha = 200 + x * 7 + y * 11;
        picture
          ..[at] = alpha * 3 ~/ 4
          ..[at + 1] = alpha ~/ 2
          ..[at + 2] = alpha ~/ 5
          ..[at + 3] = alpha;
      }
    }
    const color = [0.2, 0.4, 0.6, 0.5];
    Float64List values(double x, double y) => Float64List.fromList([
      x, 0, 0, 0, //
      y, 0, 0, 0,
      ...color,
    ]);
    FxPluginMoment at(double scale) =>
        (frameIndex: 0, time: 0.0, frameRate: 24.0, scale: scale);

    // What the example draws, worked out here on its own: the picture over
    // its alpha moved by the offset (in output pixels, rounded half away
    // from zero) and painted in the colour, both premultiplied.
    Uint8List shadowed(double x, double y, double scale) {
      int rounded(double v) => (v < 0 ? v - 0.5 : v + 0.5).truncate();
      int byte(double unit) => (unit * 255 + 0.5).floor();
      int times(int a, int b) => ((a * b + 128) + ((a * b + 128) >> 8)) >> 8;
      final dx = rounded(x * scale);
      final dy = rounded(y * scale);
      final out = Uint8List(picture.length);
      for (var row = 0; row < height; row += 1) {
        for (var column = 0; column < width; column += 1) {
          final at = (row * width + column) * 4;
          final fromX = column - dx;
          final fromY = row - dy;
          final inside =
              fromX >= 0 && fromY >= 0 && fromX < width && fromY < height;
          final cast = inside ? picture[(fromY * width + fromX) * 4 + 3] : 0;
          final alpha = times(cast, byte(color[3]));
          final behind = 255 - picture[at + 3];
          for (var c = 0; c < 3; c += 1) {
            out[at + c] =
                picture[at + c] + times(times(byte(color[c]), alpha), behind);
          }
          out[at + 3] = picture[at + 3] + times(alpha, behind);
        }
      }
      return out;
    }

    test('says who it is as the app reads a description', () {
      final plugin = openExample();
      final description = FxPluginDescription.read(plugin.describe()!);
      expect(description, isNotNull);
      expect(description!.id, 'com.example.shadow');
      expect([
        for (final p in description.parameters)
          (p.id, p.unit, p.defaultValue, p.minimum, p.maximum),
      ], [
        ('x', EffectParameterUnit.number, 8, -200, 200),
        ('y', EffectParameterUnit.number, 8, -200, 200),
        ('color', EffectParameterUnit.color, 0x99000000, 0, 0xFFFFFFFF),
      ]);
      plugin.close();
    }, skip: skipExample);

    test('reaches as far as the shadow is moved, in output pixels', () {
      final plugin = openExample();
      expect(plugin.reach(values(2, 1), at(1)), 2);
      expect(plugin.reach(values(-3, 1), at(1)), 3);
      expect(plugin.reach(values(8, -9), at(0.5)), 5);
      plugin.close();
    }, skip: skipExample);

    test('draws the picture over its shadow', () {
      final plugin = openExample();
      const offsets = [(2.0, 1.0, 1.0), (-3.0, 2.0, 1.0), (5.0, -4.0, 0.5)];
      for (final (x, y, scale) in offsets) {
        expect(
          plugin.render(
            input: (
              pixels: picture,
              width: width,
              height: height,
              left: -2,
              top: -1,
            ),
            values: values(x, y),
            layers: const [],
            moment: at(scale),
          ),
          shadowed(x, y, scale),
          reason: 'offset ($x, $y) at scale $scale',
        );
      }
      plugin.close();
    }, skip: skipExample);

    // Its C build and the header it reads are compiled without /utf-8
    // (packages/qa_native/src/CMakeLists.txt), so MSVC reads them in the
    // machine's code page: on a Japanese or Korean Windows it warns at
    // every byte past ASCII, and one at a line's end can take the line
    // break with it. ↩️Until 2026-11-07 they were the SDK's, read by a
    // maker's compiler; the connection round deletes both.
    test('its C is ASCII, as every code page reads it', () {
      for (final path in [
        'packages/qa_native/src/anicel_fx_plugin.h',
        'packages/qa_native/src/qa_fx_sdk_example.c',
      ]) {
        final bytes = File(path).readAsBytesSync();
        expect(
          [for (var i = 0; i < bytes.length; i += 1) if (bytes[i] > 0x7E) i],
          isEmpty,
          reason: path,
        );
      }
    });
  });
}

/// The plugin [target] the engine's build makes in its own folder — where
/// QA_ENGINE_PATH points ([nativeEngineLibraryPathOrNull]).
String? _builtBeside(String libraryPath, String target) {
  final folder = File(libraryPath).parent.path;
  final name = Platform.isWindows
      ? '$target.dll'
      : Platform.isMacOS
      ? 'lib$target.dylib'
      : 'lib$target.so';
  final path = '$folder${Platform.pathSeparator}$name';
  if (File(path).existsSync()) {
    return path;
  }
  if (nativeEngineRequired) {
    fail('QA_REQUIRE_NATIVE=1 but no $target beside the engine: $path');
  }
  return null;
}
