import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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

  ScrollPosition acrossOf(WidgetTester tester) => tester
      .state<ScrollableState>(
        find.descendant(
          of: find.byType(MediaPoolList),
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is Scrollable &&
                widget.axisDirection == AxisDirection.right,
          ),
        ),
      )
      .position;

  /// The head's columns — its line is the list's first.
  Rect headColumnsOf(WidgetTester tester) => tester.getRect(
    find
        .descendant(
          of: find.descendant(
            of: find.byType(MediaPoolList),
            matching: find.byType(OverflowBox),
          ).first,
          matching: find.byType(Row),
        )
        .first,
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
      // A list of its own at each width — one widened while scrolled to its
      // end is the next test's.
      await tester.pumpWidget(const SizedBox());
      await pump(tester, view: const MediaPoolView(), width: width);
      final across = acrossOf(tester);
      final end = across.maxScrollExtent;
      expect(end, greaterThan(0), reason: 'LIVENESS: $width overflows');
      across.jumpTo(end);
      await tester.pump();

      expect(
        headColumnsOf(tester).right,
        moreOrLessEquals(laneOf(tester).left),
        reason: 'at $width',
      );
    }
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  // 🚨card a-widened-pool-list-leaves-its-window-behind (2026-11-20): the
  // view read its place at the build, and a viewport pulls its position
  // back into range in its layout without a word — scrolled to its end at
  // 190 and widened to 260, the names, the lines and the lane stood where
  // the old end had put them.
  testWidgets('🚨widened while scrolled to its end, the list stands where '
      'its position came back to — the lane at the panel\'s edge, the last '
      'column ending at it', (tester) async {
    await pump(tester, view: const MediaPoolView(), width: 190);
    double nameLeft() => tester.getRect(find.text('foot.wav')).left;
    final unscrolledName = nameLeft();
    final narrowEnd = acrossOf(tester).maxScrollExtent;
    acrossOf(tester).jumpTo(narrowEnd);
    await tester.pump();

    await pump(tester, view: const MediaPoolView(), width: 260);

    final across = acrossOf(tester);
    expect(
      (across.pixels, across.pixels < narrowEnd),
      (across.maxScrollExtent, true),
      reason: 'the premise: the position came back to a nearer end',
    );
    final lane = laneOf(tester);
    expect(lane.right, moreOrLessEquals(260));
    expect(headColumnsOf(tester).right, moreOrLessEquals(lane.left));
    expect(
      nameLeft(),
      moreOrLessEquals(unscrolledName),
      reason: 'the names stay at the view\'s left',
    );
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  // The columns ride the scroll where they are painted, and a file's line
  // is a picture of its own — so a scroll must paint it again, or the
  // screen keeps the columns where they were while every rect (read at
  // the paint transform, now) says they moved.
  testWidgets('scrolled sideways, a file\'s columns are SEEN where they '
      'went', (tester) async {
    // The screen read in the list's own pixels.
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(800, 600);
    addTearDown(tester.view.reset);
    // At 190 the names take all but the lane: no column is in view.
    await pump(tester, view: const MediaPoolView());
    final columns = tester.getRect(
      find
          .descendant(
            of: find.byType(MediaPoolList),
            matching: find.byType(OverflowBox),
          )
          .at(1),
    );
    Future<List<int>> seen() async {
      final screen = tester.layers.first as OffsetLayer;
      final bytes = await tester.runAsync(() async {
        final image = await screen.toImage(columns);
        try {
          return (await image.toByteData())!;
        } finally {
          image.dispose();
        }
      });
      return bytes!.buffer.asUint8List().toList();
    }

    final before = await seen();
    acrossOf(tester).jumpTo(acrossOf(tester).maxScrollExtent);
    await tester.pump();

    expect(await seen(), isNot(before));
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));
}
