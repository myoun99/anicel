import 'package:flutter_test/flutter_test.dart';

import '../helpers/dart_sources.dart';

/// ⛔No core, model, service or controller file keeps its own words per
/// language.
///
/// 유저 2026-09-15 (blend-mode-names-language-Q1): 「블렌드 모드도 모든 언어로
/// 번역」. Five enums had carried a Japanese table inline under the 07-22 rule
/// (ja localized first, every other language the shared English) — a second
/// copy of the law the string tables keep (I-4, `AppStrings.layerProcessName`:
/// the model holds its English and a key, the tables hold every other
/// language). A copy that answers today's languages passes every behaviour
/// test, which is why this reads the source.
///
/// ⚠️`models/app_language.dart` is the one exception: each language's name
/// written in ITSELF (日本語 · 한국어) is the universal convention, and the
/// notation default names a language rather than translating a word.
void main() {
  test('no inner-layer file names a language to pick its words', () {
    final namedLanguage = RegExp(r'AppLanguage\.(ja|ko|fr|zhHans)\b');
    final offenders = <String>[];
    for (final dir in const [
      'lib/src/core',
      'lib/src/models',
      'lib/src/services',
      'lib/src/controllers',
    ]) {
      for (final file in dartFilesUnder(dir)) {
        final path = libPath(file);
        if (path == 'lib/src/models/app_language.dart') {
          continue;
        }
        if (namedLanguage.hasMatch(file.readAsStringSync())) {
          offenders.add(path);
        }
      }
    }
    expect(offenders, isEmpty);
  });
}
