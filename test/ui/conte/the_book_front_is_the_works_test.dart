import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/models/conte/conte_sheet_layout.dart';
import 'package:anicel/src/ui/brush/brush_canvas_panel.dart';
import 'package:anicel/src/ui/brush/brush_tool_state.dart';
import 'package:anicel/src/ui/conte/conte_book_page.dart';
import 'package:anicel/src/ui/conte/conte_ink.dart';
import 'package:anicel/src/ui/conte/conte_tab_host.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/text/app_strings.dart';
import 'package:anicel/src/ui/widgets/panel_flyout.dart';
import 'package:anicel/src/ui/widgets/pill_strip.dart';

/// 🗣️I-59 (유저 2026-10-02): 「콘티 용지패널, 1페이지 헤더 넣기/뺴기,
/// 2페이지 빈용지 넣기빼기 기능추가. 위치는 콘티 용지패널의 설정버튼안에.
/// 이게 내보내기시에도 연동」 — and where that button opens (I-93, 10-12):
/// 「타임시트처럼 전용 설정창 만들어서 거기다 표지 빈용지체크 이런거 다
/// 넣고」. The book's front is put in and taken out in the conte sheet's
/// format window, and kept with the work — and so are the sheet's form and
/// its black (I-118, 10-21).
void main() {
  late EditorSessionManager session;

  Future<void> pumpHost(WidgetTester tester) async {
    session = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(session.dispose);
    final view = ValueNotifier<CanvasViewport?>(null);
    addTearDown(view.dispose);
    final ink = ConteInkController();
    addTearDown(ink.dispose);
    final tool = ValueNotifier<BrushToolState>(BrushToolState.defaults);
    addTearDown(tool.dispose);
    await tester.binding.setSurfaceSize(const Size(900, 900));
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

  int pages(WidgetTester tester) =>
      tester
          .widget<BrushCanvasPanel>(find.byType(BrushCanvasPanel))
          .book
          ?.pages
          .length ??
      0;

  Future<void> tap(WidgetTester tester, String key) async {
    final target = find.byKey(ValueKey<String>(key));
    await tester.ensureVisible(target);
    await tester.pumpAndSettle();
    await tester.tap(target);
    await tester.pumpAndSettle();
  }

  bool pillOn(WidgetTester tester, String key) =>
      tester.widget<Pill>(find.byKey(ValueKey<String>(key))).selected;

  testWidgets('the cover and its blank back are taken out in the format '
      'window: the book loses them on save, the work keeps it, and one undo '
      'puts both back', (tester) async {
    await pumpHost(tester);
    final whole = pages(tester);
    expect(whole, greaterThanOrEqualTo(2), reason: 'fixture: a front');

    await tap(tester, 'conte-format-button');
    expect(pillOn(tester, 'conte-format-cover'), isTrue);
    expect(pillOn(tester, 'conte-format-blank-page'), isTrue);
    await tap(tester, 'conte-format-cover');
    await tap(tester, 'conte-format-blank-page');
    expect(pages(tester), whole, reason: 'nothing is written before save');
    await tap(tester, 'conte-format-save-button');

    expect(session.timesheetInfo.conteCover, isFalse);
    expect(session.timesheetInfo.conteBlankPage, isFalse);
    expect(pages(tester), whole - 2, reason: 'the cover and its blank back');

    // The window says what the book is now.
    await tap(tester, 'conte-format-button');
    expect(pillOn(tester, 'conte-format-cover'), isFalse);
    expect(pillOn(tester, 'conte-format-blank-page'), isFalse);
    await tap(tester, 'conte-format-cancel-button');

    session.undo();
    await tester.pumpAndSettle();
    expect(session.timesheetInfo.conteCover, isTrue);
    expect(session.timesheetInfo.conteBlankPage, isTrue);
    expect(pages(tester), whole);
  });

  testWidgets('each switch is its own page: the cover alone leaves its blank '
      'back in, and the window opens on that', (tester) async {
    await pumpHost(tester);
    final whole = pages(tester);

    await tap(tester, 'conte-format-button');
    await tap(tester, 'conte-format-cover');
    await tap(tester, 'conte-format-save-button');

    expect(session.timesheetInfo.conteCover, isFalse);
    expect(session.timesheetInfo.conteBlankPage, isTrue);
    expect(pages(tester), whole - 1, reason: 'the cover alone');

    await tap(tester, 'conte-format-button');
    expect(pillOn(tester, 'conte-format-cover'), isFalse);
    expect(pillOn(tester, 'conte-format-blank-page'), isTrue);
  });

  testWidgets('a window cancelled writes nothing', (tester) async {
    await pumpHost(tester);
    final whole = pages(tester);

    await tap(tester, 'conte-format-button');
    await tap(tester, 'conte-format-cover');
    await tap(tester, 'conte-format-cancel-button');

    expect(session.timesheetInfo.conteCover, isTrue);
    expect(pages(tester), whole);
    expect(session.canUndo, isFalse);
  });

  testWidgets('the sheet\'s form and its black are picked in the same window: '
      'the book is laid in them on save, the work keeps them, and one undo '
      'puts the analog sheet in black back', (tester) async {
    // 유저 2026-10-21 (I-118): 「디지털식? … 그리고 서식 옵션으로
    // 공통적용되게 화면에 검은 외곽선 적용/미적용 버튼」.
    await pumpHost(tester);
    ConteSheetMetrics laid() => tester
        .widget<ConteBookPage>(find.byType(ConteBookPage).first)
        .page
        .metrics;
    String formShown() => tester
        .widget<PanelFlyoutButton>(
          find.byKey(const ValueKey<String>('conte-format-form')),
        )
        .label;
    expect((laid().form, laid().outlined), (ConteSheetForm.analog, true));

    await tap(tester, 'conte-format-button');
    expect(formShown(), AppText.strings.conteFormAnalog);
    expect(pillOn(tester, 'conte-format-outline'), isTrue);
    await tap(tester, 'conte-format-form');
    await tap(tester, 'conte-format-form-digital');
    await tap(tester, 'conte-format-outline');
    expect(laid().form, ConteSheetForm.analog, reason: 'nothing before save');
    await tap(tester, 'conte-format-save-button');

    expect(
      (session.timesheetInfo.conteForm, session.timesheetInfo.conteOutlined),
      (ConteSheetForm.digital, false),
    );
    expect((laid().form, laid().outlined), (ConteSheetForm.digital, false));

    // The window says what the sheet is now.
    await tap(tester, 'conte-format-button');
    expect(formShown(), AppText.strings.conteFormDigital);
    expect(pillOn(tester, 'conte-format-outline'), isFalse);
    await tap(tester, 'conte-format-cancel-button');

    session.undo();
    await tester.pumpAndSettle();
    expect((laid().form, laid().outlined), (ConteSheetForm.analog, true));
  });

  testWidgets('the cells\' fixed text is taken out in the same window: the '
      'sheet writes none on save, the work keeps it, and one undo puts it '
      'back', (tester) async {
    // 유저 2026-10-12 (I-93): 「고정텍스트 표기할지 안할지 콘티용지패널에
    // 설정할수있도록. 타임시트처럼 전용 설정창 만들어서」.
    await pumpHost(tester);
    bool written() => tester
        .widget<ConteBookPage>(find.byType(ConteBookPage).first)
        .source
        .fixedText;
    expect(written(), isTrue, reason: 'written unless taken out');

    await tap(tester, 'conte-format-button');
    expect(pillOn(tester, 'conte-format-fixed-text'), isTrue);
    await tap(tester, 'conte-format-fixed-text');
    expect(written(), isTrue, reason: 'nothing before save');
    await tap(tester, 'conte-format-save-button');

    expect(session.timesheetInfo.conteFixedText, isFalse);
    expect(written(), isFalse);

    // The window says what the sheet is now.
    await tap(tester, 'conte-format-button');
    expect(pillOn(tester, 'conte-format-fixed-text'), isFalse);
    await tap(tester, 'conte-format-cancel-button');

    session.undo();
    await tester.pumpAndSettle();
    expect(session.timesheetInfo.conteFixedText, isTrue);
    expect(written(), isTrue);
  });

  testWidgets('I-82: how much a moving camera\'s cell takes is picked in the '
      'same window — every cut takes it on save, a cut that keeps its own '
      'keeps that, and each undo takes one back', (tester) async {
    // I-82-Q1 「서식 전체 + 컷마다 덮어쓰기」.
    await pumpHost(tester);
    List<ConteCameraRoom> rooms() => [
      for (final cut
          in tester
              .widget<ConteBookPage>(find.byType(ConteBookPage).first)
              .source
              .cuts)
        cut.cameraRoom,
    ];
    String roomShown() => tester
        .widget<PanelFlyoutButton>(
          find.byKey(const ValueKey<String>('conte-format-camera-room')),
        )
        .label;
    expect(rooms(), isNotEmpty, reason: 'fixture');
    expect(rooms(), everyElement(ConteCameraRoom.inCell));

    await tap(tester, 'conte-format-button');
    expect(roomShown(), AppText.strings.conteCameraRoomInCell);
    await tap(tester, 'conte-format-camera-room');
    await tap(tester, 'conte-format-camera-room-grows');
    expect(
      rooms(),
      everyElement(ConteCameraRoom.inCell),
      reason: 'nothing before save',
    );
    await tap(tester, 'conte-format-save-button');

    expect(session.timesheetInfo.conteCameraRoom, ConteCameraRoom.grows);
    expect(rooms(), everyElement(ConteCameraRoom.grows));

    // The window says what the sheet is now.
    await tap(tester, 'conte-format-button');
    expect(roomShown(), AppText.strings.conteCameraRoomGrows);
    await tap(tester, 'conte-format-cancel-button');

    // The window's 컷 설정 row.
    await tap(tester, 'conte-format-button');
    await tap(tester, 'conte-format-cut-camera-room');
    await tap(tester, 'conte-format-cut-camera-room-inCell');
    await tap(tester, 'conte-format-save-button');
    expect(
      rooms().first,
      ConteCameraRoom.inCell,
      reason: 'the cut\'s own over the format\'s',
    );

    session.undo();
    await tester.pumpAndSettle();
    expect(rooms(), everyElement(ConteCameraRoom.grows));
    session.undo();
    await tester.pumpAndSettle();
    expect(rooms(), everyElement(ConteCameraRoom.inCell));
  });
}
