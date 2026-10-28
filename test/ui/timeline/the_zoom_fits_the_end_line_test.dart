import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/storyboard_timeline_layout.dart'
    show movieEndFrames;
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/theme/app_theme.dart';
import 'package:anicel/src/ui/shortcuts/editor_action_registry.dart';
import 'package:anicel/src/ui/shortcuts/editor_shortcut_scope.dart';
import 'package:anicel/src/ui/timeline/layer_rail_window.dart';
import 'package:anicel/src/ui/timeline/timeline_edge_auto_pan.dart'
    show keptAxisWindows;
import 'package:anicel/src/ui/timeline/timeline_panel.dart';
import 'package:anicel/src/ui/timeline/timeline_view_cluster.dart';
import 'package:anicel/src/ui/timeline/timeline_zoom_limits.dart';
import 'package:anicel/src/ui/widgets/app_icon_button.dart';

import '../../helpers/scrollable_of.dart';
import '../../helpers/timeline_zoom.dart';

/// 🗣️I-111 (유저 2026-10-19): 「타임라인/콘티패널등 줌 fit 버튼 추가. 해당
/// 패널의 엔드라인에 맞춰서 스크롤바 fit하는것」 · 「위치는 줌 확대버튼
/// 오른쪽」.
///
/// The fit is the closest zoom at which the panel's end line stands inside
/// its window — a step of the bar (F-403) — with the axis at its start.
///
/// 🗣️F-472 (유저 2026-10-26): 「엔드라인조차 안보이니까 엔드라인뒤 1코마까지
/// 추가로 보여주는걸로」 — one koma past the end line stands in it too.
void main() {
  const frames = 120;
  /// A step of the bar: 1% of its 100%, half the zoom a cut opens at (F-491).
  const step = TimelineZoomLimits.referencePixelsPerFrame / 200;

  Cut cut(String id, int duration) => Cut(
    id: CutId(id),
    name: id,
    duration: duration,
    canvasSize: const CanvasSize(width: 640, height: 360),
    layers: [
      Layer(id: LayerId('$id-layer'), name: 'A', frames: const []),
    ],
  );

  /// The cut worked in, far longer than the timeline's window at 100% — and
  /// one after it, so the movie ends where the cut does not.
  Project film() => Project(
    id: const ProjectId('zoom-fit'),
    name: 'Zoom fit',
    createdAt: DateTime.utc(2026, 10, 20),
    tracks: [
      Track(
        id: const TrackId('t'),
        name: 'Video',
        cuts: [cut('cut', frames), cut('next', 60)],
      ),
    ],
  );

  final frameScroller = find.byKey(
    const ValueKey<String>('timeline-frame-scroll-viewport'),
  );
  final fit = find.byKey(const ValueKey<String>('timeline-zoom-fit-button'));

  Future<EditorSessionManager> open(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1500, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: HomePage(initialProject: film()),
      ),
    );
    await tester.pumpAndSettle();
    return tester.widget<EditorWorkspace>(find.byType(EditorWorkspace)).session;
  }

  ScrollPosition frameAxisOf(WidgetTester tester) =>
      scrollableOf(tester, frameScroller).controller!.position;

  double timelineZoom(WidgetTester tester) =>
      tester.widget<TimelinePanel>(find.byType(TimelinePanel)).pixelsPerFrame;

  /// [zoom] is the closest step at which [count] frames stand in [window].
  void expectFits(double zoom, int count, double window) {
    expect(count * zoom, lessThanOrEqualTo(window), reason: 'it stands in');
    expect(
      count * (zoom + step),
      greaterThan(window),
      reason: 'a step closer would not',
    );
  }

  // ↩️「위치는 줌 확대버튼 오른쪽」 (I-111) — F-463 took the + off, and the
  // fit stayed where it was: 「그 옆의 줌 fit버튼은 그대로」. ↩️It stood
  // past the readout's own pencil, until F-463 took that off too (10-27).
  testWidgets('it stands right of the zoom\'s readout, the cluster\'s first '
      'button', (tester) async {
    await open(tester);
    final buttons = [
      for (final button in tester.widgetList<AppIconButton>(
        find.descendant(
          of: find.byType(TimelineViewCluster),
          matching: find.byType(AppIconButton),
        ),
      ))
        button.keyValue,
    ];
    expect(buttons.indexOf('timeline-zoom-fit-button'), 0, reason: '$buttons');
    expect(
      tester.getRect(fit).left,
      greaterThanOrEqualTo(tester.getRect(timelineZoomReadout).right),
    );
  });

  testWidgets('🚨on the timeline, the cut\'s end line stands in the window '
      'and the axis at its start — and the cut keeps the zoom', (
    tester,
  ) async {
    final session = await open(tester);
    await dragTimelineZoom(tester, 25);
    frameAxisOf(tester).jumpTo(300);
    await tester.pumpAndSettle();
    expect(frameAxisOf(tester).pixels, greaterThan(0), reason: '⛔전제');

    await tester.tap(fit);
    await tester.pumpAndSettle();

    final zoom = timelineZoom(tester);
    expectFits(zoom, frames + 1, frameAxisOf(tester).viewportDimension);
    expect(frameAxisOf(tester).pixels, 0, reason: 'at its start');
    expect(session.timelineZoom.zoomOf(session.activeCutId), zoom);
  });

  testWidgets('on the conte, the movie\'s end line', (tester) async {
    final session = await open(tester);
    await tester.tap(
      find.byKey(const ValueKey<String>('timeline-mode-storyboard-button')),
    );
    await tester.pumpAndSettle();
    await zoomTimelineTo(tester, TimelineZoomLimits.maxPixelsPerFrame);
    final kept = session.panelViews.frameAxisOffsets[LayerRailId.storyboard]!;
    kept.value = 200;
    await tester.pumpAndSettle();
    expect(kept.value, greaterThan(0), reason: '⛔전제: it scrolled away');
    final movie = movieEndFrames(session.repository.requireProject());
    expect(movie, greaterThan(frames), reason: '⛔전제: past the cut\'s end');

    await tester.tap(fit);
    await tester.pumpAndSettle();

    expectFits(
      session.panelViews.storyboardPixelsPerFrame.value,
      movie + 1,
      keptAxisWindows[kept]!,
    );
    expect(kept.value, 0, reason: 'at its start');
  });

  group('the fit stays on the bar', () {
    const fps = 24;

    test('a film too long to stand in stops at the widest', () {
      expect(
        TimelineZoomLimits.fitting(1000, frames: 1 << 20, framesPerSecond: fps),
        closeTo(TimelineZoomLimits.minPixelsPerFrameAt(fps), 1e-9),
      );
    });

    test('a film shorter than the window stops at the closest — and no '
        'frames at all is not a division by nothing', () {
      for (final count in [1, 0]) {
        expect(
          TimelineZoomLimits.fitting(1000, frames: count, framesPerSecond: fps),
          closeTo(TimelineZoomLimits.maxPixelsPerFrame, 1e-9),
          reason: '$count frames',
        );
      }
    });

    test('a fit that falls between two steps takes the wider — past the '
        'middle of them too, where the nearer would run over', () {
      // 1000 / 100 = 10px is 104.17 steps of 1% of 9.6px; 1000 / 96 =
      // 10.42px is 108.51.
      expect(
        TimelineZoomLimits.fitting(1000, frames: 100, framesPerSecond: fps),
        closeTo(104 * step, 1e-9),
      );
      expect(
        TimelineZoomLimits.fitting(1000, frames: 96, framesPerSecond: fps),
        closeTo(108 * step, 1e-9),
      );
    });
  });

  testWidgets('a key recorded for it fits the panel worked in', (
    tester,
  ) async {
    await open(tester);
    EditorShortcutScope.peek(
      tester.element(find.byType(EditorWorkspace)),
    )!.setActivators(EditorActionIds.timelineZoomFit, const [
      SingleActivator(LogicalKeyboardKey.keyK),
    ]);
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
    await tester.pumpAndSettle();

    expectFits(
      timelineZoom(tester),
      frames + 1,
      frameAxisOf(tester).viewportDimension,
    );
  });
}
