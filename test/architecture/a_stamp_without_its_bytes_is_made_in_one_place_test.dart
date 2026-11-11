import 'package:flutter_test/flutter_test.dart';

import '../helpers/dart_sources.dart';

/// 🚨A STAMP WITHOUT ITS BYTES IS MADE BY `EngineStampPictures` ALONE
/// (`lib/src/native/engine_stamp_pictures.dart`).
///
/// 🗣️gpu-canonical-store-Q11 (유저 2026-11-10): 「RAM 에 사본을 두고 앱을
/// 유지한다」 — 「잃는 것은 그리던 획 정도다」. A stamp read from elsewhere
/// (`BrushStampImage.read`) has no bytes here till something asks for
/// them, and one the engine made is a picture of ITS device, gone with it.
/// The one place that makes them keeps what made each — the stamp it was
/// made of and the numbers it was made by — and makes it again on the next
/// engine (`EngineStampPictures._makes`). A stamp made without its bytes
/// anywhere else is lost with its device, and no test of the one place
/// says so: this SCANS SOURCE (관제 2026-11-12: 「그 「하나뿐」을 소스 스캔
/// 래칫으로 잠가라」).
void main() {
  test('nothing in lib makes a stamp without its bytes but '
      'EngineStampPictures, once — which keeps what made it', () {
    expect(
      {
        for (final file in dartFilesUnder('lib'))
          for (final read in _reads(file.readAsStringSync()))
            (libPath(file), read),
      },
      {
        ('lib/src/models/brush_stamp_image.dart', 'BrushStampImage.read({'),
        (_theOnePlace, 'made = BrushStampImage.read('),
      },
      reason:
          'a stamp the engine made goes with its device unless what made '
          'it is kept: make it through `EngineStampPictures`, where it is '
          '(`_made`), not beside it',
    );
  });

  test('the scan sees a planted one, torn off or called, and not a stamp '
      'with its bytes or a comment', () {
    const planted = '''
final stamp = BrushStampImage.read(id: id, width: 1, height: 1, rgba: read);
final make = BrushStampImage.read;
final whole = BrushStampImage(id: id, width: 1, height: 1, rgba: bytes);
/// A stamp read from elsewhere ([BrushStampImage.read]).
// ↩️It was BrushStampImage.read(id: id, width: 1, height: 1, rgba: read).
''';
    expect(_reads(planted), [
      'final stamp = BrushStampImage.read(id: id, width: 1, height: 1, '
          'rgba: read);',
      'final make = BrushStampImage.read;',
    ]);
  });
}

const _theOnePlace = 'lib/src/native/engine_stamp_pictures.dart';

/// Each line of [source] that names the stamp read from elsewhere —
/// trimmed, comments skipped.
List<String> _reads(String source) => [
  for (final line in source.split('\n'))
    if (!line.trimLeft().startsWith('//') && _read.hasMatch(line)) line.trim(),
];

final _read = RegExp(r'\bBrushStampImage\.read\b');
