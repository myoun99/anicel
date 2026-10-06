import 'dart:async';
import 'dart:io';

import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/cel_text.dart';
import 'package:anicel/src/models/text_cel_style.dart';
import 'package:anicel/src/services/font_file_reader.dart';
import 'package:anicel/src/ui/brush/tool_settings_panel.dart';
import 'package:anicel/src/ui/canvas/text/cel_text_chrome.dart';
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/text/canvas_letter_faces.dart';
import 'package:file_selector/file_selector.dart' show XFile, XTypeGroup;
import 'package:file_selector_platform_interface/file_selector_platform_interface.dart'
    show FileSelectorPlatform;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/cel_text_tool_harness.dart';
import '../../../helpers/font_file_fixture.dart';
import '../../../helpers/font_library_in_memory.dart';
import '../../../helpers/project_scratch_folder.dart';

/// R9-rest (the text tool's faces): THE REAL APP KEEPS THE DEVICE'S FONTS
/// — the workspace reads their index, stands them as the run's faces, and
/// hands them to the text tool's settings; and the tool on the canvas hears
/// when a face arrives.
///
/// What each part does is measured where it lives. Here: they are wired.
void main() {
  Finder row(String name) => find.byKey(ValueKey<String>('text-tool-$name'));

  final sans = fontFileSaying(family: 'Probe Sans');

  FontLibraryInMemory deviceWithProbeSans() => FontLibraryInMemory()
    ..files['font-1.ttf'] = sans
    ..index = [(file: 'font-1.ttf', facts: readFontFaceFacts(sans)!)];

  /// The real app with the text tool in hand and its settings on screen, on
  /// a device that holds [library]'s fonts. (In a tall window: see
  /// `the_tool_settings_set_the_text_in_hand_test`.)
  Future<void> pumpWithSettings(
    WidgetTester tester,
    FontLibraryInMemory library,
  ) async {
    await pumpTextToolApp(
      tester,
      size: const Size(1600, 1500),
      fonts: library,
    );
    await takeTextTool(tester);
    final settingsGroup = EditorWorkspace.railGroupId(right: false, slot: 2);
    await tester.tap(find.byKey(ValueKey<String>('rail-group-$settingsGroup')));
    await pumpFrames(tester);
    expect(find.byType(ToolSettingsPanel), findsOneWidget, reason: '⛔fixture');
  }

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

  testWidgets('🚨the fonts this device was brought are the run\'s faces '
      'while the app is up — read by their index alone — and nobody\'s '
      'when it is gone', (tester) async {
    final library = deviceWithProbeSans();

    await pumpWithSettings(tester, library);

    expect(CanvasLetterFaces.current.holds('Probe Sans'), isTrue);
    expect(library.read, isEmpty, reason: 'no file is opened to list it');

    await tester.pumpWidget(const SizedBox());
    await tester.pump();

    expect(CanvasLetterFaces.current.holds('Probe Sans'), isFalse);
  });

  testWidgets('🚨the real panel lists them, with the ＋ — and a face picked '
      'there is the next text\'s, and is sent for at once', (tester) async {
    final library = deviceWithProbeSans();
    await pumpWithSettings(tester, library);

    await tester.tap(row('font'));
    await pumpFrames(tester);

    expect(row('font-Probe Sans'), findsOneWidget);
    expect(row('font-import'), findsOneWidget);
    expect(library.read, isEmpty);

    await tester.tap(row('font-Probe Sans'));
    await pumpFrames(tester);

    expect(
      textToolOf(tester).host.options.letters.fontFamily,
      'Probe Sans',
    );
    expect(
      library.read,
      ['font-1.ttf'],
      reason: 'the tool in hand sends for the next text\'s face',
    );
  });

  testWidgets('🚨the ＋ in the real panel opens the platform\'s own file '
      'dialog, EVERY file offered, and brings the file that was picked — '
      'whatever it was called', (tester) async {
    final directory = Directory.systemTemp.createTempSync('anicel_font_pick_');
    deleteAfterSessionEnds(directory);
    final picked = File('${directory.path}/whatever.bin')
      ..writeAsBytesSync(sans);
    final real = FileSelectorPlatform.instance;
    final dialog = _HandsOver(picked.path);
    FileSelectorPlatform.instance = dialog;
    addTearDown(() => FileSelectorPlatform.instance = real);
    final library = FontLibraryInMemory();
    await pumpWithSettings(tester, library);

    await tester.tap(row('font'));
    await pumpFrames(tester);
    await tester.tap(row('font-import'));
    // The picked file is read off the disk, outside the test's own clock.
    await letTheEngineAnswer(
      tester,
      () => CanvasLetterFaces.current.holds('Probe Sans'),
    );

    expect(dialog.filters, [isEmpty], reason: 'one dialog, no filter');
    expect(library.files.values, [sans]);
    expect(
      textToolOf(tester).host.options.letters.fontFamily,
      'Probe Sans',
      reason: 'the face brought is the face picked',
    );
  });

  testWidgets('🚨a text on the cel written in a face that is on its way '
      'wears no box — and wears it the moment the face is here', (tester) async {
    final library = deviceWithProbeSans()..gate = Completer<void>();
    await pumpWithSettings(tester, library);
    final c = canvasPixelInView(tester);
    // A text of the cel in the brought face, as a project opened here would
    // carry one.
    final inProbeSans = CelTextContent(
      spans: const [
        CelTextSpan(
          text: 'hi',
          style: TextLetterStyle(fontSize: 48, fontFamily: 'Probe Sans'),
        ),
      ],
      anchor: CanvasPoint(x: c.dx, y: c.dy),
    );
    coordinatorOf(tester).restoreSurfaceSnapshot(
      textToolKey,
      celOf(tester).withTexts([
        CelText(id: 1, content: inProbeSans, plate: const {}),
      ]),
    );
    textToolOf(tester).celTextsChanged();
    await pumpFrames(tester);

    int restingBoxes() => tester
        .widgetList<CustomPaint>(textChrome())
        .map((paint) => paint.painter)
        .whereType<CelTextChromePainter>()
        .single
        .restingBoxes
        .length;

    expect(restingBoxes(), 0);
    expect(library.read, ['font-1.ttf'], reason: 'drawing it sent for it');
    expect(textToolOf(tester).list.texts, isEmpty);

    library.gate!.complete();
    await letTheEngineAnswer(
      tester,
      () => !CanvasLetterFaces.current.isOnItsWay('Probe Sans'),
    );
    await pumpFrames(tester);

    expect(restingBoxes(), 1);
    expect(textToolOf(tester).list.texts, [
      (id: 1, text: 'hi', inHand: false),
    ]);
  });
}

/// The layer UNDER the app's file dialog: one that hands over the file at
/// [path], and keeps the filter each opening asked for.
class _HandsOver extends FileSelectorPlatform {
  _HandsOver(this.path);

  final String path;

  /// The filter of every dialog that was opened.
  final List<List<XTypeGroup>> filters = [];

  @override
  Future<XFile?> openFile({
    List<XTypeGroup>? acceptedTypeGroups,
    String? initialDirectory,
    String? confirmButtonText,
  }) async {
    filters.add(acceptedTypeGroups ?? const []);
    return XFile(path);
  }
}
