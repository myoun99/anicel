import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../helpers/dart_sources.dart';

/// 🚨ONE CONVERSION OF THE CANVAS TO A RECT.
///
/// `PasteboardBounds.canvasRect`, beside the `pasteboardRect` F-85 made the
/// one conversion for the pasteboard. Until the 2026-09-15 audit the canvas
/// rect was typed out from the size in eleven places across seven files —
/// all of them agreeing, which is exactly what a behaviour test cannot tell
/// from one law.
///
/// ⛔SO THIS SCANS SOURCE: a `Rect.fromLTWH(0, 0, …canvasSize.width
/// .toDouble(), …canvasSize.height.toDouble())` anywhere in `lib` has
/// started the next copy.
void main() {
  const home = 'lib/src/models/pasteboard_bounds.dart';
  final typedOut = RegExp(
    r'Rect\.fromLTWH\(\s*0(?:\.0)?,\s*0(?:\.0)?,\s*[\w.]*[cC]anvasSize\.width'
    r'\.toDouble\(\),\s*[\w.]*[cC]anvasSize\.height\.toDouble\(\),?\s*\)',
  );

  /// [file]'s code with every comment cut off and its lines kept — a
  /// comment may quote the form it replaced.
  String codeOf(File file) => file
      .readAsLinesSync()
      .map((line) {
        final comment = line.indexOf('//');
        return comment < 0 ? line : line.substring(0, comment);
      })
      .join('\n');

  test('premise: the canvas rect has its one home, and the scan sees the '
      'typed-out form', () {
    expect(
      File(home).readAsStringSync(),
      contains('ui.Rect get canvasRect =>'),
    );
    expect(
      typedOut.hasMatch(
        'Rect.fromLTWH(\n  0,\n  0,\n  surface.canvasSize.width.toDouble(),\n'
        '  surface.canvasSize.height.toDouble(),\n)',
      ),
      isTrue,
      reason: 'the shape the eleven copies were written in',
    );
  });

  test('nobody types the canvas rect out of its size', () {
    final offenders = <String>[];
    var scanned = 0;
    for (final file in dartFilesUnder('lib')) {
      scanned += 1;
      final code = codeOf(file);
      for (final match in typedOut.allMatches(code)) {
        final line = '\n'.allMatches(code.substring(0, match.start)).length;
        offenders.add('${libPath(file)}:${line + 1}');
      }
    }
    expect(scanned, greaterThan(500), reason: 'the scan found lib');
    expect(offenders, isEmpty, reason: 'ask canvasSize.canvasRect');
  });
}
