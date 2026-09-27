import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/storyboard_panel.dart';
import 'package:anicel/src/ui/storyboard_playhead_mapping.dart'
    show commitStoryboardScrub, scrubStoryboardGlobalFrame;
import 'package:anicel/src/ui/theme/app_theme.dart';
import 'package:anicel/src/ui/timeline/collapsed_row_overlay.dart';
import 'package:anicel/src/ui/timeline/timeline_frame_cursor_layer.dart';
import 'package:anicel/src/ui/timeline/timeline_zoom_limits.dart';

import '../../helpers/home_page_probes.dart';
import '../../helpers/repaint_strays.dart';
import '../../helpers/scrollable_of.dart';

/// 🚨★★★**THE FOLDED ROW FOLLOWS PLAYBACK — THE PLAYHEAD, THE INDEX AND THE
/// PAGE, BY THE OPEN PANEL'S OWN LAWS.**
///
/// 🗣️유저 2026-09-27 (folded-row-playhead-during-playback-Q1): 「재생을
/// 따른다」 — 「로직만 가볍게 잘 해줘 층 최대한 나눠서 굽는다던가 알아서
/// 접힌 오버레이도 재생헤드나 인덱스나 스크롤이동이나 다 구조적으로 동기화」.
///
/// Measured before (09-27, this file's probe): playing frame 150, the folded
/// row's playhead still at 0 — it read the EDITING cursor, which a playing
/// film does not move. Its axis turned, but by the folded-away grid, against
/// that grid's window (19 cells) rather than the row's own (22) — and in the
/// sheet's orientation nothing turned it at all.
///
/// ⛔THE WHOLE FAMILY: the timeline's folded row, the same row folded from
/// the sheet's orientation, and the storyboard's folded track row.
void main() {
  /// A cut long enough to page several times at the default zoom.
  Project longCut() {
    final project = createDefaultProject();
    final track = project.tracks.first;
    return project.copyWith(
      tracks: [
        track.copyWith(cuts: [track.cuts.first.copyWith(duration: 480)]),
      ],
    );
  }

  /// A short cut before the long one, so the track's frames and the playing
  /// cut's own stop agreeing once the film is past it — the storyboard's
  /// row counts the TRACK's, and a row fed the cut's would stand 24 frames
  /// short.
  Project shortThenLong() => Project(
    id: const ProjectId('folded-follows'),
    name: 'Folded follows',
    createdAt: DateTime.utc(2026, 9, 27),
    tracks: [
      Track(
        id: const TrackId('t'),
        name: 'Video',
        cuts: [
          for (final (id, duration) in [('a', 24), ('b', 600)])
            Cut(
              id: CutId(id),
              name: id,
              duration: duration,
              canvasSize: const CanvasSize(width: 640, height: 360),
              layers: [
                Layer(id: LayerId('$id-cel'), name: 'A', frames: const []),
              ],
            ),
        ],
      ),
    ],
  );

  final overlay = find.byType(CollapsedRowOverlay);

  Future<EditorSessionManager> pumpFolded(
    WidgetTester tester, {
    String? before,
    Project? project,
    Future<void> Function()? beforeFold,
  }) async {
    await tester.binding.setSurfaceSize(const Size(1500, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: HomePage(initialProject: project ?? longCut()),
      ),
    );
    await tester.pumpAndSettle();
    if (before != null) {
      await tapToolbarButton(tester, ValueKey<String>(before));
    }
    await tester.drag(
      find.byKey(const ValueKey<String>('dock-resize-bottom')),
      const Offset(0, -420),
    );
    await tester.pumpAndSettle();
    await beforeFold?.call();
    await tester.tap(
      find.byKey(const ValueKey<String>('floating-bottom-collapse')),
    );
    await tester.pumpAndSettle();
    expect(overlay, findsOneWidget, reason: '⛔전제: the panel folded');
    return tester
        .widget<EditorWorkspace>(find.byType(EditorWorkspace))
        .session;
  }

  Future<void> play(WidgetTester tester) async {
    await tester.tap(
      find.byKey(const ValueKey<String>('playback-play-button')),
    );
    await tester.pump();
  }

  Future<void> tick(WidgetTester tester) =>
      tester.pump(const Duration(milliseconds: 42));

  /// Where the folded row's axis stands, in pixels.
  double origin(WidgetTester tester) =>
      tester.widget<CollapsedRowOverlay>(overlay).frameAxisOffset!.value;

  /// The folded row's frame window — the clip its frame half is laid out in.
  Finder frameWindow() => find
      .ancestor(
        of: find.byKey(const ValueKey<String>('collapsed-grid-sheet')),
        matching: find.byType(ClipRect),
      )
      .first;

  double window(WidgetTester tester) => tester.getSize(frameWindow()).width;

  double cellOf(WidgetTester tester) =>
      tester.widget<CollapsedRowOverlay>(overlay).pixelsPerFrame;

  /// Plays until the playhead has left the folded window's first page, and
  /// checks at every tick that the page law held ON THIS ROW'S WINDOW: the
  /// playing frame is always inside it, and it moved only when the frame
  /// would have left it — to stand that frame at its start.
  Future<void> playPastAPage(
    WidgetTester tester,
    int Function() playing,
  ) async {
    final cell = cellOf(tester);
    final view = window(tester);
    final firstOutside = (view / cell).floor();
    expect(
      firstOutside,
      greaterThan(3),
      reason: '⛔전제: the window holds a page of frames',
    );
    var turned = 0;
    for (var i = 0; i < firstOutside * 2 + 8; i += 1) {
      final before = origin(tester);
      await tick(tester);
      final frame = playing();
      final now = origin(tester);
      if (now != before) {
        turned += 1;
        expect(
          now,
          frame * cell,
          reason: '「넘어가면 룰러가 왼쪽에 오도록」 — the frame that left '
              'stands at the window start (frame $frame)',
        );
        expect(
          (frame + 1) * cell > before + view,
          isTrue,
          reason: 'the page turned at frame $frame, which was still inside '
              'the row\'s own window [$before, ${before + view}) — the '
              'folded-away grid\'s narrower window was turning it',
        );
      }
      expect(
        frame * cell >= now && (frame + 1) * cell <= now + view,
        isTrue,
        reason: 'the playhead (frame $frame) stays inside the folded '
            'window [$now, ${now + view})',
      );
    }
    expect(turned, greaterThan(0), reason: '⛔전제: the run crossed a page');
  }

  testWidgets('🚨folded, the playhead and the index follow the playing '
      'frame', (tester) async {
    final session = await pumpFolded(tester);
    final playback = session.playbackRig.playback;
    await play(tester);
    for (var i = 0; i < 12; i += 1) {
      await tick(tester);
    }
    final playing = playback.position!.localFrameIndex;
    expect(playing, greaterThan(5), reason: '⛔전제: the film is playing');
    final layer = tester.widget<TimelineCursorLayer>(
      find.descendant(of: overlay, matching: find.byType(TimelineCursorLayer)),
    );
    expect(
      layer.frameCursor.value,
      playing,
      reason: '🚨유저: 「재생을 따른다」 — the folded row\'s playhead and its '
          'selected cell stood at the frame playback started from',
    );
    playback.stop();
    await tester.pump();
  });

  testWidgets('🚨folded, the row turns its page on its OWN window, anchors a '
      'zoom there, and the grid folded away undoes none of it', (
    tester,
  ) async {
    final session = await pumpFolded(tester);
    final playback = session.playbackRig.playback;
    await play(tester);
    await playPastAPage(tester, () => playback.position!.localFrameIndex);

    playback.stop();
    await tester.pumpAndSettle();

    // A zoom after the page anchors on the playhead where the folded row
    // shows it (the zoom buttons are closed while playing).
    final stoppedAt = session.playheadCursors.cutFrame.value;
    final before = cellOf(tester);
    await tester.tap(
      find.byKey(const ValueKey<String>('timeline-zoom-in-button')),
    );
    await tester.pumpAndSettle();
    final zoomed = cellOf(tester);
    expect(zoomed, greaterThan(before), reason: '⛔전제: the zoom stepped in');
    final at = origin(tester);
    expect(
      stoppedAt * zoomed >= at &&
          (stoppedAt + 1) * zoomed <= at + window(tester),
      isTrue,
      reason: 'the playhead (frame $stoppedAt) left the folded window '
          '[$at, ${at + window(tester)}) on a zoom — nothing anchored the '
          'folded row\'s axis',
    );

    // The folded-away grid re-reads its own scroll position into the axis
    // whenever it lays out again — a window resized while folded is one —
    // and syncs to the axis first, or it puts a stale one back.
    final zoomedAt = origin(tester);
    await tester.binding.setSurfaceSize(const Size(1480, 1000));
    await tester.pumpAndSettle();
    session.notifyChanged();
    await tester.pumpAndSettle();
    expect(
      origin(tester),
      zoomedAt,
      reason: 'the grid folded away put its stale position back',
    );

    // And unfolded, the open grid stands where the folded row stood.
    await tester.tap(
      find.byKey(const ValueKey<String>('floating-bottom-collapse')),
    );
    await tester.pumpAndSettle();
    expect(
      scrollableOf(
        tester,
        find.byKey(const ValueKey<String>('timeline-frame-scroll-viewport')),
      ).controller!.offset,
      closeTo(zoomedAt, 0.5),
      reason: '「구조적으로 동기화」 — one axis, whichever panel shows it',
    );
  });

  testWidgets('🚨folded, a zoom anchors on the playhead where the FOLDED row '
      'shows it, not where the grid folded away would', (tester) async {
    // ⛔The grid folded away is narrower than the folded row, so a playhead
    // can stand inside the row's window and past the grid's. Both anchored
    // a zoom then, with two answers — the playhead for the row, the leading
    // edge for the grid — and the grid's, written from the middle of a
    // build, both won and dirtied the folded row as it built.
    const scrolledCells = 10;
    final frameScroller = find.byKey(
      const ValueKey<String>('timeline-frame-scroll-viewport'),
      skipOffstage: false,
    );
    ScrollPosition gridAxis() => tester
        .state<ScrollableState>(
          find
              .descendant(
                of: frameScroller,
                matching: find.byType(Scrollable, skipOffstage: false),
                skipOffstage: false,
              )
              .first,
        )
        .position;
    final session = await pumpFolded(
      tester,
      // Scrolled right before the fold (F-143), so the axis the grid
      // anchors from is not frame 0 — where its leading edge would
      // answer 0 at every zoom and agree by accident.
      beforeFold: () async {
        final axis = gridAxis();
        axis.jumpTo(scrolledCells * TimelineZoomLimits.defaultPixelsPerFrame);
        await tester.pumpAndSettle();
      },
    );
    final cell = cellOf(tester);
    final view = window(tester);
    final gridView = gridAxis().viewportDimension;
    final start = origin(tester);
    expect(
      start,
      scrolledCells * cell,
      reason: '⛔전제: folded with the axis scrolled',
    );
    final frame = ((start + gridView) / cell).ceil();
    final onScreen = (frame + 0.5) * cell - start;
    expect(
      onScreen > gridView && onScreen <= view,
      isTrue,
      reason: '⛔전제: frame $frame ($onScreen) is inside the row\'s window '
          '($view) and past the grid\'s ($gridView)',
    );
    session.selectFrameIndex(frame);
    await tester.pumpAndSettle();
    expect(origin(tester), start, reason: '⛔전제: a seek scrolls nothing');

    await tester.tap(
      find.byKey(const ValueKey<String>('timeline-zoom-in-button')),
    );
    await tester.pumpAndSettle();
    final zoomed = cellOf(tester);
    expect(zoomed, greaterThan(cell), reason: '⛔전제: the zoom stepped in');
    expect(
      (frame + 0.5) * zoomed - origin(tester),
      closeTo(onScreen, 0.5),
      reason: 'the playhead stays where the folded row showed it through '
          'the zoom',
    );
  });

  testWidgets('🚨folded, a walk is revealed on the row\'s own window, and a '
      'seek with nothing playing turns no page', (tester) async {
    final session = await pumpFolded(tester);
    final cell = cellOf(tester);
    final view = window(tester);

    // F-110 ③: a hand's seek is the walk's business, not a page's — with
    // nothing playing, a seek far off the window moves nothing.
    final far = (view / cell).ceil() + 40;
    session.selectFrameIndex(far);
    await tester.pumpAndSettle();
    expect(origin(tester), 0, reason: 'a seek with nothing playing paged');
    session.selectFrameIndex(0);
    await tester.pumpAndSettle();

    // R5: a walk (the `.` key: the step, then the reveal) that leaves the
    // window brings it along — on the row's own window, as the open grid's
    // does on its own.
    final steps = (view / cell).ceil() + 4;
    for (var i = 0; i < steps; i += 1) {
      session.frameVerbs.selectNextFrame();
      session.revealSelection();
      await tester.pump();
      await tester.pump();
      final frame = session.playheadCursors.cutFrame.value;
      final at = origin(tester);
      expect(
        frame * cell >= at && (frame + 1) * cell <= at + view,
        isTrue,
        reason: 'the walk left frame $frame outside the folded window '
            '[$at, ${at + view})',
      );
    }
    expect(origin(tester), greaterThan(0), reason: '⛔전제: the walk revealed');
  });

  testWidgets('🚨a page turn repaints the folded row\'s own layer and nothing '
      'around it', (tester) async {
    // 유저: 「층 최대한 나눠서 굽는다던가」 — the row lies over the artwork with
    // nothing between, so its page turn repainted whatever boundary stood
    // above the workspace.
    final session = await pumpFolded(tester);
    final playback = session.playbackRig.playback;
    final row = tester.renderObject(
      find.descendant(of: overlay, matching: find.byType(RepaintBoundary)).first,
    );
    await play(tester);
    var turned = false;
    for (var i = 0; i < 80 && !turned; i += 1) {
      final before = origin(tester);
      await tester.pump(const Duration(milliseconds: 42), EnginePhase.layout);
      if (origin(tester) != before) {
        turned = true;
        final strays = {
          for (final view in tester.binding.renderViews)
            ...repaintStrays(
              view,
              allowed: {...tickLayersAndCanvas(tester), row},
            ),
        };
        expect(
          strays.map(nameOfBoundary),
          isEmpty,
          reason: strays.map(nameOfBoundary).join('\n\n'),
        );
      }
      await tester.pump();
    }
    expect(turned, isTrue, reason: '⛔전제: a page turned');
    playback.stop();
    await tester.pump();
  });

  testWidgets('🚨folded over a GAP, the strip\'s playhead stands on the '
      'track\'s frame and follows a scrub through the gap', (tester) async {
    // ⛔The folded timeline row falls back to its strip where the row it
    // stands on has no widget — parked in a gap there is no cut, and the
    // strip draws the TRACK's snapshot. Its playhead has to count the
    // track's frames too, and move with a scrub, which parks per move and
    // notifies nothing that rebuilds the row.
    final project = shortThenLong();
    final track = project.tracks.single;
    final session = await pumpFolded(
      tester,
      project: project.copyWith(
        tracks: [
          track.copyWith(
            cuts: [
              track.cuts.first,
              track.cuts.last.copyWith(leadingGapFrames: 30),
            ],
          ),
        ],
      ),
    );
    // The gap runs over the track's frames 24 to 54.
    session.selectGlobalFrame(40);
    await tester.pumpAndSettle();
    expect(session.activeCutOrNull, isNull, reason: '⛔전제: parked in the gap');
    final head = find.byKey(const ValueKey<String>('collapsed-strip-playhead'));
    expect(head, findsOneWidget, reason: '⛔전제: the folded row is the strip');

    int standsAt() {
      final strokes = _PlayheadAt();
      tester
          .widget<CustomPaint>(head)
          .painter!
          .paint(strokes, tester.getSize(head));
      final cell = cellOf(tester);
      return (strokes.left! / cell).round() + (origin(tester) / cell).floor();
    }

    expect(standsAt(), 40, reason: 'the track\'s frame, where it is parked');
    scrubStoryboardGlobalFrame(session, 45);
    await tester.pump();
    expect(
      standsAt(),
      45,
      reason: '🚨a scrub through the gap left the strip\'s playhead where '
          'its snapshot was taken',
    );
    commitStoryboardScrub(session);
    await tester.pumpAndSettle();
  });

  testWidgets('🚨folded from the SHEET\'s orientation, the row still turns '
      'its page', (tester) async {
    // ⛔The folded row is the timeline's horizontal row whatever the
    // orientation, and only the grid showing that axis turned it — in the
    // sheet's orientation that grid is not mounted at all.
    final session = await pumpFolded(
      tester,
      before: 'timeline-orientation-toggle-button',
    );
    final playback = session.playbackRig.playback;
    await play(tester);
    await playPastAPage(tester, () => playback.position!.localFrameIndex);
    playback.stop();
    await tester.pump();
  });

  testWidgets('🚨the folded STORYBOARD draws the playhead and turns its '
      'page on the track\'s frames', (tester) async {
    final session = await pumpFolded(
      tester,
      before: 'timeline-mode-storyboard-button',
      project: shortThenLong(),
    );
    final playback = session.playbackRig.playback;
    await play(tester);
    // Past the short cut, where the track's frames and the cut's part.
    for (var i = 0; i < 40; i += 1) {
      await tick(tester);
    }
    expect(
      playback.position!.cutId,
      const CutId('b'),
      reason: '⛔전제: playing the second cut',
    );
    final tint = find.descendant(
      of: overlay,
      matching: find.byType(StoryboardPlayheadTint),
    );
    expect(
      tint,
      findsOneWidget,
      reason: '🚨the folded track row drew no playhead at all',
    );
    final at = playback.globalFrameIndexListenable.value!;
    final cell = cellOf(tester);
    final left =
        tester.getTopLeft(
          find.descendant(
            of: tint,
            matching: find.byKey(const ValueKey<String>('storyboard-playhead')),
          ),
        ).dx -
        tester.getTopLeft(frameWindow()).dx;
    expect(
      left,
      closeTo(at * cell - origin(tester), 0.5),
      reason: 'the tint stands on the playing frame ($at)',
    );
    await playPastAPage(tester, () => playback.globalFrameIndexListenable.value!);
    playback.stop();
    await tester.pump();
  });
}

/// Where the strip's playhead is drawn: the left of its one filled line.
class _PlayheadAt implements Canvas {
  double? left;

  @override
  void drawRect(Rect rect, Paint paint) => left = rect.left;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
