import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/project_background.dart';
import 'package:anicel/src/ui/dialogs/project_background_dialog.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/widgets/field_slider.dart';

/// R10-⑥: the project background — model round trip, the session's
/// one-undo setter and the File-menu dialog.
void main() {
  test('json omits the default and round-trips color/transparent', () {
    final project = createDefaultProject();
    expect(project.background, ProjectBackground.defaultBackground);
    expect(project.toJson().containsKey('background'), isFalse);

    final black = project.copyWith(background: ProjectBackground.black);
    final restoredBlack = ProjectBackground.fromJson(
      black.toJson()['background'] as Map<String, dynamic>,
    );
    expect(restoredBlack, ProjectBackground.black);

    final transparent = project.copyWith(
      background: const ProjectBackground.transparent(),
    );
    final restoredTransparent = ProjectBackground.fromJson(
      transparent.toJson()['background'] as Map<String, dynamic>,
    );
    expect(restoredTransparent.transparent, isTrue);
    expect(
      restoredTransparent.argb,
      0x00FFFFFF,
      reason:
          'transparent IS alpha-0 paper now (R3b) — the alpha is real, '
          'on screen and in exports alike',
    );
  });

  test('setProjectBackground is one undo step and no-ops when unchanged', () {
    final s = EditorSessionManager(initialProject: createDefaultProject());

    s.projectSettings.setProjectBackground(ProjectBackground.black);
    expect(s.projectSettings.projectBackground, ProjectBackground.black);
    expect(s.canUndo, isTrue);

    // Unchanged: no extra undo entry.
    s.projectSettings.setProjectBackground(ProjectBackground.black);
    s.undo();
    expect(s.projectSettings.projectBackground, ProjectBackground.defaultBackground);
    expect(s.canUndo, isFalse);

    s.redo();
    expect(s.projectSettings.projectBackground, ProjectBackground.black);
  });

  testWidgets('the dialog applies a preset and a custom hex color', (
    tester,
  ) async {
    final s = EditorSessionManager(initialProject: createDefaultProject());
    Future<void> openDialog() async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (context) => ProjectBackgroundDialog(session: s),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    await openDialog();
    await tester.tap(find.byKey(const ValueKey<String>('background-black')));
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey<String>('background-apply-button')),
    );
    await tester.pumpAndSettle();
    expect(s.projectSettings.projectBackground, ProjectBackground.black);

    await openDialog();
    await tester.tap(find.byKey(const ValueKey<String>('background-custom')));
    await tester.pump();
    await tester.enterText(
      find.byKey(const ValueKey<String>('background-custom-hex')),
      '3366CC',
    );
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey<String>('background-apply-button')),
    );
    await tester.pumpAndSettle();
    expect(s.projectSettings.projectBackground, const ProjectBackground.color(0xFF3366CC));

    await openDialog();
    await tester.tap(
      find.byKey(const ValueKey<String>('background-transparent')),
    );
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey<String>('background-apply-button')),
    );
    await tester.pumpAndSettle();
    expect(s.projectSettings.projectBackground.transparent, isTrue);
  });

  group('the stage bars', () {
    Future<void> openBackgroundDialog(
      WidgetTester tester,
      EditorSessionManager session,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (context) =>
                      ProjectBackgroundDialog(session: session),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    FieldSlider barAt(WidgetTester tester, String key) =>
        tester.widget<FieldSlider>(find.byKey(ValueKey<String>(key)));

    testWidgets('🚨alpha is a BYTE on the track and per cent on the screen — '
        'one stop per byte, so a drag lands on a value the file holds', (
      tester,
    ) async {
      final session = EditorSessionManager(
        initialProject: createDefaultProject(),
      );
      await openBackgroundDialog(tester, session);

      final paper = barAt(tester, 'background-paper-alpha');
      expect(paper.min, 0);
      expect(paper.max, 255);
      expect(
        paper.divisions,
        255,
        reason: 'a byte has 255 steps — 0.4963 of one is not a colour',
      );
      Finder writtenOn(String key) => find.descendant(
        of: find.byKey(ValueKey<String>(key)),
        matching: find.byType(Text),
      );
      expect(
        tester.widget<Text>(writtenOn('background-paper-alpha')).data,
        '100.0%',
      );

      paper.onChanged!(128);
      await tester.pump();
      expect(
        tester.widget<Text>(writtenOn('background-paper-alpha')).data,
        '50.2%',
        reason: '128 of 255 is not a whole half — F-9 says show what it is',
      );
      // 🚨And the digit is there AT EVERY VALUE, which is F-34: 255 stops
      // over 100% is a fractional step, so full alpha reads `100.0%` and not
      // `100%`. The count is the bar's, and it does not move.
      expect(find.text('100%'), findsNothing);
    });

    testWidgets('🚨the pasteboard extent reads as the MULTIPLE of the canvas '
        'it reaches, not as the margin it stores', (tester) async {
      final session = EditorSessionManager(
        initialProject: createDefaultProject(),
      );
      await openBackgroundDialog(tester, session);

      final extent = barAt(tester, 'background-pasteboard-extent');
      expect(
        extent.valueTextBuilder!(0, '0.0'),
        '×1.0',
        reason: 'no margin is the canvas itself',
      );
      expect(
        extent.valueTextBuilder!(0.5, '0.5'),
        '×2.0',
        reason: 'half a canvas on EACH side is twice the canvas',
      );
      expect(extent.valueTextBuilder!(2, '2.0'), '×5.0');
    });

    testWidgets('⛔the stage bars are FieldSliders like every other bar in '
        'the app — a Material Slider here would not obey the press-claim '
        'law inside this scrollable dialog', (tester) async {
      final session = EditorSessionManager(
        initialProject: createDefaultProject(),
      );
      await openBackgroundDialog(tester, session);

      expect(find.byType(Slider), findsNothing);
      expect(find.byType(FieldSlider), findsNWidgets(3));
    });
  });
}
