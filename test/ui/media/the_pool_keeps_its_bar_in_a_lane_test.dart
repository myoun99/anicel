import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/media_asset.dart';
import 'package:anicel/src/ui/media/media_pool_list.dart';
import 'package:anicel/src/ui/media/media_pool_panel.dart';
import 'package:anicel/src/ui/media/media_pool_view.dart';
import 'package:anicel/src/ui/theme/app_scroll_behavior.dart';
import 'package:anicel/src/ui/widgets/app_scrollbar.dart';
import 'package:anicel/src/ui/widgets/content_scrollbar.dart';

/// 🗣️H62 (유저 2026-11-18): 「지금 미디어풀 스크롤바같은게 안뜨는데 버근가?
/// 계속 떠있도록. 스크롤바가 필요한 상황인데도 안뜨고있음」 — the pool's
/// files keep their bar in a lane of their own, every panel's content's
/// ([ContentScrollbar], H35): on a tablet too, and while they fit.
void main() {
  const views = {
    'list': MediaPoolView(),
    'icons': MediaPoolView(icons: true),
  };
  final assets = [
    MediaAsset(path: 'C:/snd/foot.wav', name: 'foot.wav'),
    MediaAsset(path: 'C:/snd/clap.wav', name: 'clap.wav'),
  ];

  Future<void> pump(
    WidgetTester tester, {
    required MediaPoolView view,
    double width = 260,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        // The app's own behaviour — the one that laid no bar down a
        // vertical list on a tablet.
        scrollBehavior: const AppScrollBehavior(),
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: width,
              height: 300,
              child: MediaPoolPanel(
                assets: assets,
                usesOf: (_) => const [],
                onImportRequested: () {},
                onRenameAsset: (_, _) {},
                onRelinkAsset: (_, _, _) {},
                onRemoveAsset: (_) {},
                onPromoteAsset: (_) async => true,
                onExportAssetWav: (_) async => true,
                view: view,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Rect laneOf(WidgetTester tester) => tester.getRect(
    find.descendant(
      of: find.byType(ContentScrollbar),
      matching: find.byType(AppControllerScrollbar),
    ),
  );

  for (final MapEntry(key: name, value: view) in views.entries) {
    testWidgets('🚨the $name keeps its bar in a lane while its two files fit '
        '— nothing drawn under it', (tester) async {
      await pump(tester, view: view);

      expect(find.byType(ContentScrollbar), findsOneWidget);
      final lane = laneOf(tester);
      expect(lane.width, AppScrollbarLane.thin, reason: 'CLAUDE.md: 얇은 8px');
      expect(lane.height, greaterThan(0));
      final files = find.descendant(
        of: find.byType(ContentScrollbar),
        matching: find.byWidgetPredicate(
          (widget) => widget is ListView || widget is GridView,
        ),
      );
      expect(
        tester.getRect(files).right,
        lane.left,
        reason: 'a lane beside the files, not a bar laid over them',
      );
    }, variant: TargetPlatformVariant.only(TargetPlatform.android));
  }

  testWidgets('the list\'s head stops where its lines do — a head over the '
      'cells it names, none over the lane', (tester) async {
    await pump(tester, view: const MediaPoolView());

    final lane = laneOf(tester);
    // A line's columns stand in its one OverflowBox — the head's as a
    // file's.
    final columns = find.descendant(
      of: find.byType(MediaPoolList),
      matching: find.byType(OverflowBox),
    );
    expect(columns, findsAtLeastNWidgets(3), reason: 'the head and two lines');
    for (final line in columns.evaluate()) {
      expect(tester.getRect(find.byWidget(line.widget)).right, lane.left);
    }
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  // Narrower than the names and their lane, wider than the panel's least
  // body (`OverflowScrollers`), so the list itself is this wide.
  testWidgets('in a pool narrower than the names, the names give the lane '
      'its room', (tester) async {
    await pump(tester, view: const MediaPoolView(), width: 190);

    expect(tester.takeException(), isNull);
    final lane = laneOf(tester);
    expect(lane.right, 190);
    expect(lane.width, AppScrollbarLane.thin);
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  // 검증 (2026-11-20): 「풀 패널이 좁아 목록의 크기 칸 숫자가 레인 앞에서
  // 잘려 보인다(「3」 · 「220」)」 — the lane came out of the lines and not
  // out of the sideways scroll.
  testWidgets('🚨scrolled sideways to its end, the list\'s last column ends '
      'where the lane begins — none of it left under the lane', (
    tester,
  ) async {
    for (final width in [190.0, 260.0]) {
      // A list of its own at each width: one widened while scrolled to its
      // end is another question (card
      // a-widened-pool-list-leaves-its-window-behind).
      await tester.pumpWidget(const SizedBox());
      await pump(tester, view: const MediaPoolView(), width: width);
      final across = tester.state<ScrollableState>(
        find.descendant(
          of: find.byType(MediaPoolList),
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is Scrollable &&
                widget.axisDirection == AxisDirection.right,
          ),
        ),
      );
      final end = across.position.maxScrollExtent;
      expect(end, greaterThan(0), reason: 'LIVENESS: $width overflows');
      across.position.jumpTo(end);
      await tester.pump();

      // The head's columns — its line is the list's first.
      final columns = find
          .descendant(
            of: find.descendant(
              of: find.byType(MediaPoolList),
              matching: find.byType(OverflowBox),
            ).first,
            matching: find.byType(Row),
          )
          .first;
      expect(
        tester.getRect(columns).right,
        moreOrLessEquals(laneOf(tester).left),
        reason: 'at $width',
      );
    }
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));
}
