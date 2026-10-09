import 'package:flutter_test/flutter_test.dart';

import '../helpers/dart_sources.dart';

/// 🚨A DOCUMENT'S PAGES AND THE RUN THAT TURNS THEM ARE WIRED IN ONE PLACE
/// (`ViewerPagesAndRun`).
///
/// F-282 ④ (2026-10-09): the media viewer, the export window's preview and
/// the import window's each built the page cache and its run for
/// themselves, line for line — and the playback law's next round changes a
/// line of that pair (the cache asking the run how far a page is). A
/// surface that builds its own again is that copy coming back, and a
/// behaviour test cannot see it: two copies that agree today pass.
void main() {
  /// Where in [dir] a page cache or a run is BUILT, as 「file  call」 — the
  /// classes' own constructors left out.
  List<String> buildersUnder(String dir) => [
    for (final file in dartFilesUnder(dir))
      for (final call in const ['PageRasters(', 'MediaRun('])
        if (_builds(file.readAsStringSync(), call))
          '${file.path.replaceAll(r'\', '/')}  $call',
  ];

  test('⛔premise: the scan finds the one wiring', () {
    expect(
      buildersUnder('lib'),
      containsAll(<String>[
        'lib/src/ui/media/viewer_pages_and_run.dart  PageRasters(',
        'lib/src/ui/media/viewer_pages_and_run.dart  MediaRun(',
      ]),
    );
  });

  test('no surface builds a page cache or a run of its own', () {
    expect(
      [
        for (final builder in buildersUnder('lib'))
          if (!builder.startsWith('lib/src/ui/media/viewer_pages_and_run.dart'))
            builder,
      ],
      isEmpty,
      reason: 'take a ViewerPagesAndRun — see its comment for what stays the '
          'surface\'s own',
    );
  });
}

/// Whether [text] calls [call] as a constructor — not the class declaring
/// its own (`PageRasters({`), not a name that merely ends the same way.
bool _builds(String text, String call) => RegExp(
  '(?<![A-Za-z0-9_])${RegExp.escape(call)}(?!\\{)',
).hasMatch(text);
