import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/ui/canvas/brush_canvas_smoke_screen.dart';
import 'package:anicel/src/ui/canvas/brush_edit_canvas_input_settings.dart';
import 'package:anicel/src/ui/canvas/interactive_brush_canvas_smoke_host.dart';
import 'package:anicel/src/ui/canvas/interactive_brush_edit_canvas_view.dart';
import 'package:anicel/src/ui/storyboard_panel.dart';
import 'package:anicel/src/ui/timeline/timeline_panel.dart';

import 'brush_canvas_test_helpers.dart';

void main() {
  group('BrushCanvasSmokeScreen', () {
    testWidgets('builds with stable keys and default configuration', (
      tester,
    ) async {
      await tester.pumpWidget(_app(const BrushCanvasSmokeScreen()));

      expect(find.byType(BrushCanvasSmokeScreen), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('brush-canvas-smoke-screen')),
        findsOneWidget,
      );
      expect(find.byType(InteractiveBrushCanvasSmokeHost), findsOneWidget);
      expect(
        find.byKey(
          const ValueKey<String>('brush-canvas-smoke-screen-controls'),
        ),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('brush-canvas-smoke-screen-host')),
        findsOneWidget,
      );

      final host = tester.widget<InteractiveBrushCanvasSmokeHost>(
        find.byType(InteractiveBrushCanvasSmokeHost),
      );
      expect(host.layerId, const LayerId('smoke-layer'));
      expect(host.frameId, const FrameId('smoke-frame'));
      expect(host.inputSettings, BrushEditCanvasInputSettings());
      expect(host.showTransparentBackground, isTrue);
      expect(
        host.initialSessionState.canvasState.currentSurface.canvasSize,
        CanvasSize(width: 64, height: 64),
      );
      expect(host.initialSessionState.canvasState.currentSurface.tileSize, 16);
    });

    testWidgets('passes custom canvas, tile, input, and background settings', (
      tester,
    ) async {
      const layerId = LayerId('custom-layer');
      const frameId = FrameId('custom-frame');
      final inputSettings = BrushEditCanvasInputSettings(color: 0xFFFF00FF);
      final canvasSize = CanvasSize(width: 8, height: 8);

      await tester.pumpWidget(
        _app(
          BrushCanvasSmokeScreen(
            layerId: layerId,
            frameId: frameId,
            inputSettings: inputSettings,
            canvasSize: canvasSize,
            tileSize: 2,
            showTransparentBackground: false,
          ),
        ),
      );

      final host = tester.widget<InteractiveBrushCanvasSmokeHost>(
        find.byType(InteractiveBrushCanvasSmokeHost),
      );
      expect(host.layerId, layerId);
      expect(host.frameId, frameId);
      expect(host.inputSettings, inputSettings);
      expect(host.showTransparentBackground, isFalse);
      expect(
        host.initialSessionState.canvasState.currentSurface.canvasSize,
        canvasSize,
      );
      expect(host.initialSessionState.canvasState.currentSurface.tileSize, 2);
    });

    testWidgets('debug status is shown by default and can be hidden', (
      tester,
    ) async {
      await tester.pumpWidget(_app(const BrushCanvasSmokeScreen()));

      expect(
        find.byKey(
          const ValueKey<String>('brush-canvas-smoke-screen-debug-status'),
        ),
        findsOneWidget,
      );
      expect(find.textContaining('operation: none'), findsOneWidget);
      expect(find.textContaining('cacheInvalidations: 0'), findsOneWidget);
      expect(find.textContaining('color: 0xFF000000'), findsOneWidget);

      await tester.pumpWidget(
        _app(const BrushCanvasSmokeScreen(showDebugStatus: false)),
      );

      expect(
        find.byKey(
          const ValueKey<String>('brush-canvas-smoke-screen-debug-status'),
        ),
        findsNothing,
      );
    });

    testWidgets('pointer down/up updates debug status and visible state', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(
          BrushCanvasSmokeScreen(
            canvasSize: CanvasSize(width: 8, height: 8),
            tileSize: 2,
          ),
        ),
      );

      await tapCanvas(tester, const Offset(1.5, 1.5));

      expect(find.textContaining('operation: commit'), findsOneWidget);
      expect(find.textContaining('cacheInvalidations: 2'), findsOneWidget);

      // The committed stroke is materialized into the session surface.
      expect(_alphaAt(tester, 1, 1), 255);
    });

    testWidgets('color presets update host settings and future strokes', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(
          BrushCanvasSmokeScreen(
            canvasSize: CanvasSize(width: 8, height: 8),
            tileSize: 2,
          ),
        ),
      );

      expect(_host(tester).inputSettings.color, 0xFF000000);

      await _tapKey(
        tester,
        const ValueKey<String>('brush-canvas-smoke-screen-color-red'),
      );
      expect(_host(tester).inputSettings.color, 0xFFFF0000);
      expect(find.textContaining('color: 0xFFFF0000'), findsOneWidget);

      await _tapKey(
        tester,
        const ValueKey<String>('brush-canvas-smoke-screen-color-blue'),
      );
      expect(_host(tester).inputSettings.color, 0xFF0000FF);
      expect(find.textContaining('color: 0xFF0000FF'), findsOneWidget);

      await tapCanvas(tester, const Offset(1.5, 1.5));
      expect(_surfaceRgbaAt(tester, 1, 1), [0, 0, 255, 255]);

      await _tapKey(
        tester,
        const ValueKey<String>('brush-canvas-smoke-screen-reset'),
      );
      await _tapKey(
        tester,
        const ValueKey<String>('brush-canvas-smoke-screen-color-black'),
      );
      expect(_host(tester).inputSettings.color, 0xFF000000);
      await tapCanvas(tester, const Offset(1.5, 1.5));

      expect(_surfaceRgbaAt(tester, 1, 1), [0, 0, 0, 255]);
    });

    testWidgets(
      'changing frame target resets session before future brush operations',
      (tester) async {
        final canvasSize = CanvasSize(width: 8, height: 8);

        await tester.pumpWidget(
          _app(
            BrushCanvasSmokeScreen(
              layerId: const LayerId('layer-a'),
              frameId: const FrameId('frame-a'),
              canvasSize: canvasSize,
              tileSize: 2,
            ),
          ),
        );

        await tapCanvas(tester, const Offset(1.5, 1.5));
        expect(_alphaAt(tester, 1, 1), 255);

        await tester.pumpWidget(
          _app(
            BrushCanvasSmokeScreen(
              layerId: const LayerId('layer-b'),
              frameId: const FrameId('frame-b'),
              canvasSize: canvasSize,
              tileSize: 2,
            ),
          ),
        );

        expect(_host(tester).layerId, const LayerId('layer-b'));
        expect(_host(tester).frameId, const FrameId('frame-b'));
        expect(find.textContaining('operation: reset'), findsOneWidget);
        expect(_surfaceIsBlank(tester), isTrue);

        await tapCanvas(tester, const Offset(3.5, 3.5));
        expect(_alphaAt(tester, 3, 3), 255);

        await _tapKey(
          tester,
          const ValueKey<String>('brush-canvas-smoke-screen-undo'),
        );
        expect(find.textContaining('operation: undo'), findsOneWidget);
        expect(_surfaceIsBlank(tester), isTrue);
      },
    );

    testWidgets('undo, redo, and reset update visible state and debug status', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(
          BrushCanvasSmokeScreen(
            canvasSize: CanvasSize(width: 8, height: 8),
            tileSize: 2,
          ),
        ),
      );

      await tapCanvas(tester, const Offset(1.5, 1.5));
      expect(_alphaAt(tester, 1, 1), 255);

      await _tapKey(
        tester,
        const ValueKey<String>('brush-canvas-smoke-screen-undo'),
      );
      expect(find.textContaining('operation: undo'), findsOneWidget);
      expect(_surfaceIsBlank(tester), isTrue);

      await _tapKey(
        tester,
        const ValueKey<String>('brush-canvas-smoke-screen-redo'),
      );
      expect(find.textContaining('operation: redo'), findsOneWidget);
      expect(_alphaAt(tester, 1, 1), 255);

      await _tapKey(
        tester,
        const ValueKey<String>('brush-canvas-smoke-screen-reset'),
      );
      expect(find.textContaining('operation: reset'), findsOneWidget);
      expect(find.textContaining('cacheInvalidations: 0'), findsOneWidget);
      expect(_surfaceIsBlank(tester), isTrue);
    });

    testWidgets('two strokes followed by undo removes only latest stroke', (
      tester,
    ) async {
      await tester.pumpWidget(_app(_smallScreen()));

      await tapCanvas(tester, const Offset(1.5, 1.5));
      await tapCanvas(tester, const Offset(3.5, 2.5));
      expect(_alphaAt(tester, 1, 1), 255);
      expect(_alphaAt(tester, 3, 2), 255);

      await _tapKey(
        tester,
        const ValueKey<String>('brush-canvas-smoke-screen-undo'),
      );

      expect(find.textContaining('operation: undo'), findsOneWidget);
      expect(_alphaAt(tester, 1, 1), 255);
      expect(_alphaAt(tester, 3, 2), 0);
    });

    testWidgets('redo restores the latest undone stroke', (tester) async {
      await tester.pumpWidget(_app(_smallScreen()));

      await tapCanvas(tester, const Offset(1.5, 1.5));
      await tapCanvas(tester, const Offset(3.5, 2.5));
      await _tapKey(
        tester,
        const ValueKey<String>('brush-canvas-smoke-screen-undo'),
      );
      await _tapKey(
        tester,
        const ValueKey<String>('brush-canvas-smoke-screen-redo'),
      );

      expect(find.textContaining('operation: redo'), findsOneWidget);
      expect(_alphaAt(tester, 1, 1), 255);
      expect(_alphaAt(tester, 3, 2), 255);
    });

    testWidgets('reset clears canvas and prevents stale redo restore', (
      tester,
    ) async {
      await tester.pumpWidget(_app(_smallScreen()));

      await tapCanvas(tester, const Offset(1.5, 1.5));
      await _tapKey(
        tester,
        const ValueKey<String>('brush-canvas-smoke-screen-undo'),
      );
      expect(_surfaceIsBlank(tester), isTrue);
      await _tapKey(
        tester,
        const ValueKey<String>('brush-canvas-smoke-screen-reset'),
      );
      await _tapKey(
        tester,
        const ValueKey<String>('brush-canvas-smoke-screen-redo'),
      );

      expect(_surfaceIsBlank(tester), isTrue);
      expect(find.textContaining('operation: redo'), findsOneWidget);
    });

    testWidgets('blank undo and redo do not crash or change visible state', (
      tester,
    ) async {
      await tester.pumpWidget(_app(_smallScreen()));

      await _tapKey(
        tester,
        const ValueKey<String>('brush-canvas-smoke-screen-undo'),
      );
      expect(_surfaceIsBlank(tester), isTrue);
      await _tapKey(
        tester,
        const ValueKey<String>('brush-canvas-smoke-screen-redo'),
      );

      expect(_surfaceIsBlank(tester), isTrue);
      expect(find.textContaining('operation: redo'), findsOneWidget);
    });

    testWidgets(
      'color change affects future stroke without erasing existing strokes',
      (tester) async {
        await tester.pumpWidget(_app(_smallScreen()));

        await tapCanvas(tester, const Offset(1.5, 1.5));
        final blackState = _view(tester).sessionState;
        await _tapKey(
          tester,
          const ValueKey<String>('brush-canvas-smoke-screen-color-blue'),
        );
        await tapCanvas(tester, const Offset(3.5, 2.5));
        final blueState = _view(tester).sessionState;

        expect(_host(tester).inputSettings.color, 0xFF0000FF);
        expect(find.textContaining('color: 0xFF0000FF'), findsOneWidget);
        // Each commit materializes into a new session state instance and
        // the earlier stroke's pixels remain untouched.
        expect(identical(blueState, blackState), isFalse);
        expect(_surfaceRgbaAt(tester, 1, 1), [0, 0, 0, 255]);
        expect(_surfaceRgbaAt(tester, 3, 2), [0, 0, 255, 255]);
      },
    );

    testWidgets('debug status is deterministic across operations and color', (
      tester,
    ) async {
      await tester.pumpWidget(_app(_smallScreen()));

      expect(
        _debugStatus(tester),
        'operation: none, cacheInvalidations: 0, color: 0xFF000000',
      );
      await tapCanvas(tester, const Offset(1.5, 1.5));
      // R19 P3b: the commit rides the history command WITH the sink, so
      // it counts too; undo/redo are surface-snapshot restores (one
      // whole-frame invalidation each).
      expect(
        _debugStatus(tester),
        'operation: commit, cacheInvalidations: 2, color: 0xFF000000',
      );
      await _tapKey(
        tester,
        const ValueKey<String>('brush-canvas-smoke-screen-undo'),
      );
      expect(
        _debugStatus(tester),
        'operation: undo, cacheInvalidations: 3, color: 0xFF000000',
      );
      await _tapKey(
        tester,
        const ValueKey<String>('brush-canvas-smoke-screen-redo'),
      );
      expect(
        _debugStatus(tester),
        'operation: redo, cacheInvalidations: 4, color: 0xFF000000',
      );
      await _tapKey(
        tester,
        const ValueKey<String>('brush-canvas-smoke-screen-color-red'),
      );
      expect(
        _debugStatus(tester),
        'operation: redo, cacheInvalidations: 4, color: 0xFFFF0000',
      );
      await _tapKey(
        tester,
        const ValueKey<String>('brush-canvas-smoke-screen-reset'),
      );
      expect(
        _debugStatus(tester),
        'operation: reset, cacheInvalidations: 0, color: 0xFFFF0000',
      );
    });

    testWidgets('does not add GestureDetector inside interactive canvas host', (
      tester,
    ) async {
      await tester.pumpWidget(_app(const BrushCanvasSmokeScreen()));

      final hostFinder = find.byType(InteractiveBrushCanvasSmokeHost);

      expect(
        find.descendant(of: hostFinder, matching: find.byType(GestureDetector)),
        findsNothing,
      );
    });

    test(
      'does not include forbidden state management or direct commit calls',
      () {
        final source = File(
          'lib/src/ui/canvas/brush_canvas_smoke_screen.dart',
        ).readAsStringSync();

        expect(source, isNot(contains('Provider')));
        expect(source, isNot(contains('Riverpod')));
        expect(source, isNot(contains('Bloc')));
        expect(source, isNot(contains('ChangeNotifier')));
        expect(source, isNot(contains('InheritedWidget')));
        expect(source, isNot(contains('commitBrushDabSequence')));
      },
    );

    testWidgets('does not affect StoryboardPanel or TimelinePanel', (
      tester,
    ) async {
      await tester.pumpWidget(_app(const BrushCanvasSmokeScreen()));

      expect(find.byType(StoryboardPanel), findsNothing);
      expect(find.byType(TimelinePanel), findsNothing);
    });
  });
}

