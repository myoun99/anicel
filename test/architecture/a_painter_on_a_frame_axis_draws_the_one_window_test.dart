import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../helpers/dart_sources.dart';
import '../helpers/project_scratch_folder.dart';

/// 🚨ONE WINDOW FOR EVERY PAINTER ON A FRAME AXIS (2026-11-07, card
/// a-live-dock-frame-costs-a-whole-draw).
///
/// What a painter on a frame axis draws is the bucket's window clipped to
/// the axis's frames — `visibleFrameWindowFor`, or `frameWindowAtBucket` for
/// a bucket of its own (`lib/src/ui/timeline/timeline_frame_window.dart`).
/// The conte's cut blocks asked for the bucket's window unclipped and spelled
/// the no-bucket case as frames 0 … 2³⁰ themselves: one question, two
/// answers, the second found only by reading all three panels.
///
/// ⛔A behaviour test cannot hold this: a copy draws the same blocks until
/// the day the two drift. What gives one away is the unclipped window it
/// has to start from — `timelineFrameWindowFor` — so that is scanned for.
void main() {
  const home = 'lib/src/ui/timeline/timeline_frame_window.dart';

  /// The files under [root] that ask for the bucket's window unclipped,
  /// comments apart.
  List<String> askersUnder(String root) => [
    for (final file in dartFilesUnder(root))
      if (file.readAsLinesSync().any(
        (line) =>
            !line.trimLeft().startsWith('//') &&
            line.contains('timelineFrameWindowFor('),
      ))
        file.path.replaceAll(r'\', '/'),
  ];

  test('nothing under lib/ asks for the unclipped window but its home', () {
    expect(
      askersUnder('lib'),
      [home],
      reason:
          'a painter draws `visibleFrameWindowFor(bucket: …, '
          'frameStartIndex: …, frameEndIndexExclusive: …)` — the axis\'s '
          'frames, which its geometry holds',
    );
  });

  test('🚨the scan sees a window asked for by hand when there is one', () {
    final planted = Directory.systemTemp.createTempSync('anicel-window');
    deleteAfterSessionEnds(planted);
    File('${planted.path}/by_hand.dart').writeAsStringSync(
      'Object window(int bucket) => timelineFrameWindowFor(\n'
      '  bucket: bucket,\n'
      '  cellExtent: 8,\n'
      '  viewportExtent: 400,\n'
      ');\n',
    );
    File('${planted.path}/said_only.dart').writeAsStringSync(
      '// timelineFrameWindowFor( is what a copy would call\n'
      'void nothing() {}\n',
    );

    expect(askersUnder(planted.path), [
      '${planted.path.replaceAll(r'\', '/')}/by_hand.dart',
    ]);
  });
}
