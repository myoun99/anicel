import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/project_background.dart';
import 'package:anicel/src/ui/brush/brush_canvas_panel.dart';
import 'package:anicel/src/ui/brush/brush_edit_cache_invalidation_sink.dart';
import 'package:anicel/src/ui/theme/app_workspace_colors.dart';
import 'package:anicel/src/ui/widgets/color_swatch_button.dart';

import '../helpers/brush_canvas_fixture.dart';

/// R28 #9: the canvas surface colors.
///
/// Three contracts: the default paper is PURE white (it was 0xFFEDEDED,
/// the near-white the user spotted, spelled out separately in five
/// files); both swatches sit immediately right of the horizontal
/// scrollbar; and picking goes through the ONE shared color control so
/// restyling the picker restyles every caller.
void main() {
  test('R28 #9: the default paper is pure white, from one constant', () {
    expect(ProjectBackground.defaultPaperArgb, 0xFFFFFFFF);
    expect(ProjectBackground.defaultBackground.argb, 0xFFFFFFFF);
    expect(
      ProjectBackground.fromJson(const {}).argb,
      0xFFFFFFFF,
      reason: 'the JSON fallback reads the same constant',
    );
  });

  testWidgets('R28 #9: both surface swatches mount right of the scrollbar, '
      'through the shared color control', (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final frameKeys = BrushCanvasFixture.createFrameKeys();
    var paper = ProjectBackground.defaultPaperArgb;
    var pasteboard = AppWorkspaceColors.defaultPasteboardArgb;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BrushCanvasPanel(
            coordinator: BrushCanvasFixture.createCoordinator(
              frameKeys: frameKeys,
            ),
            availableFrameKeys: frameKeys,
            cacheInvalidationSink: BrushEditCacheInvalidationSink(),
            paperColor: paper,
            onPaperColorChanged: (value) => paper = value,
            pasteboardColor: pasteboard,
            onPasteboardColorChanged: (value) => pasteboard = value,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final paperButton = find.byKey(
      const ValueKey<String>('canvas-paper-color-button'),
    );
    final pasteboardButton = find.byKey(
      const ValueKey<String>('canvas-pasteboard-color-button'),
    );
    expect(paperButton, findsOneWidget);
    expect(pasteboardButton, findsOneWidget);
    expect(find.byType(ColorSwatchButton), findsNWidgets(2));

    // "가로스크롤바의 바로오른쪽에": right of the scrollbar, left of the
    // zoom cluster that owns the far right.
    final scrollbarRight = tester
        .getRect(find.byType(CanvasViewportHorizontalScrollbar))
        .right;
    final zoomLeft = tester
        .getRect(find.byKey(const ValueKey<String>('canvas-viewport-fit')))
        .left;
    final paperLeft = tester.getRect(paperButton).left;
    expect(paperLeft, greaterThanOrEqualTo(scrollbarRight));
    expect(tester.getRect(pasteboardButton).right, lessThanOrEqualTo(zoomLeft));
  });

  testWidgets('R28 #9: the swatch opens the shared picker and edits commit', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final frameKeys = BrushCanvasFixture.createFrameKeys();
    final commits = <int>[];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BrushCanvasPanel(
            coordinator: BrushCanvasFixture.createCoordinator(
              frameKeys: frameKeys,
            ),
            availableFrameKeys: frameKeys,
            cacheInvalidationSink: BrushEditCacheInvalidationSink(),
            paperColor: 0xFFFFFFFF,
            onPaperColorChanged: commits.add,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey<String>('canvas-paper-color-button')),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('color-picker-wheel')),
      findsOneWidget,
      reason: 'the shared picker opened in the shared sub-window',
    );

    // Drag on the wheel: any pick commits opaquely.
    final wheel = find.byKey(const ValueKey<String>('color-picker-wheel'));
    final wheelRect = tester.getRect(wheel);
    await tester.dragFrom(
      wheelRect.centerLeft + const Offset(6, 0),
      const Offset(2, 2),
    );
    await tester.pumpAndSettle();

    expect(commits, isNotEmpty);
    for (final color in commits) {
      expect(
        (color >> 24) & 0xFF,
        0xFF,
        reason: 'surfaces are opaque — never a stencil',
      );
    }

    // A pointer-down outside dismisses (the shared window's rule, R27 #5).
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey<String>('color-picker-wheel')), findsNothing);
  });
}
