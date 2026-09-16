import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/envelope/cut_envelope_painter.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/panels/editor_panel_tabs.dart';
import 'package:anicel/src/ui/playback/canvas_playback_controller.dart';
import 'package:anicel/src/ui/timesheet/timesheet_document_painter.dart';

/// F-90 ② — the sheet prints the cut under the playhead.
///
/// 유저 2026-09-12: 「그리고 재생시에 컷 넘어가면 타임시트패널도 다음컷 시트
/// 표시해주는데 왜 룰러 스크럽때는 그게 안되는건지? 법 하나로 통일」.
///
/// Measured first (09-16), with two one-page cuts: a playback crossing left
/// the sheet on the cut being left until stop, and a ruler drag left it
/// there until release. The app is driven with its own sheets group — the
/// sheet turns over through the workspace's listenables, which a bare host
/// would never hear.
List<Cut> _cutsOf(EditorSessionManager session) =>
    session.repository.requireProject().tracks.first.cuts;

String _printedCut(WidgetTester tester) {
  final paint = tester.widget<CustomPaint>(
    find.byKey(const ValueKey<String>('timesheet-document-paint')),
  );
  return (paint.painter! as TimesheetDocumentPainter).document.cutName;
}

int? _sheetPlayheadFrame(WidgetTester tester) {
  final paint = tester.widget<CustomPaint>(
    find.byKey(const ValueKey<String>('timesheet-playhead-overlay')),
  );
  return (paint.painter! as TimesheetPlayheadPainter).resolvePlayheadFrame();
}

List<String> _envelopeCuts(WidgetTester tester) {
  final paint = tester.widget<CustomPaint>(
    find.byKey(const ValueKey<String>('cut-envelope-page')),
  );
  return [
    for (final line in (paint.painter! as CutEnvelopePainter).source.cuts)
      line.name,
  ];
}

void main() {
  Future<EditorSessionManager> pumpApp(
    WidgetTester tester, {
    int gapBeforeSecond = 0,
    String tabId = EditorWorkspace.timesheetTabId,
  }) async {
    await tester.binding.setSurfaceSize(const Size(1600, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const MaterialApp(home: HomePage()));
    await tester.pumpAndSettle();
    final session = tester
        .widget<EditorWorkspace>(find.byType(EditorWorkspace))
        .session;
    session.cutVerbs.createCut();
    if (gapBeforeSecond > 0) {
      session.repository.updateCutLeadingGap(
        cutId: _cutsOf(session)[1].id,
        leadingGapFrames: gapBeforeSecond,
      );
    }
    session.selectCut(_cutsOf(session)[0].id);
    tester
        .widgetList<EditorPanelTabs>(find.byType(EditorPanelTabs))
        .firstWhere((host) => host.tabs.any((tab) => tab.id == tabId))
        .onTabSelected(tabId);
    await tester.pumpAndSettle();
    return session;
  }

  Future<void> settle(
    WidgetTester tester,
    EditorSessionManager session,
  ) async {
    session.playbackRig.prerenderScheduler.cancel();
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
  }

  testWidgets('playing across a cut boundary turns the sheet over to the '
      'next cut', (tester) async {
    final session = await pumpApp(tester);
    final [first, second] = _cutsOf(session);
    expect(first.name, isNot(second.name), reason: 'fixture');
    expect(_printedCut(tester), first.name, reason: 'fixture');

    session.playbackRig.playback.play(scope: PlaybackScope.allCuts);
    await tester.pump();
    session.playbackRig.playback.seekToGlobalFrame(first.duration + 2);
    await tester.pump();

    expect(_printedCut(tester), second.name);
    expect(_sheetPlayheadFrame(tester), 2);

    session.playbackRig.playback.stop();
    await settle(tester, session);
  });

  testWidgets('a ruler drag across a cut boundary turns the sheet over while '
      'the finger is still down', (tester) async {
    final session = await pumpApp(tester);
    final [first, second] = _cutsOf(session);

    session.frameScrub.scrubGlobalFrame(1);
    session.frameScrub.scrubGlobalFrame(first.duration + 2);
    session.frameScrub.scrubGlobalFrame(first.duration + 3);
    await tester.pump();

    expect(
      session.activeCutId,
      first.id,
      reason: 'fixture: a drag leaves the open cut alone (UI-R7 #9)',
    );
    expect(_printedCut(tester), second.name);
    expect(
      _sheetPlayheadFrame(tester),
      3,
      reason: 'the playhead row is the dragged frame of the printed cut',
    );

    // Inside the printed cut a drag moves nothing but the parking, and the
    // playhead row has to repaint for it.
    final overlay = tester.renderObject<RenderCustomPaint>(
      find.byKey(const ValueKey<String>('timesheet-playhead-overlay')),
    );
    expect(overlay.debugNeedsPaint, isFalse, reason: 'fixture: painted');
    session.frameScrub.scrubGlobalFrame(first.duration + 4);
    expect(
      overlay.debugNeedsPaint,
      isTrue,
      reason: 'a move of the parking repaints the playhead row',
    );
    await tester.pump();
    expect(_sheetPlayheadFrame(tester), 4);

    session.frameScrub.scrubGlobalFrame(1);
    await tester.pump();
    expect(
      _printedCut(tester),
      first.name,
      reason: 'dragging back turns it back',
    );

    session.frameScrub.commitFrameScrub();
    await settle(tester, session);
  });

  testWidgets('a ruler drag over the gap between two cuts prints no cut', (
    tester,
  ) async {
    final session = await pumpApp(tester, gapBeforeSecond: 4);
    final [first, second] = _cutsOf(session);

    session.frameScrub.scrubGlobalFrame(1);
    session.frameScrub.scrubGlobalFrame(first.duration + 1);
    session.frameScrub.scrubGlobalFrame(first.duration + 2);
    await tester.pump();
    expect(
      find.byKey(const ValueKey<String>('timesheet-empty-no-cut')),
      findsOneWidget,
    );

    session.frameScrub.scrubGlobalFrame(first.duration + 4 + 1);
    await tester.pump();
    expect(_printedCut(tester), second.name);

    session.frameScrub.commitFrameScrub();
    await settle(tester, session);
  });

  testWidgets('the cut envelope beside the sheet turns over with it', (
    tester,
  ) async {
    final session = await pumpApp(tester, tabId: EditorWorkspace.envelopeTabId);
    final [first, _] = _cutsOf(session);
    final open = _envelopeCuts(tester);

    session.frameScrub.scrubGlobalFrame(1);
    session.frameScrub.scrubGlobalFrame(first.duration + 2);
    session.frameScrub.scrubGlobalFrame(first.duration + 3);
    await tester.pump();
    final dragged = _envelopeCuts(tester);

    session.frameScrub.commitFrameScrub();
    await tester.pumpAndSettle();
    final landed = _envelopeCuts(tester);

    expect(landed, isNot(open), reason: 'fixture: the release opens the cut');
    expect(
      dragged,
      landed,
      reason: 'mid-drag it already shows the cut the release lands on',
    );
    await settle(tester, session);
  });
}
