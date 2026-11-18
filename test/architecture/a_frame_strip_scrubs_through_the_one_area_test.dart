import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../helpers/dart_sources.dart';

/// 🚨A FRAME STRIP SCRUBS THROUGH THE ONE AREA.
///
/// The timeline's ruler, the X-sheet's rail and the conte's ruler press,
/// drag and let go through one body (`TimelineFrameScrubArea`, its object
/// `TimelineFrameScrub`). The conte's ruler was the third to assemble that
/// body of its own from the same policy functions, and so it kept a press
/// that panned near its edge after the grids had stopped (board
/// the-conte-ruler-scrubs-through-the-one-area, 2026-11-18).
///
/// The scan: the pieces only a scrub's assembly asks for — whether a press
/// is the strip's to scrub by, and the per-gesture frame dedupe — are asked
/// in the home alone. A behaviour test passes two assemblies that agree
/// today; this does not.
void main() {
  const home = 'lib/src/ui/timeline/timeline_frame_scrub.dart';
  const pieces = ['rulerPressScrubs(', 'FrameScrubDedupe()'];

  List<String> asked(String text) => [
    for (final piece in pieces)
      if (text.contains(piece)) piece,
  ];

  test('premise: the home asks each piece', () {
    expect(asked(File(home).readAsStringSync()), pieces);
  });

  test('no other file assembles a scrub of its own', () {
    final offenders = <String, List<String>>{
      for (final file in dartFilesUnder('lib'))
        if (libPath(file) != home && asked(file.readAsStringSync()).isNotEmpty)
          libPath(file): asked(file.readAsStringSync()),
    };
    expect(
      offenders,
      isEmpty,
      reason:
          'mount TimelineFrameScrubArea with a TimelineFrameScrub of the '
          "strip's own",
    );
  });
}
