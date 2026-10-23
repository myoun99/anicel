import 'package:flutter_test/flutter_test.dart';

import '../helpers/dart_sources.dart';
import '../helpers/source_ledger.dart';

/// 🚨THE APP ASKS 「IS THIS A TEST RUN」 IN ONE PLACE
/// (`lib/src/services/flutter_test_run.dart`, board
/// `capture-spells-out-its-own-test-gate`, 2026-10-23).
///
/// Fifteen places read `FLUTTER_TEST` for themselves, and the microphone's
/// three had spelled out the audio device's gate beside the gate itself.
/// A copy that reads the flag right passes every behaviour test — a widget
/// test only ever sees the answer — so this reads the source.
void main() {
  const home = 'lib/src/services/flutter_test_run.dart';

  test('no file but the one reads the test flag', () {
    final readers = {
      for (final file in dartFilesUnder('lib'))
        if (_readsTheFlag(file.readAsStringSync())) libPath(file),
    };
    expectSetMatchesLedger(
      readers,
      const [home],
      unledgered:
          'ask `underFlutterTest`; the audio device comes through '
          '`audioDeviceUnlessTesting`',
      paidOff: 'the one place no longer reads it — name where it moved',
    );
  });

  test('the scan sees a read, and not a comment that names the flag', () {
    expect(
      _readsTheFlag("  if (Platform.environment['FLUTTER_TEST'] == "),
      isTrue,
    );
    expect(
      _readsTheFlag("Platform.environment.containsKey('FLUTTER_TEST')"),
      isTrue,
    );
    expect(_readsTheFlag('/// Sandboxed under `FLUTTER_TEST`.'), isFalse);
    expect(_readsTheFlag('x(); // FLUTTER_TEST keeps it off'), isFalse);
  });
}

bool _readsTheFlag(String source) =>
    codeOfLines(source).contains('FLUTTER_TEST');
