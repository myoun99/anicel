import 'package:flutter_test/flutter_test.dart';

import '../../tool/source_brackets.dart';
import '../helpers/dart_sources.dart';

/// 🚨ONE transparency checker in the app.
///
/// The user's rule for open alpha is the checker that already exists (유저
/// 2026-09-09: 「투명이라는 의미의 체크무늬 … 이미있으면 있던거 쓰고」, and
/// 2026-09-11 for the import preview: 「출력창의 미리보기에서 쓰는 … 격자무늬
/// 그대로 공용화해서 재사용하도록」). It lives in
/// `ui/canvas/paper_background.dart` (`paintAlphaCheckerboard`, and
/// `paintAbsentPlane` for an absent plane on screen); the window previews
/// draw it as their page's ground (`ViewportPageGround.checker`).
/// ↩️`AlphaCheckerboardPainter` went when the film's floor took the stage's
/// one plane (2026-10-23). ↩️`ui/widgets/checkered_picture.dart`
/// went with the import preview's 16:9 well (F-282 ④, 2026-10-09).
///
/// The cut-piece preview drew a second one — its own cell loop in the panel's
/// colours — and nothing noticed, because a hand-written checker is the same
/// algorithm under a different spelling. So this reads the source: a file
/// that talks about a checker AND lays cells out with `isEven` next to a
/// `drawRect` is drawing its own.
void main() {
  test('🚨no file but the shared one draws a transparency checker', () {
    final offenders = <String>[];
    final files = dartFilesUnder('lib/src');
    var scanned = 0;
    for (final file in files) {
      final path = file.path.replaceAll('\\', '/');
      scanned += 1;
      if (path.endsWith('ui/canvas/paper_background.dart')) {
        continue;
      }
      // Code only: a comment may talk about the checker all it likes.
      final code = file
          .readAsLinesSync()
          .map((line) {
            final comment = line.indexOf('//');
            return comment < 0 ? line : line.substring(0, comment);
          })
          .join('\n');
      final laysCells = RegExp(
        r'\.isEven[\s\S]{0,400}drawRect\(|drawRect\([\s\S]{0,400}\.isEven',
      ).hasMatch(code);
      if (laysCells && RegExp('checker', caseSensitive: false).hasMatch(code)) {
        offenders.add(path);
      }
    }
    expect(scanned, greaterThan(500), reason: 'the source scan found lib/src');
    expect(
      offenders,
      isEmpty,
      reason:
          'draw open alpha with paintAlphaCheckerboard — an absent plane '
          'on screen with paintAbsentPlane — the one checker the app has',
    );
  });

  /// 🚨AN ABSENT PLANE ON SCREEN LAYS ITS CELLS IN ONE GRID, the screen's
  /// (`paintAbsentPlane`, camera-checkerboard-rides-the-canvas, 2026-10-23).
  ///
  /// The checker's cells sit in whatever space the canvas is in, so a
  /// painter that lays it under the view or a camera lays a pattern of its
  /// own: through the camera the film's floor showed four-pixel cells at
  /// 50% against the editing canvas's eight, and pressing play changed the
  /// pattern. ⛔A behaviour test holds the planes there are and says nothing
  /// of the next one, so the callers are read off the source: past
  /// `paintAbsentPlane`, only the window previews' page ground lays the
  /// checker itself — a document's open alpha, in its pages' cells.
  test('an absent plane on screen takes the checker through one door', () {
    const shared = 'lib/src/ui/canvas/paper_background.dart';
    final callers = <String, String>{
      for (final file in dartFilesUnder('lib/src'))
        if (withoutComments(file.readAsStringSync())
            case final code when code.contains('paintAlphaCheckerboard('))
          libPath(file): code,
    };
    expect(
      callers.keys.toSet(),
      {shared, 'lib/src/ui/canvas/viewport_pages_painter.dart'},
      reason:
          'lay an absent plane on screen with paintAbsentPlane, in the '
          'screen\'s cells — the checker laid under the view or a camera '
          'is a grid of its own',
    );
    expect(
      'paintAlphaCheckerboard('.allMatches(callers[shared]!).length,
      2,
      reason: '$shared declares the checker and lays it once, inside '
          'paintAbsentPlane',
    );
  });

  /// 🗣️유저 2026-09-16 (F-146): 「설정의 알파 미리보기 **필요없어졌으니 잔재
  /// 싹 삭제**」.
  ///
  /// The checker stayed — every OTHER caller draws real absent alpha — and
  /// what went was the app-view TOGGLE that swapped the whole stage for it.
  /// ⛔A ratchet rather than a behaviour test, because what was deleted
  /// cannot be driven: the only proof left is that nothing spells its name.
  test('⛔the ALPHA-PREVIEW toggle stays deleted', () {
    final spelled = <String>[];
    for (final file in dartFilesUnder('lib/src')) {
      if (file.readAsStringSync().contains('alphaPreviewEnabled')) {
        spelled.add(file.path.replaceAll(r'\', '/'));
      }
    }
    expect(
      spelled,
      isEmpty,
      reason:
          '⛔an ABSENT plane already says 「여기는 비어 있다」 in the place it '
          'means it (F-114). A switch that says it about the WHOLE stage is '
          'the thing 유저 asked to be rid of',
    );
  });
}
