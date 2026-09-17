import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/ui/storyboard_panel.dart';
import 'package:anicel/src/ui/timeline/layer_timeline_grid.dart';
import 'package:anicel/src/ui/timeline/timeline_cell_exposure_state.dart';
import 'package:anicel/src/ui/timeline/timeline_grid_hooks.dart';
import 'package:anicel/src/ui/timeline/timeline_grid_metrics.dart';
import 'package:anicel/src/ui/timeline/timeline_horizontal_scrollbar_rail.dart';
import 'package:anicel/src/ui/timeline/xsheet_timeline_grid.dart';

/// 🚨★★★**F-110 (유저 2026-09-12)**: 「재생시에도 플레이헤드 밖 나갈때
/// 스크롤하도록. **룰러 드래그랑은 다르게 다음 페이지? 로 간다는 느낌**임.
/// 뭐냐면 넘어가면 **룰러가 왼쪽에 오도록 스크롤바 한번만 이동**」.
///
/// Before this round NOTHING scrolled on a playback tick — the reveal walk
/// answered the arrow keys and nothing else — so the playhead simply left
/// the window and stayed gone.
///
/// 🧪**Three cells per surface, and the third is the one that says this is a
/// SECOND law rather than a setting on the first**:
/// ① a tick that carries the playhead out of the window turns the page, and
///    the playhead's own frame stands at the window's START;
/// ② the next tick, still inside that window, does not move it AT ALL —
///    which is what 「스크롤바 한번만 이동」 means and what a nearest-edge
///    walk would get wrong on every single frame;
/// ③ the same move with NOTHING PLAYING does not scroll at all. A hand's
///    seek is the walk's business, and the walk arrives on its own tick.
///
/// ⛔**All three surfaces, not the one that was easiest to mount.** The rail
/// runs its frames across, the x-sheet runs them DOWN, and the storyboard
/// runs a global strip — 「전 가족 × 전 인터랙션」, and a law kept in one
/// place is only kept if every caller asks it.
void main() {
  Layer layer(String id, LayerKind kind) => Layer(
    id: LayerId(id),
    name: id,
    kind: kind,
    frames: kind == LayerKind.animation
        ? [Frame(id: FrameId('$id-cel'), duration: 1, strokes: const [])]
        : const [],
    timeline: const {},
  );

  final layers = <Layer>[
    for (var i = 0; i < 6; i += 1) layer('draw-$i', LayerKind.animation),
  ];

  const cell = 20.0;
  const frames = 400;

  /// ⛔ASKED OF THE SCROLLABLE, not of the widget that builds it. A test
  /// that names `SingleChildScrollView` pins the spelling of a viewport
  /// rather than the scroll, and the timeline's frame axis has already
  /// changed which kind of viewport it mounts once.
  ScrollPosition positionOf(WidgetTester tester, String key) => tester
      .state<ScrollableState>(
        find
            .descendant(
              of: find.byKey(ValueKey<String>(key)),
              matching: find.byType(Scrollable),
            )
            .first,
      )
      .position;

  TimelineGridHooks hooks({
    required ValueListenable<int> cursor,
    required ValueListenable<int?> playback,
  }) => TimelineGridHooks(
    activeLayerId: const LayerId('draw-0'),
    frameCursor: cursor,
    playbackFrame: playback,
    playbackFrameCount: frames,
    exposureStateForLayer: (_, _) => TimelineCellExposureState.uncovered,
    onSelectLayer: (_) {},
    onSelectFrame: (_) {},
    onToggleLayerVisibility: (_) {},
    onLayerOpacityChanged: (_, _) {},
    onToggleLayerTimesheet: (_) {},
    onLayerMarkSelected: (_, _) {},
  );

  /// The three cells, driven through whatever the surface calls its cursor.
  /// [move] puts the playhead on a frame; [offset] reads the frame axis.
  Future<void> walkTheThreeCells({
    required ValueNotifier<int?> playing,
    required Future<void> Function(int frame) move,
    required double Function() offset,
  }) async {
    expect(offset(), 0, reason: 'the fixture starts at the window start');

    // ③ FIRST, while nothing plays: the same move that pages below does
    // nothing here.
    await move(90);
    expect(
      offset(),
      0,
      reason: 'with nothing playing a cursor move is the WALK\'s business',
    );

    // ① now playing — the page turns and the playhead stands at the start.
    playing.value = 90;
    await move(91);
    expect(
      offset(),
      91 * cell,
      reason: 'the playhead\'s frame stands at the window start',
    );

    // ② the next tick is inside that window: nothing moves.
    final settled = offset();
    await move(92);
    expect(
      offset(),
      settled,
      reason: '「스크롤바 한번만 이동」 — a tick inside the window moves '
          'nothing at all',
    );
  }

  testWidgets('the rail turns its page under a playing playhead, once per '
      'window, and not at all without one', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final cursor = ValueNotifier<int>(0);
    final playing = ValueNotifier<int?>(null);
    addTearDown(cursor.dispose);
    addTearDown(playing.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LayerTimelineGrid(
            hooks: hooks(cursor: cursor, playback: playing),
            layers: layers,
            metrics: TimelineGridMetrics.defaults.copyWith(
              frameCellWidth: cell,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await walkTheThreeCells(
      playing: playing,
      move: (frame) async {
        cursor.value = frame;
        await tester.pump();
      },
      offset: () =>
          positionOf(tester, 'timeline-frame-scroll-viewport').pixels,
    );
  });

  testWidgets('the x-sheet turns its page the same way, down its own axis', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final cursor = ValueNotifier<int>(0);
    final playing = ValueNotifier<int?>(null);
    addTearDown(cursor.dispose);
    addTearDown(playing.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: XSheetTimelineGrid(
            hooks: hooks(cursor: cursor, playback: playing),
            layers: layers,
            metrics: XSheetTimelineGrid.defaultMetrics.copyWith(
              frameCellWidth: cell,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await walkTheThreeCells(
      playing: playing,
      move: (frame) async {
        cursor.value = frame;
        await tester.pump();
      },
      offset: () =>
          positionOf(tester, 'xsheet-frame-vertical-viewport').pixels,
    );
  });

  testWidgets('the storyboard strip turns its page on the GLOBAL frame', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final playhead = ValueNotifier<int?>(0);
    final playing = ValueNotifier<int?>(null);
    addTearDown(playhead.dispose);
    addTearDown(playing.dispose);
    final project = Project(
      id: const ProjectId('page-project'),
      name: 'Page',
      createdAt: DateTime.utc(2026, 9, 12),
      tracks: [
        Track(
          id: const TrackId('page-track'),
          name: 'Video',
          cuts: [
            Cut(
              id: const CutId('page-cut'),
              name: 'Page Cut',
              duration: frames,
              canvasSize: const CanvasSize(width: 640, height: 360),
              layers: const [],
            ),
          ],
        ),
      ],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StoryboardPanel(
            project: project,
            activeCutId: const CutId('page-cut'),
            pixelsPerFrame: cell,
            playheadFrame: playhead,
            playbackFrame: playing,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // ⚠️The strip has no keyed viewport of its own; its scrollbar rail is
    // handed the very controller the panel scrolls, so that is what the
    // offset is read off.
    double offset() => tester
        .widget<TimelineHorizontalScrollbarRail>(
          find.byKey(
            const ValueKey<String>('storyboard-horizontal-scrollbar'),
          ),
        )
        .controller
        .position
        .pixels;

    await walkTheThreeCells(
      playing: playing,
      move: (frame) async {
        playhead.value = frame;
        await tester.pump();
      },
      offset: offset,
    );
  });
}
