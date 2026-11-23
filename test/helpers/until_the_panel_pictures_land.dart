import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/ui/storyboard_cut_thumbnail_store.dart'
    show StoryboardThumbnails;

import 'settle_async.dart';

/// Lends both clocks until every picture the surfaces on screen asked of
/// [thumbnails] has landed ([StoryboardThumbnails.pending]) — a picture is
/// laid by the real engine, whose answer comes on the machine's clock — and
/// then settles.
///
/// 🚨A TEST THAT OPENS THE PANELS WAITS FOR THEM BEFORE IT ENDS (card
/// the-prerender-scheduler-rests-a-tile-late-on-ci, 2026-11-24): a picture
/// still being laid when a widget test ends never hears the engine's
/// answer — the test's fake clock runs no more — so the screen it was laid
/// on is never freed, and its tiles stay for every file after it in the
/// process (test/flutter_test_config.dart asks as each test ends).
Future<void> untilThePanelPicturesLand(
  WidgetTester tester,
  StoryboardThumbnails thumbnails,
) async {
  expect(
    await settleAsync(tester, () => !thumbnails.pending()),
    isTrue,
    reason: 'every picture on screen landed',
  );
  await tester.pumpAndSettle();
}
