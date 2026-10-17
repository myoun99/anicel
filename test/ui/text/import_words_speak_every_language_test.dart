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
  /// parser and converter, three the .tvpp door itself, `clip*` the CLIP
  /// STUDIO planner and door, `brushPack*` · `abr*` · `sut*` the brush file
  /// readers' refusals (F-273) — and `unsupportedLayerKind` ·
  /// `layerEffectsNotApplied` · `clippingNotApplied` · `layerMaskNotApplied`
  /// · `lockNotImported` every decoder's one word for each
  /// (`import_warning.dart`).
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
    'clipRead',
    'clipFps',
    'clipUnplaced',
    'clipNoSuchCel',
    'clipCelLayers',
    'clipSpread',
    'clipLineOrder',
    'clipVector',
    'clipSound',
    'clipSoundMissing',
    'clipSoundSpeed',
    'clipSoundVolume',
    'clipCurve',
    'clipBlend',
    'clipNotColour',
    'clipTransform',
    'clipVectorUnread',
    'clipTextUnread',
    'clipTextItalic',
    'clipTextUnderline',
    'clipTextStrike',
    'clipTextAlign',
    'clipTextSpacing',
    'clipTextAcross',
    'clipTextTurned',
    'clipTextSetHere',
    'brushPackUnreadable',
    'brushPackNotOurs',
    'brushPackNewer',
    'brushPackEmpty',
    'brushPackDamaged',
    'abrTooShort',
    'abrOldVersion',
    'abrUnknownVersion',
    'abrCorruptSection',
    'abrNoBrushes',
    'abrNothingImportable',
    'sutCannotOpen',
    'sutUnreadable',
    'sutNoBrushData',
    'sutNothingImportable',
    'unsupportedLayerKind',
    'layerEffectsNotApplied',
    'clippingNotApplied',
    'layerMaskNotApplied',
    'lockNotImported',
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

  test('F-370: a warning that opens with ONE THING parts into that thing and '
      'what it says of it, a sentence of its own, at every language\'s '
      'colon — and one that opens with none is said whole', () {
    // A name with a colon of its own: the sentence parts where ITS colon is.
    final named = unsupportedLayerKind('cel: 2');
    expect(
      named.partsFor(AppLanguage.en),
      (about: 'cel: 2', says: 'This kind of layer is not supported.'),
    );
    expect(
      named.partsFor(AppLanguage.fr),
      (about: 'cel: 2', says: "Ce type de calque n'est pas pris en charge."),
    );
    expect(
      named.partsFor(AppLanguage.zhHans),
      (about: 'cel: 2', says: '不支持此图层类型。'),
    );
    const whole = ImportWarning(
      'folderNoCutNumber',
      'No cut number found in the folder name.',
    );
    expect(
      whole.partsFor(AppLanguage.en),
      (about: null, says: 'No cut number found in the folder name.'),
    );
    // One that opens with a value but no colon after it is said whole too.
    const counted = ImportWarning('untabled', '{n} layers were merged.', {
      'n': '3',
    });
    expect(
      counted.partsFor(AppLanguage.en),
      (about: null, says: '3 layers were merged.'),
    );
    // And a sentence that does not open with the thing is not about it,
    // wherever its own colon falls.
    expect(partsOf('b: c', about: 'a'), (about: null, says: 'b: c'));
  });

  test('F-370: what opens with one thing in one language opens with it in '
      'every one — so a notice lists it the same whatever the reader '
      'speaks', () {
    bool opensWithOne(String key, AppLanguage language) {
      final words = AppStrings.of(language).importWarning(key, untabled);
      final warning = ImportWarning(key, untabled, {
        for (final placeholder in RegExp(r'\{(\w+)\}').allMatches(words))
          placeholder.group(1)!: 'x',
      });
      return warning.partsFor(language).about != null;
    }

    expect([
      for (final key in keys)
        if ({
              for (final language in translated) opensWithOne(key, language),
            }.length >
            1)
          key,
    ], isEmpty);
  });

  test('F-370-Q1: what the import window says of a file opens with that file '
      'in every language — so its notice lists the file under what was '
      'said, the Open door\'s way', () {
    // ★A NEW SENTENCE THE WINDOW SAYS OF A FILE ADDS ITSELF HERE.
    final ofAFile = <String, String Function(AppStrings, String)>{
      'imUnreadable': (s, name) => s.imUnreadable(name),
      'imCorrupt': (s, name) => s.imCorrupt(name),
      'imPagesFailed': (s, name) => s.imPagesFailed(name, 2),
      'imFramesFailed': (s, name) => s.imFramesFailed(name, 2),
      'imNoPdfRenderer': (s, name) => s.imNoPdfRenderer(name),
      'imCouldNotImport': (s, name) => s.imCouldNotImport(name),
      'imPsdNoLayers': (s, name) => s.imPsdNoLayers(name),
    };
    const name = 'a.png';
    expect([
      for (final language in AppLanguage.values)
        for (final MapEntry(key: sentence, value: said) in ofAFile.entries)
          if (partsOf(
                said(AppStrings.of(language), name),
                about: name,
              ).about !=
              name)
            '${language.name} $sentence',
    ], isEmpty);
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
