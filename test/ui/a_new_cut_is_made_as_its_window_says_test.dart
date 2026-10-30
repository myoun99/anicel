import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/timeline_row_address.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_frame_range.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/editing/default_cut_helpers.dart'
    show defaultCutCanvasSize;
import 'package:anicel/src/ui/editor_canvas_area.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/shortcuts/editor_action_registry.dart';
import 'package:anicel/src/ui/shortcuts/editor_shortcut_scope.dart';
import 'package:anicel/src/ui/widgets/panel_flyout.dart';

import '../helpers/app_shortcuts.dart';
import '../helpers/home_page_probes.dart';

/// 🗣️I-100 (유저 2026-10-14): 「새 컷 만들때, 지금 현재컷? 기준으로 크기
/// 정하는데, 그게아니라 앞으로는 컷 만들기 버튼 누르면 컷 생성창 열려서,
/// 거기서 이름(기본값 넣어줌), 캔버스 사이즈(기본값 a4 200dpi) 정하도록.
/// 거기서 정한값으로 만들어짐」 — the cut pill's ＋, and its key, ask the
/// new cut's name and canvas, and the cut is made as the window leaves
/// them.
void main() {
  const open = CanvasSize(width: 640, height: 360);

  /// One cut, 「1」, at a canvas no new cut is offered.
  Project oneCut() => Project(
    id: const ProjectId('new-cut-window'),
    name: 'NewCutWindow',
    createdAt: DateTime.utc(2026, 10, 30),
    tracks: [
      Track(
        id: const TrackId('track'),
        name: 'Video',
        cuts: [
          Cut(
            id: const CutId('cut-1'),
            name: '1',
            duration: 8,
            canvasSize: open,
            layers: const [],
          ),
        ],
      ),
    ],
  );

  group('the verb', () {
    EditorSessionManager sessionOnOneCut() {
      final session = EditorSessionManager(initialProject: oneCut());
      addTearDown(session.dispose);
      return session;
    }

    List<Cut> cutsOf(EditorSessionManager session) =>
        session.repository.requireProject().tracks.single.cuts;

    test("🎯a new cut is offered A4 200dpi, not the open cut's canvas — "
        'and is made as offered when nothing is said', () {
      final session = sessionOnOneCut();
      expect(session.activeCutOrNull?.canvasSize, open, reason: '⛔전제');

      final offered = session.cutVerbs.plannedNewCut!;
      expect(offered.canvasSize, defaultCutCanvasSize);

      session.cutVerbs.createCut();
      final made = cutsOf(session)[1];
      expect((made.name, made.canvasSize), (offered.name, offered.canvasSize));
    });

    test('it is offered the name it takes where it lands, and takes the '
        'name and the canvas it is given', () {
      final session = sessionOnOneCut();
      expect(session.cutVerbs.plannedNewCut?.name, '2');

      const given = CanvasSize(width: 1000, height: 500);
      session.cutVerbs.createCut(name: 'OP', canvasSize: given);
      final made = cutsOf(session)[1];
      expect((made.name, made.canvasSize), ('OP', given));
      expect(session.activeCutOrNull?.id, made.id);
    });

    test('nowhere to put one, nothing to offer', () {
      final session = sessionOnOneCut();
      session.trackFrameRangeSelection.value = const TrackFrameRangeSelection(
        trackId: TrackId('track'),
        anchorRow: TrackRowAddress(TrackId('track')),
        startFrame: 2,
        endFrameExclusive: 5,
      );
      expect(session.cutVerbs.plannedNewCut, isNull);
    });
  });

  group('the window', () {
    Future<EditorSessionManager> pump(WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(1500, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(home: HomePage(initialProject: oneCut())),
      );
      await tester.pumpAndSettle();
      await useAnicelKeys(tester);
      return tester
          .widget<EditorCanvasArea>(find.byType(EditorCanvasArea))
          .session;
    }

    Finder byKey(String key) => find.byKey(ValueKey<String>(key));

    TextEditingController field(WidgetTester tester, String key) =>
        tester.widget<TextField>(byKey(key)).controller!;

    Future<void> pressPlus(WidgetTester tester) => tapCutCommandButton(
      tester,
      const ValueKey<String>('new-cut-button'),
    );

    Future<void> confirm(WidgetTester tester) async {
      await tester.tap(byKey('new-cut-ok-button'));
      await tester.pumpAndSettle();
    }

    testWidgets('the ＋ opens it before any cut is made: the name the cut '
        'would take, selected and in hand, over A4 200dpi', (tester) async {
      final session = await pump(tester);
      await pressPlus(tester);

      expect(byKey('new-cut-dialog'), findsOneWidget);
      expect(session.activeTrack.cuts, hasLength(1));
      final name = field(tester, 'new-cut-text-field');
      expect(name.text, '2');
      expect(
        name.selection,
        const TextSelection(baseOffset: 0, extentOffset: 1),
      );
      final typing = tester.widget<EditableText>(
        find.descendant(
          of: byKey('new-cut-text-field'),
          matching: find.byType(EditableText),
        ),
      );
      expect(typing.focusNode.hasFocus, isTrue);
      expect(
        (
          field(tester, 'new-cut-width-field').text,
          field(tester, 'new-cut-height-field').text,
        ),
        ('${defaultCutCanvasSize.width}', '${defaultCutCanvasSize.height}'),
      );
    });

    testWidgets('a name typed and a paper picked make that cut', (
      tester,
    ) async {
      final session = await pump(tester);
      await pressPlus(tester);
      await tester.enterText(byKey('new-cut-text-field'), ' OP ');
      await tester.tap(byKey('new-cut-presets'));
      await tester.pumpAndSettle();
      await tester.tap(byKey('new-cut-preset-3508x2480'));
      await tester.pumpAndSettle();
      await confirm(tester);

      expect(session.activeTrack.cuts, hasLength(2));
      final made = session.activeCutOrNull!;
      expect(
        (made.name, made.canvasSize),
        ('OP', const CanvasSize(width: 3508, height: 2480)),
      );
    });

    testWidgets('a size typed is the size made', (tester) async {
      final session = await pump(tester);
      await pressPlus(tester);
      await tester.enterText(byKey('new-cut-width-field'), '1000');
      await tester.enterText(byKey('new-cut-height-field'), '500');
      await tester.pump();
      await confirm(tester);

      expect(
        session.activeCutOrNull?.canvasSize,
        const CanvasSize(width: 1000, height: 500),
      );
    });

    testWidgets('its cancel makes nothing', (tester) async {
      final session = await pump(tester);
      await pressPlus(tester);
      await tester.tap(byKey('new-cut-cancel-button'));
      await tester.pumpAndSettle();

      expect(byKey('new-cut-dialog'), findsNothing);
      expect(session.activeTrack.cuts, hasLength(1));
    });

    testWidgets('a size out of range greys its confirm out and Enter in the '
        'name makes nothing — back in range, it makes that size', (
      tester,
    ) async {
      final session = await pump(tester);
      await pressPlus(tester);
      await tester.enterText(byKey('new-cut-width-field'), '0');
      await tester.pump();
      expect(
        tester.widget<ButtonStyleButton>(byKey('new-cut-ok-button')).onPressed,
        isNull,
      );

      await tester.showKeyboard(byKey('new-cut-text-field'));
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(byKey('new-cut-dialog'), findsOneWidget);
      expect(session.activeTrack.cuts, hasLength(1));

      await tester.enterText(byKey('new-cut-width-field'), '800');
      await tester.pump();
      await confirm(tester);
      expect(
        session.activeCutOrNull?.canvasSize,
        CanvasSize(width: 800, height: defaultCutCanvasSize.height),
      );
    });

    testWidgets("its list is the canvas size window's — the paper's, a "
        "line, the video's — with A4 200dpi marked; no 「캔버스에서 조정」, "
        'as there is no canvas yet', (tester) async {
      await pump(tester);
      await pressPlus(tester);
      final rows = tester
          .widget<PanelFlyoutButton>(byKey('new-cut-presets'))
          .entriesBuilder();

      expect(
        [
          for (final row in rows)
            if (row is PanelFlyoutItem) row.keyValue else '—',
        ],
        [
          'new-cut-preset-1754x1240',
          'new-cut-preset-2340x1654',
          'new-cut-preset-3508x2480',
          '—',
          'new-cut-preset-1280x720',
          'new-cut-preset-1920x1080',
          'new-cut-preset-2560x1440',
          'new-cut-preset-3840x2160',
        ],
      );
      expect(
        [
          for (final row in rows)
            if (row is PanelFlyoutItem && row.selected) row.keyValue,
        ],
        ['new-cut-preset-2340x1654'],
      );
      expect(byKey('new-cut-adjust-on-canvas'), findsNothing);
    });

    testWidgets('its key opens the same window', (tester) async {
      final session = await pump(tester);
      // Worked in, as a key is pressed where a panel is being worked.
      await tester.tap(byKey('timeline-mode-timeline-button'));
      await tester.pumpAndSettle();
      EditorShortcutScope.peek(
        tester.element(find.byType(EditorCanvasArea)),
      )!.setActivators(EditorActionIds.cutNew, const [
        SingleActivator(LogicalKeyboardKey.keyN, shift: true),
      ]);
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyN);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pumpAndSettle();

      expect(byKey('new-cut-dialog'), findsOneWidget);
      expect(session.activeTrack.cuts, hasLength(1));
      await confirm(tester);
      expect(session.activeTrack.cuts, hasLength(2));
    });
  });
}
