import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/app_language.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/ui/text/app_strings.dart';
import 'package:anicel/src/ui/timeline/layer_label_controls.dart'
    show layerKindDisplayName;
import 'package:anicel/src/ui/timeline/layer_rail_columns.dart'
    show layerTypeSemanticLabel;

/// A row's KIND had three names living in three places: a translated
/// `tlKind*` table with eight of the ten kinds in it, and two switches of
/// hardcoded English with all ten. So the same row read 「디렉션」 in the
/// toolbar and `Direction` in the kind flyout, and the two kinds missing
/// from the table — transition and camera — were English everywhere.
///
/// The fix is not "translate the transition row". It is that there is one
/// table now, and the other two read it.
void main() {
  setUp(() {
    AppText.settings.value = const AppLanguageSettings();
  });
  tearDown(() {
    AppText.settings.value = const AppLanguageSettings();
  });

  void speak(AppLanguage language) {
    AppText.settings.value = AppLanguageSettings(programLanguage: language);
  }

  test('a kind name follows the program language', () {
    speak(AppLanguage.ko);
    expect(layerKindDisplayName(LayerKind.animation), '동화');
    speak(AppLanguage.ja);
    expect(layerKindDisplayName(LayerKind.animation), '動画');
    speak(AppLanguage.en);
    expect(layerKindDisplayName(LayerKind.animation), 'Animation');
  });

  test('the two kinds the table never had are in it now', () {
    speak(AppLanguage.ko);
    expect(layerKindDisplayName(LayerKind.transition), '트랜지션');
    expect(layerKindDisplayName(LayerKind.camera), '카메라');
    speak(AppLanguage.ja);
    expect(layerKindDisplayName(LayerKind.transition), 'トランジション');
    expect(layerKindDisplayName(LayerKind.camera), 'カメラ');
  });

  test('trade terms keep their own script or English — the words the studio '
      'says, not their translations', () {
    for (final language in AppLanguage.values) {
      speak(language);
      expect(
        layerKindDisplayName(LayerKind.se),
        'SE',
        reason: 'SE is spoken as SE everywhere',
      );
    }
    // 지시 was the odd one out: ja and ko already transliterate Direction
    // rather than translate it, so zh translating it was the exception.
    speak(AppLanguage.zhHans);
    expect(layerKindDisplayName(LayerKind.instruction), 'Direction');
    speak(AppLanguage.ja);
    expect(layerKindDisplayName(LayerKind.instruction), 'ディレクション');
    speak(AppLanguage.ko);
    expect(layerKindDisplayName(LayerKind.instruction), '디렉션');
  });

  test('the screen reader says the SAME name — the two cannot disagree, '
      'because one is built from the other', () {
    for (final language in AppLanguage.values) {
      speak(language);
      for (final kind in LayerKind.values) {
        if (kind == LayerKind.folder) {
          continue;
        }
        expect(
          layerTypeSemanticLabel(kind),
          contains(layerKindDisplayName(kind)),
          reason: '$kind in $language',
        );
      }
    }
  });

  test('the sentence around the name is the language\'s own, not an English '
      'suffix glued on', () {
    speak(AppLanguage.ko);
    expect(layerTypeSemanticLabel(LayerKind.animation), '동화 레이어');
    speak(AppLanguage.ja);
    expect(layerTypeSemanticLabel(LayerKind.animation), '動画レイヤー');
    speak(AppLanguage.fr);
    expect(
      layerTypeSemanticLabel(LayerKind.animation),
      'Calque Animation',
      reason: 'French puts the noun first, so a suffix could never work',
    );
  });

  test('a folder is a folder, never "a folder layer"', () {
    for (final language in AppLanguage.values) {
      speak(language);
      expect(
        layerTypeSemanticLabel(LayerKind.folder),
        layerKindDisplayName(LayerKind.folder),
        reason: 'the old table broke its own pattern here for a reason',
      );
    }
  });
}
