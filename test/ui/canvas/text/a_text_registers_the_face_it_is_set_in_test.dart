import 'dart:io';
import 'dart:typed_data';

import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_font_file.dart';
import 'package:anicel/src/services/commands/update_project_fonts_command.dart';
import 'package:anicel/src/services/font_file_reader.dart';
import 'package:anicel/src/ui/brush/tool_settings_panel.dart';
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/text/canvas_letter_faces.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/cel_text_tool_harness.dart';
import '../../../helpers/font_file_fixture.dart';
import '../../../helpers/font_library_in_memory.dart';
import '../../../helpers/project_scratch_folder.dart';

/// 🚨★★★A TEXT REGISTERS THE FACE IT IS SET IN WITH ITS PROJECT (R9-rest) —
/// the real app: a face picked in the real list, a text typed with a real
/// keyboard, and the project's own list of fonts read afterwards.
///
/// Settled in the text tool's consultation (2026-10-06, item ③ — 「쓴
/// 글꼴은 프로젝트에 같이 저장한다」, answered 「권장대로」), and of how long
/// a font then stays, the user's own words: 🗣️「뺄때까지 두는게 맞지않나
/// 싶은데. 글꼴을 사실상 등록하는거잖아. 프리미어프로처럼」. When a font
/// is registered and where it is taken out are this session's choice
/// until `R9-rest-Q3` is answered: with the text first set in it, and in
/// the list a face is picked from.
///
/// What each part does is measured where it lives (`project_fonts_test`,
/// `imported_fonts_test`, `text_tool_faces_test`). Here: they are wired.
void main() {
  Finder row(String name) => find.byKey(ValueKey<String>('text-tool-$name'));

  final sans = fontFileSaying(family: 'Probe Sans');
  final sansFacts = readFontFaceFacts(sans)!;
  final kept = fontFileSaying(family: 'Kept At Home', fsType: 2);

  FontLibraryInMemory deviceWith(Map<String, Uint8List> files) =>
      FontLibraryInMemory()
        ..files.addAll(files)
        ..index = [
          for (final MapEntry(key: file, value: bytes) in files.entries)
            (file: file, facts: readFontFaceFacts(bytes)!),
        ];

  /// Lets what the engine was asked — outside the test's own clock — come
  /// back, until [done].
  Future<void> letTheEngineAnswer(
    WidgetTester tester,
    bool Function() done,
  ) async {
    for (var turn = 0; turn < 100 && !done(); turn += 1) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    expect(done(), isTrue, reason: 'the engine did not answer');
  }

  Future<void> openFaces(WidgetTester tester) async {
    await tester.tap(row('font'));
    await pumpFrames(tester);
  }

  /// The real app on a device that holds [library]'s fonts, the text tool
  /// in hand and its settings on screen — and the pixel the tests work at.
  /// (In a tall window: see `the_tool_settings_set_the_text_in_hand_test`.)
  Future<Offset> textToolInHand(
    WidgetTester tester,
    FontLibraryInMemory library, {
    Project? project,
  }) async {
    await pumpTextToolApp(
      tester,
      size: const Size(1600, 1500),
      fonts: library,
      project: project,
    );
    await takeTextTool(tester);
    final settingsGroup = EditorWorkspace.railGroupId(right: false, slot: 2);
    await tester.tap(find.byKey(ValueKey<String>('rail-group-$settingsGroup')));
    await pumpFrames(tester);
    expect(find.byType(ToolSettingsPanel), findsOneWidget, reason: '⛔fixture');
    return canvasPixelInView(tester);
  }

  /// Picks [family] in the real list as the next text's face, and waits
  /// for the engine to have it.
  Future<void> pickFace(WidgetTester tester, String family) async {
    await openFaces(tester);
    await tester.tap(row('font-$family'));
    await pumpFrames(tester);
    await letTheEngineAnswer(
      tester,
      () => CanvasLetterFaces.current.engineFamilyOf(family) != null,
    );
  }

  /// 「hi」 typed at [c] and let go of by a click away — on the cel.
  Future<void> hiOnTheCel(WidgetTester tester, Offset c) async {
    await clickAt(tester, c.dx, c.dy);
    await typeText(tester, 'hi');
    await clickAt(tester, c.dx + 300, c.dy + 200);
    expect(celOf(tester).texts, hasLength(1), reason: '⛔fixture: it landed');
  }

  List<ProjectFontFile> fontsOfTheProject(WidgetTester tester) =>
      sessionOf(tester).repository.requireProject().fonts;

  Future<void> tapKey(WidgetTester tester, String key) async {
    final target = find.byKey(ValueKey<String>(key));
    await tester.ensureVisible(target);
    await tester.pumpAndSettle();
    await tester.tap(target);
    await tester.pumpAndSettle();
  }

  /// Another project comes on screen, in a tab of its own.
  Future<void> newProject(WidgetTester tester) async {
    await tapKey(tester, 'top-strip-project-button');
    await tapKey(tester, 'menu-file-new');
  }

  /// The font file of [sans] on a real disk, for what reads a font by its
  /// path — its path.
  String sansOnDisk() {
    final directory = Directory.systemTemp.createTempSync('anicel_font_kept_');
    deleteAfterSessionEnds(directory);
    final file = File('${directory.path}/font-1.ttf')..writeAsBytesSync(sans);
    return file.path;
  }

  final carried = ProjectFontFile(carriedAs: 'font-1.ttf', facts: sansFacts);

  testWidgets('🚨a text typed in a face this device was brought registers '
      'the font with the project — in the SAME step as the text: one undo '
      'takes both back, and one redo puts both back', (tester) async {
    final c = await textToolInHand(tester, deviceWith({'font-1.ttf': sans}));
    await pickFace(tester, 'Probe Sans');
    expect(fontsOfTheProject(tester), isEmpty, reason: 'picking is not using');
    final history = sessionOf(tester).historyManager;
    final steps = history.undoCount;

    await hiOnTheCel(tester, c);

    expect(
      celOf(tester).texts.single.content.spans.single.style.fontFamily,
      'Probe Sans',
      reason: '⛔fixture',
    );
    expect(fontsOfTheProject(tester), [
      ProjectFontFile(carriedAs: 'font-1.ttf', facts: sansFacts),
    ]);
    expect(history.undoCount, steps + 1, reason: 'one step, text and font');

    history.undo();
    await pumpFrames(tester);

    expect(celOf(tester).texts, isEmpty);
    expect(fontsOfTheProject(tester), isEmpty);

    history.redo();
    await pumpFrames(tester);

    expect(celOf(tester).texts, hasLength(1));
    expect(fontsOfTheProject(tester), hasLength(1));
  });

  testWidgets('a second text in the same face registers nothing more, and '
      'one in the app\'s own face registers nothing', (tester) async {
    final c = await textToolInHand(tester, deviceWith({'font-1.ttf': sans}));
    await hiOnTheCel(tester, c);
    expect(fontsOfTheProject(tester), isEmpty, reason: 'the app\'s own face');

    await pickFace(tester, 'Probe Sans');
    await clickAt(tester, c.dx - 200, c.dy - 100);
    await typeText(tester, 'ab');
    await clickAt(tester, c.dx + 300, c.dy + 200);
    await clickAt(tester, c.dx - 200, c.dy + 150);
    await typeText(tester, 'cd');
    await clickAt(tester, c.dx + 300, c.dy + 200);

    expect(celOf(tester).texts, hasLength(3), reason: '⛔fixture');
    expect(fontsOfTheProject(tester), hasLength(1));
  });

  testWidgets('🚨⛔a font its maker does not let ride in a document that '
      'is edited is NOT registered (R9-rest-Q1 ⓐ) — its text is set in it '
      'on this device all the same', (tester) async {
    final c = await textToolInHand(tester, deviceWith({'font-1.ttf': kept}));
    await pickFace(tester, 'Kept At Home');

    await hiOnTheCel(tester, c);

    expect(
      celOf(tester).texts.single.content.spans.single.style.fontFamily,
      'Kept At Home',
    );
    expect(fontsOfTheProject(tester), isEmpty);
  });

  testWidgets('🚨the list a face is picked from shows it as the PROJECT\'S '
      'from then on, and its 빼기 takes it out — a step of its own, which '
      'an undo takes back', (tester) async {
    final c = await textToolInHand(tester, deviceWith({'font-1.ttf': sans}));
    await openFaces(tester);
    expect(row('project-font-Probe Sans'), findsNothing, reason: 'not yet');
    await tester.tapAt(const Offset(4, 4));
    await pumpFrames(tester);
    await pickFace(tester, 'Probe Sans');
    await hiOnTheCel(tester, c);
    final history = sessionOf(tester).historyManager;
    final steps = history.undoCount;

    await openFaces(tester);
    expect(row('project-font-Probe Sans'), findsOneWidget);
    expect(row('font-Probe Sans'), findsOneWidget, reason: 'the device\'s');
    await tester.tap(row('project-font-Probe Sans-take-out'));
    await pumpFrames(tester);

    expect(fontsOfTheProject(tester), isEmpty);
    expect(history.undoCount, steps + 1);
    expect(celOf(tester).texts, hasLength(1), reason: 'its text stays');
    await openFaces(tester);
    expect(row('project-font-Probe Sans'), findsNothing);
    await tester.tapAt(const Offset(4, 4));
    await pumpFrames(tester);

    history.undo();
    await pumpFrames(tester);

    expect(fontsOfTheProject(tester), hasLength(1));
    await openFaces(tester);
    expect(row('project-font-Probe Sans'), findsOneWidget);
  });

  testWidgets('🚨★★★a font taken OFF THIS DEVICE while a project carries '
      'it and is not saved stays the PROJECT\'S (「품은 순간 데이터를 '
      '가지고있고 불변」): the project takes its bytes before the file '
      'goes, its letters are still set in it, and its row is the '
      'project\'s own', (tester) async {
    final library = deviceWith({'font-1.ttf': sans})
      ..onDisk['font-1.ttf'] = sansOnDisk();
    final c = await textToolInHand(tester, library);
    await pickFace(tester, 'Probe Sans');
    await hiOnTheCel(tester, c);
    final room = sessionOf(tester).mediaStagingStore;
    expect(room.findNamed('font-1.ttf'), isNull, reason: 'nothing copied yet');

    await openFaces(tester);
    await tester.tap(row('font-Probe Sans-delete'));
    // The project copies the file off the disk before the library lets go
    // of it — outside the test's own clock.
    await letTheEngineAnswer(tester, () => library.files.isEmpty);

    final kept = room.findNamed('font-1.ttf');
    expect(kept, isNotNull, reason: 'the project took its bytes first');
    expect(File(kept!.path).readAsBytesSync(), sans);
    expect(fontsOfTheProject(tester), hasLength(1));
    expect(
      CanvasLetterFaces.current.holds('Probe Sans'),
      isTrue,
      reason: 'its letters are still set in it — out of the room',
    );
    await openFaces(tester);
    expect(row('font-Probe Sans'), findsNothing, reason: 'not the device\'s');
    expect(row('project-font-Probe Sans'), findsOneWidget);
  });

  testWidgets('🚨a project BEHIND the one on screen takes its bytes too '
      'when the font is taken off this device: every open project that '
      'carries it', (tester) async {
    final library = deviceWith({'font-1.ttf': sans})
      ..onDisk['font-1.ttf'] = sansOnDisk();
    final c = await textToolInHand(tester, library);
    await pickFace(tester, 'Probe Sans');
    await hiOnTheCel(tester, c);
    final behind = sessionOf(tester);
    await newProject(tester);
    expect(sessionOf(tester), isNot(same(behind)), reason: '⛔fixture');

    await openFaces(tester);
    await tester.tap(row('font-Probe Sans-delete'));
    await letTheEngineAnswer(tester, () => library.files.isEmpty);

    final kept = behind.mediaStagingStore.findNamed('font-1.ttf');
    expect(kept, isNotNull);
    expect(File(kept!.path).readAsBytesSync(), sans);
  });

  testWidgets('🚨a font taken OUT of the project on screen is, from that '
      'step on, not what its letters are set with — and an undo sets them '
      'with it again', (tester) async {
    // Within reach as a file, and not one of this device's own list: a
    // project from somewhere else, as far as the list of faces can tell.
    final library = FontLibraryInMemory()..onDisk['font-1.ttf'] = sansOnDisk();
    await textToolInHand(
      tester,
      library,
      project: textToolProject().copyWith(fonts: [carried]),
    );
    expect(CanvasLetterFaces.current.holds('Probe Sans'), isTrue);

    await openFaces(tester);
    expect(row('font-Probe Sans'), findsNothing, reason: '⛔fixture');
    await tester.tap(row('project-font-Probe Sans-take-out'));
    await pumpFrames(tester);

    expect(fontsOfTheProject(tester), isEmpty);
    expect(CanvasLetterFaces.current.holds('Probe Sans'), isFalse);

    // The app's own undo: the session tells whoever shows it.
    sessionOf(tester).undo();
    await pumpFrames(tester);

    expect(fontsOfTheProject(tester), [carried]);
    expect(CanvasLetterFaces.current.holds('Probe Sans'), isTrue);
  });

  testWidgets('🚨the list\'s 빼기 takes a font out of the project ON '
      'SCREEN — not out of one behind it that carries the very same '
      'font', (tester) async {
    await textToolInHand(
      tester,
      FontLibraryInMemory(),
      project: textToolProject().copyWith(fonts: [carried]),
    );
    final first = sessionOf(tester);
    await newProject(tester);
    final second = sessionOf(tester);
    second.historyManager.execute(
      UpdateProjectFontsCommand(
        repository: second.repository,
        fonts: [carried],
      ),
    );
    await pumpFrames(tester);
    await tapKey(tester, 'project-tab-0');
    expect(sessionOf(tester), same(first), reason: '⛔fixture');

    await openFaces(tester);
    await tester.tap(row('project-font-Probe Sans-take-out'));
    await pumpFrames(tester);

    expect(first.repository.requireProject().fonts, isEmpty);
    expect(second.repository.requireProject().fonts, [carried]);
  });

  testWidgets('🚨⛔an edit that leaves the fonts as they were says nothing '
      'of them again: a project is made anew at every edit, its list of '
      'fonts with it — and saying them reads the project file', (tester) async {
    final c = await textToolInHand(tester, deviceWith({'font-1.ttf': sans}));
    await pickFace(tester, 'Probe Sans');
    await hiOnTheCel(tester, c);
    final fonts = tester
        .widget<ToolSettingsPanel>(find.byType(ToolSettingsPanel))
        .textFonts!;
    var said = 0;
    fonts.addListener(() => said += 1);

    // Another text in the same face: the project is another, its fonts
    // are what they were.
    await clickAt(tester, c.dx - 200, c.dy - 100);
    await typeText(tester, 'ab');
    await clickAt(tester, c.dx + 300, c.dy + 200);

    expect(celOf(tester).texts, hasLength(2), reason: '⛔fixture: an edit');
    expect(fontsOfTheProject(tester), hasLength(1), reason: '⛔fixture');
    expect(said, 0);
  });
}
