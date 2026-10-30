import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 🚨★★★THE COPIES PAST `flutter_gpu`'S DART CHECK ARE THE SDK'S OWN NATIVES
/// (F-509-Q10, 유저 2026-10-30 「올릴때마다 무조건 맞추도록 주의」).
///
/// A native signature that drifts from the engine's does not fail to build:
/// it crashes, and only where the copy runs. So the SDK in use is read here
/// and every Flutter upgrade answers to it — an upgrade that changes either
/// signature, or names the formats these exist for, goes red.
void main() {
  final ours = File(
    'lib/src/ui/playback/flutter_gpu_copies.dart',
  ).readAsStringSync();
  // The tester has no `Isolate.resolvePackageUri`: the package config is
  // what it resolved `flutter_gpu` by.
  final config = File('.dart_tool/package_config.json');
  final packages =
      (jsonDecode(config.readAsStringSync()) as Map<String, dynamic>)['packages']
          as List<dynamic>;
  final package =
      packages.firstWhere(
            (package) =>
                (package as Map<String, dynamic>)['name'] == 'flutter_gpu',
          )
          as Map<String, dynamic>;
  final src = config.absolute.uri
      .resolve('${package['rootUri']}/')
      .resolve('lib/src/');
  final sdk = File.fromUri(src.resolve('command_buffer.dart')).readAsStringSync();
  final formats = File.fromUri(src.resolve('formats.dart')).readAsStringSync();

  String words(String text) => text
      .split(',')
      .map((word) => word.trim())
      .where((word) => word.isNotEmpty)
      .join(', ');

  /// What [source] declares of [symbol]: the native signature, and the Dart
  /// parameters behind it.
  ({String native, String dart}) declared(String source, String symbol) {
    final found = RegExp(
      r'@Native<\s*Handle Function\(([^)]*)\)\s*>\('
      '\\s*symbol: \'$symbol\',?\\s*\\)'
      r'\s*external String\? \w+\(([^)]*)\)',
    ).firstMatch(source);
    expect(found, isNotNull, reason: 'no declaration of $symbol');
    return (native: words(found!.group(1)!), dart: words(found.group(2)!));
  }

  for (final symbol in [
    'InternalFlutterGpu_CommandBuffer_CopyBufferToTexture',
    'InternalFlutterGpu_CommandBuffer_CopyTextureToBuffer',
  ]) {
    test('$symbol has the signature the SDK declares', () {
      final theirs = declared(sdk, symbol);
      final mine = declared(ours, symbol);
      expect(mine.native, theirs.native);
      expect(
        mine.dart.replaceAll('gpu.', ''),
        'CommandBuffer commands, ${theirs.dart}',
      );
    });
  }

  test('flutter_gpu still has no name for the extended-range formats — the '
      'day it does, these copies and flutter/flutter#195675 are done', () {
    expect(
      RegExp('xr', caseSensitive: false).hasMatch(formats),
      isFalse,
      reason:
          'Drop flutter_gpu_copies.dart for its own copies, and '
          'FlutterGpuFramePictures.bytesPerTexel for bytesPerBlock.',
    );
  });
}
