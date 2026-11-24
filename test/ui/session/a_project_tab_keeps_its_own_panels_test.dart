import '../../helpers/screens_left_of_the_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/editing/default_cut_helpers.dart';
import 'package:anicel/src/services/editing/default_layer_helpers.dart';
import 'package:anicel/src/services/editing/run_id_mint.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/menu/editor_top_strip.dart';
import 'package:anicel/src/ui/open_projects.dart';
import 'package:anicel/src/ui/session/panel_view_memory.dart';
import 'package:anicel/src/ui/storyboard_panel.dart';
import 'package:anicel/src/ui/theme/app_theme.dart';
import 'package:anicel/src/ui/timeline/layer_rail_window.dart'
    show TimelineRulerViewCorner;
import 'package:anicel/src/ui/timeline/frame_ruler_view.dart';
import 'package:anicel/src/ui/timeline/timeline_zoom_limits.dart'
    show TimelineZoomLimits;

import '../../helpers/scrollable_of.dart';
import '../timeline/timeline_ruler_probe.dart' show timelineRulerPainter;

/// F-267 (유저 2026-10-01): 「콘티패널,타임라인패널 스크롤상태, 콘티패널,
/// 그리고 각 컷들 줌 상태도 프로젝트 파일에 기록해서 다시 열면 그대로
/// 열리도록」 — so each project holds its own. The window held one conte zoom
/// and one scroll per panel for every tab: a project came on screen at the
/// zoom another was left at, and a save of a tab behind wrote down the one in
/// front.
void main() {
  itsTestsLeaveScreensOfTheEngine({ScreensLeft.ofAShot});
  /// The default project with drawing rows enough for the rows to scroll.
  Project manyRows() {
    final project = createDefaultProject();
    final track = project.tracks.first;
    final cut = track.cuts.first;
    return project.copyWith(
      tracks: [
        track.copyWith(
          cuts: [
            cut.copyWith(
              layers: [
                for (var i = 0; i < 30; i += 1)
                  bornRowOfKind(
                    LayerKind.animation,
                    layerId: LayerId('row-$i'),
                    coveringFrameId: () => mintFrameId(LayerId('row-$i')),
                    cut: cut,
                  ),
                ...cut.layers,
              ],
            ),
          ],
        ),
      ],
    );
  }

  /// The default project with tracks enough for the conte's rows to scroll
  /// (four: one alone does not — measured 10-09).
  Project manyTracks() {
    final project = createDefaultProject();
    final track = project.tracks.first;
    return project.copyWith(
      tracks: [
        track,
        for (var i = 1; i < 4; i += 1)
          track.copyWith(id: TrackId('track-$i'), cuts: const []),
      ],
    );
  }

  Future<OpenProjects> openWindow(WidgetTester tester, Project project) async {
    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: HomePage(initialProject: project),
      ),
    );
    await tester.pumpAndSettle();
    return tester.widget<EditorTopStrip>(find.byType(EditorTopStrip)).projects;
  }

  testWidgets('a project tab shows the conte at ITS zoom — not at the one '
      'the last tab was left at', (tester) async {
    final projects = await openWindow(tester, createDefaultProject());
    await tester.tap(
      find.byKey(const ValueKey<String>('timeline-mode-storyboard-button')),
    );
    await tester.pumpAndSettle();
    double conteZoom() => tester
        .widget<StoryboardPanel>(find.byType(StoryboardPanel))
        .pixelsPerFrame;

    final first = projects.active;
    first.panelViews.storyboardPixelsPerFrame.value = 4;
    await tester.pumpAndSettle();
    expect(conteZoom(), 4, reason: 'premise: the conte shows the zoom');

    final second = projects.open(createDefaultProject());
    await tester.pumpAndSettle();
    expect(projects.active, same(second), reason: 'premise: B is in front');
    expect(
      conteZoom(),
      PanelViewMemory.defaultStoryboardPixelsPerFrame,
      reason: 'B was never zoomed — its conte opens at the default',
    );

    await projects.activate(first);
    await tester.pumpAndSettle();
    expect(conteZoom(), 4, reason: 'and A comes back at its own');
  });

  testWidgets('🚨a project tab writes its frames as IT was left — the '
      'rulers\' count is the project\'s, not the window\'s (F-354)', (
    tester,
  ) async {
    final projects = await openWindow(tester, createDefaultProject());
    final corner = find.byKey(
      const ValueKey<String>('timeline-time-display-toggle-button'),
    );
    FrameRulerView shown() =>
        tester.widget<TimelineRulerViewCorner>(corner).rulerView;

    final first = projects.active;
    await tester.tap(corner);
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('frame-ruler-view-pages')),
    );
    await tester.pumpAndSettle();
    expect(shown(), FrameRulerView.pages, reason: 'premise: the pick took');
    expect(first.panelViews.rulerView.value, FrameRulerView.pages);
    // I-81-Q1 「그 컷의 X시트 장을 따른다」: the open cut's paper, six
    // seconds at 24.
    final ruler = timelineRulerPainter(tester).scale;
    expect(ruler.pages, const TimelineRulerPages.every(144));
    expect(ruler.modelAt(0).secondsLabel, '0 p1');

    final second = projects.open(createDefaultProject());
    await tester.pumpAndSettle();
    expect(projects.active, same(second), reason: 'premise: B is in front');
    expect(
      shown(),
      FrameRulerView.frames,
      reason: 'B was never turned — it writes frames',
    );

    await projects.activate(first);
    await tester.pumpAndSettle();
    expect(
      shown(),
      FrameRulerView.pages,
      reason: 'and A comes back as it was left',
    );
  });

  for (final (sheet, viewportKey, rail, project, button) in [
    (
      'timeline\'s rows',
      'timeline-vertical-scroll-viewport',
      'timeline',
      manyRows,
      null,
    ),
    (
      'sheet\'s columns',
      'xsheet-layer-horizontal-viewport',
      'xsheet',
      manyRows,
      'timeline-orientation-toggle-button',
    ),
    (
      'conte\'s rows',
      'storyboard-vertical-viewport',
      'storyboard',
      manyTracks,
      'timeline-mode-storyboard-button',
    ),
  ]) {
    testWidgets('🚨a project tab shows the $sheet where IT left them — and '
        'the tab beside it at its own', (tester) async {
      final projects = await openWindow(tester, project());
      if (button != null) {
        await tester.tap(find.byKey(ValueKey<String>(button)));
        await tester.pumpAndSettle();
      }
      final layers = find.byKey(ValueKey<String>(viewportKey));
      ScrollController controller() => scrollableOf(tester, layers).controller!;
      // Half way along — whatever the window's width leaves to scroll.
      final along = (controller().position.maxScrollExtent / 2).roundToDouble();
      expect(along, greaterThan(10), reason: '⛔전제: the layers overflow');

      final first = projects.active;
      controller().jumpTo(along);
      await tester.pumpAndSettle();
      expect(
        first.panelViews.layerAxisOffsets[rail]!.value,
        along,
        reason: 'the scroll is the PROJECT\'s to keep',
      );

      projects.open(project());
      await tester.pumpAndSettle();
      expect(
        controller().offset,
        0,
        reason: 'B was never scrolled — its layers open at their start',
      );

      await projects.activate(first);
      await tester.pump();
      expect(
        controller().offset,
        along,
        reason: '🚨A comes back where it was, from its first frame',
      );
    });
  }

  /// Two cuts, each with drawing rows enough for the rows to scroll and
  /// frames enough for the frames to.
  Project twoCutsOfManyRows() {
    final project = manyRows();
    final track = project.tracks.first;
    final second = createDefaultCut(
      cutId: const CutId('c2'),
      name: '2',
      layerId: const LayerId('c2-drawing'),
    );
    return project.copyWith(
      tracks: [
        track.copyWith(
          cuts: [
            for (final cut in track.cuts) cut.copyWith(duration: 480),
            second.copyWith(
              duration: 480,
              layers: [
                for (var i = 0; i < 30; i += 1)
                  bornRowOfKind(
                    LayerKind.animation,
                    layerId: LayerId('c2-row-$i'),
                    coveringFrameId: () => mintFrameId(LayerId('c2-row-$i')),
                    cut: second,
                  ),
                ...second.layers,
              ],
            ),
          ],
        ),
      ],
    );
  }

  testWidgets('🚨each cut shows the timeline where IT was left — its rows '
      'and its frames, at its own zoom — not where the last cut was (H78, '
      '유저 2026-11-24: 「타임라인별로 스크롤상태, 줌상태 별도기억, 내부컷도 '
      '마찬가지」)', (tester) async {
    final projects = await openWindow(tester, twoCutsOfManyRows());
    final session = projects.active;
    final firstCut = session.activeCutId!;
    const secondCut = CutId('c2');
    session.timelineZoom.remember(
      secondCut,
      TimelineZoomLimits.referencePixelsPerFrame * 2,
    );
    ScrollController along(String key) =>
        scrollableOf(tester, find.byKey(ValueKey<String>(key))).controller!;
    ScrollController rows() => along('timeline-vertical-scroll-viewport');
    ScrollController frames() => along('timeline-frame-scroll-viewport');
    final down = (rows().position.maxScrollExtent / 2).roundToDouble();
    final across = (frames().position.maxScrollExtent / 2).roundToDouble();
    expect(
      [down, across],
      everyElement(greaterThan(10)),
      reason: '⛔전제: the rows and the frames overflow',
    );
    rows().jumpTo(down);
    frames().jumpTo(across);
    await tester.pumpAndSettle();

    session.selectCut(secondCut);
    await tester.pumpAndSettle();
    expect(
      [rows().offset, frames().offset],
      [0, 0],
      reason: 'a cut never scrolled opens at its start',
    );
    frames().jumpTo(64);
    await tester.pumpAndSettle();

    session.selectCut(firstCut);
    await tester.pump();
    expect(
      [rows().offset, frames().offset],
      [down, across],
      reason: '🚨the first comes back where it was, from its first frame — '
          'not bent by the zoom of the cut it came from',
    );
    await tester.pumpAndSettle();
    session.selectCut(secondCut);
    await tester.pumpAndSettle();
    expect(frames().offset, 64);
  });

  testWidgets('🚨each timeline shows the conte where IT was left — its '
      'frames at its own zoom — and one never opened at the default (H78)', (
    tester,
  ) async {
    final project = createDefaultProject();
    final track = project.tracks.first;
    final projects = await openWindow(
      tester,
      project.copyWith(
        tracks: [
          track.copyWith(
            cuts: [track.cuts.first.copyWith(duration: 480)],
          ),
        ],
      ),
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('timeline-mode-storyboard-button')),
    );
    await tester.pumpAndSettle();
    final session = projects.active;
    final first = session.timelineVerbs.currentTimelineId;
    double conteZoom() => tester
        .widget<StoryboardPanel>(find.byType(StoryboardPanel))
        .pixelsPerFrame;
    ScrollController frames() => scrollableOf(
      tester,
      find.byKey(
        const ValueKey<String>('storyboard-timeline-horizontal-viewport'),
      ),
    ).controller!;
    session.panelViews.storyboardPixelsPerFrame.value = 8;
    await tester.pumpAndSettle();
    final across = (frames().position.maxScrollExtent / 2).roundToDouble();
    expect(across, greaterThan(10), reason: '⛔전제: the frames overflow');
    frames().jumpTo(across);
    await tester.pumpAndSettle();

    session.timelineVerbs.addTimeline();
    await tester.pumpAndSettle();
    expect(session.timelineVerbs.currentTimelineId, isNot(first));
    expect(
      [conteZoom(), frames().offset],
      [PanelViewMemory.defaultStoryboardPixelsPerFrame, 0],
      reason: 'a timeline never opened shows the conte at the default zoom, '
          'at its start',
    );

    session.timelineVerbs.openTimeline(first);
    await tester.pump();
    expect(
      [conteZoom(), frames().offset],
      [8, across],
      reason: '🚨the first comes back where it was, from its first frame — '
          'not bent by the zoom of the timeline it came from',
    );
    await tester.pumpAndSettle();
  });
}
