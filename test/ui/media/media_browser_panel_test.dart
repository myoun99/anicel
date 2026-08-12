import 'package:flutter/gestures.dart' show kDoubleTapMinTime;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/media_asset.dart';
import 'package:anicel/src/ui/media/media_browser_panel.dart';

class _Callbacks {
  var importRequests = 0;
  final renamed = <(String, String)>[];
  final relinked = <(String, String)>[];
  final removed = <String>[];
  final opened = <MediaAsset>[];
  bool removeResult = true;
  Set<String> referencedPaths = {};
  Set<String> existingPaths = {};
}

Future<void> _pump(
  WidgetTester tester,
  _Callbacks callbacks, {
  List<MediaAsset> assets = const [],
  Future<String?> Function()? picker,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 260,
          child: MediaBrowserPanel(
            assets: assets,
            isAssetReferenced: callbacks.referencedPaths.contains,
            onImportRequested: () => callbacks.importRequests += 1,
            onRenameAsset: (path, name) => callbacks.renamed.add((path, name)),
            onRelinkAsset: (oldPath, newPath) =>
                callbacks.relinked.add((oldPath, newPath)),
            onRemoveAsset: (path) {
              callbacks.removed.add(path);
              return callbacks.removeResult;
            },
            onOpenAsset: callbacks.opened.add,
            audioFilePicker: picker,
            fileExists: callbacks.existingPaths.contains,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  const foot = r'C:\snd\foot.wav';

  testWidgets('empty pool shows the guidance text', (tester) async {
    await _pump(tester, _Callbacks());
    expect(
      find.byKey(const ValueKey<String>('media-browser-empty')),
      findsOneWidget,
    );
  });

  testWidgets('rows show name/path with missing and linked badges', (
    tester,
  ) async {
    final callbacks = _Callbacks()
      ..referencedPaths = {foot}
      // clap exists on disk; foot is the missing one.
      ..existingPaths = {r'C:\snd\clap.wav'};
    await _pump(
      tester,
      callbacks,
      assets: const [
        MediaAsset(path: foot, name: '발소리'),
        MediaAsset(path: r'C:\snd\clap.wav', name: 'clap.wav'),
      ],
    );

    expect(find.text('발소리'), findsOneWidget);
    expect(find.text(foot), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('media-asset-missing-$foot')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('media-asset-linked-$foot')),
      findsOneWidget,
    );
    // The existing, unlinked asset carries neither badge.
    expect(
      find.byKey(
        const ValueKey<String>(r'media-asset-missing-C:\snd\clap.wav'),
      ),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey<String>(r'media-asset-linked-C:\snd\clap.wav')),
      findsNothing,
    );
  });

  testWidgets('the import button asks for the import WINDOW, not a picker', (
    tester,
  ) async {
    // It used to open an OS picker here and copy whatever came back. The
    // panel now asks its host to open the one import window, which is
    // where copy-or-reference and multi-select live.
    final callbacks = _Callbacks();
    await _pump(tester, callbacks, picker: () async => foot);

    await tester.tap(find.byKey(const ValueKey<String>('media-import-button')));
    await tester.pumpAndSettle();

    expect(callbacks.importRequests, 1);
  });

  testWidgets('rename flows through the dialog', (tester) async {
    final callbacks = _Callbacks()..existingPaths = {foot};
    await _pump(
      tester,
      callbacks,
      assets: const [MediaAsset(path: foot, name: 'foot.wav')],
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('media-asset-menu-$foot')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('media-asset-menu-rename')),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey<String>('media-rename-field')),
      '발소리',
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('media-rename-save-button')),
    );
    await tester.pumpAndSettle();

    expect(callbacks.renamed, [(foot, '발소리')]);
  });

  testWidgets('relink picks the new file', (tester) async {
    const moved = r'C:\snd\moved\foot.wav';
    final callbacks = _Callbacks();
    await _pump(
      tester,
      callbacks,
      assets: const [MediaAsset(path: foot, name: 'foot.wav')],
      picker: () async => moved,
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('media-asset-menu-$foot')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('media-asset-menu-relink')),
    );
    await tester.pumpAndSettle();

    expect(callbacks.relinked, [(foot, moved)]);
  });

  testWidgets('open in viewer: the row menu item and a double-click both '
      'hand the asset out', (tester) async {
    final callbacks = _Callbacks()..existingPaths = {foot};
    await _pump(
      tester,
      callbacks,
      assets: const [MediaAsset(path: foot, name: 'foot.wav')],
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('media-asset-menu-$foot')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('media-asset-menu-open')),
    );
    await tester.pumpAndSettle();
    expect(callbacks.opened.map((asset) => asset.path), [foot]);

    await tester.tap(find.text('foot.wav'));
    await tester.pump(kDoubleTapMinTime);
    await tester.tap(find.text('foot.wav'));
    await tester.pumpAndSettle();
    expect(callbacks.opened, hasLength(2));
  });

  testWidgets('remove: refused removals explain themselves', (tester) async {
    final callbacks = _Callbacks()..removeResult = false;
    await _pump(
      tester,
      callbacks,
      assets: const [MediaAsset(path: foot, name: 'foot.wav')],
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('media-asset-menu-$foot')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('media-asset-menu-remove')),
    );
    await tester.pumpAndSettle();

    expect(callbacks.removed, [foot]);
    expect(find.textContaining('Still linked'), findsOneWidget);
  });
}
