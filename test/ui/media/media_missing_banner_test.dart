import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/media_asset.dart';
import 'package:anicel/src/ui/media/media_browser_panel.dart';

/// RELINK-2: the loss banner.
///
/// Its whole job is to be TRUE about a number, so the tests are about the
/// number: what it counts, what it refuses to count, and when it is absent.
void main() {
  const banner = ValueKey<String>('media-missing-banner');
  const button = ValueKey<String>('media-relink-missing');

  MediaAsset asset(String path) =>
      MediaAsset(path: path, name: path.split('/').last);

  Future<void> pump(
    WidgetTester tester, {
    required List<MediaAsset> assets,
    required Set<String> missingPaths,
    VoidCallback? onRelinkMissing,
  }) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 320,
          height: 400,
          child: MediaBrowserPanel(
            assets: assets,
            isAssetReferenced: (_) => false,
            onImportRequested: () {},
            onRenameAsset: (_, _) {},
            onRelinkAsset: (_, _, _) {},
            onRemoveAsset: (_) => true,
            onPromoteAsset: (_) => true,
            missingPaths: missingPaths,
            onRelinkMissing: onRelinkMissing,
          ),
        ),
      ),
    ),
  );

  testWidgets('nothing missing shows no banner at all', (tester) async {
    await pump(
      tester,
      assets: [asset('/m/a.wav')],
      missingPaths: const {},
    );
    expect(find.byKey(banner), findsNothing);
  });

  testWidgets('the count is what the banner says', (tester) async {
    await pump(
      tester,
      assets: [asset('/m/a.wav'), asset('/m/b.wav'), asset('/m/c.wav')],
      missingPaths: const {'/m/a.wav', '/m/c.wav'},
    );
    expect(find.byKey(banner), findsOneWidget);
    expect(find.textContaining('2'), findsOneWidget);
  });

  testWidgets('a path no longer in the pool is not counted', (tester) async {
    // The session's cache is refreshed at three moments, not continuously,
    // so a removed asset can linger in it. A banner that counts ghosts
    // sends the user hunting for a file nothing references.
    await pump(
      tester,
      assets: [asset('/m/a.wav')],
      missingPaths: const {'/m/a.wav', '/m/deleted.wav'},
    );
    expect(find.textContaining('1'), findsOneWidget);
  });

  testWidgets('every asset gone is still just the pool count', (tester) async {
    await pump(
      tester,
      assets: [asset('/m/a.wav'), asset('/m/b.wav')],
      missingPaths: const {'/m/a.wav', '/m/b.wav', '/m/ghost.wav'},
    );
    expect(find.textContaining('2'), findsOneWidget);
  });

  testWidgets('a cache that only holds ghosts shows no banner', (tester) async {
    await pump(
      tester,
      assets: [asset('/m/a.wav')],
      missingPaths: const {'/m/deleted.wav'},
    );
    expect(find.byKey(banner), findsNothing);
  });

  testWidgets('the button runs the batch relink', (tester) async {
    var started = 0;
    await pump(
      tester,
      assets: [asset('/m/a.wav')],
      missingPaths: const {'/m/a.wav'},
      onRelinkMissing: () => started += 1,
    );
    await tester.tap(find.byKey(button));
    await tester.pump();
    expect(started, 1);
  });

  testWidgets('no handler hides the button but keeps the count', (
    tester,
  ) async {
    await pump(
      tester,
      assets: [asset('/m/a.wav')],
      missingPaths: const {'/m/a.wav'},
    );
    expect(find.byKey(banner), findsOneWidget);
    expect(find.byKey(button), findsNothing);
  });
}
