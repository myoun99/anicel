import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_background.dart';
import 'package:anicel/src/ui/theme/app_theme.dart';
import 'package:anicel/src/models/app_workspace_colors.dart';

/// R3b: the stage's colors on the project — backdrop, pasteboard and paper,
/// each an RGBA colour (the backdrop since F-114) and, since F-114, a plane
/// that can be absent without losing the colour it hides.
void main() {
  test('stage colors round-trip through JSON and omit the defaults', () {
    final plain = createDefaultProject();
    final json = plain.toJson();
    expect(json.containsKey('backdropArgb'), isFalse);
    expect(json.containsKey('pasteboardArgb'), isFalse);
    expect(json.containsKey('backdropNone'), isFalse);
    expect(json.containsKey('pasteboardNone'), isFalse);
    expect(plain.backdropArgb, defaultProjectBackdropArgb);
    expect(plain.pasteboardArgb, defaultProjectPasteboardArgb);
    expect(plain.backdropNone, isFalse);
    expect(plain.pasteboardNone, isFalse);

    final colored = plain.copyWith(
      backdropArgb: 0xFF102030,
      pasteboardArgb: 0x80445566,
    );
    final restored = Project.fromJson(colored.toJson());
    expect(restored.backdropArgb, 0xFF102030);
    expect(restored.pasteboardArgb, 0x80445566);
  });

  test('none round-trips per plane and keeps the colour it hides', () {
    final absent = createDefaultProject().copyWith(
      backdropArgb: 0xFF102030,
      backdropNone: true,
      pasteboardNone: true,
    );
    final restored = Project.fromJson(absent.toJson());
    expect(restored.backdropNone, isTrue);
    expect(restored.pasteboardNone, isTrue);
    expect(
      restored.backdropArgb,
      0xFF102030,
      reason: 'the kept colour is what the next pick or slider brings back',
    );
    final back = Project.fromJson(
      restored.copyWith(backdropNone: false).toJson(),
    );
    expect(back.backdropNone, isFalse);
    expect(back.pasteboardNone, isTrue, reason: 'each plane answers alone');
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

  test('🚨the backdrop keeps its alpha — F-114 gave it the opacity the other '
      'planes have', () {
    // 유저 2026-09-15: 「페이스트보드, 백그라운드 설정에도 동일적용」. Until then
    // it was opaque by contract (R3b) and the constructor forced the byte.
    final thinned = createDefaultProject().copyWith(
      backdropArgb: 0x80102030,
    );
    expect(thinned.backdropArgb, 0x80102030);
  });

  test('paper alpha rides the argb, and none is a second field beside it', () {
    const thin = ProjectBackground.color(0x80FFFFFF);
    expect(thin.none, isFalse);
    expect(thin.toJson().containsKey('none'), isFalse);
    expect(ProjectBackground.fromJson(thin.toJson()), thin);

    const absent = ProjectBackground.color(0x80FFFFFF, none: true);
    expect(absent, isNot(thin), reason: 'none is part of the value');
    final restored = ProjectBackground.fromJson(absent.toJson());
    expect(restored, absent);
    expect(restored.argb, 0x80FFFFFF);
  });
}
