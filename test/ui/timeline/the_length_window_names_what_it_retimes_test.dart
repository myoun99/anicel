import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/app_frame_count_settings.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/timeline_frame_range.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/text/app_strings.dart';
import 'package:anicel/src/ui/widgets/app_window.dart' show AppWindowField;

import '../../helpers/home_page_probes.dart';

/// 🗣️I-24-open-entry (유저 2026-10-01): 「노출 길이 설정 (프레임), 노출 길이
/// 설정 (컷) 이렇게 하자 … 프레임이든 초+코마든 노출 프레임수라는 텍스트
/// 필요없어보임 … 기존 이름 편집같은건 이름편집열때 기존이름있고, 그거
/// 선택된상태로 있잖아. 그거 그대로 재사용해서 통일. 길이 설정도 기존 길이
/// 띄워둔다는뜻」.
///
/// The N button's window, as the button opens it: titled with what the
/// press re-times, its field bare under that title, opened on the length
/// already there with all of it selected.
void main() {
  const nButton = ValueKey<String>('set-comma-n-button');

  // Which entry the window opens on is an app-wide value that outlives a
  // test: each starts from the product default.
  void resetEntry() =>
      AppFrameCountSettings.settings.value = const AppFrameCountSettings();
  setUp(resetEntry);
  tearDown(resetEntry);

  Future<EditorSessionManager> pumpHome(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const MaterialApp(home: HomePage()));
    await tester.pumpAndSettle();
    return tester
        .widget<EditorWorkspace>(find.byType(EditorWorkspace))
        .session;
  }

  Finder titledFor(String target) => find.text(
    AppText.strings.windowTitleOn(AppText.strings.setLengthAction, target),
  );

  TextEditingValue valueOf(WidgetTester tester, String key) => tester
      .widget<TextField>(find.byKey(ValueKey<String>(key)))
      .controller!
      .value;

  TextEditingValue allSelected(String text) => TextEditingValue(
    text: text,
    selection: TextSelection(baseOffset: 0, extentOffset: text.length),
  );

  Future<void> cancel(WidgetTester tester) async {
    await tester.tap(find.text(AppText.strings.commonCancel));
    await tester.pumpAndSettle();
  }

  testWidgets('on a cel: a frame\'s length, opened on its length with all '
      'of it selected — either way it is typed', (tester) async {
    final s = await pumpHome(tester);
    s.selectFrameIndex(0);
    s.createDrawingAtCurrentFrame();
    final fps = s.projectSettings.projectFrameRate.countingBase;
    s.edgeDrag.setCommaForTimelineCursor(fps + 2);
    await tester.pumpAndSettle();

    await tapToolbarButton(tester, nButton);
    expect(titledFor(AppText.strings.tlFrame), findsOneWidget);
    expect(valueOf(tester, 'set-comma-n-field'), allSelected('${fps + 2}'));
    expect(
      find.descendant(
        of: find.byType(AppWindowField),
        matching: find.byType(Text),
      ),
      findsNothing,
      reason: '「노출 프레임수라는 텍스트 필요없어보임」',
    );
    await cancel(tester);

    AppFrameCountSettings.settings.value = const AppFrameCountSettings(
      lastEntry: FrameCountEntry.secondsPlusFrames,
    );
    await tapToolbarButton(tester, nButton);
    expect(valueOf(tester, 'set-comma-n-seconds-field'), allSelected('1'));
    expect(valueOf(tester, 'set-comma-n-koma-field'), allSelected('2'));
    await cancel(tester);
    s.playbackRig.prerenderScheduler.cancel();
  });

  testWidgets('on the storyboard\'s V row: the cut\'s length', (tester) async {
    final s = await pumpHome(tester);
    await showStoryboardPanel(tester);
    s.selectGlobalFrame(0);
    s.selectTrackRow(s.selectedTrackId);
    await tester.pumpAndSettle();

    await tapToolbarButton(tester, nButton);
    expect(titledFor(AppText.strings.tlCut), findsOneWidget);
    expect(
      valueOf(tester, 'set-comma-n-field'),
      allSelected('${s.requireActiveCut.duration}'),
    );
    await cancel(tester);
    s.playbackRig.prerenderScheduler.cancel();
  });

  testWidgets('on a transition span: a transition\'s length', (
    tester,
  ) async {
    final s = await pumpHome(tester);
    s.selectLayer(s.activeTrack.transitionLayer.id);
    s.selectFrameIndex(2);
    s.transitions.createTransitionSpanInCut();
    await tester.pumpAndSettle();

    await tapToolbarButton(tester, nButton);
    expect(titledFor(AppText.strings.tlKindTransition), findsOneWidget);
    expect(valueOf(tester, 'set-comma-n-field'), allSelected('1'));
    await cancel(tester);
    s.playbackRig.prerenderScheduler.cancel();
  });

  testWidgets('a band over a cel and a sound names both, and opens empty '
      'where their lengths differ', (tester) async {
    final s = await pumpHome(tester);
    final sound = s.activeTrack.seLayers.first.id;
    s.selectLayer(sound);
    s.selectFrameIndex(0);
    s.seEntries.createSeEntryAtCurrentFrame(name: 'se', lengthFrames: 2);
    final cel = s.layers
        .firstWhere((layer) => layer.kind == LayerKind.animation)
        .id;
    s.selectLayer(cel);
    s.selectFrameIndex(0);
    s.createDrawingAtCurrentFrame();
    s.frameRangeSelection.value = TimelineFrameRangeSelection(
      layerId: cel,
      startIndex: 0,
      endIndexExclusive: 1,
      layerIds: [cel, sound],
    );
    await tester.pumpAndSettle();

    await tapToolbarButton(tester, nButton);
    final strings = AppText.strings;
    expect(
      titledFor('${strings.tlFrame} · ${strings.tlKindSe}'),
      findsOneWidget,
    );
    expect(valueOf(tester, 'set-comma-n-field').text, isEmpty);
    await cancel(tester);
    s.playbackRig.prerenderScheduler.cancel();
  });
}
