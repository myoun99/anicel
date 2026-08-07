import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/ui/brush/brush_canvas_defaults.dart';
import 'package:anicel/src/ui/brush/brush_canvas_panel.dart';
import 'package:anicel/src/ui/brush/brush_cursor_overlay.dart';
import 'package:anicel/src/ui/brush/brush_edit_cache_invalidation_sink.dart';
import 'package:anicel/src/ui/brush/brush_tool_state.dart';
import 'package:anicel/src/ui/canvas/brush_edit_canvas_input_settings.dart';
import 'package:anicel/src/ui/canvas/brush_edit_canvas_view.dart';
import 'package:anicel/src/ui/canvas/interactive_brush_edit_canvas_view.dart';

import '../helpers/brush_canvas_fixture.dart';
import 'brush_canvas_test_helpers.dart';

void main() {
  testWidgets('renders embedded canvas without temporary debug controls', (
    tester,
  ) async {
    final frameKeys = BrushCanvasFixture.createFrameKeys();
    final coordinator = BrushCanvasFixture.createCoordinator(
      frameKeys: frameKeys,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BrushCanvasPanel(
            coordinator: coordinator,
            availableFrameKeys: frameKeys,
            cacheInvalidationSink: BrushEditCacheInvalidationSink(),
            // A canvas standing on its own IS the floor, and that is where the
            // view controls live (법: 뷰 컨트롤은 바닥에만).
            floorCover: EdgeInsets.zero,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('brush-canvas-panel')),
      findsOneWidget,
    );
    expect(find.byType(InteractiveBrushEditCanvasView), findsOneWidget);
    expect(
      tester
          .widget<InteractiveBrushEditCanvasView>(
            find.byType(InteractiveBrushEditCanvasView),
          )
          .inputSettings,
      BrushEditCanvasInputSettings(size: 10),
    );
    expect(
      find.byKey(
        const ValueKey<String>('interactive-brush-edit-canvas-view-listener'),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('brush-frame-1-button')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey<String>('brush-frame-2-button')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey<String>('brush-frame-3-button')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey<String>('brush-workspace-undo-button')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey<String>('brush-workspace-redo-button')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey<String>('brush-workspace-reset-button')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey<String>('brush-workspace-active-frame-label')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey<String>('brush-workspace-status-text')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey<String>('brush-workspace-debug-reset-help')),
      findsNothing,
    );
    expect(find.text('Debug Reset Session'), findsNothing);
    expect(find.text('Undo'), findsNothing);
    expect(find.text('Redo'), findsNothing);
    expect(find.text('Black'), findsNothing);
    expect(find.text('Red'), findsNothing);
  });

  testWidgets('canvas panel does not expose editable brush settings', (
    tester,
  ) async {
    final frameKeys = BrushCanvasFixture.createFrameKeys();
    final coordinator = BrushCanvasFixture.createCoordinator(
      frameKeys: frameKeys,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BrushCanvasPanel(
            coordinator: coordinator,
            availableFrameKeys: frameKeys,
            cacheInvalidationSink: BrushEditCacheInvalidationSink(),
            // A canvas standing on its own IS the floor, and that is where the
            // view controls live (법: 뷰 컨트롤은 바닥에만).
            floorCover: EdgeInsets.zero,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('brush-tool-options-bar')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey<String>('brush-tool-size-slider')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey<String>('brush-tool-opacity-slider')),
      findsNothing,
    );
  });

  testWidgets(
    'renders compact canvas editor panel shell and viewport controls',
    (tester) async {
      final frameKeys = BrushCanvasFixture.createFrameKeys();
      final coordinator = BrushCanvasFixture.createCoordinator(
        frameKeys: frameKeys,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BrushCanvasPanel(
              coordinator: coordinator,
              availableFrameKeys: frameKeys,
              cacheInvalidationSink: BrushEditCacheInvalidationSink(),
              // A canvas standing on its own IS the floor, and that is where the
              // view controls live (법: 뷰 컨트롤은 바닥에만).
              floorCover: EdgeInsets.zero,
            ),
          ),
        ),
      );

      expect(
        find.byKey(const ValueKey<String>('canvas-editor-panel-shell')),
        findsOneWidget,
      );
      // R2 #12: no status strip, docked or floating. The project name and
      // the layer readout are gone from every canvas panel — the user asked
      // for the space back and will ask for a pill if they want them.
      expect(
        find.byKey(const ValueKey<String>('canvas-editor-panel-status-strip')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey<String>('canvas-status-capsule')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey<String>('canvas-editor-panel-content')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('canvas-panbar-vertical')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('canvas-view-pill')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('canvas-viewport-zoom-label')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('canvas-viewport-zoom-out')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('canvas-viewport-zoom-in')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('canvas-viewport-fit')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('canvas-viewport-reset')),
        findsOneWidget,
      );
    },
  );

  testWidgets('narrow bottom bar keeps fit/reset/zoom reachable and never '
      'overflows (rotate/flip drop out)', (tester) async {
    final frameKeys = BrushCanvasFixture.createFrameKeys();
    final coordinator = BrushCanvasFixture.createCoordinator(
      frameKeys: frameKeys,
      canvasSize: const CanvasSize(width: 300, height: 300),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 280,
            height: 360,
            child: BrushCanvasPanel(
              coordinator: coordinator,
              availableFrameKeys: frameKeys,
              cacheInvalidationSink: BrushEditCacheInvalidationSink(),
              // A canvas standing on its own IS the floor, and that is where the
              // view controls live (법: 뷰 컨트롤은 바닥에만).
              floorCover: EdgeInsets.zero,
              canvasSize: const CanvasSize(width: 300, height: 300),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    // Essentials stay in the tree even in the narrowest panel.
    expect(
      find.byKey(const ValueKey<String>('canvas-viewport-fit')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('canvas-viewport-reset')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('canvas-viewport-zoom-out')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('canvas-viewport-zoom-in')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('canvas-viewport-zoom-label')),
      findsOneWidget,
    );
    // Secondary rotate/flip give up their space instead of overflowing.
    expect(
      find.byKey(const ValueKey<String>('canvas-viewport-rotate-ccw')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey<String>('canvas-viewport-flip')),
      findsNothing,
    );

    expect(tester.takeException(), isNull);
  });

  testWidgets('keeps inner drawing canvas at Cut canvas size', (tester) async {
    final frameKeys = BrushCanvasFixture.createFrameKeys();
    final coordinator = BrushCanvasFixture.createCoordinator(
      frameKeys: frameKeys,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BrushCanvasPanel(
            coordinator: coordinator,
            availableFrameKeys: frameKeys,
            cacheInvalidationSink: BrushEditCacheInvalidationSink(),
            // A canvas standing on its own IS the floor, and that is where the
            // view controls live (법: 뷰 컨트롤은 바닥에만).
            floorCover: EdgeInsets.zero,
          ),
        ),
      ),
    );

    // The view now fills the editor viewport and renders the Cut-sized
    // canvas inside the painter (viewport transform is in-picture); the
    // drawing area therefore comes from the session surface.
    final canvasView = tester.widget<BrushEditCanvasView>(
      find.byType(BrushEditCanvasView),
    );
    expect(
      canvasView.sessionState.canvasState.currentSurface.canvasSize,
      BrushCanvasDefaults.canvasSize,
    );
  });

  testWidgets('fit action uses the available editor viewport size', (
    tester,
  ) async {
    final frameKeys = BrushCanvasFixture.createFrameKeys();
    final coordinator = BrushCanvasFixture.createCoordinator(
      frameKeys: frameKeys,
      canvasSize: const CanvasSize(width: 100, height: 50),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 640,
            height: 360,
            child: BrushCanvasPanel(
              coordinator: coordinator,
              availableFrameKeys: frameKeys,
              cacheInvalidationSink: BrushEditCacheInvalidationSink(),
              // A canvas standing on its own IS the floor, and that is where the
              // view controls live (법: 뷰 컨트롤은 바닥에만).
              floorCover: EdgeInsets.zero,
              canvasSize: const CanvasSize(width: 100, height: 50),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final viewportSize = tester.getSize(
      find.byKey(const ValueKey<String>('brush-canvas-editor-viewport')),
    );

    await tester.tap(find.byKey(const ValueKey<String>('canvas-viewport-fit')));
    await tester.pump();

    final canvas = tester.widget<InteractiveBrushEditCanvasView>(
      find.byType(InteractiveBrushEditCanvasView),
    );
    final expected = CanvasViewport.fitToView(
      canvasWidth: 100,
      canvasHeight: 50,
      viewportWidth: viewportSize.width,
      viewportHeight: viewportSize.height,
    );

    expect(canvas.viewport.zoom, expected.zoom);
    expect(canvas.viewport.panX, expected.panX);
    expect(canvas.viewport.panY, expected.panY);
  });

  testWidgets('reset action restores the identity viewport', (tester) async {
    final frameKeys = BrushCanvasFixture.createFrameKeys();
    final coordinator = BrushCanvasFixture.createCoordinator(
      frameKeys: frameKeys,
      canvasSize: const CanvasSize(width: 100, height: 50),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 640,
            height: 360,
            child: BrushCanvasPanel(
              coordinator: coordinator,
              availableFrameKeys: frameKeys,
              cacheInvalidationSink: BrushEditCacheInvalidationSink(),
              // A canvas standing on its own IS the floor, and that is where the
              // view controls live (법: 뷰 컨트롤은 바닥에만).
              floorCover: EdgeInsets.zero,
              canvasSize: const CanvasSize(width: 100, height: 50),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey<String>('canvas-viewport-fit')));
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey<String>('canvas-viewport-reset')),
    );
    await tester.pump();

    final canvas = tester.widget<InteractiveBrushEditCanvasView>(
      find.byType(InteractiveBrushEditCanvasView),
    );

    expect(canvas.viewport, CanvasViewport());
  });

  group('zoom label inline percent entry', () {
    Future<void> pumpZoomPanel(WidgetTester tester) async {
      final frameKeys = BrushCanvasFixture.createFrameKeys();
      final coordinator = BrushCanvasFixture.createCoordinator(
        frameKeys: frameKeys,
        canvasSize: const CanvasSize(width: 100, height: 50),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 640,
              height: 360,
              child: BrushCanvasPanel(
                coordinator: coordinator,
                availableFrameKeys: frameKeys,
                cacheInvalidationSink: BrushEditCacheInvalidationSink(),
                // A canvas standing on its own IS the floor, and that is where the
                // view controls live (법: 뷰 컨트롤은 바닥에만).
                floorCover: EdgeInsets.zero,
                canvasSize: const CanvasSize(width: 100, height: 50),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
    }

    CanvasViewport viewportOf(WidgetTester tester) => tester
        .widget<InteractiveBrushEditCanvasView>(
          find.byType(InteractiveBrushEditCanvasView),
        )
        .viewport;

    /// R10: ONE tap opens the entry. It was a double tap, which held every
    /// tap on the readout for the double-tap window — ~300ms of nothing,
    /// which the user asked to be gone everywhere. Nothing was lost: the
    /// label had no single-tap action to collide with.
    Future<void> tapZoomLabel(WidgetTester tester) async {
      await tester.tap(
        find.byKey(const ValueKey<String>('canvas-viewport-zoom-label')),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('tap, type, and submit set the zoom', (tester) async {
      await pumpZoomPanel(tester);

      await tapZoomLabel(tester);
      final input = find.byKey(
        const ValueKey<String>('canvas-viewport-zoom-input'),
      );
      expect(input, findsOneWidget);

      await tester.enterText(input, '250');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(input, findsNothing);
      expect(viewportOf(tester).zoom, 2.5);
      expect(find.text('250%'), findsOneWidget);
    });

    testWidgets('Escape cancels the entry without committing', (tester) async {
      await pumpZoomPanel(tester);

      await tapZoomLabel(tester);
      await tester.enterText(
        find.byKey(const ValueKey<String>('canvas-viewport-zoom-input')),
        '300',
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey<String>('canvas-viewport-zoom-input')),
        findsNothing,
      );
      expect(viewportOf(tester).zoom, 1.0);
      expect(find.text('100%'), findsOneWidget);
    });

    testWidgets('out-of-range entries clamp to the zoom bounds', (
      tester,
    ) async {
      await pumpZoomPanel(tester);

      await tapZoomLabel(tester);
      await tester.enterText(
        find.byKey(const ValueKey<String>('canvas-viewport-zoom-input')),
        '5000',
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(viewportOf(tester).zoom, 16.0);
      expect(find.text('1600%'), findsOneWidget);
    });
  });

  testWidgets('passes custom initial input settings to canvas view', (
    tester,
  ) async {
    final frameKeys = BrushCanvasFixture.createFrameKeys();
    final coordinator = BrushCanvasFixture.createCoordinator(
      frameKeys: frameKeys,
    );
    final settings = BrushEditCanvasInputSettings(
      color: 0xFFFF0000,
      size: 12,
      opacity: 0.75,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BrushCanvasPanel(
            coordinator: coordinator,
            availableFrameKeys: frameKeys,
            cacheInvalidationSink: BrushEditCacheInvalidationSink(),
            // A canvas standing on its own IS the floor, and that is where the
            // view controls live (법: 뷰 컨트롤은 바닥에만).
            floorCover: EdgeInsets.zero,
            brushToolState: BrushToolState.clamped(
              color: settings.color,
              size: settings.size,
              opacity: settings.opacity,
            ),
          ),
        ),
      ),
    );

    final canvas = tester.widget<InteractiveBrushEditCanvasView>(
      find.byType(InteractiveBrushEditCanvasView),
    );
    expect(canvas.inputSettings, settings);
  });

  testWidgets('commits sampled source dabs into the brush frame store', (
    tester,
  ) async {
    final frameKeys = BrushCanvasFixture.createFrameKeys();
    final coordinator = BrushCanvasFixture.createCoordinator(
      frameKeys: frameKeys,
    );

    final sink = BrushEditCacheInvalidationSink();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BrushCanvasPanel(
            coordinator: coordinator,
            availableFrameKeys: frameKeys,
            cacheInvalidationSink: sink,
            // A canvas standing on its own IS the floor, and that is where the
            // view controls live (법: 뷰 컨트롤은 바닥에만).
            floorCover: EdgeInsets.zero,
            brushToolState: BrushToolState.clamped(size: 8),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final gesture = await tester.startGesture(
      canvasGlobalOffset(tester, const Offset(1, 1)),
      pointer: 1,
    );
    await gesture.moveTo(canvasGlobalOffset(tester, const Offset(7, 1)));
    await gesture.up();
    await tester.pump();

    // R19 P3b: the stroke lands as raster truth — the pixels are the
    // record (no command bookkeeping to inspect).
    expect(
      coordinator.frameStore.celHasRenderableContent(
        coordinator.activeFrameKey,
      ),
      isTrue,
    );
    // Commit materializes the stroke and invalidates the affected frame and
    // derived layer-tile caches so previews/playback refresh.
    expect(sink.brushFrames, hasLength(1));
    expect(sink.layerTiles, isNotEmpty);
  });

  testWidgets('prepares display cache after drawing', (tester) async {
    final frameKeys = BrushCanvasFixture.createFrameKeys();
    final coordinator = BrushCanvasFixture.createCoordinator(
      frameKeys: frameKeys,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BrushCanvasPanel(
            coordinator: coordinator,
            availableFrameKeys: frameKeys,
            cacheInvalidationSink: BrushEditCacheInvalidationSink(),
            // A canvas standing on its own IS the floor, and that is where the
            // view controls live (법: 뷰 컨트롤은 바닥에만).
            floorCover: EdgeInsets.zero,
            brushToolState: BrushToolState.clamped(size: 8),
            canvasSize: BrushCanvasFixture.canvasSize,
          ),
        ),
      ),
    );

    final gesture = await tester.startGesture(
      canvasGlobalOffset(tester, const Offset(1, 1)),
      pointer: 1,
    );
    await gesture.moveTo(canvasGlobalOffset(tester, const Offset(7, 1)));

    // Mid-stroke the live pointer path never generates a preview cache.
    expect(
      coordinator.frameStore.displayCacheOrNull(coordinator.activeFrameKey),
      isNull,
    );

    await gesture.up();
    await tester.pump();

    // Pen-up DONATES the committed session surface as the display cache —
    // nothing is generated (the immutable surface is shared), and no later
    // consumer replays the stroke.
    final cache = coordinator.frameStore.displayCacheOrNull(
      coordinator.activeFrameKey,
    )!;
    expect(cache.isValid, isTrue);
    expect(
      identical(
        cache.previewSurface,
        coordinator.activeSessionState.canvasState.currentSurface,
      ),
      isTrue,
    );

    // The committed stroke is materialized into the session surface and
    // displayed from the bitmap (WYSIWYG), not as source-dab stamps.
    // R25-④: the commit landed in the previous frame's post-frame
    // phase, so the view widget rebuilds with the post-commit session
    // state one pump later.
    await tester.pump();
    final canvasView = tester.widget<BrushEditCanvasView>(
      find.byType(BrushEditCanvasView),
    );
    expect(
      canvasView.sessionState.canvasState.currentSurface.tiles,
      isNotEmpty,
    );
    expect(
      identical(
        coordinator.frameStore.bakedSurfaceOrNull(coordinator.activeFrameKey),
        cache.previewSurface,
      ),
      isTrue,
      reason: 'the donation is also the bake (raster truth)',
    );
  });

  testWidgets('canvas editor panel shell remains safe at very small heights', (
    tester,
  ) async {
    final frameKeys = BrushCanvasFixture.createFrameKeys();
    final coordinator = BrushCanvasFixture.createCoordinator(
      frameKeys: frameKeys,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 1200,
            height: 80,
            child: BrushCanvasPanel(
              coordinator: coordinator,
              availableFrameKeys: frameKeys,
              cacheInvalidationSink: BrushEditCacheInvalidationSink(),
              // A canvas standing on its own IS the floor, and that is where the
              // view controls live (법: 뷰 컨트롤은 바닥에만).
              floorCover: EdgeInsets.zero,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(
      find.byKey(const ValueKey<String>('canvas-editor-panel-content')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('canvas-panbar-vertical')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('canvas-view-pill')),
      findsOneWidget,
    );
  });

  testWidgets('panbar drag syncs parent once at drag end', (tester) async {
    final frameKeys = BrushCanvasFixture.createFrameKeys();
    final coordinator = BrushCanvasFixture.createCoordinator(
      frameKeys: frameKeys,
      canvasSize: const CanvasSize(width: 300, height: 300),
    );
    final syncedViewports = <CanvasViewport>[];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            // Narrow enough that the zoomed canvas overflows the viewport
            // (the panel no longer insets itself 16px on each side).
            width: 560,
            height: 360,
            child: BrushCanvasPanel(
              coordinator: coordinator,
              availableFrameKeys: frameKeys,
              cacheInvalidationSink: BrushEditCacheInvalidationSink(),
              // A canvas standing on its own IS the floor, and that is where the
              // view controls live (법: 뷰 컨트롤은 바닥에만).
              floorCover: EdgeInsets.zero,
              canvasSize: const CanvasSize(width: 300, height: 300),
              viewport: CanvasViewport(zoom: 2),
              onViewportChanged: syncedViewports.add,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final gesture = await tester.startGesture(
      tester.getCenter(
        find.byKey(
          const ValueKey<String>('canvas-viewport-horizontal-scrollbar'),
        ),
      ),
    );
    await gesture.moveBy(const Offset(20, 0));
    await tester.pump();

    expect(syncedViewports, isEmpty);

    await gesture.up();
    await tester.pump();

    expect(syncedViewports, hasLength(1));
    expect(syncedViewports.single.panX, isNot(0));
  });

  testWidgets('panbar drag cancel syncs parent once with final viewport', (
    tester,
  ) async {
    final frameKeys = BrushCanvasFixture.createFrameKeys();
    final coordinator = BrushCanvasFixture.createCoordinator(
      frameKeys: frameKeys,
      canvasSize: const CanvasSize(width: 300, height: 300),
    );
    final syncedViewports = <CanvasViewport>[];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            // Narrow enough that the zoomed canvas overflows the viewport
            // (the panel no longer insets itself 16px on each side).
            width: 560,
            height: 360,
            child: BrushCanvasPanel(
              coordinator: coordinator,
              availableFrameKeys: frameKeys,
              cacheInvalidationSink: BrushEditCacheInvalidationSink(),
              // A canvas standing on its own IS the floor, and that is where the
              // view controls live (법: 뷰 컨트롤은 바닥에만).
              floorCover: EdgeInsets.zero,
              canvasSize: const CanvasSize(width: 300, height: 300),
              viewport: CanvasViewport(zoom: 2),
              onViewportChanged: syncedViewports.add,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final gesture = await tester.startGesture(
      tester.getCenter(
        find.byKey(
          const ValueKey<String>('canvas-viewport-horizontal-scrollbar'),
        ),
      ),
    );
    await gesture.moveBy(const Offset(20, 0));
    await tester.pump();

    expect(syncedViewports, isEmpty);

    await gesture.cancel();
    await tester.pump();

    expect(syncedViewports, hasLength(1));
    expect(syncedViewports.single.panX, isNot(0));
  });

  group('viewport gestures (panel-level, frame-independent)', () {
    // The gesture layer lives on the panel, so navigation must work when the
    // viewport shows the blank paper (no editable frame) — coordinator null,
    // contentOverride only.
    Widget blankPanel({
      required ValueChanged<CanvasViewport> onViewportChanged,
    }) {
      return MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 640,
            height: 360,
            child: BrushCanvasPanel(
              coordinator: null,
              availableFrameKeys: const [],
              cacheInvalidationSink: BrushEditCacheInvalidationSink(),
              // A canvas standing on its own IS the floor, and that is where the
              // view controls live (법: 뷰 컨트롤은 바닥에만).
              floorCover: EdgeInsets.zero,
              canvasSize: const CanvasSize(width: 300, height: 300),
              onViewportChanged: onViewportChanged,
              contentOverride: (context, viewport) => const SizedBox.expand(),
            ),
          ),
        ),
      );
    }

    /// How far below the viewport's top edge these gestures start.
    ///
    /// The floor's view pill is pinned to the TOP-LEFT corner, so a gesture
    /// aimed at (30, 30) is aimed at the pill. Deltas between two of these
    /// points are unaffected — but anything that measures an ABSOLUTE focal
    /// has to count the same shift, so it is a named number rather than one
    /// buried in a helper.
    const clusterClearance = 60.0;

    Offset viewportPoint(WidgetTester tester, Offset offset) {
      return tester.getTopLeft(
            find.byKey(const ValueKey<String>('brush-canvas-editor-viewport')),
          ) +
          const Offset(0, clusterClearance) +
          offset;
    }

    testWidgets('scroll wheel alone zooms without an editable frame', (
      tester,
    ) async {
      final viewports = <CanvasViewport>[];
      await tester.pumpWidget(blankPanel(onViewportChanged: viewports.add));
      await tester.pump();

      final pointer = TestPointer(1, PointerDeviceKind.mouse);
      pointer.hover(viewportPoint(tester, const Offset(40, 40)));
      await tester.sendEventToBinding(pointer.scroll(const Offset(0, -120)));
      await tester.pump();

      expect(viewports, isNotEmpty);
      expect(viewports.last.zoom, closeTo(1.1, 1e-9));

      await tester.sendEventToBinding(pointer.scroll(const Offset(0, 120)));
      await tester.pump();

      expect(viewports.last.zoom, closeTo(1.0, 1e-9));
    });

    testWidgets('middle mouse drag pans without an editable frame', (
      tester,
    ) async {
      final viewports = <CanvasViewport>[];
      await tester.pumpWidget(blankPanel(onViewportChanged: viewports.add));
      await tester.pump();

      final gesture = await tester.createGesture(
        kind: PointerDeviceKind.mouse,
        buttons: kMiddleMouseButton,
      );
      await gesture.down(viewportPoint(tester, const Offset(30, 30)));
      await gesture.moveTo(viewportPoint(tester, const Offset(42, 51)));
      await gesture.up();
      await tester.pump();

      expect(viewports, isNotEmpty);
      expect(viewports.last.panX, 12);
      expect(viewports.last.panY, 21);
    });

    testWidgets('trackpad two-finger pan pans the viewport', (tester) async {
      final viewports = <CanvasViewport>[];
      await tester.pumpWidget(blankPanel(onViewportChanged: viewports.add));
      await tester.pump();

      final gesture = await tester.createGesture(
        kind: PointerDeviceKind.trackpad,
      );
      final start = viewportPoint(tester, const Offset(50, 50));
      await gesture.panZoomStart(start);
      await gesture.panZoomUpdate(start, pan: const Offset(14, -9));
      await gesture.panZoomEnd();
      await tester.pump();

      expect(viewports, isNotEmpty);
      expect(viewports.last.zoom, 1.0);
      expect(viewports.last.panX, 14);
      expect(viewports.last.panY, -9);
    });

    testWidgets('trackpad pinch zooms the viewport', (tester) async {
      final viewports = <CanvasViewport>[];
      await tester.pumpWidget(blankPanel(onViewportChanged: viewports.add));
      await tester.pump();

      final gesture = await tester.createGesture(
        kind: PointerDeviceKind.trackpad,
      );
      final start = viewportPoint(tester, const Offset(50, 50));
      await gesture.panZoomStart(start);
      await gesture.panZoomUpdate(start, scale: 2.0);
      await gesture.panZoomEnd();
      await tester.pump();

      expect(viewports, isNotEmpty);
      expect(viewports.last.zoom, closeTo(2.0, 1e-9));
    });

    testWidgets('two-finger touch pinch zooms and pans without a frame', (
      tester,
    ) async {
      final viewports = <CanvasViewport>[];
      await tester.pumpWidget(blankPanel(onViewportChanged: viewports.add));
      await tester.pump();

      final firstFinger = await tester.createGesture(
        kind: PointerDeviceKind.touch,
      );
      final secondFinger = await tester.createGesture(
        kind: PointerDeviceKind.touch,
      );
      await firstFinger.down(viewportPoint(tester, const Offset(40, 50)));
      await secondFinger.down(viewportPoint(tester, const Offset(80, 50)));

      // Pinch out: distance 40 → 80 doubles the zoom around the start
      // focal (60,50); the new focal (80,50) drags the view 20px along x.
      await secondFinger.moveTo(viewportPoint(tester, const Offset(120, 50)));
      await firstFinger.up();
      await secondFinger.up();
      await tester.pump();

      expect(viewports, isNotEmpty);
      expect(viewports.last.zoom, closeTo(2.0, 1e-9));
      expect(viewports.last.panX, closeTo(-40, 1e-9));
      // The focal's ABSOLUTE y is what doubling reflects, so this counts
      // the clearance the gestures started below.
      expect(viewports.last.panY, closeTo(-(50 + clusterClearance), 1e-9));
    });

    testWidgets('two-finger touch navigation works over a stroke in progress', (
      tester,
    ) async {
      final frameKeys = BrushCanvasFixture.createFrameKeys();
      final coordinator = BrushCanvasFixture.createCoordinator(
        frameKeys: frameKeys,
        canvasSize: const CanvasSize(width: 300, height: 300),
      );
      final viewports = <CanvasViewport>[];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 640,
              height: 360,
              child: BrushCanvasPanel(
                coordinator: coordinator,
                availableFrameKeys: frameKeys,
                cacheInvalidationSink: BrushEditCacheInvalidationSink(),
                // A canvas standing on its own IS the floor, and that is where the
                // view controls live (법: 뷰 컨트롤은 바닥에만).
                floorCover: EdgeInsets.zero,
                canvasSize: const CanvasSize(width: 300, height: 300),
                onViewportChanged: viewports.add,
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      // Finger 1 starts what looks like a stroke; finger 2 turns the
      // interaction into navigation (the view cancels the stroke).
      final firstFinger = await tester.createGesture(
        kind: PointerDeviceKind.touch,
      );
      await firstFinger.down(viewportPoint(tester, const Offset(40, 40)));
      final secondFinger = await tester.createGesture(
        kind: PointerDeviceKind.touch,
      );
      await secondFinger.down(viewportPoint(tester, const Offset(80, 40)));
      // The view cancels the touch stroke synchronously; the panel's
      // strokeActive flag clears on the next frame — pump before moving.
      await tester.pump();

      await secondFinger.moveTo(viewportPoint(tester, const Offset(100, 40)));
      await firstFinger.up();
      await secondFinger.up();
      await tester.pumpAndSettle();

      expect(viewports, isNotEmpty);
    });

    testWidgets('scroll wheel zooms with an editable frame too', (
      tester,
    ) async {
      final frameKeys = BrushCanvasFixture.createFrameKeys();
      final coordinator = BrushCanvasFixture.createCoordinator(
        frameKeys: frameKeys,
        canvasSize: const CanvasSize(width: 300, height: 300),
      );
      final viewports = <CanvasViewport>[];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 640,
              height: 360,
              child: BrushCanvasPanel(
                coordinator: coordinator,
                availableFrameKeys: frameKeys,
                cacheInvalidationSink: BrushEditCacheInvalidationSink(),
                // A canvas standing on its own IS the floor, and that is where the
                // view controls live (법: 뷰 컨트롤은 바닥에만).
                floorCover: EdgeInsets.zero,
                canvasSize: const CanvasSize(width: 300, height: 300),
                onViewportChanged: viewports.add,
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      final pointer = TestPointer(7, PointerDeviceKind.mouse);
      pointer.hover(viewportPoint(tester, const Offset(60, 60)));
      await tester.sendEventToBinding(pointer.scroll(const Offset(0, -120)));
      await tester.pump();

      expect(viewports, isNotEmpty);
      expect(viewports.last.zoom, closeTo(1.1, 1e-9));
    });

    testWidgets('wheel zoom is suppressed while a stroke is active', (
      tester,
    ) async {
      final frameKeys = BrushCanvasFixture.createFrameKeys();
      final coordinator = BrushCanvasFixture.createCoordinator(
        frameKeys: frameKeys,
        canvasSize: const CanvasSize(width: 300, height: 300),
      );
      final viewports = <CanvasViewport>[];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 640,
              height: 360,
              child: BrushCanvasPanel(
                coordinator: coordinator,
                availableFrameKeys: frameKeys,
                cacheInvalidationSink: BrushEditCacheInvalidationSink(),
                // A canvas standing on its own IS the floor, and that is where the
                // view controls live (법: 뷰 컨트롤은 바닥에만).
                floorCover: EdgeInsets.zero,
                canvasSize: const CanvasSize(width: 300, height: 300),
                onViewportChanged: viewports.add,
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      // Start a stroke with the primary button and keep it held.
      final strokeGesture = await tester.createGesture(
        kind: PointerDeviceKind.mouse,
        buttons: kPrimaryMouseButton,
      );
      await strokeGesture.down(viewportPoint(tester, const Offset(50, 50)));
      await tester.pump();

      final wheelPointer = TestPointer(9, PointerDeviceKind.mouse);
      wheelPointer.hover(viewportPoint(tester, const Offset(60, 60)));
      await tester.sendEventToBinding(
        wheelPointer.scroll(const Offset(0, -120)),
      );
      await tester.pump();

      expect(viewports, isEmpty);

      await strokeGesture.up();
      await tester.pumpAndSettle();
      viewports.clear();

      await tester.sendEventToBinding(
        wheelPointer.scroll(const Offset(0, -120)),
      );
      await tester.pump();

      expect(viewports, isNotEmpty);
      expect(viewports.last.zoom, closeTo(1.1, 1e-9));
    });
  });

  group('brush cursor', () {
    Future<void> pumpWithTool(WidgetTester tester, CanvasTool tool) async {
      final frameKeys = BrushCanvasFixture.createFrameKeys();
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
              brushToolState: BrushToolState.clamped(size: 40, tool: tool),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    Future<void> hoverCanvas(WidgetTester tester) async {
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      await mouse.moveTo(canvasGlobalOffset(tester, const Offset(4, 4)));
      await tester.pump();
    }

    testWidgets('the brush wears a tip outline once the pointer arrives', (
      tester,
    ) async {
      await pumpWithTool(tester, CanvasTool.brush);
      // Nothing is drawn before the pointer has been anywhere.
      expect(
        find.byKey(const ValueKey<String>('brush-cursor-overlay')),
        findsNothing,
      );

      await hoverCanvas(tester);

      final painter =
          tester
                  .widget<CustomPaint>(
                    find.byKey(const ValueKey<String>('brush-cursor-overlay')),
                  )
                  .painter
              as BrushCursorPainter;
      // A 40px brush at 100% is an outline, not the small-brush crosshair.
      expect(painter.shape, isNotNull);
      expect(painter.shape!.majorRadius, closeTo(20, 1e-9));
    });

    testWidgets('the eraser wears it too', (tester) async {
      await pumpWithTool(tester, CanvasTool.eraser);
      await hoverCanvas(tester);

      expect(
        find.byKey(const ValueKey<String>('brush-cursor-overlay')),
        findsOneWidget,
      );
    });

    testWidgets('a tiny brush falls back to the crosshair', (tester) async {
      final frameKeys = BrushCanvasFixture.createFrameKeys();
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
              brushToolState: BrushToolState.clamped(size: 1),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await hoverCanvas(tester);

      final painter =
          tester
                  .widget<CustomPaint>(
                    find.byKey(const ValueKey<String>('brush-cursor-overlay')),
                  )
                  .painter
              as BrushCursorPainter;
      expect(painter.shape, isNull);
    });

    testWidgets('the non-painting tools keep their own cursors', (
      tester,
    ) async {
      for (final tool in [
        CanvasTool.fill,
        CanvasTool.selectRect,
        CanvasTool.move,
      ]) {
        await pumpWithTool(tester, tool);
        expect(
          find.byKey(const ValueKey<String>('brush-cursor-region')),
          findsNothing,
          reason: '$tool must not wear the brush outline',
        );
      }
    });
  });
}
