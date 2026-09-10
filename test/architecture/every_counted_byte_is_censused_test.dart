import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 🚨★★★**A HOLDER THAT KNOWS ITS OWN SIZE MUST BE IN THE CENSUS.**
///
/// `collectMemoryCensus` answers 유저 2026-08-28's 「이 앱이 쓰는 메모리의
/// 총합 … 어떤항목이 얼만큼 차지하는지도」 by ADDING UP counters the holders
/// already keep. That only works if the list it adds is complete, and
/// nothing made it complete.
///
/// ⛔**AND AN INCOMPLETE CENSUS DOES NOT LOOK INCOMPLETE.** Whatever it
/// misses lands in `untrackedBytes`, which the panel labels as the engine,
/// Skia and the Dart heap — so a cache holding a quarter of a gigabyte
/// reads as somebody else's overhead. The number stays plausible while
/// being wrong, which is the failure that beats a correct instinct in an
/// argument.
///
/// The app has counters in six different words — `hotBakedBytes`,
/// `residentBytes`, `estimatedBytes`, `retainedBytes`, `heldBytes`,
/// `censusBytes` — so「같은 이름이면 눈에 띈다」was never going to hold. This
/// scans the SOURCE for anything that counts bytes and demands that the
/// census either reads it or that this file says why not.
void main() {
  test('every byte counter is read by the census, or says why not', () {
    final census = File('lib/src/ui/diagnostics/memory_census.dart')
        .readAsStringSync();
    final missing = <String>[];

    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) {
        continue;
      }
      final path = entity.path.replaceAll(r'\', '/');
      final relative = path.substring(path.indexOf('lib/'));
      // ⛔`lib/dev/` is the brush lab — a harness, not the app.
      if (relative.startsWith('lib/dev/') ||
          relative == 'lib/src/ui/diagnostics/memory_census.dart') {
        continue;
      }
      for (final match in _counter.allMatches(entity.readAsStringSync())) {
        final name = match.group(1)!;
        final entry = '$relative → $name';
        if (_notCensused[entry] != null) {
          continue;
        }
        // The census reads counters by name. A getter it never names is a
        // holding nobody adds up.
        if (!census.contains('.$name')) {
          missing.add(entry);
        }
      }
    }

    expect(
      missing,
      isEmpty,
      reason:
          'these count bytes and the census does not read them — add the '
          'item to collectMemoryCensus, or put the entry in _notCensused '
          'with the reason:\n${missing.join('\n')}',
    );
  });

  test('the ledger has no stale entries', () {
    // 🚨A ledger that outlives its entry is how an exception becomes
    // permanent: the getter is renamed or deleted, the line stays, and it
    // quietly excuses the NEXT thing that takes the name.
    final live = <String>{};
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) {
        continue;
      }
      final path = entity.path.replaceAll(r'\', '/');
      final relative = path.substring(path.indexOf('lib/'));
      for (final match in _counter.allMatches(entity.readAsStringSync())) {
        live.add('$relative → ${match.group(1)}');
      }
    }
    expect(
      _notCensused.keys.where((entry) => !live.contains(entry)),
      isEmpty,
      reason: 'the ledger names counters that no longer exist',
    );
  });
}

/// `int get <something>Bytes` — the shape every byte counter in this app
/// happens to have. Deliberately crude: a counter that hides from this
/// regex also hides from the reader looking for one.
final _counter = RegExp(r'\bint get (\w*[bB]ytes)\b');

/// Counters the census does NOT read, and why. ⚠️A reason, not a name —
/// an entry whose reason is "not yet" has to say what would close it.
const _notCensused = <String, String>{
  // — Per-OBJECT sizes, not holdings. These answer "how big is this one
  // thing" for the code that owns it; the holding is counted where the
  // things are kept.
  'lib/src/models/bitmap_surface.dart → tileBytes':
      'the size of ONE tile, for the code that allocates them',
  'lib/src/services/audio/conform_pcm_codec.dart → dataBytes':
      'a header field: how long this conform file is on disk',
  'lib/src/services/audio/conform_pcm_codec.dart → totalBytes':
      'the same header, header + data — a file length, not RAM',
  'lib/src/services/cel_pixel_overwrite.dart → estimatedRetainedBytes':
      'one undo payload weighing itself; the stack sums them in '
      'HistoryManager.retainedBytes, which the census reads',
  'lib/src/services/canvas_selection_region.dart → estimatedRetainedBytes':
      'the same — one command payload, summed by the undo stack',
  'lib/src/services/undo_surface_snapshot.dart → residentBytes':
      'the same — one snapshot, summed by the undo stack',
  'lib/src/ui/widgets/static_raster.dart → rasterBytes':
      'one baked panel weighing itself; StaticRaster.censusBytes sums '
      'every live bake and THAT is what the census reads',

  // — Budgets, not holdings. A ceiling is not memory in use.
  'lib/src/ui/playback/playback_cache_budget.dart → maxBytes':
      'a CEILING. What is actually held is counted by the two playback '
      'caches the census already reads',

  // — Real holdings the census cannot reach yet. ⚠️Each says what closes it.
  'lib/src/ui/canvas/display_buffer_cache.dart → heldBytes':
      'REAL and uncounted: one canvas-resolution image per open canvas '
      'view (33MB at 4K). The census PULLS from holders the session owns '
      'and this one lives in a widget State, so it needs the pushed path '
      'RenderCaches.viewerRasterBytesByViewer already uses — next round',
  'lib/src/native/native_upload_cache.dart → residentBytes':
      'REAL and uncounted: the engine keeps two of these (stamp bytes, '
      'mask alphas) inside QaNativeEngine, byte-budgeted but not reported. '
      'Closing it means exposing them off the engine — next round',
};
