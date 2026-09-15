import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/app_language.dart';
import 'package:anicel/src/models/import/cut_folder_parse.dart';
import 'package:anicel/src/models/import/import_warning.dart';
import 'package:anicel/src/ui/text/app_strings.dart';
import 'package:anicel/src/ui/text/model_vocabulary.dart';

/// Every word an import says has a row in every translated table.
///
/// The warnings and the exclusion reasons keep the models' contract (I-4):
/// the English wording lives where the warning is raised, and every other
/// language is a lookup by key — so a key nothing tables falls back to
/// English silently, which is exactly the hole this closes (F-124,
/// 2026-09-16).
///
/// ⚠️「Tabled」 is asked with a fallback no row can equal, never as 「differs
/// from English」.
void main() {
  const untabled = ' ';
  const translated = [
    AppLanguage.ja,
    AppLanguage.ko,
    AppLanguage.fr,
    AppLanguage.zhHans,
  ];

  /// ★A NEW WARNING ADDS ITS KEY HERE. The keys are the raising sites'
  /// own — `psd*` the Photoshop reader and its layer plan, `folder*` the
  /// cut folder's parse and plan, `tvp*`/`tvpp*` the TVPaint planner,
  /// parser and converter, and the last three the .tvpp door itself.
  const keys = [
    'psdBitDepth',
    'psdVectorMask',
    'psdComposite',
    'psdExtraChannels',
    'psd32Bit',
    'psdDuotone',
    'psdMultichannel',
    'psdIndexedNoPalette',
    'psdCmyk',
    'psdLab',
    'psdAdjustment',
    'psdClipping',
    'psdBlend',
    'folderNothing',
    'folderNoBase',
    'folderNoOriginal',
    'folderMultiCutOff',
    'folderNoCutNumber',
    'tvpNoFile',
    'tvpMuted',
    'tvpBlend',
    'tvppHoldNoDrawing',
    'tvppChunkBroken',
    'celUnreadable',
    'stagedCopy',
    'soundMissing',
  ];

  for (final language in translated) {
    test('${language.name} tables every import warning and every exclusion '
        'reason', () {
      final strings = AppStrings.of(language);
      expect([
        for (final key in keys)
          if (strings.importWarning(key, untabled) == untabled) key,
      ], isEmpty, reason: 'import warnings');
      expect([
        for (final reason in ExclusionReason.values)
          if (strings.exclusionReason(reason.name, untabled) == untabled)
            reason.name,
      ], isEmpty, reason: 'exclusion reasons');
    });
  }

  test('a warning says its own language, values and all', () {
    const warning = ImportWarning(
      'tvpMuted',
      '{file}: the track was muted — its sound is linked all the same.',
      {'file': '12.mp4'},
    );
    expect(
      warning.english,
      '12.mp4: the track was muted — its sound is linked all the same.',
    );
    expect(warning.textFor(AppLanguage.ko), startsWith('12.mp4: 트랙이 뮤트'));
    expect(warning.textFor(AppLanguage.ja), contains('ミュート'));
    // ⛔A value is put in as it is: a file that happens to carry braces
    // names nothing.
    const braced = ImportWarning('soundMissing', 'x {path}', {
      'path': '{file}.wav',
    });
    expect(braced.english, 'x {file}.wav');
  });

  test('a reason says its own language, and English where the key is the '
      'fallback', () {
    expect(
      ExclusionReason.processSubfolder.labelFor(AppLanguage.en),
      'process subfolder (archive)',
    );
    expect(
      ExclusionReason.memoText.labelFor(AppLanguage.ko),
      '메모 텍스트',
    );
  });
}
