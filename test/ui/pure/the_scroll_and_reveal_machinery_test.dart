import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/ui/panels/panel_flash.dart';
import 'package:anicel/src/ui/timeline/timeline_cell_editor_policy.dart';
import 'package:anicel/src/ui/timeline/timeline_frame_axis_follower.dart';
import 'package:anicel/src/ui/timeline/timeline_scroll_offset_sync.dart';

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
        rebuild: (fn) => fn(),
        isMounted: () => true,
      );
      addTearDown(follower.dispose);

      controller.jumpTo(120);
      follower.handleScroll();
      expect(offset.value, 120, reason: 'fixture: the copy heard the scroll');

      // The copy goes stale — however it got that way, silently or late.
      offset.value = 999;
      expect(
        follower.paintedOffset,
        120,
        reason: 'what paints reads the POSITION, never the copy',
      );

      follower.rereadAfterLayout();
      await tester.pump();
      expect(
        offset.value,
        120,
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
}
