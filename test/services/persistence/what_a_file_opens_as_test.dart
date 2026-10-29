import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/media_asset.dart';
import 'package:anicel/src/services/fx_plugins/fx_plugin_bundle.dart'
    show anicelFxPluginExtension;
import 'package:anicel/src/services/persistence/file_type_groups.dart';
import 'package:anicel/src/services/persistence/provider_documents.dart';
import 'package:anicel/src/services/persistence/settings_file.dart';
import 'package:anicel/src/services/shortcuts/program_keymap.dart'
    show shortcutFileExtensions;

/// F-282 (유저 2026-10-09): every door a file comes in through asks ONE
/// judgement what it opens as — a project, media for the import window, a
/// brush, a font, a program's shortcut file (I-107) — and a file none of
/// them takes is said by name.
void main() {
  tearDown(ProviderDocuments.debugReset);

  test('each list answers its own kind, in any case', () {
    for (final extension in projectOpenExtensions) {
      expect(openedAs('C:/work/x.$extension'), OpenedAs.project);
    }
    for (final extension in brushFileExtensions) {
      expect(openedAs('/work/x.$extension'), OpenedAs.brush);
    }
    for (final extension in fontFileExtensions) {
      expect(openedAs('/work/x.$extension'), OpenedAs.font);
    }
    for (final extension in shortcutFileExtensions) {
      expect(openedAs('/work/x.$extension'), OpenedAs.shortcuts);
    }
    for (final extension in [
      ...imageFileExtensions,
      ...videoFileExtensions,
      ...audioFileExtensions,
      ...pdfFileExtensions,
    ]) {
      expect(openedAs('/work/x.$extension'), OpenedAs.media, reason: extension);
    }
    expect(openedAs('/work/CUT 12.ANICEL'), OpenedAs.project);
    expect(openedAs('/work/Pack.ABR'), OpenedAs.brush);
    expect(openedAs('/work/Face.OTF'), OpenedAs.font);
    expect(openedAs('/work/default.KHC'), OpenedAs.shortcuts);
    expect(openedAs('/work/Take3.MOV'), OpenedAs.media);
  });

  test('I-142: our own settings files — a palette goes into the palettes, '
      'a shortcut preset where every shortcut file goes', () {
    expect(openedAs('/work/팔레트 1.$anicelPaletteExtension'), OpenedAs.palette);
    expect(openedAs('/work/Mine.ANIPALETTE'), OpenedAs.palette);
    expect(
      openedAs('/work/Clip Studio based.$anicelShortcutExtension'),
      OpenedAs.shortcuts,
    );
    expect(openableExtensions, contains(anicelPaletteExtension));
    expect(openableExtensions, contains(anicelShortcutExtension));
  });

  // 🗣️I-142-Q1: 「읽기는 「파일 열기」 하나」 · Q6: 「임포트 창에 설정 파일의
  // 행으로」.
  test('I-142: every setting\'s file opens as settings, which the import '
      'window lists as rows', () {
    expect(
      openedAs('/work/Anicel 설정.$anicelSettingsExtension'),
      OpenedAs.settings,
    );
    expect(openedAs('/work/Mine.ANISETTINGS'), OpenedAs.settings);
    expect(openableExtensions, contains(anicelSettingsExtension));
  });

  test('I-132: an fx plugin\'s file is installed as one', () {
    expect(
      openedAs('/work/Invert.$anicelFxPluginExtension'),
      OpenedAs.fxPlugin,
    );
    expect(openedAs('/work/Invert.ANIFX'), OpenedAs.fxPlugin);
    expect(openableExtensions, contains(anicelFxPluginExtension));
  });

  test('media is what the pool names a kind for — the same judgement, not a '
      'second list', () {
    for (final name in ['a.png', 'b.psd', 'c.mp4', 'd.wav', 'e.pdf']) {
      expect(mediaAssetKindForPath(name), isNotNull, reason: name);
      expect(openedAs(name), OpenedAs.media, reason: name);
    }
    expect(mediaAssetKindForPath('notes.docx'), isNull);
    expect(openedAs('notes.docx'), isNull);
  });

  test('a file nothing opens has no answer — the last extension decides, '
      'and a name without one is no file kind', () {
    expect(openedAs('/work/notes.docx'), isNull);
    expect(openedAs('/work/notes.anicel.docx'), isNull);
    expect(openedAs('/work/anicel'), isNull);
    expect(openedAs('/work.anicel/readme'), isNull);
    expect(openedAs('/work/trailing.'), isNull);
  });

  test('a provider document is told by its own name, not its URI', () {
    ProviderDocuments.remember(
      const ProviderDocument(
        uri: 'content://drive/document/41',
        name: 'Layout.anicel',
      ),
    );
    expect(openedAs('content://drive/document/41'), OpenedAs.project);
  });

  test('the picker accepts exactly what some door takes', () {
    for (final extension in openableExtensions) {
      expect(openedAs('x.$extension'), isNotNull, reason: extension);
    }
    for (final extension in [
      ...projectOpenExtensions,
      ...imageFileExtensions,
      ...videoFileExtensions,
      ...audioFileExtensions,
      ...pdfFileExtensions,
      ...brushFileExtensions,
      ...fontFileExtensions,
      ...shortcutFileExtensions,
    ]) {
      expect(openableExtensions, contains(extension), reason: extension);
    }
    expect(openableExtensions.toSet().length, openableExtensions.length);
  });
}
