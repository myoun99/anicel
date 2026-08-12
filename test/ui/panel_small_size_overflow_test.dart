import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/media_asset.dart';
import 'package:anicel/src/services/color_palette_file_service.dart';
import 'package:anicel/src/ui/color/color_palette_strip.dart';
import 'package:anicel/src/ui/color/color_wheel_panel.dart';
import 'package:anicel/src/ui/media/media_browser_panel.dart';

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

  Widget host(Size size, Widget child) => MaterialApp(
    home: Scaffold(
      body: Center(
        child: SizedBox(width: size.width, height: size.height, child: child),
      ),
    ),
  );

  /// The color tab's composition (wheel above, palette strip below) as the
  /// workspace mounts it — the palette cap yields to the wheel on squat
  /// panels (the R10-① fix; keep in sync with editor_workspace.dart).
  Widget colorTab() => LayoutBuilder(
    builder: (context, constraints) {
      final paletteCap = math.min(
        140.0,
        math.max(0.0, constraints.maxHeight - 120),
      );
      return Column(
        children: [
          Expanded(
            child: ColorWheelPanel(
              color: 0xFF3366CC,
              onColorChanged: (_) {},
            ),
          ),
          ConstrainedBox(
            constraints: BoxConstraints(maxHeight: paletteCap),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: ColorPaletteStrip(
                palette: const ColorPaletteState(
                  pinned: [0xFF000000, 0xFFFF0000, 0xFF00FF00, 0xFF0000FF],
                  recent: [0xFF111111, 0xFF222222, 0xFF333333],
                ),
                currentColor: 0xFF3366CC,
                onColorSelected: (_) {},
                onPaletteChanged: (_) {},
              ),
            ),
          ),
        ],
      );
    },
  );

  Widget mediaPanel() => MediaBrowserPanel(
    assets: const [
      MediaAsset(
        path: 'C:/very/long/path/to/some/audio/file/kick.wav',
        name: 'kick',
      ),
      MediaAsset(
        path: 'C:/another/quite/long/path/snare-with-long-name.wav',
        name: 'snare-with-long-name',
      ),
    ],
    isAssetReferenced: (_) => true,
    onImportRequested: () {},
    onRenameAsset: (_, _) {},
    onRelinkAsset: (_, _) {},
    onRemoveAsset: (_) => true,
    onPromoteAsset: (_) => true,
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

  testWidgets('the Color panel never overflows at squeezed sizes', (
    tester,
  ) async {
    for (final size in probeSizes) {
      await tester.pumpWidget(host(size, colorTab()));
      await tester.pump();
      expect(describeException(tester), isNull, reason: 'color tab at $size');
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
}
