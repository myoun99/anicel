import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import '../helpers/dart_sources.dart';

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

    for (final entity in dartFilesUnder('lib')) {
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
    for (final entity in dartFilesUnder('lib')) {
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
  //
  // 🆕2026-10-17 (card census-misses-bake-once-images) — AND A FIELD WHOSE
  // TYPE NAMES NO `ui.Image`. The baked words were a `BakeOnceLru`'s, the
  // brush list's strokes one's too as `BrushStrokeSample`s, the timeline's
  // tiles an `Lru`'s as `_TileEntry`s, an export run's pictures a map
  // declared `var` — up to 512, 512 and 768 pictures the readout gave to
  // the engine. So a picture is also what wraps one ([_pictureTypesBy]),
  // and a field is one however it is declared ([_imageKeepersIn]).
  test('every field that keeps images is counted, or says why not', () {
    final sources = <String, String>{};
    for (final entity in dartFilesUnder('lib')) {
      final path = entity.path.replaceAll(r'\', '/');
      final relative = path.substring(path.indexOf('lib/'));
      if (relative.startsWith('lib/dev/')) {
        continue;
      }
      sources[relative] = entity.readAsStringSync().replaceAll('\r\n', '\n');
    }
    final pictureTypes = _pictureTypesBy(sources);
    final missing = <String>[];
    final live = <String>{};
    for (final MapEntry(key: relative, value: source) in sources.entries) {
      for (final name in _imageKeepersIn(source, pictureTypes[relative]!)) {
        final entry = '$relative → $name';
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
  'lib/src/ui/widgets/still_raster.dart → rasterBytes':
      'one dock region\'s still image weighing itself; '
      'StillRaster.censusBytes sums every live region and THAT is what the '
      'census reads',

  // — Budgets, not holdings. A ceiling is not memory in use.
  'lib/src/ui/playback/playback_cache_budget.dart → maxBytes':
      'a CEILING. What is actually held is counted by the playback cache — '
      'the layer images — which the census already reads',
  'lib/src/ui/session/playback_cache_budget.dart → lendableBytes':
      'a CEILING — how much an export run may hold on playback\'s line; '
      'what it holds is lentBytes, which the census reads',

  // — A PART of a holding the census reads whole.
  'lib/src/ui/canvas/tile_pages.dart → bytes':
      'one TilePages\' own pages — a part of liveBytes, which the census '
      'reads whole through liveImageBytes (`tileImages`); a test weighs its '
      'own pages by it, where another test\'s tiles may die meanwhile',
  'lib/src/ui/canvas/subtree_image_composite.dart → heldBelowBytes':
      'the rasters held below a pen — a part of heldBytes, which the '
      'census reads (`framePictures`); the line weighs the nodes over the '
      'pen by it',

  // — On DISK, not in RAM. The census is a RAM readout.
  'lib/src/services/brush_frame_store.dart → coldBakedBytes':
      'bytes on DISK: cooling writes a cel to the 이사대기 room of the run '
      '(ScratchCelFiles) and keeps only a file ref in memory — the census '
      'counts what is resident (2026-09-11: it used to add these as RAM)',

  // — Real holdings that reach the census through something else. The
  // `via:` prefix names the reader, and the test checks it exists.
  'lib/src/native/native_upload_cache.dart → residentBytes':
      'via:nativeUploadBytes — the engine keeps two of these (stamp bytes, '
      'mask alphas) and sums them; ALSO ledgered because the bare name is '
      'shared with BrushTipStampCache, so a name match would pass this '
      'entry for the wrong reason',
  'lib/src/ui/storyboard_cut_thumbnail_store.dart → thumbnailBytes':
      'via:storyboardThumbnailBytes — the store lives in the workspace '
      'State the session does not own, so the workspace pushes it onto '
      'RenderCaches, the way the viewers are',
  'lib/src/ui/canvas/tile_pages.dart → liveBytes':
      'via:liveImageBytes — the pages tile pictures lie in are tile '
      'pictures: the cache\'s total adds them whole (`tileImages`), so the '
      'budget that lets tile pictures go weighs them too',
  'lib/src/ui/sheet/sheet_image_cache.dart → decodedBytes':
      'via:sheetImageBytes — the sheets\' image cache lives in the '
      'workspace too, and pushes onto RenderCaches as the thumbnails do',
  'lib/src/services/cut_piece_slot.dart → pieceBytes':
      'via:allPieceBytes — the slot is the APP\'s, one for every open '
      'project (I-7), so the census reads the class-level total once '
      'rather than a number pushed onto one tab\'s session',
  'lib/src/services/last_stroke_slot.dart → strokeBytes':
      'via:allStrokeBytes — the app\'s one slot, read once, for the cut '
      'piece\'s reason',
  'lib/src/native/qa_blur_kernel.dart → debugScratchBytes':
      'via:liveBytes — the blur\'s scratch is a NativeScratch, which '
      'NativeScratch.liveBytes already sums with every other (the census\'s '
      'engineScratch row); this one is the test\'s pin that a stroke\'s end '
      'lets it go',
};

/// What a field KEEPS `ui.Image`s in — a map, list, set or queue of them,
/// or an `Expando` hanging them on other objects (the tile cache does:
/// found by widening this the day it was written, 2026-09-11), or the core
/// `Lru` (2026-10-16: the sheets' images and the storyboard's panels moved
/// onto it, card every-bounded-cache-is-one-lru — and on again 10-30, to
/// the viewer's holding; the held subtree rasters keep one) and
/// `BakeOnceLru` (the
/// baked words', the brush list's strokes — 2026-10-17). Record keys
/// are allowed — `Map<(A, B), ui.Image>` is still a holder.
/// Crude on purpose, like [_counter]: a holder that hides from this also
/// hides from the reader looking for one.
const _keepers =
    '(?:LinkedHash|Hash|SplayTree)?(?:Map|Set)|List|(?:List)?Queue|Expando'
    '|(?:BakeOnce)?Lru';

/// The fields of [source] that keep pictures — [pictures] being what a
/// type names to be one ([_pictureTypesBy]) — typed
/// (`final Map<K, ui.Image> _images = …`) or given a typed literal
/// (`var _thisFrame = <Object, ui.Image>{}`), where a field stands: the top
/// level, and the bodies of the classes and mixins ([_typesIn]). A local of
/// a top-level function stands two spaces in as a member does, and is in
/// neither. A picture type of its own type arguments is one too
/// (`Map<K, _Entry<K>>` — the frame picture store's, 2026-10-26: made
/// generic, its entries fell out of the census).
Iterable<String> _imageKeepersIn(String source, String pictures) sync* {
  final typed =
      '(?:$_keepers)<'
      r'[^;=]*\b(?:'
      '$pictures'
      r')(?:<[^;=]*?>)?\??>+\s+(\w+)\s*[=;]';
  final literal =
      r'(\w+)\s*=\s*(?:'
      '$_keepers'
      r')?<[^;]*\b(?:'
      '$pictures'
      r')(?:<[^;]*?>)?\??>\s*[{\[(]';
  final declared = '(?:late )?(?:(?:final )?$typed|(?:final |var )$literal)';
  final member = RegExp('^  (?:static )?$declared', multiLine: true);
  final topLevel = RegExp('^$declared', multiLine: true);
  for (final (name: _, :body) in _typesIn(source)) {
    for (final field in member.allMatches(body)) {
      yield field.group(1) ?? field.group(2)!;
    }
  }
  for (final field in topLevel.allMatches(source)) {
    yield field.group(1) ?? field.group(2)!;
  }
}

/// For each file, what a field's type names when it keeps a picture:
/// `ui.Image`, and every type whose values wrap one — a class or mixin with
/// a field of it, or a record typedef with one, and so on up the chain
/// (`BrushStrokeSample`, the timeline's `_TileEntry`, the move's `_Float`
/// around its warp preview). A public name is the app's; a private one is
/// its library's, its parts' included.
Map<String, String> _pictureTypesBy(Map<String, String> sources) {
  String libraryOf(String relative) =>
      switch (_partOf.firstMatch(sources[relative]!)) {
        null => relative,
        final partOf => Uri.parse(relative).resolve(partOf.group(1)!).path,
      };
  final public = <String>{};
  final private = <String, Set<String>>{};
  Set<String> namedIn(String relative) => {
    ...public,
    ...?private[libraryOf(relative)],
  };
  String picturesIn(String relative) => [
    r'ui\.Image',
    for (final name in namedIn(relative)) RegExp.escape(name),
  ].join('|');
  var grew = true;
  while (grew) {
    grew = false;
    for (final MapEntry(key: relative, value: source) in sources.entries) {
      final named = namedIn(relative);
      for (final name in _wrappersIn(source, picturesIn(relative))) {
        if (named.contains(name)) {
          continue;
        }
        final names = name.startsWith('_')
            ? (private[libraryOf(relative)] ??= <String>{})
            : public;
        names.add(name);
        grew = true;
      }
    }
  }
  return {for (final relative in sources.keys) relative: picturesIn(relative)};
}

/// The types of [source] whose values wrap one of [pictures]: a class or
/// mixin with a field of it — or of the pieces of one (2026-10-21: a
/// picture past the side is held in pieces, `List<ImagePiece>`, and the
/// stored picture and the compose, each one image the day before, fell out
/// of the chain with every holder above them) — or an abstract getter of
/// one, whose kinds each keep it their own way (2026-10-29: a tile's slot
/// came to read its page's picture on the getter, and the tile cache fell
/// out with `TilePicture`) — a record typedef with one.
/// ⛔Only pieces: a list of any picture is a holding, and a holder of
/// holdings no picture of its own (widened so, the home page's sessions
/// came up).
Iterable<String> _wrappersIn(String source, String pictures) sync* {
  final field = RegExp(
    '^  (?:late )?(?:final )?(?:$pictures|List<ImagePiece>)'
    r'\??\s+\w+\s*[;=]',
    multiLine: true,
  );
  final abstractGetter = RegExp(
    '^  (?:$pictures)'
    r'\??\s+get\s+\w+\s*;',
    multiLine: true,
  );
  final recordField = RegExp(
    r'(?:^|[(,{])\s*(?:'
    '$pictures'
    r')\??(?:\s+\w+)?\s*(?=[,)}]|$)',
    multiLine: true,
  );
  for (final (:name, :body) in _typesIn(source)) {
    if (field.hasMatch(body) || abstractGetter.hasMatch(body)) {
      yield name;
    }
  }
  for (final record in _recordTypedef.allMatches(source)) {
    final fields = record.group(2)!;
    if (!fields.contains('Function') && recordField.hasMatch(fields)) {
      yield record.group(1)!;
    }
  }
}

/// The classes and mixins of [source], each with its body: from its `{` to
/// the first `}` in the first column after it, which is where a formatted
/// body closes. An empty `{}` has none.
Iterable<({String name, String body})> _typesIn(String source) sync* {
  for (final type in _typeHeader.allMatches(source)) {
    if (source.startsWith('}', type.end)) {
      continue;
    }
    final close = source.indexOf('\n}', type.end);
    yield (
      name: type.group(1)!,
      body: source.substring(type.end, close < 0 ? source.length : close),
    );
  }
}

final _typeHeader = RegExp(
  '^(?:(?:abstract|base|final|interface|sealed) )*'
  r'(?:mixin class|class|mixin) (\w+)[^{;]*\{',
  multiLine: true,
);

/// `typedef Name = (…);` — a record, whose fields a wrapper is looked for
/// in. ⛔Not a function type: a picture it takes is no picture it keeps.
final _recordTypedef = RegExp(
  r'^typedef (\w+)(?:<[^=]*>)?\s*=\s*\(([^;]*)\);',
  multiLine: true,
);

final _partOf = RegExp("^part of '([^']+)';", multiLine: true);

/// Every field that keeps images, and how its bytes are answered for:
/// `counted:<getter>` names the byte counter the same file declares (the
/// census test holds that counter to the census); anything else is why it
/// is not a holding the readout should carry.
const _imageHolders = <String, String>{
  'lib/src/ui/storyboard_cut_blocks_painter.dart → thumbnails':
      'a cut block borrows one picture per cell from the storyboard '
      'thumbnail store, which owns and counts them (thumbnailBytes); the '
      'block only carries them into a paint',
  'lib/src/ui/canvas/subtree_image_composite.dart → _held':
      'counted:heldBytes',
  'lib/src/ui/canvas/bitmap_tile_image_cache.dart → _pictures':
      'counted:liveImageBytes',
  'lib/src/ui/canvas/tile_pages.dart → _open': 'counted:liveBytes',
  'lib/src/ui/sheet/sheet_image_cache.dart → _pictures':
      'one export render\'s media images (SheetImageRun), read for that '
      'render and let go when it ends — the working set of a render, as '
      'the ink rasters and cell pictures composed beside it are',
  'lib/src/ui/canvas/active_stroke_overlay.dart → _tileImages':
      'the tiles of the stroke in progress, each freed as it settles into '
      'the surface',
  'lib/src/ui/canvas/active_stroke_overlay.dart → tileImages':
      'an unmodifiable VIEW of _tileImages: the same holding, not a second',
  'lib/src/ui/canvas/deferred_image_disposal.dart → _buckets':
      'images already let go, kept only for the frames the raster thread '
      'may still read; a disposal queue, not a holding',

  // — 2026-10-17, what the wider shape found (card
  // census-misses-bake-once-images). Three held pictures nothing counted,
  // counted since:
  'lib/src/ui/text/word_bake.dart → _images': 'counted:imageBytes',
  'lib/src/ui/brush/brush_stroke_preview_cache.dart → _store':
      'counted:sampleBytes',
  'lib/src/ui/timeline/timeline_grid_tile_store.dart → _entries':
      'counted:tileImageBytes',
  // … holdings counted all along, by a counter of their own file …
  'lib/src/ui/playback/frame_picture_store.dart → _entries':
      'counted:estimatedBytes',
  'lib/src/ui/widgets/static_raster.dart → census': 'counted:censusBytes',
  // … or pushed to where the census reads them …
  'lib/src/ui/media/shown_rasters.dart → _held':
      'every picture drawn as large as it is shown — a viewer\'s pages, the '
      'storyboard\'s panels, the sheets\' images: every change in what is '
      'held reports its total (_report) to where the census reads it '
      '(viewerRasterBytes, storyboardThumbnailBytes, sheetImageBytes) — '
      '↩️until 10-30 three fields, each its own holding',
  'lib/src/ui/export/held_rows.dart → _rows':
      'an export run\'s row pictures: every change in what they hold is '
      'told to playback\'s line (onHeld, PlaybackCacheBudget.lend), which '
      'the census reads (lentBytes)',
  'lib/src/ui/export/held_rows.dart → _inUse':
      'the held rows ONE picture is made of — of _rows, not a holding '
      'beside them',
  // … and what one draw, one edit or one render holds while it lasts.
  'lib/src/ui/export/held_rows.dart → _passing':
      'the rows composed for one picture alone, let go once it is made '
      '(during) — the working set of a render',
  'lib/src/ui/canvas/subtree_image_composite.dart → _images':
      'what one effect chain\'s picture draws while it is laid (_Laying), '
      'let go once that picture is recorded — the working set of a chain',
  'lib/src/ui/export/held_pictures.dart → _thisFrame':
      'an export run\'s pictures — a cut\'s whole picture, the finished '
      'frame — for the frame being drawn, held one frame more and let go '
      'after (nextFrame), every one when the run ends (dispose): the '
      'working set of a render, as the sheets\' _pictures are',
  'lib/src/ui/export/held_pictures.dart → _frameBefore':
      'the same pictures one frame on: what the frame before was made of',
  'lib/src/ui/export/export_frame_renderer.dart → all':
      'one camera frame\'s track stack, laying pictures the run\'s '
      'HeldPictures holds — a frame described, not a holding',
  'lib/src/ui/canvas/canvas_selection_layer.dart → floats':
      'the open move\'s floats, one a cel it lifted: what each keeps of '
      'pictures is its warp preview — the last resample decoded for the '
      'screen, one at a time (FloatResamplePreview) — while the box is open',
  'lib/src/ui/canvas/selection_float_overlay.dart → floats':
      'a paint\'s floats: each picture is a float\'s warp preview, owned by '
      'the float (canvas_selection_layer.dart → floats)',

  // — 2026-10-21, a picture past the side held in pieces (card
  // a-cel-past-the-device-side-composes-smaller): ONE picture, as many
  // images as the side cuts it into, held and counted where its one image
  // was.
  'lib/src/ui/canvas/tiled_surface_compose.dart → pieces':
      'one compose\'s picture, in pieces past the side (piecesOver): its '
      'holder keeps and counts them as it did the one image',
  'lib/src/ui/playback/frame_picture_store.dart → waiting':
      'a patch\'s texels from its render to the write that takes them, a '
      'batch at a time, let go of once written (_writeWaiting) — a write\'s '
      'round trip, never drawn: ↩️billed with their picture while they were '
      'drawn over it until its levels were in, up to 64 at a time (F-465, '
      '2026-10-26)',
};
