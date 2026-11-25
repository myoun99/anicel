import 'package:flutter_test/flutter_test.dart';

import '../../tool/source_brackets.dart' show codeOnly;
import '../helpers/dart_sources.dart';

/// 🚨A TEST WHOSE PREMISE IS AN APP WITH NO ENGINE YET STANDS IT ITSELF
/// (`theAppHasNoEngineYet`, test/helpers/the_apps_engine_let_go.dart).
///
/// A bundle's files share one isolate (tool/test_bundles.dart), and an
/// engine once open stays open, by law. 🔬Seven files went red bundled
/// behind files that had opened it and green alone (card
/// bundled-files-find-the-engine-already-open, 2026-11-23); an eighth, made
/// two days before, was not among them and went red 10/10 behind
/// a_cel_cools_and_parks_between_screen_turns (CI 11-23 job 137699859002,
/// card a-widget-test-gets-an-engine-it-did-not-ask-for), and a ninth wrote
/// 「A file of its own」 and stood nothing. A test that stands its premise
/// passes alone either way, so no run tells the two apart: this reads the
/// source.
void main() {
  test('a test that says no engine is open has let any open one go first',
      () {
    final premised = <String>[];
    final unstood = <String>[];
    for (final file in dartFilesUnder('test')) {
      final path = file.path.replaceAll('\\', '/');
      final code = codeOnly(file.readAsStringSync());
      if (!premisesNoEngine(code)) continue;
      premised.add(path);
      if (!standsItsPremise(code)) unstood.add(path);
    }
    expect(premised, isNotEmpty, reason: '⛔the scan read nothing');
    expect(
      unstood,
      isEmpty,
      reason: 'bundled, a file ahead of these may have opened the engine: '
          'call theAppHasNoEngineYet() before saying none is open',
    );
  });

  test('the scan tells a premise stood from one that is not', () {
    const said = 'expect(appGpuEngineOpen.value, isNull);';
    const asked = 'expect(debugAppGpuEngineAskedFor, isFalse);';
    expect(standsItsPremise('theAppHasNoEngineYet(); $said'), isTrue);
    expect(standsItsPremise('theAppsEngineLostAndLetGo(); $asked'), isTrue);
    expect(standsItsPremise(said), isFalse);
    expect(standsItsPremise('$said theAppHasNoEngineYet();'), isFalse);
    expect(premisesNoEngine('expect(appGpuEngineOpen.value, isNotNull);'),
        isFalse);
  });
}

final _premise = RegExp(
  r'expect\(\s*(appGpuEngineOpen\.value\s*,\s*isNull|'
  r'debugAppGpuEngineAskedFor\s*,\s*isFalse)\b',
);
final _stood = RegExp(r'\b(theAppHasNoEngineYet|theAppsEngineLostAndLetGo)\(');

/// Whether [code] says, as a test's expectation, that no engine is open.
bool premisesNoEngine(String code) => _premise.hasMatch(code);

/// Whether [code] lets any open engine go before it first says none is.
bool standsItsPremise(String code) {
  final said = _premise.firstMatch(code);
  if (said == null) return true;
  final stood = _stood.firstMatch(code);
  return stood != null && stood.start < said.start;
}
