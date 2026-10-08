import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/editing/default_layer_helpers.dart';
import 'package:anicel/src/services/editing/run_id_mint.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/menu/editor_top_strip.dart';
import 'package:anicel/src/ui/open_projects.dart';
import 'package:anicel/src/ui/session/panel_view_memory.dart';
import 'package:anicel/src/ui/storyboard_panel.dart';
import 'package:anicel/src/ui/theme/app_theme.dart';

import '../../helpers/scrollable_of.dart';

/// F-267 (유저 2026-10-01): 「콘티패널,타임라인패널 스크롤상태, 콘티패널,
/// 그리고 각 컷들 줌 상태도 프로젝트 파일에 기록해서 다시 열면 그대로
/// 열리도록」 — so each project holds its own. The window held one conte zoom
/// and one scroll per panel for every tab: a project came on screen at the
/// zoom another was left at, and a save of a tab behind wrote down the one in
/// front.
void main() {
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

    projects.activate(first);
    await tester.pumpAndSettle();
    expect(conteZoom(), 4, reason: 'and A comes back at its own');
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

      projects.activate(first);
      await tester.pump();
      expect(
        controller().offset,
        along,
        reason: '🚨A comes back where it was, from its first frame',
      );
    });
  }
}
