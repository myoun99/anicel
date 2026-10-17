import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/shortcuts/editor_action_registry.dart';
import 'package:anicel/src/ui/shortcuts/shortcut_shelf.dart';

import '../../helpers/source_body.dart';

/// 🚨F-37 — EVERY SHORTCUT ACTION HAS A ROW IN EVERY LANGUAGE.
///
/// ⚠️THE COUNT RATCHET CANNOT SEE THIS, and reads it backwards. The registry
/// is `const`, so it cannot hold a translated string — it holds the id and
/// its own ENGLISH wording, and that wording IS the English row
/// (`AppStrings.shortcutLabel` falls back to it rather than to `_enValues`).
/// A scan for hardcoded English therefore counts 42 correct lines as debt,
/// and the one thing that IS debt — an action nobody ever tabled — looks
/// exactly like the 42.
///
/// 🔎Measured 2026-08-31: 39 actions, 35 tabled. The four missing were
/// `frame-walk-left/right/up/down` — **the ones I added myself in #1337**,
/// three days earlier, without noticing there was a table to add them to.
/// Nothing was watching that seam.
///
/// ⛔A COUNT WOULD NOT HAVE HELPED. The right instrument for a contract is
/// the contract: not 「how many are English」 but 「is every id answered」.
///
/// ⚠️AND IT ASKS THE TABLE, NOT THE ANSWER. The first version of this file
/// called `shortcutLabel(id, fallback)` and treated 「the answer equals the
/// fallback」 as absence — which reported French's `Navigation` and
/// `Timeline` missing when both are tabled and simply spell the same in
/// French. A language is allowed to agree with English; what it may not do
/// is stay silent.
void main() {
  // ⚠️A shape tile's name is COMPOSED from its verb's template and its
  // shape's name (`shapeTileLabel`, I-19) — tabling it per tile is the
  // product `CanvasShapeKind` warns about. Those ids answer through the words
  // they are composed of, which the key contract reads in every language
  // (`app_strings_keys_test`), so no table is asked for a row — and a row
  // for one is reported below as a row nothing reads. A blend action's name
  // is composed the same way, from the blend's own (`blendModeActionLabel`,
  // I-31), and so are an add-layer kind's and an add-effect kind's (I-40).
  // ↩️The families were listed here by what they press; a family says it is
  // composed itself now (`EditorActionDefinition.composedName`).
  final composedIds = {
    for (final definition in editorActionDefinitions)
      if (definition.composedName != null) definition.id,
  };
  final registryIds = editorActionDefinitions
      .map((definition) => definition.id)
      .toSet()
      .difference(composedIds);

  test('⛔fixture premise: some names ARE composed', () {
    expect(composedIds, isNotEmpty);
  });
  final registryShelves = {for (final shelf in ShortcutShelf.values) shelf.name};

  final source = File('lib/src/ui/text/app_strings.dart').readAsStringSync();

  /// The keys one language's table declares.
  ///
  /// ⛔Read out of the SOURCE because the maps are private, and read per
  /// table rather than whole-file: a key present in Japanese and absent in
  /// Korean is exactly the bug, and a whole-file scan would call it covered.
  Set<String> keysOf(String tableName, String prefix) {
    final table = sourceBodyOf(source, '$tableName = <String, String>');
    return RegExp("'$prefix\\.([A-Za-z0-9-]+)'")
        .allMatches(table)
        .map((match) => match.group(1)!)
        .toSet();
  }

  // ⛔`en` is the one language this cannot be asked of: its row lives at the
  // call site by contract, so asking would be asking the registry whether it
  // agrees with itself.
  const tables = ['_jaValues', '_koValues', '_frValues', '_zhHansValues'];

  test('⛔fixture premise: there are actions and tables to check', () {
    expect(registryIds, hasLength(greaterThan(20)));
    expect(registryShelves, hasLength(greaterThan(3)));
    for (final table in tables) {
      expect(
        keysOf(table, 'shortcutAction'),
        isNotEmpty,
        reason:
            '$table — the scan reached nothing, so nothing below means '
            'anything',
      );
    }
  });

  for (final table in tables) {
    test('every action is named in $table', () {
      expect(
        registryIds.difference(keysOf(table, 'shortcutAction')),
        isEmpty,
        reason:
            'add `shortcutAction.<id>` rows to $table — a shortcut list that '
            'reads half in English is what F-37 is about',
      );
    });

    test('every SHELF is named in $table, and no shelf that is gone', () {
      final named = keysOf(table, 'shortcutShelf');
      expect(
        registryShelves.difference(named),
        isEmpty,
        reason: 'the headings above the actions',
      );
      expect(named.difference(registryShelves), isEmpty);
    });

    test('⛔and $table names no action the registry has dropped', () {
      // The quieter half: a key nothing reads is the same bug as a key that
      // does not exist, only harder to see — this table has buried one
      // already (`autosaveSidecarFolder`, #1409).
      expect(
        keysOf(table, 'shortcutAction').difference(registryIds),
        isEmpty,
        reason: 'translated four times over and read by nobody',
      );
    });
  }
}
