import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/services/color_palette_file_service.dart';
import 'package:anicel/src/services/persistence/app_support_path.dart'
    show appSettingsFilePath;
import 'package:anicel/src/services/persistence/folder_grant.dart';
import 'package:anicel/src/services/persistence/settings_file.dart';
import 'package:anicel/src/ui/color/color_panels.dart';
import 'package:anicel/src/ui/color/palette_file_import.dart';
import 'package:anicel/src/ui/dialogs/app_confirm_dialog.dart';
import 'package:anicel/src/ui/text/app_strings.dart';

import '../../helpers/settle_async.dart';
import '../../helpers/temp_dir.dart';

/// I-142 (유저 2026-10-29): 「팔레트 내보내기(한 팔레트 내보냄) … 임포트도
/// 물론」 — and how (I-142-Q1): 「주인 자리에서 내보내고, 읽기는 「파일
/// 열기」 하나」. A palette leaves from its own ⋯ as the palette store's
/// document holding just it, and what 「파일 열기」 hands back goes on top
/// of the palettes.
void main() {
  const red = 0xFFE53935;
  const blue = 0xFF1E88E5;

  final skin = NamedPalette(
    id: 'p1',
    name: 'Skin',
    slots: NamedPalette.placed(const [red, null, blue]),
    locked: true,
  );
  final sky = NamedPalette(
    id: 'p2',
    name: 'Sky',
    slots: NamedPalette.placed(const [blue]),
    folded: true,
  );

  ColorPaletteState mine() => ColorPaletteState(
    palettes: [
      NamedPalette(
        id: 'p1',
        name: 'Mine',
        slots: NamedPalette.placed(const [red]),
      ),
      NamedPalette(
        id: 'p3',
        name: 'Other',
        slots: NamedPalette.placed(const [blue]),
      ),
    ],
    defaultId: 'p3',
  );

  /// What [palette] is, beside its id — a list, which a matcher compares
  /// deep (a record's list compares by identity).
  List<Object?> shapeOf(NamedPalette palette) =>
      [palette.name, palette.slots, palette.folded, palette.locked];

  Uint8List bytesOf(String text) => Uint8List.fromList(utf8.encode(text));

  group('the file', () {
    test('a palette comes back as it left — its name, its places, how it '
        'stands', () {
      for (final palette in [skin, sky]) {
        expect(
          [
            for (final back in palettesInSettingsFile(
              paletteSettingsFile(palette),
            )!)
              shapeOf(back),
          ],
          [shapeOf(palette)],
        );
      }
    });

    test('it is the palette store\'s own document, under the name of the '
        'store\'s file', () {
      expect(
        appSettingsFilePath(ColorPaletteFileService.fileName),
        ColorPaletteFileService.defaultColorPaletteFilePath(),
      );
      final documents = decodeSettingsFile(paletteSettingsFile(skin))!;
      expect(documents.keys, [ColorPaletteFileService.fileName]);
      expect(
        documents.values.single['version'],
        ColorPaletteFileService.version,
      );
    });

    test('a file this build cannot read holds no palette', () {
      String withDocument(Map<String, dynamic> document) =>
          encodeSettingsFile({ColorPaletteFileService.fileName: document});
      final written = decodeSettingsFile(paletteSettingsFile(skin))!.values
          .single;

      expect(palettesInSettingsFile('not json'), isNull);
      expect(palettesInSettingsFile(encodeSettingsFile({})), isNull);
      expect(
        palettesInSettingsFile(
          withDocument({
            ...written,
            'version': ColorPaletteFileService.version + 1,
          }),
        ),
        isNull,
      );
      expect(
        palettesInSettingsFile(withDocument({...written, 'palettes': []})),
        isNull,
      );
      expect(
        palettesInSettingsFile(withDocument({...written, 'palettes': 'x'})),
        isNull,
      );
      expect(
        palettesInSettingsFile(withDocument({...written, 'version': 'two'})),
        isNull,
        reason: 'a document the store would throw on is no palette either',
      );
      expect(
        palettesInSettingsFile(withDocument(written)),
        hasLength(1),
        reason: '⛔전제: the document as it was written is read',
      );
    });
  });

  group('brought in', () {
    test('on top, in the file\'s order, each under an id of its own — '
        'the default stays', () {
      final after = mine().withBrought([skin, sky]);

      expect([for (final palette in after.palettes) palette.name], [
        'Skin',
        'Sky',
        'Mine',
        'Other',
      ]);
      expect(
        {for (final palette in after.palettes) palette.id},
        hasLength(4),
      );
      expect(after.palettes.take(2).map((palette) => palette.id), [
        isNot(anyOf('p1', 'p3')),
        isNot(anyOf('p1', 'p3')),
      ]);
      expect(after.defaultId, 'p3');
      expect(after.palettes[2].slots, mine().palettes.first.slots);
    });

    test('「파일 열기」 hands a palette file in: the palettes after, and a '
        'line for each it brought', () {
      final (:palettes, :said) = importPaletteFile(
        mine(),
        'Skin.anipalette',
        bytesOf(paletteSettingsFile(skin)),
      );

      expect([for (final palette in palettes!.palettes) palette.name], [
        'Skin',
        'Mine',
        'Other',
      ]);
      expect(shapeOf(palettes.palettes.first), shapeOf(skin));
      expect(said, AppText.strings.paletteBrought('Skin'));
    });

    test('a file that holds no palette changes nothing, and is named', () {
      for (final bytes in [
        bytesOf('not json'),
        Uint8List.fromList([0xFF, 0xFE, 0x00]),
      ]) {
        final (:palettes, :said) = importPaletteFile(
          mine(),
          'Broken.anipalette',
          bytes,
        );
        expect(palettes, isNull);
        expect(said, AppText.strings.imUnreadable('Broken.anipalette'));
      }
    });
  });

  group('the palette\'s ⋯', () {
    late Directory folder;

    setUp(() => folder = Directory.systemTemp.createTempSync('qa_palette_'));
    tearDown(() {
      FolderPicker.debugOperatingSystem = null;
      FolderPicker.debugSaveDestinationPicker = null;
      deleteTempQuietly(folder);
    });

    Finder byKey(String key) => find.byKey(ValueKey<String>(key));
    final notice = find.byType(AppConfirmDialog);

    /// Sky's 「내보내기」 pressed, the save window answering [answer] for the
    /// name it was asked under — every name it was asked under, and what
    /// was said after (null: nothing). Where [says] is false nothing is
    /// waited for past the question: a backed-out save does no IO, and a
    /// wait for a notice that never comes would sit out its whole patience.
    Future<({List<String> asked, String? said})> exportSky(
      WidgetTester tester,
      Future<FolderGrant> Function(String suggestedName) answer, {
      bool says = true,
    }) async {
      FolderPicker.debugOperatingSystem = 'windows';
      final asked = <String>[];
      FolderPicker.debugSaveDestinationPicker = ({
        required String suggestedName,
        String? initialDirectory,
      }) {
        asked.add(suggestedName);
        return answer(suggestedName);
      };
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 300,
              height: 600,
              child: ColorPickerPanel(
                kind: ColorPickerKind.palette,
                color: red,
                palette: ColorPaletteState(
                  palettes: [skin, sky],
                  defaultId: 'p1',
                ),
                onColorChanged: (_) {},
                onPaletteChanged: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      await tester.tap(byKey('palette-p2-more'), kind: PointerDeviceKind.mouse);
      await tester.pumpAndSettle();
      await tester.tap(byKey('palette-export'), kind: PointerDeviceKind.mouse);
      await settleAsync(
        tester,
        () => asked.isNotEmpty,
        everyFrame: tester.pump,
      );
      if (says) {
        await settleAsync(
          tester,
          () => notice.evaluate().isNotEmpty,
          everyFrame: tester.pump,
        );
      } else {
        await tester.pumpAndSettle();
      }
      return (
        asked: asked,
        said: notice.evaluate().isEmpty
            ? null
            : tester.widget<AppConfirmDialog>(notice).message,
      );
    }

    testWidgets('「내보내기」 asks where under the palette\'s name, writes '
        'the file 「파일 열기」 reads back, and says so', (tester) async {
      final (:asked, :said) = await exportSky(
        tester,
        (name) async => FolderGrant.granted(
          path: '${folder.path}/$name',
          kind: GrantKind.file,
        ),
      );

      expect(asked, ['Sky.$anicelPaletteExtension']);
      final written = File('${folder.path}/${asked.single}');
      expect([
        for (final palette in palettesInSettingsFile(
          written.readAsStringSync(),
        )!)
          shapeOf(palette),
      ], [shapeOf(sky)]);
      expect(said, AppText.strings.settingsExported('Sky'));
    });

    testWidgets('backed out of, nothing is written and nothing said', (
      tester,
    ) async {
      final (:asked, :said) = await exportSky(
        tester,
        (_) async => const FolderGrant.cancelled(),
        says: false,
      );

      expect(asked, hasLength(1));
      expect(said, isNull);
      expect(folder.listSync(), isEmpty);
    });

    testWidgets('a place not chosen and a file not written are each said', (
      tester,
    ) async {
      final unchosen = await exportSky(
        tester,
        (_) async => throw StateError('no window'),
      );
      expect(
        unchosen.said,
        AppText.strings.fileExportPlaceUnchosen('Bad state: no window'),
      );
      await tester.tap(find.byKey(const ValueKey<String>('app-notice-close')));
      await tester.pumpAndSettle();

      final unwritten = await exportSky(
        tester,
        (name) async => FolderGrant.granted(
          path: '${folder.path}/no/such/folder/$name',
          kind: GrantKind.file,
        ),
      );
      expect(
        unwritten.said,
        startsWith(AppText.strings.settingsExportNotWritten('')),
      );
    });
  });
}
