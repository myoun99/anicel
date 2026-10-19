import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/services/persistence/app_support_path.dart';
import '../helpers/dart_sources.dart';

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
    final names = _askedFor(_anyStore);
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
    expect(
      appSettingsEntries.toSet().difference(_askedFor(_anyStore)),
      isEmpty,
    );
  });

  test(
    'a store that keeps the real file under a test is one no test builds',
    () {
      final real = _askedFor(_realStore);
      expect(
        real,
        hasLength(greaterThan(10)),
        reason: 'source scan failed — the helper was renamed or the call '
            'sites stopped using a literal',
      );
      expect(
        real.difference(_builtOnlyOutsideTests.keys.toSet()),
        isEmpty,
        reason: 'a store resolves the user\'s own settings even under a '
            'test: resolve it through testRedirectedAppSettingsPath, or — if '
            'no test can build it — enter it below with the place that '
            'builds it',
      );
      expect(
        _builtOnlyOutsideTests.keys.toSet().difference(real),
        isEmpty,
        reason: 'an entry no store resolves unredirected any more',
      );
    },
  );
}

/// Every settings entry a store asks for, by either road.
final _anyStore = RegExp(
  r"(?:appSettingsFilePath|testRedirectedAppSettingsPath)\(\s*'([^']+)'",
);

/// The entries a store asks for WITHOUT the test sandbox.
final _realStore = RegExp(r"\bappSettingsFilePath\(\s*'([^']+)'");

/// The names [pattern] finds in the app's source, outside the file that
/// defines the helpers.
Set<String> _askedFor(RegExp pattern) => {
  for (final file in dartFilesUnder('lib'))
    if (!file.path.endsWith('app_support_path.dart'))
      for (final match in pattern.allMatches(file.readAsStringSync()))
        match.group(1)!,
};

/// The stores that resolve the user's OWN settings even under a test, and
/// the place that builds each — safe only because none of those places runs
/// under `flutter test`: HomePage makes them through `_unlessTesting`, so a
/// widget test has no store at all and nothing reads or writes the file.
///
/// 🚨A store a test CAN reach through the app's wiring resolves through
/// `testRedirectedAppSettingsPath` instead. The brush presets and tips did
/// not — the workspace builds both itself — and every widget test that
/// pumped HomePage read the developer's own brush library (board
/// `tests-read-the-real-brush-library`). ⛔An entry here is a claim about the
/// wiring that no test checks: name the place, so the next reader can.
const _builtOnlyOutsideTests = <String, String>{
  'accent_settings.json': 'HomePage, _unlessTesting',
  'audio_sync_settings.json': 'HomePage, _unlessTesting',
  'camera_path_settings.json': 'HomePage, _unlessTesting',
  'color_palette.json': 'HomePage, _unlessTesting',
  'frame_count_settings.json': 'HomePage, _unlessTesting',
  'frame_grid_settings.json': 'HomePage, _unlessTesting',
  'input_settings.json': 'HomePage, _unlessTesting',
  'language_settings.json': 'HomePage, _unlessTesting',
  'memory_settings.json': 'HomePage, _unlessTesting',
  'onion_skin_settings.json': 'HomePage, _unlessTesting',
  'pixel_verb_settings.json': 'HomePage, _unlessTesting',
  'save_settings.json': 'HomePage, _unlessTesting',
  'shortcut_overrides.json': 'HomePage, _unlessTesting',
  'ui_scale.json': 'HomePage, _unlessTesting — and the two main()s',
  'window.json':
      'main(), WindowPlace and WindowFullScreen.restore — a test names its '
      'file',
  'workspace_colors.json': 'HomePage, _unlessTesting',
  'workspace_layout.json': 'EditorWorkspace, its own FLUTTER_TEST check',
};
