import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/app_language.dart';
import 'package:anicel/src/models/camera_instruction.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/models/conte/conte_sheet_source.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/layer_link_registry.dart';
import 'package:anicel/src/models/layer_section_defaults.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/timesheet_document.dart';
import 'package:anicel/src/models/sheet_memo_side.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/editing/default_cut_helpers.dart';
import 'package:anicel/src/services/editing/default_layer_helpers.dart';
import 'package:anicel/src/ui/brush/brush_tool_state.dart';
import 'package:anicel/src/ui/conte/conte_book_page.dart';
import 'package:anicel/src/ui/conte/conte_ink.dart';
import 'package:anicel/src/ui/conte/conte_tab_host.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/sheet/sheet_text_edit_layer.dart';
import 'package:anicel/src/ui/text/app_strings.dart';
import 'package:anicel/src/ui/timesheet/timesheet_document_painter.dart';
import 'package:anicel/src/ui/timesheet/timesheet_header_edit_layer.dart';
import 'package:anicel/src/ui/timesheet/timesheet_ink_controller.dart';
import 'package:anicel/src/ui/timesheet_tab_host.dart';
import 'package:anicel/src/ui/widgets/panel_flyout.dart';

/// 🗣️F-542 (유저 2026-11-02): 「고정텍스트 적용/미적용 설정 똑같이 만들어서 법
/// 통일. 그리고 타임시트용지나 콘티용지든 고정텍스트를 카메라 움직임처럼
/// 전체설정이랑 현재컷 설정 두개로 나눔.」 — the two format windows set it
/// alike, and the papers print what they set.
void main() {
  const track = TrackId('track');
  const otherTrack = TrackId('other-track');
  late EditorSessionManager session;

  Cut cut(String id, int sequence) => createDefaultCut(
    cutId: CutId(id),
    name: id,
    layerId: defaultLayerIdForSequence(sequence),
  );

  /// Cuts A and B, 겸용, and C on its own, a fade in on A's head — A's 겸용
  /// cut D on a track of its own, with [elsewhere].
  Project work({bool elsewhere = false}) => Project(
    id: const ProjectId('fixed-text'),
    name: 'Fixed text',
    createdAt: DateTime.utc(2026, 11, 2),
    tracks: [
      Track(
        id: track,
        name: 'V',
        cuts: [cut('A', 1), cut('B', 2), cut('C', 3)],
        transitionLayer: createTrackTransitionLayer(track).copyWith(
          instructions: {
            0: const InstructionEvent(instructionId: 'fi', length: 6),
          },
        ),
      ),
      if (elsewhere)
        Track(id: otherTrack, name: 'V2', cuts: [cut('D', 4)]),
    ],
    linkRegistry: LayerLinkRegistry(
      groups: [
        LayerLinkGroup(
          id: 'g',
          members: [
            LayerLinkMember(
              trackId: track,
              cutId: const CutId('A'),
              layerId: defaultLayerIdForSequence(1),
            ),
            LayerLinkMember(
              trackId: track,
              cutId: const CutId('B'),
              layerId: defaultLayerIdForSequence(2),
            ),
            if (elsewhere)
              LayerLinkMember(
                trackId: otherTrack,
                cutId: const CutId('D'),
                layerId: defaultLayerIdForSequence(4),
              ),
          ],
        ),
      ],
    ),
  );

  Future<void> tap(WidgetTester tester, String key) async {
    final target = find.byKey(ValueKey<String>(key));
    await tester.ensureVisible(target);
    await tester.pumpAndSettle();
    await tester.tap(target);
    await tester.pumpAndSettle();
  }

  String shownOn(WidgetTester tester, String key) => tester
      .widget<PanelFlyoutButton>(find.byKey(ValueKey<String>(key)))
      .label;

  bool? sheetOf(String id) =>
      session.cutById(CutId(id))!.metadata.sheetFixedText;
  bool? conteOf(String id) =>
      session.cutById(CutId(id))!.metadata.conteFixedText;

  group('the timesheet', () {
    const window = 'timesheet-format-button';
    const save = 'timesheet-format-save-button';
    const button = 'timesheet-format-cut-fixed-text';

    Future<void> pumpHost(WidgetTester tester, {Project? project}) async {
      session = EditorSessionManager(initialProject: project ?? work());
      addTearDown(session.dispose);
      final ink = TimesheetInkController();
      addTearDown(ink.dispose);
      final brush = ValueNotifier<BrushToolState>(BrushToolState.defaults);
      addTearDown(brush.dispose);
      await tester.binding.setSurfaceSize(const Size(1200, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TimesheetTabHost(
              session: session,
              viewport: CanvasViewport(),
              onViewportChanged: (_) {},
              inkController: ink,
              brushToolState: brush,
              brushAllowed: false,
              onBrushAllowedChanged: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    TimesheetDocument sheet(WidgetTester tester) => tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .map((paint) => paint.painter)
        .whereType<TimesheetDocumentPainter>()
        .first
        .document;

    List<String> linesOn(WidgetTester tester) => sheet(tester).fixedLinesOf(0);

    testWidgets('🎯the memo field opens under the lines — where the page '
        'prints what is typed there', (tester) async {
      await pumpHost(tester);
      final layout = tester
          .widget<TimesheetHeaderEditLayer>(
            find.byType(TimesheetHeaderEditLayer),
          )
          .layout;
      final target = tester
          .widget<SheetTextEditLayer>(find.byType(SheetTextEditLayer))
          .targets
          .singleWhere((each) => each.keyValue == 'timesheet-memo-edit-p0');

      expect(linesOn(tester), isNotEmpty, reason: '⛔전제');
      const side = SheetMemoSide.left;
      expect(target.textRect, layout.memoWordsRect(0, side));
      expect(target.box, layout.memoEditBox(0, side));
      expect(
        target.box.top,
        layout.memoSideRect(0, side).top +
            linesOn(tester).length * TimesheetDocumentPainter.memoLine,
      );
    });

    testWidgets('the whole work\'s is switched in the window, saved with it '
        'and one undo puts it back', (tester) async {
      await pumpHost(tester);
      expect(linesOn(tester), isNotEmpty, reason: '⛔전제');

      await tap(tester, window);
      await tap(tester, 'timesheet-format-fixed-text');
      expect(linesOn(tester), isNotEmpty, reason: 'nothing before save');
      await tap(tester, save);

      expect(session.timesheetInfo.sheetFixedText, isFalse);
      expect(linesOn(tester), isEmpty);
      expect(session.timesheetInfo.conteFixedText, isTrue);

      session.undo();
      await tester.pumpAndSettle();
      expect(session.timesheetInfo.sheetFixedText, isTrue);
      expect(linesOn(tester), isNotEmpty);
    });

    testWidgets('🎯the cut\'s is named beside its button, on the format\'s '
        'until picked, and a pick takes the 겸용 pair in the format\'s step', (
      tester,
    ) async {
      await pumpHost(tester);
      final strings = AppText.strings;
      await tap(tester, window);
      expect(find.text(strings.conteCameraRoomCurrentCut('A')), findsOneWidget);
      expect(shownOn(tester, button), strings.conteCameraRoomAsSheet);

      await tap(tester, button);
      await tap(tester, '$button-off');
      expect(shownOn(tester, button), strings.conteOutlineOff);
      expect(sheetOf('A'), isNull, reason: 'nothing before save');
      await tap(tester, save);

      expect([sheetOf('A'), sheetOf('B'), sheetOf('C')], [false, false, null]);
      expect(conteOf('A'), isNull, reason: 'the sheet\'s answer alone');
      expect(linesOn(tester), isEmpty);

      await tap(tester, window);
      expect(shownOn(tester, button), strings.conteOutlineOff);
      await tap(tester, button);
      await tap(tester, '$button-format');
      await tap(tester, save);
      expect([sheetOf('A'), sheetOf('B')], [null, null]);
      expect(linesOn(tester), isNotEmpty);

      session.undo();
      await tester.pumpAndSettle();
      expect(sheetOf('A'), isFalse);
      session.undo();
      await tester.pumpAndSettle();
      expect(sheetOf('A'), isNull);
    });

    testWidgets('a cut set on over the work\'s off writes', (tester) async {
      await pumpHost(tester);
      await tap(tester, window);
      await tap(tester, 'timesheet-format-fixed-text');
      await tap(tester, button);
      await tap(tester, '$button-on');
      await tap(tester, save);

      expect(session.timesheetInfo.sheetFixedText, isFalse);
      expect(sheetOf('A'), isTrue);
      expect(linesOn(tester), isNotEmpty);
    });

    testWidgets('🎯the sheet reprints when what its lines read changes: the '
        'sheet\'s language', (tester) async {
      await pumpHost(tester);
      session.languageSettings.value = session.languageSettings.value.copyWith(
        notationLanguage: AppLanguage.ja,
      );
      await tester.pumpAndSettle();
      expect(linesOn(tester), ['カット頭 FI']);

      session.languageSettings.value = session.languageSettings.value.copyWith(
        notationLanguage: AppLanguage.ko,
      );
      await tester.pumpAndSettle();
      expect(linesOn(tester), ['컷 앞 FI']);
    });

    // 🗣️F-558 (유저 2026-11-04): 「겸용컷은 고정텍스트 위치가 이게아님. 그리고
    // 고정텍스트 on이든 off이든 연관없음. 항상 보여줌. 위치는 헤더의 컷 번호
    // 아래」.
    testWidgets('🎯the header names the 겸용 cuts, one on another track among '
        'them, again when one is renamed — and the memo writes none', (
      tester,
    ) async {
      await pumpHost(tester, project: work(elsewhere: true));
      expect(sheet(tester).linkedCuts, ['B', 'D']);
      expect(linesOn(tester), hasLength(1), reason: 'the fade\'s alone');

      session.cutVerbs.renameCuts({const CutId('D'): 'D2'});
      await tester.pumpAndSettle();
      expect(sheet(tester).linkedCuts, ['B', 'D2']);
      session.cutVerbs.renameCuts({const CutId('B'): 'B2'});
      await tester.pumpAndSettle();
      expect(sheet(tester).linkedCuts, ['B2', 'D2']);
    });

    testWidgets('🎯…whether the sheet writes its lines or not', (tester) async {
      await pumpHost(tester);
      await tap(tester, window);
      await tap(tester, 'timesheet-format-fixed-text');
      await tap(tester, save);

      expect(session.timesheetInfo.sheetFixedText, isFalse, reason: '⛔전제');
      expect(linesOn(tester), isEmpty);
      expect(sheet(tester).linkedCuts, ['B']);
    });
  });

  group('the conte', () {
    const button = 'conte-format-cut-fixed-text';
    const save = 'conte-format-save-button';

    Future<void> pumpHost(WidgetTester tester) async {
      session = EditorSessionManager(initialProject: work());
      addTearDown(session.dispose);
      final view = ValueNotifier<CanvasViewport?>(null);
      addTearDown(view.dispose);
      final ink = ConteInkController();
      addTearDown(ink.dispose);
      final tool = ValueNotifier<BrushToolState>(BrushToolState.defaults);
      addTearDown(tool.dispose);
      await tester.binding.setSurfaceSize(const Size(900, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
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
      );
      await tester.pumpAndSettle();
    }

    /// The 겸용 cuts each cut's first cell writes.
    List<List<String>> linkedOn(WidgetTester tester) => [
      for (final ConteCutSource cut
          in tester
              .widget<ConteBookPage>(find.byType(ConteBookPage).first)
              .source
              .cuts)
        cut.cells.first.fixedLines.linkedCuts,
    ];

    testWidgets('🎯the same field: the cut\'s beside the work\'s, the 겸용 pair '
        'taking a pick, and the sheet\'s left alone', (tester) async {
      await pumpHost(tester);
      final strings = AppText.strings;
      expect(linkedOn(tester).first, isNotEmpty, reason: '⛔전제');

      await tap(tester, 'conte-format-button');
      expect(shownOn(tester, button), strings.conteCameraRoomAsSheet);
      await tap(tester, button);
      await tap(tester, '$button-off');
      await tap(tester, save);

      expect([conteOf('A'), conteOf('B'), conteOf('C')], [false, false, null]);
      expect(sheetOf('A'), isNull, reason: 'the conte\'s answer alone');
      expect(linkedOn(tester).first, isEmpty);

      await tap(tester, 'conte-format-button');
      expect(shownOn(tester, button), strings.conteOutlineOff);
      await tap(tester, 'conte-format-cancel-button');

      session.undo();
      await tester.pumpAndSettle();
      expect(conteOf('A'), isNull);
      expect(linkedOn(tester).first, isNotEmpty);
    });
  });
}
