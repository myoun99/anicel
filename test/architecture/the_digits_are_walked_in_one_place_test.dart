import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../helpers/dart_sources.dart';
import '../helpers/project_scratch_folder.dart';

/// 🚨ONE WALK OF THE DIGITS (F-383, 2026-10-17).
///
/// A box that holds whatever number it will say is as wide as the widest of
/// that number written with each digit in turn: the pill's zoom and angle
/// readouts, the colour bar's channels and hex, the battery, the frame
/// ruler and the page turner. Five of them spelled the ten digits out by
/// hand and the page turner was about to be the sixth. They read
/// `everyDigitIn` (`lib/src/ui/text/text_measure.dart`) now.
///
/// ⛔A behaviour test cannot hold this: a seventh walk written by hand
/// measures just as well. What gives one away is what it has to spell — the
/// ten digits in a row, or a digit counted up to nine — so that is what is
/// scanned for.
void main() {
  const walk = 'lib/src/ui/text/text_measure.dart';

  /// The files under [root] that walk the digits themselves, comments
  /// apart.
  List<String> walkersUnder(String root) => [
    for (final file in dartFilesUnder(root))
      if (file.readAsLinesSync().any(
        (line) =>
            !line.trimLeft().startsWith('//') && _walksTheDigits.hasMatch(line),
      ))
        file.path.replaceAll(r'\', '/'),
  ];

  test('nothing under lib/ walks the digits but the one walk', () {
    expect(
      walkersUnder('lib'),
      [walk],
      reason:
          'the widest a number can be set is `measure.widest(everyDigitIn('
          '(digit) => …))`',
    );
  });

  test('🚨the scan sees a walk written by hand when there is one', () {
    final planted = Directory.systemTemp.createTempSync('anicel-digits');
    deleteAfterSessionEnds(planted);
    final root = planted.path.replaceAll(r'\', '/');
    File('$root/spelled.dart').writeAsStringSync(
      "final runs = [for (final d in '0123456789'.split('')) d * 3];\n",
    );
    File('$root/counted.dart').writeAsStringSync(
      "final runs = [for (var digit = 0; digit <= 9; digit += 1) '\$digit'];\n",
    );
    File('$root/said_only.dart').writeAsStringSync(
      "// '0123456789' is what a walk by hand would spell\n"
      'void nothing() {}\n',
    );

    expect(walkersUnder(planted.path)..sort(), [
      '$root/counted.dart',
      '$root/spelled.dart',
    ]);
  });
}

/// The ten digits in a row, or a digit counted up to nine.
final RegExp _walksTheDigits = RegExp(
  r'0123456789|\b(digit|d)\s*(<=\s*9|<\s*10)\b',
);
