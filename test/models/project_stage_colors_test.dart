import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_background.dart';
import 'package:anicel/src/ui/theme/app_theme.dart';
import 'package:anicel/src/ui/theme/app_workspace_colors.dart';

/// R3b: the stage's colors on the project — backdrop (opaque by
/// contract), pasteboard (RGBA), paper (alpha absorbed the old
/// display-only transparent flag).
void main() {
  test('stage colors round-trip through JSON and omit the defaults', () {
    final plain = createDefaultProject();
    expect(plain.toJson().containsKey('backdropArgb'), isFalse);
    expect(plain.toJson().containsKey('pasteboardArgb'), isFalse);
    expect(plain.backdropArgb, defaultProjectBackdropArgb);
    expect(plain.pasteboardArgb, defaultProjectPasteboardArgb);

    final colored = plain.copyWith(
      backdropArgb: 0xFF102030,
      pasteboardArgb: 0x80445566,
    );
    final restored = Project.fromJson(colored.toJson());
    expect(restored.backdropArgb, 0xFF102030);
    expect(restored.pasteboardArgb, 0x80445566);
  });

  test('the default stage floor is ONE colour written in three places, and '
      'drift between them is a silent bug', () {
    // Three constants say the same number and none of them can import the
    // others' home: the models layer may not reach the theme, and the app's
    // workspace colours are app state rather than project data. Their
    // comments each say "must stay in step" — this is the only thing that
    // can actually hold them there.
    //
    // What drift costs: a project OMITS `pasteboardArgb` from its JSON when
    // it equals the default, so an app default that disagreed with the
    // project default would make a saved file change colour on the way back
    // in — silently, and only for files written before the drift.
    expect(
      AppWorkspaceColors.defaultPasteboardArgb,
      defaultProjectPasteboardArgb,
      reason: 'app-level and project-level pasteboard defaults',
    );
    expect(
      defaultProjectBackdropArgb,
      defaultProjectPasteboardArgb,
      reason: '유저, R3 #4: the two planes are one field out of the box',
    );
    expect(
      defaultProjectBackdropArgb,
      AppColors.backdrop.toARGB32(),
      reason: '유저, R4 #2: the stage floor IS the app floor, not black',
    );
  });

  test('the backdrop is opaque by contract — the constructor forces the '
      'alpha byte, so no path can thin the stage\'s final answer', () {
    final thinned = createDefaultProject().copyWith(
      backdropArgb: 0x00102030,
    );
    expect(thinned.backdropArgb, 0xFF102030);
  });

  test('paper alpha rides the argb; the legacy transparent flag reads as '
      'alpha 0 and never writes back', () {
    const thin = ProjectBackground.color(0x80FFFFFF);
    expect(thin.transparent, isFalse);
    expect(ProjectBackground.fromJson(thin.toJson()), thin);

    final legacy = ProjectBackground.fromJson({'transparent': true});
    expect(legacy.transparent, isTrue);
    expect(legacy.argb >>> 24, 0);
    expect(legacy.toJson().containsKey('transparent'), isFalse);
    expect(ProjectBackground.fromJson(legacy.toJson()), legacy);
  });
}
