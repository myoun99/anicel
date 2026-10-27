import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/media_asset.dart';
import 'package:anicel/src/services/color_palette_file_service.dart';
import 'package:anicel/src/ui/color/color_panels.dart';
import 'package:anicel/src/ui/media/media_pool_panel.dart';
import 'package:anicel/src/ui/widgets/overflow_scrollers.dart';

/// R10-①: the Color and Media panels must lay out WITHOUT overflow at any
/// squeezed dock size — a docked panel can be dragged very small.
void main() {
  const probeSizes = [
    Size(80, 400),
    Size(100, 100),
    Size(160, 120),
    Size(220, 90),
    Size(60, 60),
    Size(300, 500),
  ];

  Widget host(Size size, Widget child, {double textScale = 1}) => MaterialApp(
    builder: (context, app) => MediaQuery(
      data: MediaQuery.of(context).copyWith(
        textScaler: TextScaler.linear(textScale),
      ),
      child: app!,
    ),
    home: Scaffold(
      body: Center(
        child: SizedBox(width: size.width, height: size.height, child: child),
      ),
    ),
  );

  /// A colour panel ON ITS FLOOR — inside the scrollers the dock gives a
  /// tab that publishes one (`EditorPanelTabs._onItsFloor`): the default
  /// palette under the wheel and the RGB bars does not shrink (I-131), and
  /// the floor is what keeps it from cutting the status bar off.
  Widget colorTab(ColorPickerKind kind) => Builder(
    builder: (context) => OverflowScrollers(
      minWidth: ColorPickerPanel.minContentWidthIn(context),
      minHeight: ColorPickerPanel.contentExtentIn(context, kind) ?? 0,
      child: ColorPickerPanel(
        kind: kind,
        color: 0xFF3366CC,
        palette: ColorPaletteState.starter('Palette 1')
            .withNewPalette('Palette 2')
            .withView(PaletteView.cards)
            .withRecentColor(0xFF111111)
            .withRecentColor(0xFF222222),
        onColorChanged: (_) {},
        onPaletteChanged: (_) {},
      ),
    ),
  );

  Widget mediaPanel() => MediaPoolPanel(
    assets: [
      MediaAsset(
        path: 'C:/very/long/path/to/some/audio/file/kick.wav',
        name: 'kick',
      ),
      MediaAsset(
        path: 'C:/another/quite/long/path/snare-with-long-name.wav',
        name: 'snare-with-long-name',
      ),
    ],
    usesOf: (_) => const ['C1 · kick'],
    onImportRequested: () {},
    onRenameAsset: (_, _) {},
    onRelinkAsset: (_, _, _) {},
    onRemoveAsset: (_) {},
    onPromoteAsset: (_) async => true,
    onExportAssetWav: (_) async => true,
    // RELINK-2: nothing missing is the default now, which is what
    // `fileExists: (_) => true` was saying.
  );

  Object? describeException(WidgetTester tester) {
    final exception = tester.takeException();
    if (exception is FlutterError) {
      debugPrint(exception.toStringDeep());
    }
    return exception;
  }

  testWidgets('the Color panels never overflow at squeezed sizes, with '
      'their words read at twice the size too', (tester) async {
    for (final kind in ColorPickerKind.values) {
      for (final textScale in const [1.0, 2.0]) {
        for (final size in probeSizes) {
          await tester.pumpWidget(
            host(size, colorTab(kind), textScale: textScale),
          );
          await tester.pump();
          expect(
            describeException(tester),
            isNull,
            reason: '$kind at $size, words ×$textScale',
          );
        }
      }
    }
  });

  testWidgets('the Media panel never overflows at squeezed sizes', (
    tester,
  ) async {
    for (final size in probeSizes) {
      await tester.pumpWidget(host(size, mediaPanel()));
      await tester.pump();
      expect(describeException(tester), isNull, reason: 'media panel at $size');
    }
  });

  testWidgets('the Media panel never overflows at squeezed sizes with its '
      'words read at twice the size — a row\'s extension is measured, not '
      'guessed', (tester) async {
    for (final size in probeSizes) {
      await tester.pumpWidget(host(size, mediaPanel(), textScale: 2));
      await tester.pump();
      expect(
        describeException(tester),
        isNull,
        reason: 'media panel at $size, words ×2',
      );
    }
  });
}
