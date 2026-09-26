import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/ui/dialogs/rename_frame_dialog.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/storyboard_panel.dart';
import 'package:anicel/src/ui/timeline/toolbar_panel_context.dart';

import '../../helpers/conte_track_fixture.dart';
import '../../helpers/home_page_probes.dart';
import '../flyout_test_helpers.dart' show readCommandEnabled;

/// 🗣️F-186 (유저 2026-09-26): 「콘티패널 컷블록에 대한 선택범위랑 콘티블록에
/// 대한 선택범위있거든? 타임라인 버튼은 기본적으로 선택안한상태에선
/// 컷블록을 대상으로 하고, 콘티블록 선택하면 지금 편집버튼같은거
/// 활성화안되는데 활성화시키고 로직작동가능하도록」.
///
/// The conte-block band is the strip's cut-local selection — the timeline's
/// own band, on the conte row the press stood the timeline on (F-187) — so
/// the storyboard's buttons answer it with the timeline's verbs.
/// [conteTrackProject]: cut-1's conte row is three panels, [0,4) [4,8)
/// [8,12).
void main() {
  const conteId = LayerId('cut-1-conte');
  const edit = ValueKey<String>('shared-edit-button');

  EditorSessionManager sessionOf(WidgetTester tester) =>
      tester.widget<EditorWorkspace>(find.byType(EditorWorkspace)).session;

  Future<EditorSessionManager> pumpStoryboard(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(home: HomePage(initialProject: conteTrackProject())),
    );
    await tester.pumpAndSettle();
    await showStoryboardPanel(tester);
    return sessionOf(tester);
  }

  /// A point on the V row's STRIP over [globalFrame].
  Offset stripPoint(WidgetTester tester, int globalFrame) {
    final row = find.byKey(
      ValueKey<String>('storyboard-track-timeline-area-${conteTrackId.value}'),
    );
    final rect = tester.getTopLeft(row) & tester.getSize(row);
    final pixelsPerFrame = tester
        .widget<StoryboardPanel>(find.byType(StoryboardPanel))
        .pixelsPerFrame;
    return Offset(
      rect.left + (globalFrame + 0.5) * pixelsPerFrame,
      rect.top + rect.height / 2,
    );
  }

  /// Sweeps cut-1's SECOND panel, [4, 8), on the strip.
  Future<void> sweepTheSecondPanel(WidgetTester tester) async {
    final gesture = await tester.startGesture(
      stripPoint(tester, 5),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    await gesture.moveTo(stripPoint(tester, 6));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
  }

  testWidgets('with nothing selected Edit is the CUT block\'s; a conte block '
      'selected lights it for the block, and it opens the block\'s own '
      'editor', (tester) async {
    final session = await pumpStoryboard(tester);
    expect(
      StoryboardToolbarPanelContext(session).editTarget,
      isA<StoryboardEditCut>(),
      reason: '「선택안한상태에선 컷블록을 대상으로」',
    );

    await sweepTheSecondPanel(tester);
    expect(
      session.frameRangeSelection.value?.layerId,
      conteId,
      reason: 'premise: the strip swept a conte block',
    );
    expect(
      await readCommandEnabled(tester, edit),
      isTrue,
      reason: '「콘티블록 선택하면 … 편집버튼 … 활성화」',
    );

    await tester.tap(find.byKey(edit));
    await tester.pumpAndSettle();
    expect(
      find.byType(RenameFrameDialog),
      findsOneWidget,
      reason: 'the block\'s own editor — what the timeline\'s Edit opens '
          'on that cell',
    );
    Navigator.of(tester.element(find.byType(RenameFrameDialog))).pop();
    await tester.pumpAndSettle();
  });

  testWidgets('the band\'s clipboard, X, mark and 링크 독립 are the timeline\'s '
      'answers', (tester) async {
    final session = await pumpStoryboard(tester);
    await sweepTheSecondPanel(tester);
    final timeline = TimelineToolbarPanelContext(session);

    Future<void> expectTheTimelinesAnswers() async {
      final answers = {
        'shared-cut-button': timeline.canCutRun,
        'shared-copy-button': timeline.canCopyFrame,
        'shared-paste-independent-button': timeline.canPasteIndependentFrame,
        'shared-paste-linked-button': timeline.canPasteLinkedFrame,
        'blank-exposure-button': timeline.canBlankExposure,
        'toggle-mark-button': timeline.canToggleMark,
        'shared-unlink-button': timeline.canUnlink,
      };
      for (final MapEntry(:key, :value) in answers.entries) {
        expect(
          await readCommandEnabled(tester, ValueKey<String>(key)),
          value,
          reason: '$key answers the band the way the timeline does',
        );
      }
    }

    await expectTheTimelinesAnswers();
    expect(
      [timeline.canCutRun, timeline.canCopyFrame, timeline.canToggleMark],
      everyElement(isTrue),
      reason: 'LIVENESS: 잘라내기, copy and the mark are lit on the band',
    );

    // The press is the timeline's too: a copy made HERE is what the two
    // pastes then offer.
    await tester.tap(find.byKey(const ValueKey<String>('shared-copy-button')));
    await tester.pumpAndSettle();
    await expectTheTimelinesAnswers();
    expect(
      timeline.canPasteLinkedFrame,
      isTrue,
      reason: 'LIVENESS: the copy reached the clipboard, and a paste is lit',
    );
  });
}
