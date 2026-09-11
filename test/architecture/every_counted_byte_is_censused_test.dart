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
        final excuse = _notCensused[entry];
        if (excuse != null) {
          // 🚨A HOLDING REPORTED THROUGH SOMETHING ELSE STILL HAS TO BE
          // REPORTED. `via:<symbol>` says the census reads that instead —
          // the push paths, where a widget State writes its bytes onto
          // something the session owns. Checked, not taken on trust.
          if (excuse.startsWith('via:')) {
            final forwarder = excuse.substring(4).split(' ').first;
            if (!census.contains('.$forwarder')) {
              missing.add('$entry (claims via:$forwarder — census has no '
                  'such reader)');
            }
          }
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

  // 🆕2026-09-11 — THE BLIND SPOT OF THE TEST ABOVE. It finds holders by
  // their byte COUNTER, and a holder that never learned its own size has
  // no counter to find. The storyboard's thumbnails were exactly that:
  // every panel ever looked at, at 640px, resident until the workspace
  // closed and named by nothing. So this looks for the other half of the
  // shape — a field that keeps images — and demands a counter or a reason.
  test('every field that keeps images is counted, or says why not', () {
    final missing = <String>[];
    final live = <String>{};
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) {
        continue;
      }
      final path = entity.path.replaceAll(r'\', '/');
      final relative = path.substring(path.indexOf('lib/'));
      if (relative.startsWith('lib/dev/')) {
        continue;
      }
      final source = entity.readAsStringSync();
      for (final match in _imageHolder.allMatches(source)) {
        final entry = '$relative → ${match.group(1)}';
        live.add(entry);
        final answer = _imageHolders[entry];
        if (answer == null) {
          missing.add(entry);
        } else if (answer.startsWith('counted:')) {
          // Counted means a counter THIS file declares — which the test
          // above then holds to the census.
          final getter = answer.substring('counted:'.length);
          if (!RegExp(r'\bint get ' + getter + r'\b').hasMatch(source)) {
            missing.add(
              '$entry (claims counted:$getter — the file has no such '
              'counter)',
            );
          }
        }
      }
    }
    expect(
      missing,
      isEmpty,
      reason:
          'a field that keeps ui.Images is counted by the census '
          '(counted:<its byte getter>) or ledgered with a reason',
    );
    expect(
      _imageHolders.keys.where((entry) => !live.contains(entry)),
      isEmpty,
      reason: 'the ledger names image holders that no longer exist',
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

  // — On DISK, not in RAM. The census is a RAM readout.
  'lib/src/services/brush_frame_store.dart → coldBakedBytes':
      'bytes on DISK: cooling writes a cel to the 이사대기 room of the run '
      '(ScratchCelFiles) and keeps only a file ref in memory — the census '
      'counts what is resident (2026-09-11: it used to add these as RAM)',

  // — Real holdings that reach the census through something else. The
  // `via:` prefix names the reader, and the test checks it exists.
  'lib/src/ui/canvas/display_buffer_cache.dart → heldBytes':
      'via:canvasBufferBytes — the census PULLS from holders the session '
      'owns and this lives in a widget State, so the view pushes it onto '
      'RenderCaches, the way the media viewers already do',
  'lib/src/native/native_upload_cache.dart → residentBytes':
      'via:nativeUploadBytes — the engine keeps two of these (stamp bytes, '
      'mask alphas) and sums them; ALSO ledgered because the bare name is '
      'shared with BrushTipStampCache, so a name match would pass this '
      'entry for the wrong reason',
  'lib/src/ui/storyboard_cut_thumbnail_store.dart → thumbnailBytes':
      'via:storyboardThumbnailBytes — the store lives in the workspace '
      'State the session does not own, so the workspace pushes it onto '
      'RenderCaches, the way the canvas buffer and the viewers are',
  'lib/src/services/cut_piece_slot.dart → pieceBytes':
      'via:cutPieceBytes — the slot lives in the workspace State the '
      'session does not own, so the workspace pushes it onto RenderCaches, '
      'the way the storyboard thumbnails are',
  'lib/src/ui/canvas/static_composite_bake.dart → heldBytes':
      'via:canvasBufferBytes — the view that owns the bake reports it '
      'together with its display buffer: both are the view holding a '
      'raster of itself',
};

/// A class-level field that KEEPS `ui.Image`s — a map, list or set of them,
/// or an `Expando` hanging them on other objects (the tile cache does:
/// found by widening this the day it was written, 2026-09-11). Record keys
/// are allowed — `Map<(A, B), ui.Image>` is still a holder.
/// Crude on purpose, like [_counter]: a holder that hides from this also
/// hides from the reader looking for one.
final _imageHolder = RegExp(
  '^  (?:static )?(?:late )?(?:final )?'
  '(?:LinkedHashMap|Map|List|Set|Expando)<'
  r'[^;=]*\bui\.Image\??>+\s+(\w+)\s*[=;]',
  multiLine: true,
);

/// Every field that keeps images, and how its bytes are answered for:
/// `counted:<getter>` names the byte counter the same file declares (the
/// census test holds that counter to the census); anything else is why it
/// is not a holding the readout should carry.
const _imageHolders = <String, String>{
  'lib/src/ui/storyboard_cut_thumbnail_store.dart → _images':
      'counted:thumbnailBytes',
  'lib/src/ui/storyboard_cut_blocks_painter.dart → thumbnails':
      'a cut block borrows one picture per cell from the storyboard '
      'thumbnail store, which owns and counts them (thumbnailBytes); the '
      'block only carries them into a paint',
  'lib/src/ui/canvas/bitmap_tile_image_cache.dart → _images':
      'counted:liveImageBytes',
  'lib/src/ui/canvas/bitmap_tile_image_cache.dart → _provisional':
      'counted:liveImageBytes',
  'lib/src/ui/canvas/static_composite_bake.dart → _rasters':
      'counted:heldBytes',
  'lib/src/ui/envelope/envelope_image_cache.dart → _images':
      'a handful of decoded logos and stamps, one per role, decoded once '
      'for the life of the workspace; its own doc says it needs an eviction '
      'the day it holds cels',
  'lib/src/ui/export/export_preview_engine.dart → _cache':
      'the export window preview: an LRU of at most `capacity` frames, owned '
      'by the window State and gone when the window closes',
  'lib/src/ui/import/import_preview.dart → _frames':
      'the import window preview frames, freed when the window closes or '
      'the pick changes',
  'lib/src/ui/playback/canvas_track_stack_view.dart → _heldFrames':
      'clones of the composites on screen, one per covered cut; each is '
      'pinned in the composite cache (`_heldPins`), which the census reads '
      'as playbackFrames',
  'lib/src/ui/playback/canvas_track_stack_view.dart → _heldSources':
      'identities only: the cache images the clones came from, possibly '
      'already disposed; nothing is held through them',
  'lib/src/ui/canvas/active_stroke_overlay.dart → _tileImages':
      'the tiles of the stroke in progress, each freed as it settles into '
      'the surface',
  'lib/src/ui/canvas/active_stroke_overlay.dart → tileImages':
      'an unmodifiable VIEW of _tileImages: the same holding, not a second',
  'lib/src/ui/canvas/deferred_image_disposal.dart → _buckets':
      'images already let go, kept only for the frames the raster thread '
      'may still read; a disposal queue, not a holding',
};
