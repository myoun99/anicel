import 'dart:io';

import 'package:anicel/src/services/crate_licences.dart';
import 'package:anicel/src/services/licence_entry.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';

import 'helpers/dart_sources.dart';

/// A licence the app ships a binary under is SHOWN with it — the About ▸
/// licenses screen registers each text in `assets/licenses/`, and each font's
/// OFL text beside it in `assets/fonts/` (THIRD_PARTY.md: 「a component whose
/// license requires a notice in shipped binaries must also appear in the
/// app's about/licenses screen」). A text put in a folder and never
/// registered ships unread — the Rust crates' one list
/// (`rust_crates.json`, tool/crate_notices.dart) as much as a text.
void main() {
  test('every licence text the app bundles is registered at launch', () {
    final main = File('lib/main.dart').readAsStringSync();
    final texts = [
      for (final folder in [
        Directory('assets/licenses'),
        Directory('assets/fonts'),
      ])
        for (final file in folder.listSync())
          if (file is File &&
              (file.path.endsWith('.txt') || file.path.endsWith('.json')))
            "'${folder.path}/${file.uri.pathSegments.last}'",
    ];
    expect(texts, contains("'assets/licenses/LICENSE-PDFium.txt'"));
    expect(texts, contains("'assets/licenses/LICENSE-RNNoise.txt'"));
    expect(texts, contains("'assets/licenses/LICENSE-zstd.txt'"));
    expect(texts, contains("'assets/licenses/rust_crates.json'"));
    expect(texts, contains("'assets/fonts/OFL-NotoSansSC.txt'"));
    for (final text in texts) {
      expect(main, contains(text), reason: '$text is bundled but not shown');
    }
  });

  // A `\r` left in a paragraph is drawn as a box (서피스 검증 2026-11-08
  // 10:35) — every text as the asset bundle hands it to the app (this
  // checkout's bytes, CRLF under core.autocrlf), and the crates' notices,
  // five of them CRLF as they ship ([licenceEntry]).
  test('every licence text the app shows reads without a carriage return',
      () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final entries = [
      for (final folder in ['assets/licenses', 'assets/fonts'])
        for (final file in Directory(folder).listSync())
          if (file is File && file.path.endsWith('.txt'))
            licenceEntry(
              [file.path],
              await rootBundle.loadString(
                '$folder/${file.uri.pathSegments.last}',
              ),
            ),
      ...crateLicenceEntries(
        await rootBundle.loadString('assets/licenses/rust_crates.json'),
      ),
      licenceEntry(const ['old Mac'], 'one\rtwo\r\n\r\nthree'),
    ];
    for (final entry in entries) {
      for (final paragraph in entry.paragraphs) {
        expect(
          paragraph.text,
          isNot(contains('\r')),
          reason: '${entry.packages.first}: ${paragraph.text}',
        );
      }
    }
    expect(
      [for (final p in entries.last.paragraphs) p.text],
      ['one two', 'three'],
    );
  });

  test('every licence entry in lib is made through licenceEntry', () {
    final makers = [
      for (final file in dartFilesUnder('lib'))
        if (file.readAsStringSync().contains('LicenseEntryWithLineBreaks('))
          file.uri.pathSegments.last,
    ];
    expect(makers, ['licence_entry.dart']);
  });
}
