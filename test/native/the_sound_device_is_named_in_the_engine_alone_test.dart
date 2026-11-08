import 'dart:ffi';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../helpers/native_engine_path.dart';

/// The crate that answers the sound device's names, and the C that did —
/// each named as a path, so a lane that changed either runs this file
/// (`affected_tests` picks a test by the paths it writes out).
const _device = 'packages/gpu_engine/rust/native/audio_device';
const _mixer = 'packages/gpu_engine/rust/native/audio_mix';
const _c = 'packages/qa_native/src';

/// A name of each door the C carried, and of the mixer's.
const _names = [
  'qa_audio_device_open',
  'qa_audio_device_set_schedule',
  'qa_audio_capture_start',
  'qa_audio_buffer_new',
  'qa_audio_clock_now_us',
  'qa_audio_mix',
  'qa_audio_bus_to_float',
  'qa_audio_clip_sizeof',
];

/// 🚨THE SOUND DEVICE AND ITS MIXER ARE NAMED IN THE GPU ENGINE ALONE
/// (connection-round-checklist H, 관제 2026-11-08 07:26 ⓐ).
///
/// The app binds them with `@Native` in the engine's code asset. While the
/// C engine carried the same names, Apple's `DynamicLibrary.process()` —
/// the C linked into the executable, the engine a framework loaded after
/// it — answered with the C's first (as the loaders are documented; not
/// measured on a device, 타임라인/콘티 06:17): which library played a
/// sound was the order the images loaded in. So the binding and the C's
/// going were one landing, and a name the C exports again is this red.
void main() {
  String rustSource(String crate) => Directory('$crate/src')
      .listSync()
      .whereType<File>()
      .where((file) => file.path.endsWith('.rs'))
      .map((file) => file.readAsStringSync())
      .join('\n');

  test('the engine\'s crates export every one of them', () {
    final rust = '${rustSource(_device)}\n${rustSource(_mixer)}';
    for (final name in _names) {
      expect(
        rust.contains('extern "C" fn $name('),
        isTrue,
        reason: '$name is not exported by $_device or $_mixer',
      );
    }
  });

  test('the C exports none of them', () {
    final exported = RegExp(r'QA_EXPORT[^;{]*\b(qa_audio_\w+)\s*\(');
    final offenders = <String>[];
    for (final file in Directory(_c).listSync().whereType<File>()) {
      if (!file.path.endsWith('.c') && !file.path.endsWith('.m')) {
        continue;
      }
      for (final match in exported.allMatches(file.readAsStringSync())) {
        if (_names.contains(match.group(1))) {
          offenders.add('${file.uri.pathSegments.last}: ${match.group(1)}');
        }
      }
    }
    expect(offenders, isEmpty);
  });

  final libraryPath = nativeEngineLibraryPathOrNull();
  test('a built C engine answers none of them', () {
    final library = DynamicLibrary.open(libraryPath!);
    expect([
      for (final name in _names)
        if (library.providesSymbol(name)) name,
    ], isEmpty);
  }, skip: libraryPath != null ? false : nativeEngineMissingSkipReason);
}
