import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../helpers/dart_sources.dart';
import '../helpers/project_scratch_folder.dart';

/// 🚨★★★A PICTURE BUILT FRESH IS A PLACE A TEXT CAN FALL (R9-rest).
///
/// A cel's texts live in its picture's own value (유저 2026-10-06: 「셀의
/// 그림이랑 정확히 동일. 복사/링크도 같이감」), and every surface DERIVED from
/// one hands them on by construction — `putTiles`, `putMaterializedTiles`,
/// `withRebuiltTiles`, `withTexts`. The one way to lose them is to build a
/// surface FRESH from another's parts: `BitmapSurface(canvasSize: …, tiles:
/// old.tiles)` compiles, draws the same drawing, and has silently deleted
/// every letter on the cel.
///
/// ⛔A behaviour test cannot hold this — it passes for every cel a fixture
/// happens to hold, which is a cel without texts. So the places that build a
/// surface fresh are a LEDGER: each is named here with the reason it may —
/// it starts a picture that has no text yet, or it puts the texts back
/// itself. A new one turns this red and asks its author the question.
void main() {
  /// Every file under `lib/` that builds a surface fresh, how many times,
  /// and why each may. ⚠️The model's own file is not here: its derivations
  /// are what `a_picture_carries_its_texts_test` measures one by one.
  const ledger = <String, ({int count, String why})>{
    'lib/src/services/bitmap_surface_geometry.dart': (
      count: 4,
      why:
          'a resize and a move build their result fresh — each passes '
          '`texts: _textsMoved(…)`; the fourth wraps one plate so it can '
          'take the same pass',
    ),
    'lib/src/services/undo_surface_snapshot.dart': (
      count: 1,
      why:
          'a snapshot is put back together from the tiles it kept in ONE '
          'place (`_pictureOf`) — the drawing\'s as its tiles, and each '
          'text it pinned with the plate tiles kept for it (`texts: [`); '
          'what it parks is that same picture of the tiles it owns',
    ),
    'lib/src/services/persistence/brush_drawing_binary_codec.dart': (
      count: 1,
      why: 'a saved cel is read back — tiles and `texts:` both',
    ),
    'lib/src/services/brush_frame_display_cache_service.dart': (
      count: 2,
      why: 'a blank stand-in for a cel with nothing to show',
    ),
    'lib/src/services/brush_frame_edit_session_store.dart': (
      count: 1,
      why: 'a session that has not been seeded from its cel yet',
    ),
    'lib/src/services/canvas_selection_paint_clip.dart': (
      count: 1,
      why: 'a scratch surface a stroke\'s coverage is laid on and read from',
    ),
    'lib/src/services/commands/swap_layer_reference_command.dart': (
      count: 1,
      why: 'the 「nothing was here」 an undo puts back for a cel that had none',
    ),
    'lib/src/services/commands/unlink_layer_command.dart': (
      count: 1,
      why: 'the empty picture that takes a forked cel away again',
    ),
    'lib/src/services/import/raster_cel_import.dart': (
      count: 3,
      why:
          'a picture imported from an image — it begins here; and the cel '
          'a decoding door\'s tiles begin as (`bakeCelTiles` — a .tvpp\'s, '
          'a .clip\'s)',
    ),
    'lib/src/ui/canvas/canvas_selection_layer.dart': (
      count: 1,
      why: 'a scratch surface the selection\'s outline is stamped on',
    ),
  };

  /// The places that put the texts back themselves, and how many times
  /// each says so.
  const carriers = <String, int>{
    'lib/src/services/bitmap_surface_geometry.dart': 3,
    'lib/src/services/undo_surface_snapshot.dart': 1,
    // Read back from an entry, and written into one.
    'lib/src/services/persistence/brush_drawing_binary_codec.dart': 2,
  };

  const model = 'lib/src/models/bitmap_surface.dart';

  // The constructor called by its own name: not a derivation through the
  // private one (`._`), and not a function whose name ends in the word.
  final fresh = RegExp(r'(?<![A-Za-z0-9_.])BitmapSurface\(');

  /// How many times [source] builds a surface fresh, comments apart.
  int freshIn(String source) {
    var count = 0;
    for (final line in source.split('\n')) {
      if (!line.trimLeft().startsWith('//')) {
        count += fresh.allMatches(line).length;
      }
    }
    return count;
  }

  Map<String, int> freshUnder(String root) => {
    for (final file in dartFilesUnder(root))
      if (freshIn(file.readAsStringSync()) case final count when count > 0)
        file.path.replaceAll(r'\', '/'): count,
  };

  test('every place under lib/ that builds a picture fresh is in the '
      'ledger, as many times as it is written there', () {
    final found = freshUnder('lib')..remove(model);

    expect(
      found,
      {for (final entry in ledger.entries) entry.key: entry.value.count},
      reason:
          'a surface built fresh carries NO texts unless it is handed them. '
          'If the new one is made from another picture\'s tiles, derive it '
          'instead (`putTiles`, `withRebuiltTiles`, `withTexts`) or pass '
          '`texts:`; if it really starts a picture, name it in the ledger '
          'with the reason',
    );
    expect(found.values.fold<int>(0, (sum, count) => sum + count), 16);
  });

  test('the places that rebuild a picture from its parts hand the texts '
      'back', () {
    for (final entry in carriers.entries) {
      expect(
        'texts: _'.allMatches(File(entry.key).readAsStringSync()).length +
            'texts: ['.allMatches(File(entry.key).readAsStringSync()).length,
        entry.value,
        reason:
            '${entry.key} puts a picture back together from its tiles — '
            'every one of those is where its texts come back too',
      );
      expect(ledger.containsKey(entry.key), isTrue, reason: 'fixture');
    }
  });

  test('🚨the scan sees a fresh picture when there is one', () {
    final planted = Directory.systemTemp.createTempSync('anicel-fresh');
    deleteAfterSessionEnds(planted);
    File('${planted.path}/a_verb.dart').writeAsStringSync(
      'BitmapSurface copyOf(BitmapSurface old) {\n'
      '  // BitmapSurface(canvasSize: …) would drop the texts\n'
      '  final derived = old.withTexts(const []);\n'
      '  final private = BitmapSurface._derived();\n'
      '  final named = translateBitmapSurface(old);\n'
      '  return BitmapSurface(canvasSize: old.canvasSize, tiles: old.tiles);\n'
      '}\n',
    );
    File('${planted.path}/clean.dart').writeAsStringSync(
      'BitmapSurface same(BitmapSurface old) => old.putTiles(const []);\n',
    );

    expect(freshUnder(planted.path), {
      '${planted.path.replaceAll(r'\', '/')}/a_verb.dart': 1,
    });
  });
}
