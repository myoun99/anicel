import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/ui/brush/brush_canvas_panel.dart';
import 'package:anicel/src/ui/brush/brush_tool_state.dart';
import 'package:anicel/src/ui/conte/conte_ink.dart';
import 'package:anicel/src/ui/conte/conte_tab_host.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/widgets/pill_strip.dart';

/// 🗣️I-59 (유저 2026-10-02): 「콘티 용지패널, 1페이지 헤더 넣기/뺴기,
/// 2페이지 빈용지 넣기빼기 기능추가. 위치는 콘티 용지패널의 설정버튼안에.
/// 이게 내보내기시에도 연동」 — and where that button opens (I-93, 10-12):
/// 「타임시트처럼 전용 설정창 만들어서 거기다 표지 빈용지체크 이런거 다
/// 넣고」. The book's front is put in and taken out in the conte sheet's
/// format window, and kept with the work.
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
}
