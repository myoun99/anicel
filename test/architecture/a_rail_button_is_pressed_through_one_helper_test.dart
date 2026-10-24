import 'package:flutter_test/flutter_test.dart';

import '../helpers/dart_sources.dart';
import '../helpers/source_ledger.dart';

/// 🚨**A TEST FINDS A RAIL GROUP'S BUTTON THROUGH ONE HELPER** —
/// `railGroupButton` (`test/helpers/rail_group_button.dart`), and opens the
/// tool settings through `pressToolSettingsButton`.
///
/// Board open-the-tool-settings-in-one-helper (2026-10-13): thirteen tests
/// worked out the tool settings' group id (left rail, slot 2) and pressed
/// `rail-group-<id>` by hand, and some sixty more spelled that key — the
/// same two lines, past the third copy, so a slot that moved meant a sweep.
///
/// A behaviour test cannot hold this — every copy passes on its own — so the
/// ratchet is a source scan, and it proves it can see what it forbids.
void main() {
  /// ⚠️Exempt from its own scan: the lines it plants are STRINGS holding
  /// the very spellings the scan matches.
  const itself =
      'test/architecture/a_rail_button_is_pressed_through_one_helper_test.dart';
  const helper = 'test/helpers/rail_group_button.dart';

  /// The files that spell the tool settings' slot themselves, and why.
  const slotLedger = <String, String>{
    'test/ui/rail_groups_gap_test.dart':
        'measures the gap between the left rail\'s FIRST two groups — the '
        'second slot is its subject, whatever group ships in it',
  };

  final buttonKey = RegExp(r'''['"]rail-group-(\$|rail-)''');
  final settingsSlot = RegExp(r'railGroupId\(\s*right: false,\s*slot: 2\b');

  List<String> hits(RegExp spelling) => [
    for (final file in dartFilesUnder('test'))
      if (file.path.replaceAll(r'\', '/') case final path
          when path != itself &&
              path != helper &&
              spelling.hasMatch(file.readAsStringSync()))
        path,
  ];

  test('the scans see what they forbid', () {
    expect(buttonKey.hasMatch("byKey(ValueKey('rail-group-\$id'))"), isTrue);
    expect(buttonKey.hasMatch("'rail-group-\${EditorWorkspace.x}'"), isTrue);
    expect(buttonKey.hasMatch("ValueKey('rail-group-rail-L2')"), isTrue);
    expect(buttonKey.hasMatch("'rail-group-body-rail-R3'"), isFalse);
    expect(buttonKey.hasMatch("'rail-group-gap'"), isFalse);
    expect(
      settingsSlot.hasMatch('EditorWorkspace.railGroupId(right: false, '
          'slot: 2)'),
      isTrue,
    );
    expect(
      settingsSlot.hasMatch('railGroupId(\n  right: false,\n  slot: 2,\n)'),
      isTrue,
    );
    expect(settingsSlot.hasMatch('railGroupId(right: true, slot: 2)'), isFalse);
  });

  test('no test spells a rail group button\'s key by hand', () {
    expect(
      hits(buttonKey),
      isEmpty,
      reason: 'find it with `railGroupButton(railId)` — or, for a helper '
          'that presses a key by name, `railGroupButtonKey(railId)`',
    );
  });

  test('no test works out the tool settings\' group, outside the ledger', () {
    expectSetMatchesLedger(
      hits(settingsSlot),
      slotLedger.keys,
      unledgered: 'open them with `pressToolSettingsButton(tester)`; their '
          'id is `toolSettingsGroupId`',
      paidOff: 'these no longer spell the slot — take them off slotLedger',
    );
    expectEveryEntrySaysWhy(slotLedger);
  });
}
