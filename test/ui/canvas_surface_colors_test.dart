import 'dart:typed_data';
import 'dart:ui' show ImageByteFormat;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/models/project_background.dart';
import 'package:anicel/src/ui/brush/brush_canvas_panel.dart';
import 'package:anicel/src/ui/brush/brush_edit_cache_invalidation_sink.dart';
import 'package:anicel/src/ui/brush/canvas_floor_insets.dart';
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

  testWidgets('R2 #3: the three stage colours are three PLACES — the '
      'pasteboard stops, and the backdrop is what lies beyond it', (
    tester,
  ) async {
    // Both planes used to fill the whole panel, one over the other. That
    // is a stack for ALPHA and says nothing about WHERE either one is, so
    // an opaque pasteboard hid the backdrop everywhere and forever: three
    // colours in the settings, two of them ever visible, and changing the
    // pasteboard repainted what the user meant by "the background".
    await tester.binding.setSurfaceSize(const Size(900, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final frameKeys = BrushCanvasFixture.createFrameKeys();
    const backdrop = 0xFF102030;
    const pasteboard = 0xFF00A0FF;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RepaintBoundary(
            key: const ValueKey<String>('stage-capture'),
            child: BrushCanvasPanel(
              coordinator: BrushCanvasFixture.createCoordinator(
                frameKeys: frameKeys,
              ),
              availableFrameKeys: frameKeys,
              cacheInvalidationSink: BrushEditCacheInvalidationSink(),
              canvasSize: BrushCanvasFixture.canvasSize,
              floorCover: EdgeInsets.zero,
              backdropArgb: backdrop,
              pasteboardColor: pasteboard,
              // A quarter of a canvas out on every side, and zoomed out —
              // so the panel shows the apron AND what lies beyond it,
              // which is the whole point of the number.
              pasteboardMargin: 0.25,
              viewport: CanvasViewport(zoom: 0.05, panX: 450, panY: 300),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(const ValueKey<String>('stage-capture')),
    );
    final image = boundary.toImageSync();
    late Uint8List bytes;
    await tester.runAsync(() async {
      final data = await image.toByteData(format: ImageByteFormat.rawRgba);
      bytes = data!.buffer.asUint8List();
    });
    image.dispose();
    int rgbAt(int x, int y) {
      final i = (y * 900 + x) * 4;
      return (bytes[i] << 16) | (bytes[i + 1] << 8) | bytes[i + 2];
    }

    // The corners of a 900×600 panel at 5% zoom are far outside a
    // quarter-canvas apron — that is the BACKDROP, and it used to be
    // unreachable because the pasteboard was painted over the whole box.
    expect(rgbAt(2, 2), backdrop & 0xFFFFFF, reason: 'top-left corner');
    expect(rgbAt(897, 597), backdrop & 0xFFFFFF, reason: 'bottom-right');
    // Just outside the paper, still inside the apron: the PASTEBOARD.
    expect(
      rgbAt(450 - 12, 300 - 12),
      pasteboard & 0xFFFFFF,
      reason: 'the apron around the paper',
    );
  });

  testWidgets('유저 R4 #2: a canvas panel given NO stage colours takes the '
      'shell\'s, so every canvas-based panel sits in the same room', (
    tester,
  ) async {
    // The drawing floor dug the project's colours out of the session and
    // passed them down; the timesheet, the conte, the cut envelope and the
    // media viewer construct `BrushCanvasPanel` without them and so sat on
    // the CONSTANT DEFAULT — four canvas panels on hard black while the
    // floor followed the project. Nothing about that was visible in a test,
    // because every colour test passed the colours in explicitly.
    //
    // ⚠️This test passes NONE, which is the whole point: it is the only
    // shape that can tell the scope apart from a default. Rip
    // `CanvasStageColors` back out of the panel and these pixels fall back
    // to #141517 and go red.
    await tester.binding.setSurfaceSize(const Size(900, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final frameKeys = BrushCanvasFixture.createFrameKeys();
    const backdrop = 0xFF102030;
    const pasteboard = 0xFF00A0FF;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CanvasStageColors(
            backdropArgb: backdrop,
            pasteboardArgb: pasteboard,
            pasteboardMargin: 0.25,
            child: RepaintBoundary(
              key: const ValueKey<String>('scoped-stage-capture'),
              child: BrushCanvasPanel(
                coordinator: BrushCanvasFixture.createCoordinator(
                  frameKeys: frameKeys,
                ),
                availableFrameKeys: frameKeys,
                cacheInvalidationSink: BrushEditCacheInvalidationSink(),
                canvasSize: BrushCanvasFixture.canvasSize,
                floorCover: EdgeInsets.zero,
                viewport: CanvasViewport(zoom: 0.05, panX: 450, panY: 300),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(const ValueKey<String>('scoped-stage-capture')),
    );
    final image = boundary.toImageSync();
    late Uint8List bytes;
    await tester.runAsync(() async {
      final data = await image.toByteData(format: ImageByteFormat.rawRgba);
      bytes = data!.buffer.asUint8List();
    });
    image.dispose();
    int rgbAt(int x, int y) {
      final i = (y * 900 + x) * 4;
      return (bytes[i] << 16) | (bytes[i + 1] << 8) | bytes[i + 2];
    }

    expect(rgbAt(2, 2), backdrop & 0xFFFFFF, reason: 'backdrop from the scope');
    expect(
      rgbAt(450 - 12, 300 - 12),
      pasteboard & 0xFFFFFF,
      reason: 'pasteboard AND its margin from the scope',
    );
  });

  testWidgets('유저 R4 #2: a panel\'s own colours still win over the shell — '
      'the fixtures and the dev harness mount outside it', (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final frameKeys = BrushCanvasFixture.createFrameKeys();
    const scoped = 0xFF102030;
    const own = 0xFF902010;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CanvasStageColors(
            backdropArgb: scoped,
            pasteboardArgb: scoped,
            pasteboardMargin: 0.25,
            child: RepaintBoundary(
              key: const ValueKey<String>('override-stage-capture'),
              child: BrushCanvasPanel(
                coordinator: BrushCanvasFixture.createCoordinator(
                  frameKeys: frameKeys,
                ),
                availableFrameKeys: frameKeys,
                cacheInvalidationSink: BrushEditCacheInvalidationSink(),
                canvasSize: BrushCanvasFixture.canvasSize,
                floorCover: EdgeInsets.zero,
                backdropArgb: own,
                viewport: CanvasViewport(zoom: 0.05, panX: 450, panY: 300),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(const ValueKey<String>('override-stage-capture')),
    );
    final image = boundary.toImageSync();
    late Uint8List bytes;
    await tester.runAsync(() async {
      final data = await image.toByteData(format: ImageByteFormat.rawRgba);
      bytes = data!.buffer.asUint8List();
    });
    image.dispose();
    final i = (2 * 900 + 2) * 4;
    expect(
      (bytes[i] << 16) | (bytes[i + 1] << 8) | bytes[i + 2],
      own & 0xFFFFFF,
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
            // A canvas standing on its own IS the floor, and that is where the
            // view controls live (법: 뷰 컨트롤은 바닥에만).
            floorCover: EdgeInsets.zero,
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

    // The original wording — "가로스크롤바의 바로오른쪽에" — described the
    // swatches' place in a bottom BAR that ran the width of the panel with
    // the panbar stretched through its middle. The floor has no such bar:
    // the panbar is its own capsule on the top edge and the view controls
    // are a cluster in the corner. What survives is the ORDER the user
    // asked for — the swatches come after the view controls, at the far
    // end, because they are the thing you touch once a project.
    final zoomRight = tester
        .getRect(find.byKey(const ValueKey<String>('canvas-viewport-zoom-in')))
        .right;
    expect(tester.getRect(paperButton).left, greaterThanOrEqualTo(zoomRight));
    expect(
      tester.getRect(pasteboardButton).left,
      greaterThanOrEqualTo(tester.getRect(paperButton).right),
    );
    // And the panbar is no longer beside them at all — it floats.
    expect(find.byType(CanvasViewportHorizontalScrollbar), findsOneWidget);
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
            // A canvas standing on its own IS the floor, and that is where the
            // view controls live (법: 뷰 컨트롤은 바닥에만).
            floorCover: EdgeInsets.zero,
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
