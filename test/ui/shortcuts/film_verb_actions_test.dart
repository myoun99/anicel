import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/app_language.dart';
import 'package:anicel/src/ui/shortcuts/editor_action_registry.dart';
import 'package:anicel/src/ui/text/app_strings.dart';

/// The film verbs joined the registry so they can be bound to a key, and
/// so a future custom rail slot has something to point at. Before this
/// they existed only as toolbar icons — the most-pressed buttons in the
/// app with no id to their name.
void main() {
  const filmVerbs = <String>[
    EditorActionIds.frameNewDrawing,
    EditorActionIds.frameBlankExposure,
    EditorActionIds.frameToggleMark,
    EditorActionIds.timelinePushBlocks,
    EditorActionIds.timelinePullBlocks,
  ];

  EditorActionDefinition definitionFor(String id) =>
      editorActionDefinitions.firstWhere((definition) => definition.id == id);

  test('every film verb is registered under Timeline', () {
    for (final id in filmVerbs) {
      final definition = definitionFor(id);
      expect(definition.category, 'Timeline', reason: id);
      expect(definition.label, isNotEmpty, reason: id);
    }
  });

  test('the film verbs ship deliberately unbound', () {
    // Which key belongs on these is a working habit, not something to
    // guess — and the digits are already the comma set's. Registering
    // them unbound is what puts a row in the shortcut dialog to fill in.
    for (final id in filmVerbs) {
      expect(definitionFor(id).defaultActivators, isEmpty, reason: id);
    }
  });

  test('no action id is registered twice', () {
    final ids = editorActionDefinitions.map((d) => d.id).toList();
    expect(ids.toSet().length, ids.length);
  });

  test('every film verb reads in every language', () {
    // The registry is const and holds only English; the other languages
    // are tabled by id. An untabled verb falls back to English silently,
    // which is exactly how two menu ids stayed English for months.
    for (final language in AppLanguage.values) {
      if (language == AppLanguage.en) {
        continue;
      }
      final strings = AppStrings.of(language);
      for (final id in filmVerbs) {
        final english = definitionFor(id).label;
        expect(
          strings.shortcutLabel(id, english),
          isNot(english),
          reason: '$id has no ${language.name} wording',
        );
      }
    }
  });
}
