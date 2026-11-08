import 'dart:ffi';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../helpers/dart_sources.dart';
import '../helpers/native_engine_path.dart';

/// The engine's grid pass, and the C that rastered the grids — each named
/// as a path, so a lane that changed either runs this file
/// (`affected_tests` picks a test by the paths it writes out).
const _grid = 'packages/gpu_engine/rust/src/kernels/timeline/grid';
const _c = 'packages/qa_native/src';

/// 🚨THE FRAME GRIDS' TILES ARE DRAWN ON THE GPU ENGINE ALONE
/// (grid-on-the-engine ⑥, 관제 2026-11-08 23:12).
///
/// The tile store draws every tile with the engine's grid pass. The C's
/// rasterizer (`qa_grid_raster_tile`) and its Dart reference were the
/// tiles' two rasters before, pinned byte for byte to each other; neither
/// draws a tile now, and a third raster nobody draws with is a law kept
/// in two places. A grid export the C carries again is this red.
void main() {
  test('the engine exports the grid\'s pass', () {
    final rust = filesUnder(_grid)
        .where((file) => file.path.endsWith('.rs'))
        .map((file) => file.readAsStringSync())
        .join('\n');
    expect(rust, contains('extern "C" fn gpu_engine_grid_draw('));
  });

  test('the C exports no grid raster', () {
    final exported = RegExp(r'QA_EXPORT[^;{]*\b(qa_grid_\w+)\s*\(');
    final offenders = <String>[];
    for (final file in Directory(_c).listSync().whereType<File>()) {
      if (!file.path.endsWith('.c') && !file.path.endsWith('.m')) {
        continue;
      }
      for (final match in exported.allMatches(file.readAsStringSync())) {
        offenders.add('${file.uri.pathSegments.last}: ${match.group(1)}');
      }
    }
    expect(offenders, isEmpty);
  });

  final libraryPath = nativeEngineLibraryPathOrNull();
  test('a built C engine answers no grid raster', () {
    final library = DynamicLibrary.open(libraryPath!);
    expect(library.providesSymbol('qa_grid_raster_tile'), isFalse);
  }, skip: libraryPath != null ? false : nativeEngineMissingSkipReason);
}
