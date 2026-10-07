import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/ui/brush/brush_canvas_panel.dart';
import 'package:anicel/src/ui/brush/brush_tool_state.dart';
import 'package:anicel/src/ui/conte/conte_ink.dart';
import 'package:anicel/src/ui/conte/conte_tab_host.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';

import '../../helpers/boolean_dot_probe.dart';
import '../../helpers/canvas_pill.dart';

/// 🗣️I-59 (유저 2026-10-02): 「콘티 용지패널, 1페이지 헤더 넣기/뺴기,
/// 2페이지 빈용지 넣기빼기 기능추가. 위치는 콘티 용지패널의 설정버튼안에.
/// 이게 내보내기시에도 연동」 — the book's front is put in and taken out in
/// the conte panel's settings list, and kept with the work.
void main() {
  testWidgets('the cover and its blank back are taken out in the panel\'s '
      'settings: the book loses them, the work keeps it, and each undo puts '
      'one back', (tester) async {
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

    int pages() =>
        tester
            .widget<BrushCanvasPanel>(find.byType(BrushCanvasPanel))
            .book
            ?.pages
            .length ??
        0;
    final whole = pages();
    expect(whole, greaterThanOrEqualTo(2), reason: 'fixture: a front');

    await tapInViewSettings(tester, 'conte-cover-toggle');
    expect(session.timesheetInfo.conteCover, isFalse);
    expect(pages(), whole - 1, reason: 'the cover is out of the book');

    await tapInViewSettings(tester, 'conte-blank-page-toggle');
    expect(session.timesheetInfo.conteBlankPage, isFalse);
    expect(pages(), whole - 2, reason: 'and its blank back');

    // The list says what the book is now.
    await openViewSettings(tester);
    for (final key in ['conte-cover-toggle', 'conte-blank-page-toggle']) {
      expect(
        tester.booleanDotIn(find.byKey(ValueKey<String>(key))).value,
        isFalse,
        reason: key,
      );
    }
    await tester.tapAt(Offset.zero);
    await tester.pumpAndSettle();

    session.undo();
    await tester.pumpAndSettle();
    expect(session.timesheetInfo.conteBlankPage, isTrue);
    expect(pages(), whole - 1);
    session.undo();
    await tester.pumpAndSettle();
    expect(session.timesheetInfo.conteCover, isTrue);
    expect(pages(), whole);
  });
}
