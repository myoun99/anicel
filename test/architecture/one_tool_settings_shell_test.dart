import 'package:flutter_test/flutter_test.dart';
import '../helpers/dart_sources.dart';

/// 🚨THE TOOL SETTINGS SECTIONS WEAR ONE SHELL — and the shell is the only
/// place that spells its name.
///
/// Eight sections had written the same three facts by hand: the key the
/// panel is found by, the inset it is read at, and the style of the line
/// that says which tool is showing. Nothing failed; they had simply drifted
/// — one used a `Padding` where the rest used a list, one wrote its heading
/// in another style — and a ninth tool would have copied whichever
/// neighbour it landed beside. That is the shape 「사본 금지」 names:
/// **the same thing built more than once**, whatever the text looks like.
///
/// ⛔A BEHAVIOUR TEST CANNOT SEE THIS. Two sections that agree today pass
/// every widget test ever written about them; what has to be pinned is that
/// there is one PLACE, which only a source scan can say.
///
/// **When this goes red**: the section that spelled the key by hand should
/// call `ToolSettingsSection` (or `ToolSettingsSection.keyFor` when it is
/// too empty for the shell — see the stamp with no slot). ⛔Do not add it to
/// an exception list; there is deliberately none.
void main() {
  Iterable<({String path, int line, String text})> sourceLines() sync* {
    for (final file in dartFilesUnder('lib/src/ui')) {
      final relative = file.path.replaceAll(r'\', '/');
      final key = relative.substring(relative.indexOf('lib/src/ui'));
      final lines = file.readAsLinesSync();
      for (var index = 0; index < lines.length; index += 1) {
        yield (path: key, line: index + 1, text: lines[index]);
      }
    }
  }

  const shell = 'lib/src/ui/brush/tool_settings_section.dart';

  test('the premise: it read the real tree', () {
    expect(sourceLines().length, greaterThan(20000));
  });

  test('🚨the section key is spelled in ONE place', () {
    final hits = [
      for (final line in sourceLines())
        if (line.text.contains("'tool-settings-")) line,
    ];

    // A scan that matches nothing passes everything.
    expect(
      hits,
      isNotEmpty,
      reason:
          'nobody spells the section key any more — either the shell stopped '
          'minting it (then this scan measures nothing and has to be fixed) '
          'or the key changed name.',
    );
    expect(
      hits.map((line) => line.path).toSet(),
      {shell},
      reason:
          'a tool settings section spells its own key. Call '
          'ToolSettingsSection, or ToolSettingsSection.keyFor for a section '
          'with nothing to show.\n'
          '${hits.map((line) => '${line.path}:${line.line}  ${line.text.trim()}').join('\n')}',
    );
  });
}
