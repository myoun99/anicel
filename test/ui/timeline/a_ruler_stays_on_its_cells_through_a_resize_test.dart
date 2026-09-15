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

/// F-95 — a ruler stays on its cells through a resize.
///
/// 유저 2026-09-12: 「타임라인패널이든 스토리보드패널이든 패널의 스플리터로 좌우
/// 길이 바꾸면 타임라인 룰러랑 내부 프레임 영역이랑 위치가 좌우 방향으로
/// 어긋남. 근본/구조적으로 어긋나지 않도록」.
///
/// 🧪Measured before the fix, on the timeline: scrolled to 2635 and widened
/// from 700 to 1300, the cells went to 2035 and the ruler stayed at 2635. A
/// viewport whose content no longer reaches past it corrects its position
/// during layout and calls no listener, and the ruler moved by a copy fed
/// from listeners. So every case here stands at the END, where that
/// correction happens, and reads the two halves in the frame of each step —
/// a ruler that caught up a frame later still came off its cells while the
/// splitter moved.
///
/// ⚠️At a FRACTIONAL ratio, so the device-grid correction both halves wear
/// is not the identity (「이음매 테스트는 소수 배율에서」).
void main() {
  Layer drawing(String id) => Layer(
    id: LayerId(id),
    name: id,
    kind: LayerKind.animation,
    frames: [Frame(id: FrameId('$id-cel'), duration: 1, strokes: const [])],
    timeline: const {},
  );
  final layers = <Layer>[for (var i = 0; i < 3; i += 1) drawing('draw-$i')];
  const step = 97.5;

  Future<void> atAFractionalRatio(WidgetTester tester, Size surface) async {
    tester.view.devicePixelRatio = 1.5;
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.binding.setSurfaceSize(surface);
    addTearDown(() => tester.binding.setSurfaceSize(null));
  }

  /// The timeline grid [width] wide over a film of [frames] frames.
  Widget timelineHost({
    required ValueNotifier<double> width,
    required ValueNotifier<int> frames,
    required ValueNotifier<int> cursor,
    ValueChanged<int>? onSelectFrame,
  }) => MaterialApp(
    home: Scaffold(
      body: Align(
        alignment: Alignment.topLeft,
        child: ListenableBuilder(
          listenable: Listenable.merge([width, frames]),
          builder: (context, _) => SizedBox(
            width: width.value,
            height: 264,
            child: LayerTimelineGrid(
              hooks: TimelineGridHooks(
                activeLayerId: const LayerId('draw-0'),
                frameCursor: cursor,
                playbackFrameCount: frames.value,
                exposureStateForLayer: (_, _) =>
                    TimelineCellExposureState.uncovered,
                onSelectLayer: (_) {},
                onSelectFrame: onSelectFrame ?? (_) {},
                onToggleLayerVisibility: (_) {},
                onLayerOpacityChanged: (_, _) {},
                onToggleLayerTimesheet: (_) {},
                onLayerMarkSelected: (_, _) {},
              ),
              layers: layers,
            ),
          ),
        ),
      ),
    ),
  );

  final timelineRuler = find.byKey(
    const ValueKey<String>('timeline-frame-ruler'),
  );
  final timelineCells = find.byKey(
    const ValueKey<String>('timeline-frame-scroll-content'),
  );
  ScrollController timelineController(WidgetTester tester) => tester
      .widget<TimelineHorizontalScrollbarRail>(
        find.byKey(const ValueKey<String>('timeline-horizontal-scrollbar')),
      )
      .controller;

  /// Scrolls [controller] to its end, grows [extent] in steps and shrinks
  /// it back, reading [ruler] against [cells] after every step. [atTheWidest]
  /// runs once the grown panel has settled.
  Future<void> resizeAtTheEnd(
    WidgetTester tester, {
    required ValueNotifier<double> extent,
    required ScrollController controller,
    required double Function() ruler,
    required double Function() cells,
    Future<void> Function()? atTheWidest,
  }) async {
    controller.jumpTo(controller.position.maxScrollExtent);
    await tester.pumpAndSettle();
    // The two keys need not sit on the same pixel; they must not MOVE
    // apart. At rest that is F-32's own test.
    final apart = ruler() - cells();
    final scrolled = controller.offset;

    for (var i = 0; i < 6; i += 1) {
      extent.value += step;
      await tester.pump();
      expect(
        ruler() - cells(),
        moreOrLessEquals(apart, epsilon: 0.01),
        reason: 'grown to ${extent.value}: the ruler must stand on its cells '
            'in the frame the panel grew',
      );
    }
    expect(
      controller.offset,
      lessThan(scrolled),
      reason: 'fixture: growing past the end pulled the position back — the '
          'correction this is about',
    );
    await tester.pumpAndSettle();
    await atTheWidest?.call();
    final pulledTo = controller.offset;

    for (var i = 0; i < 6; i += 1) {
      extent.value -= step;
      await tester.pump();
      expect(
        ruler() - cells(),
        moreOrLessEquals(apart, epsilon: 0.01),
        reason: 'shrunk to ${extent.value}: the ruler must stay on its cells',
      );
    }
    await tester.pumpAndSettle();
    expect(
      controller.offset,
      pulledTo,
      reason: 'narrowing again must not pull the view back toward where it '
          'stood before the panel grew — the layout clamp asked for that '
          'offset from a copy the growth never reached',
    );
  }

  testWidgets('the timeline ruler stays on its cells while its panel is '
      'resized at the end', (tester) async {
    await atAFractionalRatio(tester, const Size(1800, 400));
    final width = ValueNotifier<double>(700);
    addTearDown(width.dispose);
    final frames = ValueNotifier<int>(120);
    addTearDown(frames.dispose);
    final cursor = ValueNotifier<int>(0);
    addTearDown(cursor.dispose);
    final selected = <int>[];
    await tester.pumpWidget(
      timelineHost(
        width: width,
        frames: frames,
        cursor: cursor,
        onSelectFrame: selected.add,
      ),
    );
    await tester.pumpAndSettle();

    await resizeAtTheEnd(
      tester,
      extent: width,
      controller: timelineController(tester),
      ruler: () => tester.getRect(timelineRuler).left,
      cells: () => tester.getRect(timelineCells).left,
      // A press on the grown ruler names the frame under it: the scrub
      // counts from the offset the ruler is painted at.
      atTheWidest: () async {
        final area = tester.getRect(
          find.byKey(const ValueKey<String>('timeline-frame-grid-area')),
        );
        final x = area.left + area.width / 4;
        selected.clear();
        await tester.tapAt(Offset(x, tester.getRect(timelineRuler).center.dy));
        await tester.pump();
        expect(
          selected,
          isNotEmpty,
          reason: 'fixture: the press reached the ruler',
        );
        expect(
          selected.first,
          ((x - tester.getRect(timelineCells).left) /
                  TimelineGridMetrics.defaults.frameCellWidth)
              .floor(),
        );
      },
    );
  });

  testWidgets('the timeline ruler stays on its cells when the film shortens '
      'under it at the end', (tester) async {
    // F-119 (유저 2026-09-12): 「마지막에 있던 컷 블록을 앞으로 당기면 최종
    // 영상 엔드라인이 움직이면서 룰러랑 프레임영역이랑 어긋남 … 타임라인에도
    // 같은 현상 있는지 확인해서 법 하나로 통일」. A film that SHORTENS under
    // a view standing at its end makes the correction a growing panel makes.
    await atAFractionalRatio(tester, const Size(1800, 400));
    final width = ValueNotifier<double>(700);
    addTearDown(width.dispose);
    final frames = ValueNotifier<int>(160);
    addTearDown(frames.dispose);
    final cursor = ValueNotifier<int>(0);
    addTearDown(cursor.dispose);
    await tester.pumpWidget(
      timelineHost(width: width, frames: frames, cursor: cursor),
    );
    await tester.pumpAndSettle();

    final controller = timelineController(tester);
    controller.jumpTo(controller.position.maxScrollExtent);
    await tester.pumpAndSettle();
    double apartNow() =>
        tester.getRect(timelineRuler).left - tester.getRect(timelineCells).left;
    final apart = apartNow();
    final scrolled = controller.offset;

    for (final count in <int>[150, 130, 100]) {
      frames.value = count;
      await tester.pump();
      expect(
        apartNow(),
        moreOrLessEquals(apart, epsilon: 0.01),
        reason: 'shortened to $count frames: the ruler must stand on its '
            'cells in the frame the film shortened',
      );
    }
    expect(
      controller.offset,
      lessThan(scrolled),
      reason: 'fixture: the shorter film pulled the position back — the '
          'correction this is about',
    );
  });

  testWidgets('the x-sheet frame rail stays on its cells while its panel is '
      'resized at the end', (tester) async {
    await atAFractionalRatio(tester, const Size(560, 1800));
    final height = ValueNotifier<double>(520);
    addTearDown(height.dispose);
    final cursor = ValueNotifier<int>(0);
    addTearDown(cursor.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: ValueListenableBuilder<double>(
              valueListenable: height,
              builder: (context, extent, _) => SizedBox(
                width: 560,
                height: extent,
                child: TimelinePanel(
                  layers: layers,
                  activeLayerId: const LayerId('draw-0'),
                  frameCursor: cursor,
                  playbackFrameCount: 240,
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
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final viewport = find.byKey(
      const ValueKey<String>('xsheet-frame-vertical-viewport'),
    );
    await resizeAtTheEnd(
      tester,
      extent: height,
      controller: tester.widget<SingleChildScrollView>(viewport).controller!,
      ruler: () => tester
          .getRect(find.byKey(const ValueKey<String>('xsheet-frame-number-rail')))
          .top,
      cells: () => tester
          .getRect(
            find.descendant(of: viewport, matching: find.byType(SizedBox)).first,
          )
          .top,
    );
  });

  testWidgets('the storyboard ruler stays on its cells while its panel is '
      'resized at the end', (tester) async {
    await atAFractionalRatio(tester, const Size(1800, 900));
    final session = EditorSessionManager(
      initialProject: createDefaultProject(),
    );
    addTearDown(session.dispose);
    final width = ValueNotifier<double>(700);
    addTearDown(width.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: ValueListenableBuilder<double>(
              valueListenable: width,
              builder: (context, extent, _) => SizedBox(
                width: extent,
                height: 600,
                child: ListenableBuilder(
                  listenable: session,
                  builder: (context, _) => StoryboardTabHost(
                    session: session,
                    pixelsPerFrame: 24,
                    onPixelsPerFrameChanged: (_) {},
                    showSeconds: false,
                    onShowSecondsChanged: (_) {},
                    thumbnailFor: null,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final viewport = find.byKey(
      const ValueKey<String>('storyboard-timeline-horizontal-viewport'),
    );
    final controller = tester.widget<SingleChildScrollView>(viewport).controller!;
    final ruler = find.byKey(const ValueKey<String>('storyboard-ruler'));
    await resizeAtTheEnd(
      tester,
      extent: width,
      controller: controller,
      ruler: () => tester.getRect(ruler).left,
      cells: () => tester
          .getRect(
            find.descendant(of: viewport, matching: find.byType(Stack)).first,
          )
          .left,
      // 🚨The storyboard ruler measures a press against the offset COPY to
      // decide whether it landed in an edge band. A copy the growth never
      // reached puts a press a quarter of the way in past the left edge,
      // and the view pans under a plain tap.
      atTheWidest: () async {
        final strip = tester.getRect(viewport);
        final before = controller.offset;
        await tester.tapAt(
          Offset(
            strip.left + strip.width / 4,
            tester.getRect(ruler).center.dy,
          ),
        );
        await tester.pumpAndSettle();
        expect(
          controller.offset,
          before,
          reason: 'a press a quarter of the way into the ruler is no push '
              'toward an edge',
        );
      },
    );
  });
}
