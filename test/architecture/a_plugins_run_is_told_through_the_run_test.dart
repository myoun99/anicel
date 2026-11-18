import 'package:flutter_test/flutter_test.dart';

import '../helpers/dart_sources.dart';

/// 🚨★A CLOSED RUNNER'S RUN TELLS NOBODY (card a-closed-plugin-runners-run-
/// tells-no-one, 관제 2026-11-13) — and every route that shows a plug-in's
/// picture tells how it went through the one place that says so
/// (`FxPluginRun.tell`): a step run or kept, a picture shown again, a
/// reach the plugin failed to say. ⛔A behaviour test proves the routes it
/// knows of; this scan proves no other calls a teller of its own.
void main() {
  const home = 'lib/src/models/fx_plugin_run.dart';
  // A teller asked how a run went: `told(failed: …)`,
  // `told?.call(failed: …)`, `told!(failed: …)`.
  final asked = RegExp(r'\btold[!?]?(\.call)?\(\s*failed:');

  List<String> callers() => [
    for (final file in dartFilesUnder('lib/src'))
      if (file
          .readAsLinesSync()
          .any((line) =>
              !line.trimLeft().startsWith('//') && asked.hasMatch(line)))
        libPath(file),
  ];

  test('a plugin\'s run is told through the run alone', () {
    expect(
      callers(),
      [home],
      reason: 'a route that tells a teller itself tells of a closed '
          'runner\'s run too — tell it through FxPluginRun.tell',
    );
  });
}