Widget _app(Widget child) {
  return MaterialApp(
    home: Scaffold(
      body: Align(alignment: Alignment.topLeft, child: child),
    ),
  );
}

InteractiveBrushCanvasSmokeHost _host(WidgetTester tester) {
  return tester.widget<InteractiveBrushCanvasSmokeHost>(
    find.byType(InteractiveBrushCanvasSmokeHost),
  );
}

List<int> _surfaceRgbaAt(WidgetTester tester, int x, int y) {
  final surface = _view(tester).sessionState.canvasState.currentSurface;
  final tileSize = surface.tileSize;
  final tile = surface.tileAt(TileCoord(x: x ~/ tileSize, y: y ~/ tileSize));
  if (tile == null) {
    return const [0, 0, 0, 0];
  }
  final pixels = tile.pixels;
  final offset = tile.byteOffsetForPixel(x: x % tileSize, y: y % tileSize);
  return [
    pixels[offset],
    pixels[offset + 1],
    pixels[offset + 2],
    pixels[offset + 3],
  ];
}

int _alphaAt(WidgetTester tester, int x, int y) =>
    _surfaceRgbaAt(tester, x, y)[3];

bool _surfaceIsBlank(WidgetTester tester) {
  final surface = _view(tester).sessionState.canvasState.currentSurface;
  return surface.tiles.values.every((tile) => tile.isFullyTransparent);
}

InteractiveBrushEditCanvasView _view(WidgetTester tester) {
  return tester.widget<InteractiveBrushEditCanvasView>(
    find.byType(InteractiveBrushEditCanvasView),
  );
}

Future<void> _tapKey(WidgetTester tester, Key key) async {
  await tester.tap(find.byKey(key));
  await tester.pump();
}

BrushCanvasSmokeScreen _smallScreen() {
  return BrushCanvasSmokeScreen(
    canvasSize: CanvasSize(width: 8, height: 8),
    tileSize: 2,
  );
}

String _debugStatus(WidgetTester tester) {
  return tester
      .widget<Text>(
        find.byKey(
          const ValueKey<String>('brush-canvas-smoke-screen-debug-status'),
        ),
      )
      .data!;
}
