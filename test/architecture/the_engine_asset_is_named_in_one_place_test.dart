import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/import_graph.dart';
import '../helpers/dart_sources.dart';

/// THE GPU ENGINE'S CODE ASSET IS NAMED IN ONE APP FILE THAT IMPORTS
/// NOTHING, AND A MODULE TAKES IT FROM THERE — never from package:gpu_engine
/// (관제 2026-11-08 09:05, connection-round-checklist H).
///
/// A module that imported the name from the package read as code that
/// draws through the engine: the display and the pen, which the test config
/// reaches, made a change to the engine's Rust every suite's, and the
/// Windows CI shards would have left 685 more files to Linux
/// (lib/src/native/gpu_engine_asset.dart says it whole). A test that runs
/// the modules cannot see that import come back — they bind the same names
/// either way —, and the selection pin sees it only where the config
/// reaches: the fx host's would come back unseen. The scan reads them all.
void main() {
  const home = 'lib/src/native/gpu_engine_asset.dart';
  final declares = RegExp(r'\bconst\s+gpuEngineAsset\b');

  test('the asset is declared in its own file alone — not in the engine '
      'package — and that file imports nothing', () {
    expect(
      [
        for (final file in [
          ...dartFilesUnder('lib'),
          ...dartFilesUnder('packages/gpu_engine/lib'),
        ])
          if (declares.hasMatch(file.readAsStringSync()))
            file.path.replaceAll(r'\', '/'),
      ],
      [home],
    );
    expect(importsOf(home, File(home).readAsStringSync()), isEmpty);
  });

  test('a file that names the asset takes it from that file, and imports '
      'nothing of package:gpu_engine', () {
    final naming = [
      for (final file in dartFilesUnder('lib'))
        if (libPath(file) != home &&
            file.readAsStringSync().contains('gpuEngineAsset'))
          file,
    ];
    expect(naming, isNotEmpty, reason: 'the scan read no module');
    for (final file in naming) {
      final source = file.readAsStringSync();
      expect(
        importsOf(libPath(file), source),
        contains(home),
        reason: libPath(file),
      );
      expect(
        importsPackage(source, 'gpu_engine'),
        isFalse,
        reason: '${libPath(file)} imports package:gpu_engine — take the '
            'asset from $home and nothing of the engine\'s code',
      );
    }
  });
}
