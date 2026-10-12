import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/ui/panels/panel_collapsed_scope.dart';
import 'package:anicel/src/ui/panels/panel_flash.dart';
import 'package:anicel/src/ui/timeline/timeline_cell_editor_policy.dart';
import 'package:anicel/src/ui/timeline/timeline_frame_axis_follower.dart';
import 'package:anicel/src/ui/timeline/timeline_scroll_offset_sync.dart';
import 'package:anicel/src/ui/timeline/timeline_edge_auto_pan.dart';

/// The scroll-and-reveal machinery of the timeline, none of which a test
/// named (the audit's untested-file pass, 2026-09-05). Each of these
/// objects exists because two or three hosts kept their own copy.
void main() {
  /// A real scrollable, because these objects read a live ScrollPosition —
  /// a fake one would be measuring the fake.
  Future<ScrollController> pumpScrollable(
    WidgetTester tester, {
    double contentExtent = 4000,
    double viewportExtent = 400,
  }) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            height: viewportExtent,
            width: 200,
            child: ListView(
              controller: controller,
              children: [SizedBox(height: contentExtent)],
            ),
          ),
        ),
      ),
    );
    return controller;
  }

  group('which rows open the cell editor', () {
    test('🚨EVERY ordinary kind opens it — the entrance is unified, so a '
        'new kind opts out here rather than no-opping in its host', () {
      for (final kind in [
        LayerKind.image,
        LayerKind.storyboard,
        LayerKind.se,
        LayerKind.instruction,
        LayerKind.camera,
      ]) {
        expect(
          layerKindOpensCellEditorOnDoubleTap(kind),
          isTrue,
          reason: '$kind',
        );
      }
    });

    test('⛔a row that owns no cel of its own does NOT — a folder shows its '
        'subtree\'s union and an adjustment shows its effects, and there '
        'is nothing there to edit', () {
      expect(layerKindOpensCellEditorOnDoubleTap(LayerKind.folder), isFalse);
      expect(
        layerKindOpensCellEditorOnDoubleTap(LayerKind.adjustment),
        isFalse,
      );
    });
  });

  group('TimelineScrollOffsetSync', () {
    testWidgets('the controller is pulled to the resolved offset, one frame '
        'later', (tester) async {
      final controller = await pumpScrollable(tester);
      final sync = TimelineScrollOffsetSync(controller, isMounted: () => true);

      sync.synchronize(120);
      expect(controller.offset, 0, reason: 'not yet — it waits a frame');

      await tester.pump();
      expect(controller.offset, 120);
    });

    testWidgets('🚨a stale offset PAST the end is clamped — that is the '
        'whole point: shrinking content left the controller out of range, '
        'and windowing from there inflated the leading spacer', (tester) async {
      final controller = await pumpScrollable(tester, contentExtent: 500);
      final sync = TimelineScrollOffsetSync(controller, isMounted: () => true);

      sync.synchronize(99999);
      await tester.pump();

      expect(controller.offset, controller.position.maxScrollExtent);
    });

    testWidgets('a pull to where it already is does nothing', (tester) async {
      final controller = await pumpScrollable(tester);
      controller.jumpTo(60);
      final sync = TimelineScrollOffsetSync(controller, isMounted: () => true);

      sync.synchronize(60);
      await tester.pump();

      expect(controller.offset, 60);
    });

    testWidgets('an UNMOUNTED host is not pulled — the frame ends after the '
        'State is gone', (tester) async {
      final controller = await pumpScrollable(tester);
      final sync = TimelineScrollOffsetSync(controller, isMounted: () => false);

      sync.synchronize(120);
      await tester.pump();

      expect(controller.offset, 0);
    });

    testWidgets('a second pull to a DIFFERENT offset wins — the last word '
        'is what the layout resolved', (tester) async {
      final controller = await pumpScrollable(tester);
      final sync = TimelineScrollOffsetSync(controller, isMounted: () => true);

      sync.synchronize(120);
      sync.synchronize(240);
      await tester.pump();

      expect(controller.offset, 240);
    });
  });

  group('TimelineFrameAxisFollower', () {
    testWidgets('scrolling moves the offset notifier without a setState per '
        'pixel', (tester) async {
      final controller = await pumpScrollable(tester);
      final offset = ValueNotifier<double>(0);
      final bucket = ValueNotifier<int>(0);
      addTearDown(offset.dispose);
      addTearDown(bucket.dispose);
      var rebuilds = 0;
      final follower = TimelineFrameAxisFollower(
        controller: controller,
        frameAxisOffset: offset,
        frameWindowBucket: bucket,
        cellExtent: () => 20,
        baseFrameCount: () => 100,
        viewportFillFrames: () => 0,
        rebuild: (fn) {
          rebuilds += 1;
          fn();
        },
        isMounted: () => true,
      );
      addTearDown(follower.dispose);

      controller.jumpTo(200);
      follower.handleScroll();

      expect(offset.value, 200);
      expect(
        rebuilds,
        0,
        reason: 'the trailing room did not change, so nothing rebuilt',
      );
    });

    testWidgets('the window bucket only changes when the bucket changes', (
      tester,
    ) async {
      final controller = await pumpScrollable(tester);
      final offset = ValueNotifier<double>(0);
      final bucket = ValueNotifier<int>(0);
      addTearDown(offset.dispose);
      addTearDown(bucket.dispose);
      var bucketWrites = 0;
      bucket.addListener(() => bucketWrites += 1);
      final follower = TimelineFrameAxisFollower(
        controller: controller,
        frameAxisOffset: offset,
        frameWindowBucket: bucket,
        cellExtent: () => 20,
        baseFrameCount: () => 100,
        viewportFillFrames: () => 0,
        rebuild: (fn) => fn(),
        isMounted: () => true,
      );
      addTearDown(follower.dispose);

      controller.jumpTo(1);
      follower.handleScroll();
      final afterTiny = bucketWrites;

      controller.jumpTo(2000);
      follower.handleScroll();

      expect(
        bucketWrites,
        greaterThan(afterTiny),
        reason: 'a long jump crosses a bucket',
      );
    });

    testWidgets('a scroll to the same offset is ignored entirely', (
      tester,
    ) async {
      final controller = await pumpScrollable(tester);
      final offset = ValueNotifier<double>(0);
      final bucket = ValueNotifier<int>(0);
      addTearDown(offset.dispose);
      addTearDown(bucket.dispose);
      var offsetWrites = 0;
      offset.addListener(() => offsetWrites += 1);
      final follower = TimelineFrameAxisFollower(
        controller: controller,
        frameAxisOffset: offset,
        frameWindowBucket: bucket,
        cellExtent: () => 20,
        baseFrameCount: () => 100,
        viewportFillFrames: () => 0,
        rebuild: (fn) => fn(),
        isMounted: () => true,
      );
      addTearDown(follower.dispose);

      controller.jumpTo(200);
      follower.handleScroll();
      follower.handleScroll();

      expect(offsetWrites, 1);
    });

    testWidgets('🚨F-95: what PAINTS reads the position, and the copy catches '
        'up when a layout says to', (tester) async {
      // ↩️This case used to make a REAL silent correction: a viewport grown
      // past the end of its content pulled its position back during layout
      // and called no listener (유저 2026-09-12: 「패널의 스플리터로 좌우
      // 길이 바꾸면 … 룰러랑 내부 프레임 영역이랑 위치가 … 어긋남」).
      //
      // ⛔That timing is Flutter's, and it MOVED. On 3.47.4 the same toy
      // leaves the position OUT OF RANGE for frames and then brings it home
      // WITH listeners (measured 2026-09-16: pixels 3800 against a max of
      // 3500 for two pumps, nine notifies by the time it settled). A test
      // that pins the engine's schedule goes red for a reason that is not
      // ours — and this one also asked for 3200 where the surface only ever
      // allowed 3400, so it pinned a number the toy could not reach.
      //
      // 🚨The APP's law is pinned where it belongs, on the real panels and
      // in the user's own terms: `a_ruler_stays_on_its_cells_through_a_
      // resize_test` — measured again on 3.47.4, where the symptom is
      // unchanged (the cells follow the correction by 600px and the ruler
      // does not).
      //
      // What is OURS, and what this pins, is the follower's two promises,
      // driven directly so no engine schedule can move them.
      final controller = await pumpScrollable(tester);
      final offset = ValueNotifier<double>(0);
      final bucket = ValueNotifier<int>(0);
      addTearDown(offset.dispose);
      addTearDown(bucket.dispose);
      final follower = TimelineFrameAxisFollower(
        controller: controller,
        frameAxisOffset: offset,
        frameWindowBucket: bucket,
        cellExtent: () => 20,
        baseFrameCount: () => 200,
        viewportFillFrames: () => 0,
        rebuild: (fn) => fn(),
        isMounted: () => true,
      );
      addTearDown(follower.dispose);

      controller.jumpTo(120);
      follower.handleScroll();
      expect(offset.value, 120, reason: 'fixture: the copy heard the scroll');

      // The copy goes stale: the position moves and nobody is told — what a
      // layout's correction does (`correctBy`). ↩️This wrote the copy
      // instead, which since 09-28 is someone else turning the axis (the
      // folded row does), and the scrollable follows it.
      controller.position.correctPixels(40);
      expect(offset.value, 120, reason: 'fixture: the copy was not told');
      expect(
        follower.paintedOffset,
        40,
        reason: 'what paints reads the POSITION, never the copy',
      );

      follower.rereadAfterLayout();
      await tester.pump();
      expect(
        offset.value,
        40,
        reason: 'the copy catches up the frame after the layout that asked',
      );
    });

    testWidgets('the trailing room GROWS as the view reaches past the end', (
      tester,
    ) async {
      final controller = await pumpScrollable(tester);
      final offset = ValueNotifier<double>(0);
      final bucket = ValueNotifier<int>(0);
      addTearDown(offset.dispose);
      addTearDown(bucket.dispose);
      final follower = TimelineFrameAxisFollower(
        controller: controller,
        frameAxisOffset: offset,
        frameWindowBucket: bucket,
        cellExtent: () => 20,
        baseFrameCount: () => 4,
        viewportFillFrames: () => 0,
        rebuild: (fn) => fn(),
        isMounted: () => true,
      );
      addTearDown(follower.dispose);

      controller.jumpTo(3500);
      follower.handleScroll();

      expect(follower.trailingFrames, greaterThan(0));
    });

    testWidgets('🚨it must not collapse UNDER THE FINGER — while a real '
        'scroll is live the room only grows, and the settle is the one '
        'moment it may shrink', (tester) async {
      final controller = await pumpScrollable(tester);
      final offset = ValueNotifier<double>(0);
      final bucket = ValueNotifier<int>(0);
      addTearDown(offset.dispose);
      addTearDown(bucket.dispose);
      final follower = TimelineFrameAxisFollower(
        controller: controller,
        frameAxisOffset: offset,
        frameWindowBucket: bucket,
        cellExtent: () => 20,
        baseFrameCount: () => 4,
        viewportFillFrames: () => 0,
        rebuild: (fn) => fn(),
        isMounted: () => true,
      );
      addTearDown(follower.dispose);

      controller.jumpTo(3500);
      follower.handleScroll();
      final grown = follower.trailingFrames;
      expect(grown, greaterThan(0));

      // A finger goes down and drags the list back toward the top. The
      // position is SCROLLING for as long as it is held.
      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(ListView)),
      );
      await gesture.moveBy(const Offset(0, 400));
      await tester.pump();
      expect(
        controller.position.isScrollingNotifier.value,
        isTrue,
        reason: 'the premise: a live scroll',
      );

      follower.handleScroll();
      expect(
        follower.trailingFrames,
        grown,
        reason: 'the room must not collapse while the finger is down',
      );

      await gesture.up();
      await tester.pumpAndSettle();

      expect(
        follower.trailingFrames,
        lessThan(grown),
        reason: 'the settle is the one moment it may shrink',
      );
    });

    testWidgets('🚨a run\'s next page is where the turn stands the axis, '
        'built as its own cut builds it there: grown under the last page '
        'before the cut\'s end, and shrunk back by the wrap', (tester) async {
      // A 400px viewport of 20px cells — twenty frames a page — over 30
      // frames of content, with a run of 32: two frames of handle past it.
      final controller = await pumpScrollable(tester);
      final offset = ValueNotifier<double>(0);
      final bucket = ValueNotifier<int>(0);
      addTearDown(offset.dispose);
      addTearDown(bucket.dispose);
      final follower = TimelineFrameAxisFollower(
        controller: controller,
        frameAxisOffset: offset,
        frameWindowBucket: bucket,
        cellExtent: () => 20,
        baseFrameCount: () => 30,
        viewportFillFrames: () => 20,
        rebuild: (fn) => fn(),
        isMounted: () => true,
      );
      addTearDown(follower.dispose);
      // The window spans five cells a bucket: 100px.
      controller.jumpTo(200);
      follower.handleScroll();
      expect(follower.renderedFrameCount, 30, reason: '⛔premise: built to 30');

      expect(
        follower.nextPage(runFrames: 32),
        (bucket: 6, builtFrames: 50),
        reason: 'frame 30 leaves the window first, and the turn standing it '
            'at 600px builds the axis to the view\'s end',
      );
      expect(
        (follower.trailingFrames, bucket.value),
        (0, 2),
        reason: 'asking where the turn stands it moves nothing',
      );

      controller.jumpTo(600);
      follower.handleScroll();
      expect(follower.renderedFrameCount, 50, reason: '⛔premise: the turn');
      expect(
        follower.nextPage(runFrames: 32),
        (bucket: 0, builtFrames: 30),
        reason: 'the run wraps before it leaves this page, and the first page '
            'lets the room it grew go',
      );
    });
  });

  group('keepWhereShown — the one write both axes keep theirs through', () {
    Future<ScrollController> pumpIn(
      WidgetTester tester, {
      required bool folded,
      ScrollController? controller,
    }) async {
      final scroll = controller ?? ScrollController();
      if (controller == null) {
        addTearDown(scroll.dispose);
      }
      await tester.pumpWidget(
        MaterialApp(
          home: PanelCollapsedScope(
            collapsed: folded,
            child: SizedBox(
              height: 400,
              child: ListView(
                controller: scroll,
                children: const [SizedBox(height: 4000)],
              ),
            ),
          ),
        ),
      );
      return scroll;
    }

    testWidgets('a shown scrollable hands the axis where it stands', (
      tester,
    ) async {
      final kept = ValueNotifier<double>(0);
      addTearDown(kept.dispose);
      final controller = await pumpIn(tester, folded: false);
      controller.jumpTo(300);

      keepWhereShown(controller.position, kept);

      expect(kept.value, 300);
    });

    testWidgets('🚨one folded away hands it NOTHING — its place is not where '
        'anybody turned the axis', (tester) async {
      final kept = ValueNotifier<double>(120);
      addTearDown(kept.dispose);
      final controller = await pumpIn(tester, folded: true);
      controller.jumpTo(300);

      keepWhereShown(controller.position, kept);

      expect(
        kept.value,
        120,
        reason: 'the row on screen owns the frame axis while folded, and a '
            'layer axis folded away is not being looked at',
      );
      await pumpIn(tester, folded: false, controller: controller);
      keepWhereShown(controller.position, kept);
      expect(kept.value, 300, reason: 'and unfolded, it is written again');
    });
  });

  group('followKeptAxis — a layer axis the project keeps (F-267)', () {
    testWidgets('every scroll is kept, and letting go stops it', (
      tester,
    ) async {
      final kept = ValueNotifier<double>(0);
      addTearDown(kept.dispose);
      final controller = await pumpScrollable(tester);
      final letGo = followKeptAxis(controller, kept, isMounted: () => true);
      await tester.pump();

      controller.jumpTo(300);
      expect(kept.value, 300);
      letGo();
      controller.jumpTo(100);
      expect(kept.value, 300, reason: 'let go of, it keeps nothing');
    });

    testWidgets('🚨a scrollable born past its end is held there SILENTLY — '
        'and the first layout is kept, not the place nobody sees', (
      tester,
    ) async {
      final kept = ValueNotifier<double>(1000);
      addTearDown(kept.dispose);
      final controller = ScrollController(initialScrollOffset: kept.value);
      addTearDown(controller.dispose);
      followKeptAxis(controller, kept, isMounted: () => true);
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: SizedBox(
              height: 100,
              child: SingleChildScrollView(
                controller: controller,
                child: const SizedBox(height: 300),
              ),
            ),
          ),
        ),
      );

      expect(controller.offset, 200, reason: '⛔전제: held to its end');
      expect(kept.value, 200);
    });
  });

  group('PanelFlashController', () {
    test('🚨the SAME tab twice re-triggers — the sequence is what makes a '
        'second ask visible', () {
      final controller = PanelFlashController();
      addTearDown(controller.dispose);

      controller.flash('color');
      final first = controller.requests.value!;
      controller.flash('color');
      final second = controller.requests.value!;

      expect(second.tabId, 'color');
      expect(second.seq, greaterThan(first.seq));
    });

    test('the tab travels with the request', () {
      final controller = PanelFlashController();
      addTearDown(controller.dispose);

      controller.flash('timeline');

      expect(controller.requests.value?.tabId, 'timeline');
    });

    test('nothing has been asked for yet', () {
      final controller = PanelFlashController();
      addTearDown(controller.dispose);

      expect(controller.requests.value, isNull);
    });
  });

  group('the two ways a window comes to an item (F-110)', () {
    // 🎯THE CONTRAST IS THE TEST. A walk moves the least it can; playback
    // turns the page. Same window, same item, two answers — which is why
    // they are two functions and not one with a flag (유저 2026-09-12:
    // 「룰러 드래그랑은 다르게 다음 페이지? 로 간다는 느낌」).
    const window = (offset: 0.0, viewport: 100.0);
    const justPast = (start: 120.0, extent: 10.0, margin: 8.0);

    test('a walk brings the item to the near edge, keeping its margin', () {
      expect(revealScrollOffset(window, justPast), 38);
    });

    test('a page puts it at the window START, margin unread', () {
      expect(pageScrollOffset(window, justPast), 120);
    });

    test('neither moves a window the item is already inside', () {
      const inside = (start: 20.0, extent: 10.0, margin: 8.0);
      expect(revealScrollOffset(window, inside), window.offset);
      expect(pageScrollOffset(window, inside), window.offset);
    });

    test('an item straddling the far edge is OUT for the page, while the '
        'walk only pulls its tail in', () {
      const straddling = (start: 95.0, extent: 10.0, margin: 0.0);
      expect(revealScrollOffset(window, straddling), 5);
      expect(pageScrollOffset(window, straddling), 95);
    });

    test('a window with no length answers with itself, both ways', () {
      const none = (offset: 40.0, viewport: 0.0);
      expect(revealScrollOffset(none, justPast), 40);
      expect(pageScrollOffset(none, justPast), 40);
    });
  });

  group('the page a run turns to next — the page law asked ahead', () {
    // Ten-pixel steps under a hundred-pixel window.
    double next(double offset, {required int runSteps, double view = 100}) =>
        nextPageScrollOffset(
          (offset: offset, viewport: view),
          extent: 10,
          runSteps: runSteps,
        );

    test('the step the playhead leaves by comes to the window\'s start', () {
      expect(next(0, runSteps: 50), 100);
      expect(
        next(0, runSteps: 50, view: 95),
        90,
        reason: 'the step straddling the far edge is the one it leaves by',
      );
    });

    test('🚨the last page before the run\'s end is turned to — the run '
        'wraps only once it leaves that one', () {
      expect(next(300, runSteps: 45), 400);
      expect(next(400, runSteps: 45), 0);
    });

    test('a run that wraps inside the window turns no page', () {
      expect(next(0, runSteps: 8), 0);
    });
  });
}
