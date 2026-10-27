import 'package:flutter_test/flutter_test.dart';
import '../helpers/dart_sources.dart';
import '../helpers/source_ledger.dart';

/// 🚨AN IMAGE'S SHADER FILLS NO MORE THAN WHAT SHOWS
/// (deep-zoom-blanks-the-canvas, 2026-10-27).
///
/// A rect an `ImageShader` fills cost the GPU by its whole extent on the
/// device and, past 16384 device pixels a side, filled white — the canvas
/// went blank past 670% on a 2340 page. `drawShadedRect`
/// (`display_resample.dart`) cuts such a rect to the clip. A shader drawn
/// any other way may pass the cap at some zoom nobody tried, and the pixel
/// tests only see the routes they drive — so every `ImageShader` in `lib/`
/// is one somebody routed, written down here with how.
void main() {
  final shaders = RegExp(r'\bImageShader\(');

  /// What `lib/` is allowed to hold, and how each is drawn. ⚠️The COUNT is
  /// part of the entry.
  const ledger = <String, ({int count, String how})>{
    'lib/src/ui/canvas/display_resample.dart': (
      count: 1,
      how: 'an image laid on the pixel grid (`drawImageRectOnThePixelGrid`) '
          '— the canvas\'s frame picture and display buffer above 100% — '
          'through `drawShadedRect`.',
    ),
    'lib/src/ui/canvas/paper_background.dart': (
      count: 1,
      how: 'the alpha checker, through `drawShadedRect` '
          '(`paintAlphaCheckerboard`).',
    ),
  };

  test('🚨every ImageShader in lib/ fills only what shows', () {
    final found = <String, int>{};
    for (final file in dartFilesUnder('lib')) {
      final path = file.path.replaceAll(r'\', '/');
      for (final line in file.readAsLinesSync()) {
        final code = line.trim();
        if (code.startsWith('//') || code.startsWith('*')) {
          continue;
        }
        found[path] =
            (found[path] ?? 0) + shaders.allMatches(code).length;
      }
    }
    found.removeWhere((_, count) => count == 0);

    expectCountsMatchLedger(
      found,
      {for (final entry in ledger.entries) entry.key: entry.value.count},
      grew:
          'an image\'s shader filling a rect past 16384 device pixels '
          'fills it white, and under that costs the GPU by the whole '
          'rect: draw it through `drawShadedRect` (or a draw that covers '
          'only the clip, as `drawPaint` does) and add it here WITH how:',
      paidOff:
          'these are in the ledger and not in the tree any more, or not as '
          'many times — take the line out or lower its count:',
    );
  });
}
