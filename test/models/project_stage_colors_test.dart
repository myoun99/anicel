import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_background.dart';

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
