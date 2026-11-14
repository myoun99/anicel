import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/native/qa_audio_device.dart';
import 'package:anicel/src/native/qa_audio_native.dart';

/// Where the Dart loaders live. ⚠️Spelled as ONE literal so the test
/// selection reads it (`libPrefixesReadAsText`): spelled in pieces, the
/// bare lib segment read as the whole tree and every lib change ran it.
const _nativeSource = 'lib/src/native';

/// 🚨A LOADER BINDS IN THE GPU ENGINE'S LIBRARY BY NAME (`@Native`, in the
/// asset `gpu_engine_asset.dart` names) AND OPENS NO LIBRARY OF ITS OWN.
///
/// ↩️Till the C engine went (connection-round-checklist, 2026-11-13) this
/// guarded that engine's ONE loader and its ONE ABI number
/// (`qa_engine_abi.dart`): a loader that opened the binary by hand carried
/// its own copy of the candidate list and skipped the version gate, and
/// this codebase had paid for a copy twice — a bump that missed the audio
/// constant wiped out thirteen parity suites (R26), and the loader that
/// actually reaches a speaker shipped with no gate at all while its less
/// important sibling had two. The asset has no path to copy and no number
/// to miss; what is left to refuse is a loader that opens a library at
/// all.
///
/// ⛔SOURCE tests: a library opened by hand works on the machine that wrote
/// it, so no run there can see it.
void main() {
  final root = Directory.current.path;
  String at(List<String> parts) =>
      [root, ...parts].join(Platform.pathSeparator);

  String readSource(List<String> parts) {
    final file = File(at(parts));
    expect(
      file.existsSync(),
      isTrue,
      reason: '${parts.join('/')} moved — update this guard with it',
    );
    return file.readAsStringSync();
  }

  group('loader roster', () {
    final nativeDir = Directory(at(_nativeSource.split('/')));
    final loaders = nativeDir
        .listSync()
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'))
        .toList();

    test('no loader opens a library by hand', () {
      expect(loaders, isNotEmpty);
      final offenders = <String>[];
      for (final file in loaders) {
        final name = file.uri.pathSegments.last;
        // windows_screen_reader.dart opens user32, which every Windows has —
        // no candidate list to copy, no version to gate (I-57-Q3) —
        // device_battery.dart kernel32, for the same reason (I-103-Q1),
        // windows_key_state.dart user32 again, for the held keys (I-61), and
        // device_description.dart the OS's own (advapi32, libc, the process
        // for sysctl), for what the feedback forms are told (I-139).
        if (name == 'windows_screen_reader.dart' ||
            name == 'device_battery.dart' ||
            name == 'windows_key_state.dart' ||
            name == 'device_description.dart') {
          continue;
        }
        final source = file.readAsStringSync();
        if (source.contains('DynamicLibrary.open') ||
            source.contains('DynamicLibrary.process')) {
          offenders.add(name);
        }
      }
      expect(
        offenders,
        isEmpty,
        reason: 'these open a library themselves, so each carries its own '
            'answer to where the engine is. Bind by `@Native` under '
            '`@DefaultAsset(gpuEngineAsset)` instead — the asset is the one '
            'place the engine\'s library is found.',
      );
    });

    test('both audio loaders check the struct layout', () {
      // Scalars and byte pointers cannot be misread by a layout change, so
      // only the two files that pass STRUCTS need this. If a third one
      // starts sharing QaAudioClipStruct, add it here and to the check.
      for (final name in ['qa_audio_native.dart', 'qa_audio_device.dart']) {
        final source = readSource([..._nativeSource.split('/'), name]);
        expect(
          source.contains('qaAudioStructLayoutsMatch'),
          isTrue,
          reason: '$name hands the audio structs to the engine. Unchecked, a '
              'layout change makes every field read garbage — and garbage '
              'in an audio buffer is a loud noise in someone\'s headphones.',
        );
      }
    });
  });

  group('the audio structs, which the GPU engine reads', () {
    tearDown(QaAudioDevice.debugResetForTests);

    test('are laid out as Dart lays them', () {
      expect(
        qaAudioStructLayoutsMatch(),
        isTrue,
        reason: 'the audio structs disagree byte-for-byte',
      );
    });

    test('and the gate does not stand the real device down', () {
      // The point of the change: QaAudioDevice went from ungated to gated.
      // A gate that is subtly wrong looks exactly like "no binary" —
      // playback quietly plays without sound and nothing fails.
      QaAudioDevice.debugResetForTests();
      expect(QaAudioDevice.instance, isNotNull);
    });
  });
}
