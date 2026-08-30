import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/shortcuts/editor_action_registry.dart';

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
  final registryIds = editorActionDefinitions
      .map((definition) => definition.id)
      .toSet();
  final registryCategories = editorActionDefinitions
      .map((definition) => definition.category)
      .toSet();

  final source = File('lib/src/ui/text/app_strings.dart').readAsStringSync();

  /// The keys one language's table declares.
  ///
  /// ⛔Read out of the SOURCE because the maps are private, and read per
  /// table rather than whole-file: a key present in Japanese and absent in
  /// Korean is exactly the bug, and a whole-file scan would call it covered.
  Set<String> keysOf(String tableName, String prefix) {
    final start = source.indexOf('$tableName = <String, String>{');
    expect(start, greaterThan(0), reason: '$tableName not found');
    var depth = 0;
    var i = source.indexOf('{', start);
    final open = i;
    for (; i < source.length; i++) {
      if (source[i] == '{') depth++;
      if (source[i] == '}') {
        depth--;
        if (depth == 0) break;
      }
    }
    return RegExp("'$prefix\\.([A-Za-z0-9-]+)'")
        .allMatches(source.substring(open, i))
        .map((match) => match.group(1)!)
        .toSet();
  }

  // ⛔`en` is the one language this cannot be asked of: its row lives at the
  // call site by contract, so asking would be asking the registry whether it
  // agrees with itself.
  const tables = ['_jaValues', '_koValues', '_frValues', '_zhHansValues'];

  test('⛔fixture premise: there are actions and tables to check', () {
    expect(registryIds, hasLength(greaterThan(20)));
    expect(registryCategories, hasLength(greaterThan(3)));
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

    test('every action CATEGORY is named in $table', () {
      expect(
        registryCategories.difference(keysOf(table, 'shortcutCategory')),
        isEmpty,
        reason: 'the headings above the actions',
      );
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
