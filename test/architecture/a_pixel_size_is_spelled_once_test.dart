import 'package:flutter_test/flutter_test.dart';
import '../helpers/dart_sources.dart';

/// 🚨A pixel size is spelled in ONE place: `pixelSizeLabel` (F-375,
/// 2026-10-17).
///
/// The import window's resolution column made the seventh place to write
/// one, and each of the six before it wrote its own — two `1920 × 1080`,
/// the rest `1920×1080`, three of them inside every language's template.
/// A behaviour test passes two copies that agree, so this reads the source:
/// a `×` between two numbers filled in — interpolations or a template's
/// placeholders — is a size spelled by hand.
void main() {
  /// Files whose `×` between two filled-in numbers is not a size on screen.
  const notASizeOnScreen = {
    'lib/src/models/envelope/cut_envelope_form.dart':
        'toString of a rect, read in a failing test',
    'lib/src/models/transform_pose.dart':
        'an assert naming a pose\'s two scale factors',
    'lib/src/ui/layout/device_grid_audit.dart':
        'the audit\'s report line, in fractional logical pixels',
    'lib/src/ui/widgets/still_raster.dart':
        'a rect in a profile build\'s log',
  };
  final filledTimesFilled = RegExp(r'(\}|\$\w+)\s*×\s*(\$|\{)');

  test('🚨no file but pixel_size_label.dart spells a pixel size', () {
    final spelling = <String>{};
    var scanned = 0;
    for (final file in dartFilesUnder('lib/src')) {
      scanned += 1;
      // Code only: a comment may write a size all it likes.
      final code = file.readAsLinesSync().map((line) {
        final comment = line.indexOf('//');
        return comment < 0 ? line : line.substring(0, comment);
      });
      if (code.any(filledTimesFilled.hasMatch)) {
        spelling.add(libPath(file));
      }
    }
    expect(scanned, greaterThan(500), reason: 'the source scan found lib/src');
    expect(
      spelling,
      contains('lib/src/ui/text/pixel_size_label.dart'),
      reason: 'CONTROL: the one place is found',
    );
    expect(
      spelling.difference({
        'lib/src/ui/text/pixel_size_label.dart',
        ...notASizeOnScreen.keys,
      }),
      isEmpty,
      reason:
          'spell a pixel size with pixelSizeLabel — a template takes it '
          'whole, as {size}',
    );
    expect(
      notASizeOnScreen.keys.toSet().difference(spelling),
      isEmpty,
      reason: 'a file that no longer spells one leaves this list',
    );
  });
}
