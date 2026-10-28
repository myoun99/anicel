import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/services/persistence/settings_file.dart';

/// I-142-Q5 (유저 2026-10-29): 「json? … 최대한 최신식인 저장형식 뭐
/// 가벼운거? 그런건 맡김」 — Anicel's settings file is the settings' own
/// documents, by their stores' file names, in one small JSON envelope.
void main() {
  const documents = {
    'color_palette.json': {'version': 2, 'palettes': <Object?>[]},
    'shortcut_overrides.json': {'version': 3},
  };

  test('the documents come back as they went, by their stores\' names', () {
    expect(decodeSettingsFile(encodeSettingsFile(documents)), documents);
  });

  test('a file this build cannot read holds no documents — not JSON, not '
      'the envelope, or a newer envelope', () {
    String envelope(Object? version, Object? held) =>
        jsonEncode({'anicelSettings': version, 'documents': held});

    expect(decodeSettingsFile('not json'), isNull);
    expect(decodeSettingsFile(jsonEncode(documents)), isNull);
    expect(decodeSettingsFile(envelope('1', documents)), isNull);
    expect(decodeSettingsFile(envelope(1, [documents])), isNull);
    expect(
      decodeSettingsFile(envelope(settingsFileVersion + 1, documents)),
      isNull,
    );
    expect(
      decodeSettingsFile(envelope(settingsFileVersion, documents)),
      documents,
      reason: '⛔전제: the same file at this version is read',
    );
  });

  test('what is no document is not one', () {
    expect(
      decodeSettingsFile(
        jsonEncode({
          'anicelSettings': settingsFileVersion,
          'documents': {
            'color_palette.json': {'version': 2},
            'stray.json': 'text',
            'list.json': [1],
          },
        }),
      ),
      {
        'color_palette.json': {'version': 2},
      },
    );
  });
}
