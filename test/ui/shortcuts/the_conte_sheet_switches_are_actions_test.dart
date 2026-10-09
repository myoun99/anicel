// 🗣️I-40 (유저 2026-09-18): 「버튼 전수감사해서 숏컷리스트에 등록 … 뭐든 모든
// 버튼」; asked how far (I-40-Q1, 10-08): the editing screen's command
// buttons and menu rows.
//
// THE CONTE SHEET'S TWO SETTINGS SWITCHES ARE ACTIONS — the cover and the
// blank page its book is printed with (I-59) — and a key presses the row
// the panel's settings show: bound by the panel while it is mounted, the
// one panel of its kind, whatever tool is in hand.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/app_language.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/ui/brush/brush_tool_state.dart';
import 'package:anicel/src/ui/conte/conte_ink.dart';
import 'package:anicel/src/ui/conte/conte_tab_host.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/shortcuts/editor_action_registry.dart';
import 'package:anicel/src/ui/shortcuts/editor_shortcut_scope.dart';
import 'package:anicel/src/ui/shortcuts/panel_keys.dart';
import 'package:anicel/src/ui/text/app_strings.dart';
import 'package:anicel/src/ui/theme/app_theme.dart';
import 'package:anicel/src/ui/widgets/panel_flyout.dart';

const k = LogicalKeyboardKey.keyK;

const switches = [EditorActionIds.conteCover, EditorActionIds.conteBlankPage];

void main() {
  group('the registry', () {
    test('both are rows of a menu under the conte sheet\'s own heading, and '
        'neither ships with a key', () {
      for (final id in switches) {
        final definition = editorActionDefinitions.singleWhere(
          (definition) => definition.id == id,
        );
        expect(definition.menuRow, isTrue, reason: id);
        expect(definition.category, 'Conte Sheet', reason: id);
        expect(definition.defaultActivators, isEmpty, reason: id);
      }
    });

    test('…named by the row\'s own word, in the program\'s language', () {
      addTearDown(() => AppText.settings.value = const AppLanguageSettings());
      AppText.settings.value = const AppLanguageSettings(
        programLanguage: AppLanguage.ko,
      );
      expect(editorActionLabel(EditorActionIds.conteCover), '표지');
      expect(editorActionLabel(EditorActionIds.conteBlankPage), '빈 용지');
      expect(
        AppStrings.of(AppLanguage.ko).shortcutCategory('Conte Sheet', ''),
        '콘티 용지',
      );
    });
  });

  testWidgets('the panel binds its settings\' rows: a press of each flips '
      'what its row flips, the work keeping it — and the rows go with the '
      'panel', (tester) async {
    final session = EditorSessionManager(
      initialProject: createDefaultProject(),
    );
    addTearDown(session.dispose);
    final view = ValueNotifier<CanvasViewport?>(null);
    addTearDown(view.dispose);
    final ink = ConteInkController();
    addTearDown(ink.dispose);
    final tool = ValueNotifier<BrushToolState>(BrushToolState.defaults);
    addTearDown(tool.dispose);
    final keys = PanelKeys();
    await tester.binding.setSurfaceSize(const Size(900, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: PanelKeysScope(
          keys: keys,
          child: Scaffold(
            body: ListenableBuilder(
              listenable: session,
              builder: (context, _) => ConteTabHost(
                session: session,
                thumbnails: null,
                viewportController: view,
                inkController: ink,
                brushToolState: tool,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final cover = session.timesheetInfo.conteCover;
    final blank = session.timesheetInfo.conteBlankPage;

    pressFlyoutRow(
      keys.menuRows(CanvasTool.select),
      EditorActionIds.conteCover,
    );
    await tester.pumpAndSettle();
    expect(session.timesheetInfo.conteCover, !cover);
    expect(session.timesheetInfo.conteBlankPage, blank);

    pressFlyoutRow(
      keys.menuRows(CanvasTool.brush),
      EditorActionIds.conteBlankPage,
    );
    await tester.pumpAndSettle();
    expect(session.timesheetInfo.conteBlankPage, !blank);

    await tester.pumpWidget(const SizedBox());
    expect(keys.menuRows(CanvasTool.brush), isEmpty);
  });

  testWidgets('in the app: a key recorded for the cover does nothing while '
      'the sheet is shut — then flips it, and again puts it back', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(theme: buildAppTheme(), home: const HomePage()),
    );
    await tester.pumpAndSettle();
    final workspace = find.byType(EditorWorkspace);
    final session = tester.widget<EditorWorkspace>(workspace).session;
    EditorShortcutScope.peek(tester.element(workspace))!.setActivators(
      EditorActionIds.conteCover,
      const [SingleActivator(k)],
    );
    await tester.pump();
    final cover = session.timesheetInfo.conteCover;

    // The sheet ships shut — its settings are on no panel to press.
    await tester.sendKeyEvent(k);
    await tester.pumpAndSettle();
    expect(session.timesheetInfo.conteCover, cover);

    await tester.tap(
      find.byKey(const ValueKey<String>('timeline-mode-conte-button')),
    );
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(k);
    await tester.pumpAndSettle();
    expect(session.timesheetInfo.conteCover, !cover);
    await tester.sendKeyEvent(k);
    await tester.pumpAndSettle();
    expect(session.timesheetInfo.conteCover, cover);
  });
}
