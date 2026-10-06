import 'dart:typed_data';

import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/cel_text.dart';
import 'package:anicel/src/models/font_face_facts.dart';
import 'package:anicel/src/models/text_cel_style.dart';
import 'package:anicel/src/ui/brush/cel_text_commands.dart';
import 'package:anicel/src/ui/brush/picked_file.dart';
import 'package:anicel/src/ui/brush/text_tool_options.dart';
import 'package:anicel/src/ui/brush/text_tool_settings.dart';
import 'package:anicel/src/ui/text/app_strings.dart';
import 'package:anicel/src/ui/text/canvas_letter_faces.dart';
import 'package:anicel/src/ui/text/imported_fonts.dart';
import 'package:anicel/src/ui/theme/app_theme.dart';
import 'package:anicel/src/ui/widgets/panel_flyout.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/cel_text_hand.dart';
import '../../helpers/font_file_fixture.dart';
import '../../helpers/font_library_in_memory.dart';

/// R9-rest (the text tool's faces): THE LIST A FACE IS PICKED FROM — the
/// drawing 유저 took on 2026-10-06: 「글꼴」 and a ＋ over it, the app's own
/// faces, then the ones this device was brought, each with its delete.
///
/// 🗣️유저 2026-10-06: 「유저가 알아서 자기가 가지고있는 글꼴 넣는게
/// 아니야?」 — the ＋ picks a file. And of a face its maker does not let ride
/// in a project (R9-rest-Q1 ⓐ): 「글꼴 고를때든 도구 설정에서 해당 글꼴에
/// 이 글꼴은 편집하는 문서에 넣도록 허용되지않아서 다른 기기에서 열면
/// 바뀐다 이런식으로 적어두자」.
///
/// What the library keeps and what the engine is handed are measured where
/// they live (`imported_fonts_test`, `canvas_letter_faces_test`); here: the
/// list shows them, and a hand on it reaches the text.
void main() {
  const plain = TextLetterStyle(fontSize: 16);

  CelTextContent said(String words, [TextLetterStyle style = plain]) =>
      CelTextContent(
        spans: [CelTextSpan(text: words, style: style)],
        anchor: CanvasPoint(x: 8, y: 8),
      );

  Finder row(String name) => find.byKey(ValueKey<String>('text-tool-$name'));

  /// The settings over a hand that holds [text] by its box, or nothing —
  /// on a device that was brought [brought], and whose file dialog hands
  /// over what [picker] does.
  Future<({TextHand hand, ImportedFonts fonts, FontLibraryInMemory library})>
  pumpFaces(
    WidgetTester tester, {
    CelTextContent? text,
    List<Uint8List> brought = const [],
    FilePicker? picker,
    bool keepsFonts = true,
    ProjectFontsOnScreen? project,
  }) async {
    final library = FontLibraryInMemory();
    final fonts = ImportedFonts(
      service: library,
      picker: picker ?? () async => null,
      // The engine is not asked: no letter is drawn here.
      register: (bytes, {required engineFamily}) async {},
    );
    addTearDown(fonts.dispose);
    for (final bytes in brought) {
      expect((await fonts.importBytes(bytes)).refusal, isNull);
    }
    if (project != null) {
      fonts.showCarried(project);
    }
    final hand = textHand(
      bake: bakesAtOnce,
      text: text,
      next: const TextToolOptions(letters: plain),
    );
    final commands = CelTextCommands()..bind(hand.tool);
    addTearDown(commands.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 260,
              height: 640,
              child: TextToolSettings(
                options: hand.options,
                commands: commands,
                fonts: keepsFonts ? fonts : null,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    return (hand: hand, fonts: fonts, library: library);
  }

  Future<void> openList(WidgetTester tester) async {
    await tester.tap(row('font'));
    await tester.pumpAndSettle();
  }

  /// The rows of the open list, top to bottom, by what each says.
  List<String> listed(WidgetTester tester) => [
    for (final item in tester.widgetList<PopupMenuItem<PanelFlyoutItem>>(
      find.byType(PopupMenuItem<PanelFlyoutItem>),
    ))
      if (item.value case final face?) face.label,
  ];

  PanelFlyoutItem face(WidgetTester tester, String name) => tester
      .widget<PopupMenuItem<PanelFlyoutItem>>(row('font-$name'))
      .value!;

  String faceInUse(WidgetTester tester) =>
      tester.widget<PanelFlyoutButton>(row('font')).label;

  final sans = fontFileSaying(family: 'Probe Sans');
  final serif = fontFileSaying(family: 'Probe Serif', fsType: 8);
  final kept = fontFileSaying(family: 'Kept At Home', fsType: 2);

  group('the list', () {
    testWidgets('🚨is the app\'s own faces, then the ones this device was '
        'brought — by name — under 「글꼴」 and its ＋', (tester) async {
      await pumpFaces(tester, brought: [serif, sans]);

      await openList(tester);

      expect(listed(tester), [
        AppTypography.bundledFamily,
        ...AppTypography.bundledFallback,
        'Probe Sans',
        'Probe Serif',
      ]);
      expect(
        find.descendant(
          of: row('font-import-header'),
          matching: find.text(AppText.strings.textToolFont),
        ),
        findsOneWidget,
      );
      expect(row('font-import'), findsOneWidget);
      // A plus, in the colour a plus wears everywhere.
      expect(
        tester
            .widget<Icon>(
              find.descendant(
                of: row('font-import'),
                matching: find.byIcon(Icons.add),
              ),
            )
            .color,
        AppColors.addGlyph(enabled: true),
      );
      // One rule between the app's faces and the ones brought.
      expect(find.byType(PopupMenuDivider), findsOneWidget);
      // Each brought face with a delete of its own; the app's with none.
      expect(row('font-Probe Sans-delete'), findsOneWidget);
      expect(row('font-Probe Serif-delete'), findsOneWidget);
      expect(face(tester, AppTypography.bundledFamily).action, isNull);
      expect(face(tester, 'Nanum Gothic').action, isNull);
      expect(
        face(tester, 'Probe Sans').action!.does,
        PanelFlyoutActionDoes.deletes,
      );
    });

    testWidgets('on a device that was brought none it is the app\'s faces, '
        'and the ＋', (tester) async {
      await pumpFaces(tester);

      await openList(tester);

      expect(listed(tester), [
        AppTypography.bundledFamily,
        ...AppTypography.bundledFallback,
      ]);
      expect(row('font-import'), findsOneWidget);
      expect(find.byType(PopupMenuDivider), findsNothing);
    });

    testWidgets('in a host that keeps no fonts there is nothing to bring: '
        'the caption, the app\'s faces, and no ＋', (tester) async {
      await pumpFaces(tester, brought: [sans], keepsFonts: false);

      await openList(tester);

      expect(listed(tester), [
        AppTypography.bundledFamily,
        ...AppTypography.bundledFallback,
      ]);
      expect(find.text(AppText.strings.textToolFont), findsWidgets);
      expect(row('font-import'), findsNothing);
    });

    testWidgets('🚨a face that may NOT ride in a project says so at its own '
        'row — and one that may says nothing', (tester) async {
      await pumpFaces(tester, brought: [sans, kept]);

      await openList(tester);

      expect(
        face(tester, 'Kept At Home').warning,
        AppText.strings.textToolFontStaysOnThisDevice,
      );
      expect(
        find.descendant(
          of: row('font-Kept At Home'),
          matching: find.text(AppText.strings.textToolFontStaysOnThisDevice),
        ),
        findsOneWidget,
      );
      expect(face(tester, 'Probe Sans').warning, isNull);
      expect(face(tester, AppTypography.bundledFamily).warning, isNull);
    });

    testWidgets('the face in use is the one marked', (tester) async {
      await pumpFaces(
        tester,
        text: said('ab', plain.copyWith(fontFamily: 'Probe Serif')),
        brought: [sans, serif],
      );

      expect(faceInUse(tester), 'Probe Serif');
      await openList(tester);

      // Named once: a face this device holds is not also listed as missing.
      expect(listed(tester), [
        AppTypography.bundledFamily,
        ...AppTypography.bundledFallback,
        'Probe Sans',
        'Probe Serif',
      ]);
      expect(face(tester, 'Probe Serif').selected, isTrue);
      expect(face(tester, 'Probe Sans').selected, isFalse);
      expect(face(tester, AppTypography.bundledFamily).selected, isFalse);
    });
  });

  group('a brought face picked', () {
    testWidgets('🚨is the face of the text in hand — one step — and of the '
        'next text', (tester) async {
      final (:hand, fonts: _, library: _) = await pumpFaces(
        tester,
        text: said('ab'),
        brought: [sans],
      );

      await openList(tester);
      await tester.tap(row('font-Probe Sans'));
      await tester.pumpAndSettle();

      expect(landedOn(hand.cel).spans.single.style.fontFamily, 'Probe Sans');
      expect(hand.host.ran, hasLength(1));
      expect(hand.options.value.letters.fontFamily, 'Probe Sans');
      expect(faceInUse(tester), 'Probe Sans');
    });

    testWidgets('🚨with nothing in hand it is the next text\'s — and it is '
        'read NOW, so that a press that begins a text finds it here', (
      tester,
    ) async {
      final (:hand, :fonts, :library) = await pumpFaces(
        tester,
        brought: [sans],
      );
      expect(library.read, isEmpty, reason: '⛔fixture: listed, not read');

      await openList(tester);
      expect(library.read, isEmpty, reason: 'opening the list reads none');
      await tester.tap(row('font-Probe Sans'));
      await tester.pumpAndSettle();

      expect(hand.options.value.letters.fontFamily, 'Probe Sans');
      expect(hand.host.ran, isEmpty);
      expect(faceInUse(tester), 'Probe Sans');
      expect(library.read, hasLength(1));
      expect(fonts.faces.engineFamilyOf('Probe Sans'), isNotNull);
    });
  });

  group('the ＋', () {
    Future<void> pressPlus(WidgetTester tester) async {
      await openList(tester);
      await tester.tap(row('font-import'));
      await tester.pumpAndSettle();
    }

    testWidgets('🚨brings the picked file as a font: it is listed, and it '
        'is the face picked — of the text in hand and of the next', (
      tester,
    ) async {
      final (:hand, :fonts, :library) = await pumpFaces(
        tester,
        text: said('ab'),
        picker: () async => (name: 'anything.bin', bytes: sans),
      );

      await pressPlus(tester);

      expect([for (final family in fonts.families) family.name], ['Probe Sans']);
      expect(library.files.values, [sans]);
      expect(landedOn(hand.cel).spans.single.style.fontFamily, 'Probe Sans');
      expect(hand.options.value.letters.fontFamily, 'Probe Sans');
      expect(faceInUse(tester), 'Probe Sans');
      expect(find.byKey(const ValueKey<String>('app-notice-close')), findsNothing);
      await openList(tester);
      expect(listed(tester), contains('Probe Sans'));
      expect(face(tester, 'Probe Sans').selected, isTrue);
    });

    testWidgets('🚨a file that is not a font is refused with a notice that '
        'says so, and nothing changes', (tester) async {
      final (:hand, :fonts, :library) = await pumpFaces(
        tester,
        text: said('ab'),
        picker: () async => (
          name: 'photo.png',
          bytes: Uint8List.fromList(List.filled(64, 7)),
        ),
      );

      await pressPlus(tester);

      expect(find.text(AppText.strings.textToolFontUnreadable), findsOneWidget);
      expect(fonts.families, isEmpty);
      expect(library.files, isEmpty);
      expect(landedOn(hand.cel).spans.single.style.fontFamily, isNull);
      expect(hand.host.ran, isEmpty);
      expect(faceInUse(tester), AppTypography.bundledFamily);

      await tester.tap(find.byKey(const ValueKey<String>('app-notice-close')));
      await tester.pumpAndSettle();
      expect(find.text(AppText.strings.textToolFontUnreadable), findsNothing);
    });

    testWidgets('🚨a font that may not ride in a project IS brought and '
        'picked — and the notice says what that means, when it is '
        'registered', (tester) async {
      final (:hand, :fonts, library: _) = await pumpFaces(
        tester,
        text: said('ab'),
        picker: () async => (name: 'kept.ttf', bytes: kept),
      );

      await pressPlus(tester);

      expect(
        find.text(AppText.strings.textToolFontStaysOnThisDevice),
        findsOneWidget,
      );
      expect(fonts.familyNamed('Kept At Home'), isNotNull);
      expect(landedOn(hand.cel).spans.single.style.fontFamily, 'Kept At Home');
    });

    testWidgets('a dialog closed without a file brings nothing, and says '
        'nothing', (tester) async {
      final (:hand, :fonts, library: _) = await pumpFaces(
        tester,
        text: said('ab'),
        picker: () async => null,
      );

      await pressPlus(tester);

      expect(fonts.families, isEmpty);
      expect(hand.host.ran, isEmpty);
      expect(find.byKey(const ValueKey<String>('app-notice-close')), findsNothing);
    });

    testWidgets('one of the app\'s own, picked as a file, is refused with '
        'its own sentence', (tester) async {
      final (hand: _, :fonts, library: _) = await pumpFaces(
        tester,
        picker: () async => (
          name: 'own.ttf',
          bytes: fontFileSaying(family: AppTypography.bundledFamily),
        ),
      );

      await pressPlus(tester);

      expect(find.text(AppText.strings.textToolFontIsTheApps), findsOneWidget);
      expect(fonts.families, isEmpty);
    });
  });

  group('a brought face\'s delete', () {
    testWidgets('🚨takes the face off this device — and picks nothing', (
      tester,
    ) async {
      final (:hand, :fonts, :library) = await pumpFaces(
        tester,
        text: said('ab'),
        brought: [sans, serif],
      );

      await openList(tester);
      await tester.tap(row('font-Probe Sans-delete'));
      await tester.pumpAndSettle();

      expect([for (final family in fonts.families) family.name], ['Probe Serif']);
      expect(library.files.values, [serif]);
      expect(hand.host.ran, isEmpty);
      expect(landedOn(hand.cel).spans.single.style.fontFamily, isNull);
      await openList(tester);
      expect(listed(tester), isNot(contains('Probe Sans')));
      expect(listed(tester), contains('Probe Serif'));
    });
  });

  group('🚨the fonts the PROJECT carries (유저 2026-10-06: 「뺄때까지 '
      '두는게 맞지않나 싶은데. 글꼴을 사실상 등록하는거잖아」)', () {
    PanelFlyoutItem projectFace(WidgetTester tester, String name) => tester
        .widget<PopupMenuItem<PanelFlyoutItem>>(row('project-font-$name'))
        .value!;

    /// A project on screen whose list names [families], the bytes of
    /// [readable] among them within reach — all of them, unless said — and
    /// a note of every family taken out of it.
    ({ProjectFontsOnScreen project, List<String> takenOut}) projectCarrying(
      List<String> families, {
      List<String>? readable,
    }) {
      final takenOut = <String>[];
      return (
        project: (
          files: () => [
            for (final family in readable ?? families)
              (
                name: 'ab12-cd34-${family.replaceAll(' ', '_')}.ttf',
                facts: FontFaceFacts(
                  family: family,
                  weight: 400,
                  italic: false,
                  fsType: 0,
                ),
                read: () async => Uint8List(4),
              ),
          ],
          families: () => families,
          takeOut: takenOut.add,
        ),
        takenOut: takenOut,
      );
    }

    testWidgets('🚨are listed as ITS OWN — under their own heading, between '
        'the app\'s faces and this device\'s — each with the taking of it '
        'out', (tester) async {
      final carrying = projectCarrying(['Probe Carried']);
      await pumpFaces(tester, brought: [sans], project: carrying.project);

      await openList(tester);

      expect(listed(tester), [
        AppTypography.bundledFamily,
        ...AppTypography.bundledFallback,
        'Probe Carried',
        'Probe Sans',
      ]);
      expect(find.text(AppText.strings.textToolFontsOfProject), findsOneWidget);
      expect(find.text(AppText.strings.textToolFontsOfDevice), findsOneWidget);
      final carried = projectFace(tester, 'Probe Carried');
      expect(carried.warning, isNull);
      expect(carried.action!.does, PanelFlyoutActionDoes.deletes);
      expect(carried.action!.tooltip, AppText.strings.textToolFontTakeOut);
      expect(row('project-font-Probe Carried-take-out'), findsOneWidget);
      expect(
        row('font-Probe Carried-delete'),
        findsNothing,
        reason: 'it is not this device\'s to delete',
      );
    });

    testWidgets('a project that carries none has no such heading — and the '
        'device\'s fonts still have theirs', (tester) async {
      await pumpFaces(
        tester,
        brought: [sans],
        project: projectCarrying(const []).project,
      );

      await openList(tester);

      expect(find.text(AppText.strings.textToolFontsOfProject), findsNothing);
      expect(find.text(AppText.strings.textToolFontsOfDevice), findsOneWidget);
    });

    testWidgets('🚨one picked is the next text\'s face — on a device that '
        'was never brought it', (tester) async {
      final (:hand, :fonts, library: _) = await pumpFaces(
        tester,
        project: projectCarrying(['Probe Carried']).project,
      );
      expect(fonts.families, isEmpty, reason: '⛔fixture');

      await openList(tester);
      await tester.tap(row('project-font-Probe Carried'));
      await tester.pumpAndSettle();

      expect(hand.options.value.letters.fontFamily, 'Probe Carried');
      expect(faceInUse(tester), 'Probe Carried');
    });

    testWidgets('🚨its 빼기 takes the family out of the PROJECT — and '
        'nothing off this device, which holds the same family', (tester) async {
      final carrying = projectCarrying(['Probe Sans']);
      final (hand: _, :fonts, :library) = await pumpFaces(
        tester,
        brought: [sans],
        project: carrying.project,
      );

      await openList(tester);
      await tester.tap(row('project-font-Probe Sans-take-out'));
      await tester.pumpAndSettle();

      expect(carrying.takenOut, ['Probe Sans']);
      expect(
        [for (final family in fonts.families) family.name],
        ['Probe Sans'],
      );
      expect(library.files.values, [sans]);
    });

    testWidgets('🚨one whose bytes are NOWHERE this device can read is the '
        'project\'s all the same, and says so at its own row — one this '
        'device holds too says nothing', (tester) async {
      await pumpFaces(
        tester,
        brought: [sans],
        project: projectCarrying(
          ['Dead Sans', 'Probe Sans'],
          readable: const [],
        ).project,
      );

      await openList(tester);

      expect(
        projectFace(tester, 'Dead Sans').warning,
        AppText.strings.textToolFontNotOnThisDevice,
      );
      expect(projectFace(tester, 'Probe Sans').warning, isNull);
    });

    testWidgets('a text written in one of them has no stray row of its own: '
        'its face is the project\'s row, and that is the one marked', (
      tester,
    ) async {
      await pumpFaces(
        tester,
        text: said(
          'ab',
          const TextLetterStyle(fontSize: 16, fontFamily: 'Probe Carried'),
        ),
        project: projectCarrying(['Probe Carried']).project,
      );

      await openList(tester);

      expect(row('font-Probe Carried'), findsNothing);
      expect(projectFace(tester, 'Probe Carried').selected, isTrue);
      expect(faceInUse(tester), 'Probe Carried');
    });
  });

  group('🚨a face a text is written in that this device does not hold', () {
    const elsewhere = TextLetterStyle(fontSize: 16, fontFamily: 'Far Sans');

    testWidgets('is named, as the one in use, and says what that means — '
        'and is nothing to pick or to delete', (tester) async {
      await pumpFaces(tester, text: said('ab', elsewhere), brought: [sans]);

      expect(faceInUse(tester), 'Far Sans');
      await openList(tester);

      expect(listed(tester), [
        AppTypography.bundledFamily,
        ...AppTypography.bundledFallback,
        'Far Sans',
        'Probe Sans',
      ]);
      final missing = face(tester, 'Far Sans');
      expect(missing.selected, isTrue);
      expect(missing.warning, AppText.strings.textToolFontNotOnThisDevice);
      expect(missing.onSelected, isNull);
      expect(missing.action, isNull);
      expect(face(tester, AppTypography.bundledFamily).selected, isFalse);
    });

    testWidgets('a face taken off this device while a text is written in '
        'it is that face from then on', (tester) async {
      final (hand: _, :fonts, library: _) = await pumpFaces(
        tester,
        text: said('ab', plain.copyWith(fontFamily: 'Probe Sans')),
        brought: [sans],
      );

      await openList(tester);
      await tester.tap(row('font-Probe Sans-delete'));
      await tester.pumpAndSettle();

      expect(fonts.families, isEmpty);
      expect(faceInUse(tester), 'Probe Sans');
      await openList(tester);
      expect(
        face(tester, 'Probe Sans').warning,
        AppText.strings.textToolFontNotOnThisDevice,
      );
      expect(row('font-Probe Sans-delete'), findsNothing);
    });

    testWidgets('picking one of the app\'s own in its place sets the text '
        'in that', (tester) async {
      final (:hand, fonts: _, library: _) = await pumpFaces(
        tester,
        text: said('ab', elsewhere),
      );

      await openList(tester);
      await tester.tap(row('font-${AppTypography.bundledFamily}'));
      await tester.pumpAndSettle();

      expect(landedOn(hand.cel).spans.single.style.fontFamily, isNull);
      expect(faceInUse(tester), AppTypography.bundledFamily);
    });

    testWidgets('letters that do not agree on their face name no missing '
        'one, and mark none', (tester) async {
      await pumpFaces(
        tester,
        text: CelTextContent(
          spans: const [
            CelTextSpan(text: 'ab', style: plain),
            CelTextSpan(text: 'cd', style: elsewhere),
          ],
          anchor: CanvasPoint(x: 8, y: 8),
        ),
      );

      expect(faceInUse(tester), '—');
      await openList(tester);

      expect(listed(tester), [
        AppTypography.bundledFamily,
        ...AppTypography.bundledFallback,
      ]);
      expect(face(tester, AppTypography.bundledFamily).selected, isFalse);
      expect(CanvasLetterFaces.isAppFace('Far Sans'), isFalse);
    });
  });
}
