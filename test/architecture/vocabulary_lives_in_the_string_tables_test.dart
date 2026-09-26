import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../helpers/dart_sources.dart';

/// ⛔No file keeps its own words per language: the string tables do.
///
/// 유저 2026-09-15 (blend-mode-names-language-Q1): 「블렌드 모드도 모든 언어로
/// 번역」. Five enums had carried a Japanese table inline under the 07-22 rule
/// (ja localized first, every other language the shared English) — a second
/// copy of the law the string tables keep (I-4, `AppStrings.layerProcessName`:
/// the model holds its English and a key, the tables hold every other
/// language). A copy that answers today's languages passes every behaviour
/// test, which is why this reads the source.
///
/// The screen's layer too, since 2026-09-26: the timesheet's printed words
/// were a table per language of their own in `ui/` (UI-R10, older than this
/// law), so 「what does the notation language print」 had two answers — the
/// conte's from the string tables, the sheet's from its own enum.
///
/// The files that may name a language, and why:
const _mayNameALanguage = <String, String>{
  // Each language's name written in ITSELF (日本語 · 한국어) is the
  // universal convention, and the notation default names a language rather
  // than translating a word.
  'lib/src/models/app_language.dart': 'the languages themselves',
  'lib/src/ui/text/app_strings.dart': 'the tables, and the door that picks one',
  // A face per language — Chinese falls to the OS's (app-typeface) — and no
  // word at all.
  'lib/src/ui/theme/app_theme.dart': 'the face each language is set in',
};

void main() {
  test('no file outside the string tables names a language to pick its '
      'words', () {
    final namedLanguage = RegExp(r'AppLanguage\.(ja|ko|fr|zhHans)\b');
    final offenders = <String>[];
    for (final dir in const [
      'lib/src/core',
      'lib/src/models',
      'lib/src/services',
      'lib/src/controllers',
      'lib/src/ui',
    ]) {
      for (final file in dartFilesUnder(dir)) {
        final path = libPath(file);
        if (_mayNameALanguage.containsKey(path)) {
          continue;
        }
        if (namedLanguage.hasMatch(file.readAsStringSync())) {
          offenders.add(path);
        }
      }
    }
    expect(offenders, isEmpty);
  });

  test('every file allowed to name a language still does', () {
    // A stale entry would wave a future offender through by its path.
    final namedLanguage = RegExp(r'AppLanguage\.(ja|ko|fr|zhHans)\b');
    for (final path in _mayNameALanguage.keys) {
      expect(
        namedLanguage.hasMatch(File(path).readAsStringSync()),
        isTrue,
        reason: path,
      );
    }
  });
}
