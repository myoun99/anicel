import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/app_language.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/storyboard_panel.dart';
import 'package:anicel/src/ui/timeline/timeline_command_bar.dart';
import 'package:anicel/src/ui/timeline/timeline_view_cluster.dart';
import 'package:anicel/src/ui/widgets/app_icon_button.dart';

import '../../helpers/rail_group_button.dart';
import '../../helpers/storyboard_host.dart';
import '../../helpers/timeline_host.dart';

/// F-111 (유저 2026-09-12: 「재생 버튼쪽 역시 다른곳으로 옮기고싶음. 문턱이아니라
/// 그냥 타임라인 버튼있는쪽 제일 왼쪽에 둔다던가?」), answered 10-08
/// (F-111-Q1 「버튼행 맨 왼쪽에 고정 — 알약 칸 밖」): each frame panel's
/// transport leads its own command bar, pinned outside the pills' overflow
/// scroller — and the region's 문턱 holds its tabs and its ⌃ alone.
///
/// The bar and its transport are the TAB's, so most of this opens the tab
/// alone, at the size the app lays it out. What the app answers opens the
/// app: the fold (the workspace's ⌃), a panel moved to a rail of its own,
/// and a language switch — the panel strip is what hears the language and
/// builds the tab again (`OpenTabContent`), and the tab alone has no strip.
void main() {
  /// Either tab as the app lays it out in a 1700 × 900 window (🔬1069 ×
  /// 396, both, 2026-10-25).
  const appTab = Size(1069, 396);

  Future<void> pumpApp(WidgetTester tester, Size size) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(home: HomePage(initialProject: createDefaultProject())),
    );
    await tester.pumpAndSettle();
  }

  EditorSessionManager sessionOf(WidgetTester tester) =>
      tester.widget<EditorWorkspace>(find.byType(EditorWorkspace)).session;

  Finder byKey(String key) => find.byKey(ValueKey<String>(key));

  Finder barOf(Finder piece) =>
      find.ancestor(of: piece, matching: find.byType(TimelineCommandBar));

  /// The pills' overflow scroller on [bar].
  Finder scrollerOn(Finder bar) =>
      find.descendant(of: bar, matching: find.byType(SingleChildScrollView));

  final panels = [
    (
      name: 'timeline',
      tab: 'timeline-mode-timeline-button',
      pumpTab: (WidgetTester tester) =>
          pumpTimelineHost(tester, createDefaultProject(), surface: appTab),
      transport: 'playback-transport-activeCut',
      camera: 'timeline-camera-view-button',
    ),
    (
      name: 'storyboard',
      tab: 'timeline-mode-storyboard-button',
      pumpTab: (WidgetTester tester) =>
          pumpStoryboardHost(tester, createDefaultProject(), surface: appTab),
      transport: 'playback-transport-allCuts',
      camera: 'storyboard-camera-view-button',
    ),
  ];

  for (final panel in panels) {
    testWidgets('🚨the ${panel.name}\'s transport leads its bar — at the '
        'bar\'s left edge, the camera view beside it, outside the pills\' '
        'scroller', (tester) async {
      await panel.pumpTab(tester);

      final transport = byKey(panel.transport);
      expect(transport, findsOneWidget);
      final bar = barOf(transport);
      expect(bar, findsOneWidget, reason: 'on the bar, not on the 문턱');
      final camera = byKey(panel.camera);
      expect(barOf(camera), findsOneWidget);
      final scroller = scrollerOn(bar);
      expect(scroller, findsOneWidget);
      expect(
        find.descendant(of: scroller, matching: transport),
        findsNothing,
        reason: 'outside the scroller',
      );
      expect(
        tester.getRect(transport).left,
        moreOrLessEquals(
          tester.getRect(bar).left + TimelineCommandBar.padding.left,
        ),
      );
      expect(
        tester.getRect(camera).left,
        greaterThanOrEqualTo(tester.getRect(transport).right),
      );
      expect(
        tester.getRect(scroller).left,
        greaterThan(tester.getRect(camera).right),
        reason: 'the pills come after it',
      );
    });
  }

  for (final panel in panels) {
    testWidgets('a notify that moves nothing on it builds none of the '
        '${panel.name}\'s transport again — its host keeps it', (
      tester,
    ) async {
      final session = await panel.pumpTab(tester);
      List<Widget> controls() => [
        ...tester.widgetList(
          find.descendant(
            of: byKey(panel.transport),
            matching: find.byType(AppIconButton),
          ),
        ),
        tester.widget(byKey(panel.camera)),
      ];
      final before = controls();
      expect(before.length, greaterThan(3), reason: 'premise: the buttons');

      // A full session notify — the host is built again — that changes
      // nothing the transport shows.
      session.layerSwitches.toggleLayerVisibility(
        session.layers.firstWhere((layer) => layer.kind == LayerKind.se).id,
      );
      await tester.pump();

      final after = controls();
      expect(after.length, before.length);
      for (var i = 0; i < after.length; i += 1) {
        expect(identical(after[i], before[i]), isTrue, reason: 'control $i');
      }
      session.playbackRig.prerenderScheduler.cancel();
    });
  }

  /// The play button in [transport], as built.
  AppIconButton playOn(WidgetTester tester, String transport) => tester
      .widgetList<AppIconButton>(
        find.descendant(
          of: byKey(transport),
          matching: find.byType(AppIconButton),
        ),
      )
      .firstWhere((button) => button.keyValue == 'playback-play-button');

  for (final panel in panels) {
    testWidgets('a language switch says the ${panel.name}\'s transport in '
        'the new language — the bar seats the transport built for it', (
      tester,
    ) async {
      await pumpApp(tester, const Size(1700, 900));
      await tester.tap(byKey(panel.tab));
      await tester.pumpAndSettle();
      final session = sessionOf(tester);
      final was = session.languageSettings.value;
      addTearDown(() => session.setLanguageSettings(was));
      final said = playOn(tester, panel.transport).tooltip;

      session.setLanguageSettings(
        AppLanguageSettings(
          programLanguage: was.programLanguage == AppLanguage.ko
              ? AppLanguage.en
              : AppLanguage.ko,
        ),
      );
      await tester.pump();

      expect(playOn(tester, panel.transport).tooltip, isNot(said));
    });
  }

  for (final (panel, seek) in [
    (panels[0], (EditorSessionManager s) => s.selectFrameIndex(2)),
    (panels[1], (EditorSessionManager s) => s.selectGlobalFrame(2)),
  ]) {
    testWidgets('the ${panel.name}\'s play button plays from where its '
        'playhead stands', (tester) async {
      final session = await panel.pumpTab(tester);
      seek(session);
      await tester.pumpAndSettle();

      await tester.tap(
        find.descendant(
          of: byKey(panel.transport),
          matching: byKey('playback-play-button'),
        ),
      );
      await tester.pump();

      final playback = session.playbackRig.playback;
      expect(playback.isPlaying, isTrue, reason: '⛔premise: it plays');
      expect(playback.playlistFrame, 2);
      playback.stop();
      await tester.pumpAndSettle();
    });
  }

  testWidgets('a pill row scrolled to its end leaves the transport where it '
      'stands', (tester) async {
    // The timeline as the app lays it out in a 1000 × 900 window (🔬640 ×
    // 396, 2026-10-25).
    await pumpTimelineHost(
      tester,
      createDefaultProject(),
      surface: const Size(640, 396),
    );
    final transport = byKey('playback-transport-activeCut');
    final scroller = scrollerOn(barOf(transport));
    final position = tester
        .state<ScrollableState>(
          find.descendant(of: scroller, matching: find.byType(Scrollable)),
        )
        .position;
    expect(
      position.maxScrollExtent,
      greaterThan(0),
      reason: '⛔premise: the pills overflow at this width',
    );
    final pill = find
        .descendant(of: scroller, matching: find.byType(AppIconButton))
        .first;
    final before = tester.getRect(transport);
    final pillBefore = tester.getRect(pill);

    position.jumpTo(position.maxScrollExtent);
    await tester.pump();

    expect(
      tester.getRect(pill).left,
      lessThan(pillBefore.left),
      reason: '⛔liveness: the row scrolled',
    );
    expect(tester.getRect(transport), before);
  });

  testWidgets('the fold keeps the bar, and the transport on it plays', (
    tester,
  ) async {
    await pumpApp(tester, const Size(1700, 900));
    await tester.tap(byKey('floating-bottom-collapse'));
    await tester.pumpAndSettle();

    final session = sessionOf(tester);
    expect(session.playbackRig.playback.isPlaying, isFalse);
    await tester.tap(
      find.descendant(
        of: byKey('playback-transport-activeCut'),
        matching: byKey('playback-play-button'),
      ),
    );
    await tester.pump();
    expect(session.playbackRig.playback.isPlaying, isTrue);
    session.playbackRig.playback.stop();
    await tester.pumpAndSettle();
  });

  testWidgets('with no cut selected, the transport stands where it stands '
      'with one', (tester) async {
    final session = await panels[0].pumpTab(tester);
    final cut = session.repository.requireProject().tracks.first.cuts.first;
    session.repository.updateCutLeadingGap(
      cutId: cut.id,
      leadingGapFrames: 3,
    );
    session.selectCut(cut.id);
    await tester.pumpAndSettle();
    final transport = byKey('playback-transport-activeCut');
    final withACut = tester.getRect(transport);

    session.selectGlobalFrame(1);
    await tester.pumpAndSettle();

    expect(session.activeCutOrNull, isNull, reason: '⛔premise: the gap');
    expect(byKey('timeline-empty-no-cut'), findsOneWidget);
    expect(transport, findsOneWidget);
    expect(tester.getRect(transport), withACut);
  });

  testWidgets('🚨the storyboard alone in a rail — narrower than its bar\'s '
      'two ends, and narrowed to the least it can be — shows its transport '
      'and its cluster whole, smaller, runs nothing over, and still plays', (
    tester,
  ) async {
    await pumpApp(tester, const Size(1600, 1000));

    final railId = EditorWorkspace.railGroupId(right: true, slot: 6);
    final freeSlot = railGroupButton(railId);
    final gesture = await tester.startGesture(
      tester.getCenter(byKey('panel-grip-storyboard')),
    );
    await tester.pump(const Duration(milliseconds: 20));
    await gesture.moveBy(const Offset(30, 0));
    await tester.pump();
    expect(freeSlot, findsOneWidget, reason: 'premise: the free slot');
    await gesture.moveTo(tester.getCenter(freeSlot));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
    expect(find.byType(StoryboardPanel), findsOneWidget, reason: 'premise');

    // A right rail narrows as its inner edge moves right. The grip runs the
    // group's height beside the panel's own controls, so it is taken where
    // nothing lies over it.
    final grip = byKey('dock-resize-$railId');
    Offset? handle() {
      final rect = tester.getRect(grip);
      final box = tester.renderObject(grip);
      for (var y = rect.top + 4; y < rect.bottom; y += 8) {
        final at = Offset(rect.center.dx, y);
        if (tester
            .hitTestOnBinding(at)
            .path
            .any((entry) => entry.target == box)) {
          return at;
        }
      }
      return null;
    }

    // A rail is narrower than the bar's two ends: the transport is shown
    // smaller than itself, the case this pins. Shown, it is scaled; laid
    // out, it keeps its own size.
    final transport = byKey('playback-transport-allCuts');
    expect(
      tester.getRect(transport).width,
      lessThan(tester.getSize(transport).width - 0.5),
      reason: '⛔premise: at the rail\'s own width the transport gives way',
    );
    // …and narrowed a step at a time down to the least the rail lets it be.
    double barWidth() => tester.getRect(barOf(transport)).width;
    final atFirst = barWidth();
    var was = double.infinity;
    for (var step = 0; step < 80 && barWidth() < was; step += 1) {
      was = barWidth();
      final at = handle();
      expect(at, isNotNull, reason: 'premise: the rail\'s grip is free');
      await tester.dragFrom(
        at!,
        const Offset(4, 0),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'at step $step');
    }
    expect(barWidth(), lessThan(atFirst), reason: '⛔LIVENESS: it narrowed');

    final bar = tester.getRect(barOf(transport));
    final shown = tester.getRect(transport);
    final cluster = tester.getRect(
      find.descendant(
        of: barOf(transport),
        matching: find.byType(TimelineViewCluster),
      ),
    );
    expect(shown.left, greaterThanOrEqualTo(bar.left));
    expect(shown.right, lessThanOrEqualTo(cluster.left));
    expect(cluster.right, lessThanOrEqualTo(bar.right));

    final session = sessionOf(tester);
    await tester.tap(
      find.descendant(of: transport, matching: byKey('playback-play-button')),
    );
    await tester.pump();
    expect(session.playbackRig.playback.isPlaying, isTrue);
    session.playbackRig.playback.stop();
    await tester.pumpAndSettle();
  });
}
