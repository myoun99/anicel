import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/services/persistence/app_support_path.dart';

/// 🚨★★★**THE MIGRATION'S LIST AND THE CALL SITES CANNOT DRIFT.**
///
/// The settings moved into `<container>/Settings/`, and one const list
/// tells [migrateSettingsIntoTheirRoom] what to look for at the old
/// address. A store that asks for a name missing from that list is
/// harmless if the setting is NEW — nothing is sitting at the old address
/// — and silent if it is old: the user's file stays where it was, the
/// store finds nothing, and the app hands back a factory default.
///
/// ⛔That is the failure this file exists for, and it is invisible to
/// every behaviour test: both halves work perfectly on a machine with no
/// files to migrate, which is every machine in CI.
void main() {
  test('every settings entry a store asks for is in the migration list', () {
    final names = <String>{};
    for (final file in Directory('lib').listSync(recursive: true)) {
      if (file is! File ||
          !file.path.endsWith('.dart') ||
          file.path.endsWith('app_support_path.dart')) {
        continue;
      }
      final source = file.readAsStringSync();
      for (final match in RegExp(
        r"(?:appSettingsFilePath|testRedirectedAppSettingsPath)\(\s*'([^']+)'",
      ).allMatches(source)) {
        names.add(match.group(1)!);
      }
    }
    // If the scan finds nothing the assertions below pass vacuously, which
    // would be the same silent hole wearing a green tick.
    expect(
      names,
      hasLength(greaterThan(10)),
      reason: 'source scan failed — the helper was renamed or the call '
          'sites stopped using a literal',
    );
    expect(
      names.difference(appSettingsEntries.toSet()),
      isEmpty,
      reason: 'asked for by a store but never migrated: the user\'s copy '
          'would stay at the old address and the app would open with a '
          'default over the top of it',
    );
  });

  test('and the list names nothing no store asks for', () {
    // The other direction is cheaper but not free: a stale name means the
    // migration moves a file the app has stopped reading, into a folder
    // where nobody will ever look for it again.
    final names = <String>{};
    for (final file in Directory('lib').listSync(recursive: true)) {
      if (file is! File ||
          !file.path.endsWith('.dart') ||
          file.path.endsWith('app_support_path.dart')) {
        continue;
      }
      for (final match in RegExp(
        r"(?:appSettingsFilePath|testRedirectedAppSettingsPath)\(\s*'([^']+)'",
      ).allMatches(file.readAsStringSync())) {
        names.add(match.group(1)!);
      }
    }
    expect(appSettingsEntries.toSet().difference(names), isEmpty);
  });
}
