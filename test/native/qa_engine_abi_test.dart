import 'dart:ffi';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/native/qa_audio_device.dart';
import 'package:anicel/src/native/qa_audio_native.dart';
import 'package:anicel/src/native/qa_engine_abi.dart';

import '../helpers/native_engine_path.dart';

/// Guards for the ONE ABI number and the ONE loader.
///
/// The C exports a single `qa_engine_abi_version()`, so every extra copy
/// of "which version" or "which file" in Dart is a copy of one fact — and
/// this codebase has already paid for that twice: a bump that missed the
/// audio constant wiped out thirteen parity suites (R26), and the loader
/// that actually reaches a speaker shipped with no gate at all while its
/// less important sibling had two.
///
/// These tests are deliberately SOURCE tests. The drift they exist to
/// catch happens on machines with no engine binary — the very runs where
/// a behavioural test can only skip.
void main() {
  final root = Directory.current.path;
  String at(List<String> parts) => [root, ...parts].join(Platform.pathSeparator);

  String readSource(List<String> parts) {
    final file = File(at(parts));
    expect(
      file.existsSync(),
      isTrue,
      reason: '${parts.join('/')} moved — update this guard with it',
    );
    return file.readAsStringSync();
  }

  test('the C and Dart agree on the ABI version', () {
    final c = readSource(['packages', 'qa_native', 'src', 'qa_engine.c']);
    final match = RegExp(
      r'qa_engine_abi_version\(void\)\s*\{\s*return\s+(\d+)\s*;',
    ).firstMatch(c);
    expect(
      match,
      isNotNull,
      reason: 'qa_engine_abi_version() is no longer a plain literal return; '
          'this guard reads it statically so it works with no binary built',
    );
    expect(
      int.parse(match!.group(1)!),
      kQaEngineAbiVersion,
      reason: 'the C bumped without kQaEngineAbiVersion (or the reverse). '
          'Every loader would stand down and the app would silently run on '
          'its Dart fallbacks — which is exactly how the R26 audio parity '
          'wipeout looked.',
    );
  });

  group('loader roster', () {
    final nativeDir = Directory(at(['lib', 'src', 'native']));
    final loaders = nativeDir
        .listSync()
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'))
        .toList();

    test('every engine loader opens through openQaEngineLibrary', () {
      expect(loaders, isNotEmpty);
      final offenders = <String>[];
      for (final file in loaders) {
        final name = file.uri.pathSegments.last;
        // qa_engine_abi.dart IS the loader; qa_tablet_bridge.dart opens a
        // DIFFERENT binary (the Wintab sidecar, its own qat_abi_version).
        if (name == 'qa_engine_abi.dart' || name == 'qa_tablet_bridge.dart') {
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
        reason: 'these open the engine themselves, so they carry their own '
            'copy of the candidate list AND skip the version gate. Call '
            'openQaEngineLibrary() instead — it resolves the path, opens, '
            'and gates in one step.',
      );
    });

    test('no loader keeps its own path override', () {
      final offenders = <String>[];
      for (final file in loaders) {
        final name = file.uri.pathSegments.last;
        // qa_tablet_bridge.dart overrides a DIFFERENT binary's path
        // (QA_TABLET_PATH), so its own hook is the correct shape.
        if (name == 'qa_tablet_bridge.dart') {
          continue;
        }
        if (file.readAsStringSync().contains('debugLibraryPathOverride')) {
          offenders.add(name);
        }
      }
      expect(
        offenders,
        isEmpty,
        reason: 'where the engine binary is, is ONE fact about the process. '
            'Six statics meant a caller could set some and miss the rest — '
            'the conform worker set two of six. Use '
            'debugQaEngineLibraryPathOverride.',
      );
    });

    test('both audio loaders check the struct layout', () {
      // Scalars and byte pointers cannot be misread by a layout change, so
      // only the two files that pass STRUCTS need this. If a third one
      // starts sharing QaAudioClipStruct, add it here and to the check.
      for (final name in ['qa_audio_native.dart', 'qa_audio_device.dart']) {
        final source = readSource(['lib', 'src', 'native', name]);
        expect(
          source.contains('qaAudioStructLayoutsMatch'),
          isTrue,
          reason: '$name hands the audio structs to the C. Unchecked, a '
              'layout change makes every field read garbage — and garbage '
              'in an audio buffer is a loud noise in someone\'s headphones.',
        );
      }
    });
  });

  group('with a built engine', () {
    final libraryPath = nativeEngineLibraryPathOrNull();
    final skip = libraryPath != null ? false : nativeEngineMissingSkipReason;

    tearDown(() {
      QaAudioDevice.debugResetForTests();
      debugQaEngineLibraryPathOverride = null;
    });

    test('the binary passes both gates', () {
      final library = DynamicLibrary.open(libraryPath!);
      expect(
        qaEngineAbiMatches(library),
        isTrue,
        reason: 'the built binary reports a different ABI than this source '
            'expects — rebuild build/native_standalone',
      );
      expect(
        qaAudioStructLayoutsMatch(library),
        isTrue,
        reason: 'the audio structs disagree byte-for-byte',
      );
    }, skip: skip);

    test('the gate does not stand the real device down', () {
      // The point of the change: QaAudioDevice went from ungated to gated.
      // A gate that is subtly wrong looks exactly like "no binary" —
      // playback quietly drops to the platform player and nothing fails.
      QaAudioDevice.debugResetForTests();
      debugQaEngineLibraryPathOverride = libraryPath;
      expect(QaAudioDevice.instance, isNotNull);
    }, skip: skip);
  });
}
