import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/storyboard_tab_host.dart';
import 'package:anicel/src/ui/timeline/layer_timeline_grid.dart';
import 'package:anicel/src/ui/timeline/timeline_cell_exposure_state.dart';
import 'package:anicel/src/ui/timeline/timeline_grid_hooks.dart';
import 'package:anicel/src/ui/timeline/timeline_grid_metrics.dart';
import 'package:anicel/src/ui/timeline/timeline_horizontal_scrollbar_rail.dart';
import 'package:anicel/src/ui/timeline/timeline_orientation.dart';
import 'package:anicel/src/ui/timeline/timeline_panel.dart';

/// 🚨F-174 (유저 2026-09-21): 「컷길이 엔드라인에 딱 맞추면 스크롤 쭉 해도
/// 엔드라인 안보이고 룰러 살짝 움직여야 엔드라인 보이니까, 스크롤바는
/// 엔드라인+1콤마? 를 기본 최소치로」.
///
/// The end line is drawn just PAST its frame, so a scroll range that stopped
/// on the line showed everything but it. Every frame axis that draws one is
/// here — the timeline, the x-sheet and the storyboard — and each is read
/// where the user reads it: the line's own rect against the far edge of its
/// view, with the scrollbar pushed all the way.
///
/// ⚠️Each film is LONGER than its view, so the scroll range — not the paper
/// that fills a wide view — decides where the scrollbar stops.
void main() {
  Layer drawing(String id) => Layer(
    id: LayerId(id),
    name: id,
    kind: LayerKind.animation,
    frames: [Frame(id: FrameId('$id-cel'), duration: 1, strokes: const [])],
    timeline: const {},
  );
  final layers = <Layer>[drawing('draw-0'), drawing('draw-1')];

  final rulerEndLine = find.byKey(
    const ValueKey<String>('timeline-cut-end-boundary-ruler'),
  );
  final bodyEndLine = find.byKey(
    const ValueKey<String>('timeline-cut-end-boundary'),
  );

  /// Pushes [controller] to the end of its range, as the scrollbar's thumb
  /// dragged all the way does.
  ///
  /// ⚠️And the range must STAY where it was: the axis grows only under a
  /// ruler edge-drag (UI-R12 #16). A follower resting one comma short of the
  /// extent would grow it by a comma on every push to the end — the one
  /// comma turning into an endless scrollbar.
  Future<void> scrollAllTheWay(
    WidgetTester tester,
    ScrollController controller,
  ) async {
    controller.jumpTo(controller.position.maxScrollExtent);
    await tester.pumpAndSettle();
    expect(
      controller.offset,
      controller.position.maxScrollExtent,
      reason: 'a push to the end leaves the range where it was',
    );
  }

  /// The paper between a line's leading edge and the view's far edge, along
  /// [axis] — one comma is 「엔드라인+1콤마」; zero or less is the line gone.
  double paperPast(Rect line, Rect view, Axis axis) =>
      axis == Axis.horizontal ? view.right - line.left : view.bottom - line.top;

  void expectTheLineShowsWithOneCommaAfterIt(
    WidgetTester tester, {
    required Finder line,
    required Rect view,
    required Axis axis,
    required double comma,
  }) {
    expect(line, findsWidgets, reason: 'fixture: the end line is built');
    for (final element in line.evaluate()) {
      final rect = tester.getRect(find.byWidget(element.widget));
      final farEdge = axis == Axis.horizontal ? rect.right : rect.bottom;
      final viewEdge = axis == Axis.horizontal ? view.right : view.bottom;
      expect(
        farEdge,
        lessThanOrEqualTo(viewEdge),
        reason: '「스크롤 쭉 해도 엔드라인 안보이고」 — the line is in view',
      );
      expect(
        paperPast(rect, view, axis),
        moreOrLessEquals(comma, epsilon: 0.5),
        reason: '「엔드라인+1콤마」 — one comma of paper after it, not a tail',
      );
    }
  }

  testWidgets('the timeline: pushed all the way, the end line shows with one '
      'comma after it', (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 320));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final cursor = ValueNotifier<int>(0);
    addTearDown(cursor.dispose);
    const frames = 160;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LayerTimelineGrid(
            hooks: TimelineGridHooks(
              activeLayerId: const LayerId('draw-0'),
              frameCursor: cursor,
              playbackFrameCount: frames,
              exposureStateForLayer: (_, _) =>
                  TimelineCellExposureState.uncovered,
              onSelectLayer: (_) {},
              onSelectFrame: (_) {},
              onToggleLayerVisibility: (_) {},
              onLayerOpacityChanged: (_, _) {},
              onToggleLayerTimesheet: (_) {},
              onLayerMarkSelected: (_, _) {},
            ),
            layers: layers,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final view = tester.getRect(
      find.byKey(const ValueKey<String>('timeline-frame-grid-area')),
    );
    final comma = TimelineGridMetrics.defaults.frameCellWidth;
    expect(frames * comma, greaterThan(view.width), reason: 'fixture');

    await scrollAllTheWay(
      tester,
      tester
          .widget<TimelineHorizontalScrollbarRail>(
            find.byKey(const ValueKey<String>('timeline-horizontal-scrollbar')),
          )
          .controller,
    );

    for (final line in [rulerEndLine, bodyEndLine]) {
      expectTheLineShowsWithOneCommaAfterIt(
        tester,
        line: line,
        view: view,
        axis: Axis.horizontal,
        comma: comma,
      );
    }
  });

  testWidgets('the x-sheet: pushed all the way down, the end line shows with '
      'one comma below it', (tester) async {
    await tester.binding.setSurfaceSize(const Size(560, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final cursor = ValueNotifier<int>(0);
    addTearDown(cursor.dispose);
    const frames = 240;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TimelinePanel(
            layers: layers,
            activeLayerId: const LayerId('draw-0'),
            frameCursor: cursor,
            playbackFrameCount: frames,
            exposureStateForLayer: (_, _) =>
                TimelineCellExposureState.uncovered,
            onSelectLayer: (_) {},
            onSelectFrame: (_) {},
            onAddLayer: () {},
            onToggleLayerVisibility: (_) {},
            onLayerOpacityChanged: (_, _) {},
            onToggleLayerTimesheet: (_) {},
            onLayerMarkSelected: (_, _) {},
            orientation: TimelineOrientation.vertical,
            onOrientationChanged: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final viewport = find.byKey(
      const ValueKey<String>('xsheet-frame-vertical-viewport'),
    );
    final view = tester.getRect(viewport);
    // The sheet's frame cell is the metrics' frame extent, turned on its
    // side: a row's HEIGHT.
    final comma = TimelineGridMetrics.defaults.frameCellWidth;
    expect(frames * comma, greaterThan(view.height), reason: 'fixture');

    await scrollAllTheWay(
      tester,
      tester.widget<SingleChildScrollView>(viewport).controller!,
    );

    for (final line in [rulerEndLine, bodyEndLine]) {
      expectTheLineShowsWithOneCommaAfterIt(
        tester,
        line: line,
        view: view,
        axis: Axis.vertical,
        comma: comma,
      );
    }
  });

  /// The storyboard over a movie whose end line sits at [cutFrames] +
  /// [gapFrames]: the line at the last cut's end, or past it on a trailing
  /// gap — the one case the strip's grip padding used to hide.
  Future<void> expectTheStoryboardEndShows(
    WidgetTester tester, {
    required int cutFrames,
    required int gapFrames,
  }) async {
    await tester.binding.setSurfaceSize(const Size(900, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final session = EditorSessionManager(
      initialProject: createDefaultProject(),
    );
    addTearDown(session.dispose);
    session.repository.updateCutDuration(
      cutId: session.repository.requireProject().tracks.first.cuts.first.id,
      duration: cutFrames,
    );
    session.repository.updateTrailingFrames(gapFrames);
    const pixelsPerFrame = 24.0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListenableBuilder(
            listenable: session,
            builder: (context, _) => StoryboardTabHost(
              session: session,
              pixelsPerFrame: pixelsPerFrame,
              onPixelsPerFrameChanged: (_) {},
              showSeconds: false,
              onShowSecondsChanged: (_) {},
              thumbnails: null,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final viewport = find.byKey(
      const ValueKey<String>('storyboard-timeline-horizontal-viewport'),
    );
    final view = tester.getRect(viewport);
    expect(
      (cutFrames + gapFrames) * pixelsPerFrame,
      greaterThan(view.width),
      reason: 'fixture',
    );

    await scrollAllTheWay(
      tester,
      tester.widget<SingleChildScrollView>(viewport).controller!,
    );

    expectTheLineShowsWithOneCommaAfterIt(
      tester,
      line: rulerEndLine,
      view: view,
      axis: Axis.horizontal,
      comma: pixelsPerFrame,
    );
  }

  testWidgets('the storyboard: pushed all the way, the movie\'s end line '
      'shows with one comma after it — at the last cut\'s end', (
    tester,
  ) async {
    await expectTheStoryboardEndShows(tester, cutFrames: 200, gapFrames: 0);
  });

  testWidgets('the storyboard: … and past it, on a trailing gap', (
    tester,
  ) async {
    await expectTheStoryboardEndShows(tester, cutFrames: 24, gapFrames: 100);
  });
}
