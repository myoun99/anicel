import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/media_asset.dart';
import 'package:anicel/src/ui/media/media_pool_panel.dart';
import 'package:anicel/src/ui/media/media_pool_view.dart';
import 'package:anicel/src/ui/text/app_strings.dart';
import 'package:anicel/src/ui/timeline/layer_label_controls.dart'
    show layerKindDisplayName;
import 'package:anicel/src/ui/timeline/timeline_grid_metrics.dart'
    show timelineLayerRowHeight;
import 'package:anicel/src/ui/widgets/app_icon_button.dart';

/// 🗣️asset-placement-presets Q4 · Q6 (유저 2026-11-17): the pool is a list
/// of one line a file, as a layer is a line — the names stay put and the
/// columns right of them scroll sideways (「프리미어방식」) — with two view
/// buttons right of its ＋: the preset face, and list ↔ icons.
void main() {
  const door = 'C:/snd/door.wav';
  const cloud = 'C:/pic/cloud.png';

  final assets = [
    MediaAsset(
      path: door,
      name: 'door',
      preset: const MediaPreset(seName: 'BGM', dialogue: 'slam'),
    ),
    MediaAsset(path: cloud, name: 'cloud', kind: MediaAssetKind.image),
  ];

  Future<List<MediaPoolView>> pump(
    WidgetTester tester, {
    MediaPoolView view = const MediaPoolView(),
    double width = 260,
  }) async {
    final asked = <MediaPoolView>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: width,
            height: 300,
            child: MediaPoolPanel(
              assets: assets,
              usesOf: (_) => const [],
              onImportRequested: () {},
              onRenameAsset: (_, _) {},
              onRelinkAsset: (_, _, _) {},
              onRemoveAsset: (_) {},
              onExportAssetWav: (_) async => true,
              onPromoteAsset: (_) async => true,
              view: view,
              onViewChanged: asked.add,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return asked;
  }

  Finder cell(String column, String path) =>
      find.byKey(ValueKey<String>('media-pool-cell-$column-$path'));
  Finder line(String path) =>
      find.byKey(ValueKey<String>('media-asset-row-$path'));

  testWidgets('a file is one line as high as a layer\'s, and its columns say '
      'what it is', (tester) async {
    await pump(tester);
    expect(tester.getSize(line(door)).height, timelineLayerRowHeight);
    expect(find.text(AppText.strings.mediaLength), findsOneWidget);
    expect(
      tester.widget<Text>(cell('kept', door)).data,
      AppText.strings.mediaReferencedState,
    );
  });

  testWidgets('scrolled sideways, the names stay where they are and the '
      'columns move under them', (tester) async {
    await pump(tester);
    final name = find.text('cloud');
    final date = cell('date', cloud);
    final nameAt = tester.getTopLeft(name);
    final sizeAt = tester.getTopLeft(cell('size', cloud));

    // From the head of the first column — the one the 260px panel shows.
    await tester.drag(
      find.text(AppText.strings.imFile),
      const Offset(-120, 0),
    );
    await tester.pumpAndSettle();

    expect(tester.getTopLeft(name), nameAt, reason: 'pinned');
    expect(
      tester.getTopLeft(cell('size', cloud)).dx,
      lessThan(sizeAt.dx),
      reason: 'the columns scrolled',
    );
    expect(date, findsOneWidget);
  });

  testWidgets('the preset button lights while on and asks the other face; '
      'the shape button draws the view it goes to', (tester) async {
    final asked = await pump(tester);
    AppIconButton button(String key) => tester.widget<AppIconButton>(
      find.byWidgetPredicate(
        (widget) => widget is AppIconButton && widget.keyValue == key,
      ),
    );
    expect(button('media-view-presets').isSelected, isFalse);
    expect(button('media-view-icons').tooltip, AppText.strings.mediaViewIcons);

    await tester.tap(
      find.byKey(const ValueKey<String>('media-view-presets')),
    );
    await tester.tap(find.byKey(const ValueKey<String>('media-view-icons')));
    expect(asked, [
      const MediaPoolView(presets: true),
      const MediaPoolView(icons: true),
    ]);

    await pump(tester, view: const MediaPoolView(presets: true, icons: true));
    expect(button('media-view-presets').isSelected, isTrue);
    expect(button('media-view-icons').tooltip, AppText.strings.mediaViewList);
  });

  testWidgets('the preset face says what a placement makes: the sound\'s '
      'block with its name tag and words, the picture\'s kind of layer', (
    tester,
  ) async {
    await pump(tester, view: const MediaPoolView(presets: true));
    expect(
      find.byKey(const ValueKey<String>('media-asset-preset-block-$door')),
      findsOneWidget,
    );
    expect(find.text('BGM'), findsOneWidget);
    expect(find.text('slam'), findsOneWidget);
    expect(
      tester.widget<Text>(cell('kind', cloud)).data,
      layerKindDisplayName(LayerKind.image),
    );
  });
}
