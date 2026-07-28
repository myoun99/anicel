import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/brush_bitmap_materialization_history_state.dart';
import 'package:anicel/src/models/brush_edit_session_state.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/canvas_surface_state.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/ui/canvas/brush_edit_canvas_input_settings.dart';
import 'package:anicel/src/ui/canvas/interactive_brush_canvas_smoke_host.dart';
import 'package:anicel/src/ui/canvas/interactive_brush_edit_canvas_view.dart';
import 'package:anicel/src/ui/storyboard_panel.dart';
import 'package:anicel/src/ui/timeline/timeline_panel.dart';

import 'brush_canvas_test_helpers.dart';

void main() {
  group('InteractiveBrushCanvasSmokeHost', () {
    const layerId = LayerId('layer-a');
    const frameId = FrameId('frame-a');
    final inputSettings = BrushEditCanvasInputSettings(color: 0xFFFF0000);

    testWidgets('builds and passes configuration to interactive canvas', (
      tester,
    ) async {
      final sessionState = _sessionState();
      final sink = FakeCacheInvalidationSink();

      await tester.pumpWidget(
        _app(
          InteractiveBrushCanvasSmokeHost(
            initialSessionState: sessionState,
            layerId: layerId,
            frameId: frameId,
            inputSettings: inputSettings,
            cacheInvalidationSink: sink,
            showTransparentBackground: false,
          ),
        ),
      );

      final hostFinder = find.byType(InteractiveBrushCanvasSmokeHost);
      expect(hostFinder, findsOneWidget);
      expect(
        find.descendant(
          of: hostFinder,
          matching: find.byType(InteractiveBrushEditCanvasView),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: hostFinder,
          matching: find.byKey(
            const ValueKey<String>('interactive-brush-canvas-smoke-host-view'),
          ),
        ),
        findsOneWidget,
      );

      final view = tester.widget<InteractiveBrushEditCanvasView>(
        find.byType(InteractiveBrushEditCanvasView),
      );
      expect(identical(view.sessionState, sessionState), isTrue);
      expect(view.layerId, layerId);
      expect(view.frameId, frameId);
      expect(view.inputSettings, inputSettings);
      expect(sink.totalCalls, 0);
      expect(view.showTransparentBackground, isFalse);
    });

    testWidgets('tap commits source stroke without bitmap materialization', (
      tester,
    ) async {
      final sessionState = _sessionState();
      final originalCanvasState = sessionState.canvasState;
      final originalHistoryState = sessionState.materializationHistoryState;
      final originalSessionSnapshot = sessionState.toString();
      final originalCanvasSnapshot = originalCanvasState.toString();
      final originalHistorySnapshot = originalHistoryState.toString();
      final sink = FakeCacheInvalidationSink();

      await tester.pumpWidget(
        _app(
          InteractiveBrushCanvasSmokeHost(
            initialSessionState: sessionState,
            layerId: layerId,
            frameId: frameId,
            inputSettings: inputSettings,
            cacheInvalidationSink: sink,
          ),
        ),
      );

      await tapCanvas(tester, const Offset(1.5, 1.5));

      final view = tester.widget<InteractiveBrushEditCanvasView>(
        find.byType(InteractiveBrushEditCanvasView),
      );
      expect(identical(view.sessionState, sessionState), isTrue);
      expect(view.sessionState.canvasState.currentSurface.tiles, isEmpty);
      expect(
        view.sessionState.materializationHistoryState.undoEntries,
        isEmpty,
      );
      expect(sink.totalCalls, 0);

      expect(identical(sessionState.canvasState, originalCanvasState), isTrue);
      expect(
        identical(
          sessionState.materializationHistoryState,
          originalHistoryState,
        ),
        isTrue,
      );
      expect(sessionState.toString(), originalSessionSnapshot);
      expect(originalCanvasState.toString(), originalCanvasSnapshot);
      expect(originalHistoryState.toString(), originalHistorySnapshot);
    });

    testWidgets(
      'changing initialSessionState and sessionResetToken updates child view',
      (tester) async {
        final firstState = _sessionState();
        final secondState = _sessionState(width: 10, height: 10);
        final sink = FakeCacheInvalidationSink();

        await tester.pumpWidget(
          _app(
            InteractiveBrushCanvasSmokeHost(
              initialSessionState: firstState,
              layerId: layerId,
              frameId: frameId,
              inputSettings: inputSettings,
              cacheInvalidationSink: sink,
              sessionResetToken: 0,
            ),
          ),
        );
        expect(identical(_view(tester).sessionState, firstState), isTrue);

        await tester.pumpWidget(
          _app(
            InteractiveBrushCanvasSmokeHost(
              initialSessionState: secondState,
              layerId: layerId,
              frameId: frameId,
              inputSettings: inputSettings,
              cacheInvalidationSink: sink,
              sessionResetToken: 1,
            ),
          ),
        );

        expect(identical(_view(tester).sessionState, secondState), isTrue);
        expect(
          _view(tester).sessionState.canvasState.currentSurface.canvasSize,
          CanvasSize(width: 10, height: 10),
        );
      },
    );

    testWidgets(
      'same initialSessionState identity does not reset local stroke',
      (tester) async {
        final sessionState = _sessionState();
        final sink = FakeCacheInvalidationSink();

        await tester.pumpWidget(
          _app(
            InteractiveBrushCanvasSmokeHost(
              initialSessionState: sessionState,
              layerId: layerId,
              frameId: frameId,
              inputSettings: inputSettings,
              cacheInvalidationSink: sink,
            ),
          ),
        );

        await tapCanvas(tester, const Offset(1.5, 1.5));
        final strokedState = _view(tester).sessionState;
        expect(strokedState.canvasState.currentSurface.tiles, isEmpty);

        await tester.pumpWidget(
          _app(
            InteractiveBrushCanvasSmokeHost(
              initialSessionState: sessionState,
              layerId: layerId,
              frameId: frameId,
              inputSettings: inputSettings,
              cacheInvalidationSink: sink,
            ),
          ),
        );

        expect(identical(_view(tester).sessionState, strokedState), isTrue);
        expect(
          _view(tester).sessionState.canvasState.currentSurface.tiles,
          isEmpty,
        );
        expect(sessionState.canvasState.currentSurface.tiles, isEmpty);
      },
    );

    testWidgets(
      'changing initialSessionState without token change preserves local stroke',
      (tester) async {
        final firstState = _sessionState();
        final secondState = _sessionState(width: 10, height: 10);
        final sink = FakeCacheInvalidationSink();

        await tester.pumpWidget(
          _app(
            InteractiveBrushCanvasSmokeHost(
              initialSessionState: firstState,
              layerId: layerId,
              frameId: frameId,
              inputSettings: inputSettings,
              cacheInvalidationSink: sink,
              sessionResetToken: 0,
            ),
          ),
        );

        await tapCanvas(tester, const Offset(1.5, 1.5));
        final strokedState = _view(tester).sessionState;
        expect(strokedState.canvasState.currentSurface.tiles, isEmpty);

        await tester.pumpWidget(
          _app(
            InteractiveBrushCanvasSmokeHost(
              initialSessionState: secondState,
              layerId: layerId,
              frameId: frameId,
              inputSettings: inputSettings,
              cacheInvalidationSink: sink,
              sessionResetToken: 0,
            ),
          ),
        );

        expect(identical(_view(tester).sessionState, strokedState), isTrue);
        expect(
          _view(tester).sessionState.canvasState.currentSurface.tiles,
          isEmpty,
        );
        expect(secondState.canvasState.currentSurface.tiles, isEmpty);
      },
    );

    testWidgets(
      'blank factory preserves local stroked state across parent rebuild',
      (tester) async {
        final sink = FakeCacheInvalidationSink();

        await tester.pumpWidget(
          _app(
            InteractiveBrushCanvasSmokeHost.blank(
              layerId: layerId,
              frameId: frameId,
              inputSettings: inputSettings,
              cacheInvalidationSink: sink,
              canvasSize: CanvasSize(width: 8, height: 8),
              tileSize: 2,
            ),
          ),
        );

        await tapCanvas(tester, const Offset(1.5, 1.5));
        final strokedState = _view(tester).sessionState;
        expect(strokedState.canvasState.currentSurface.tiles, isEmpty);

        await tester.pumpWidget(
          _app(
            InteractiveBrushCanvasSmokeHost.blank(
              layerId: layerId,
              frameId: frameId,
              inputSettings: inputSettings,
              cacheInvalidationSink: sink,
              canvasSize: CanvasSize(width: 8, height: 8),
              tileSize: 2,
            ),
          ),
        );

        expect(identical(_view(tester).sessionState, strokedState), isTrue);
        expect(
          _view(tester).sessionState.canvasState.currentSurface.tiles,
          isEmpty,
        );
      },
    );

    testWidgets(
      'repeated strokes do not mutate bitmap materialization session state',
      (tester) async {
        final sink = FakeCacheInvalidationSink();

        await tester.pumpWidget(
          _app(
            InteractiveBrushCanvasSmokeHost(
              initialSessionState: _sessionState(),
              layerId: layerId,
              frameId: frameId,
              inputSettings: inputSettings,
              cacheInvalidationSink: sink,
            ),
          ),
        );

        await tapCanvas(tester, const Offset(1.5, 1.5));
        final firstState = _view(tester).sessionState;
        await tapCanvas(tester, const Offset(2.5, 1.5));
        final secondState = _view(tester).sessionState;

        expect(identical(secondState, firstState), isTrue);
        expect(secondState.canvasState.currentSurface.tiles, isEmpty);
        expect(secondState.materializationHistoryState.undoEntries, isEmpty);
        expect(sink.totalCalls, 0);
      },
    );

    testWidgets(
      'sessionResetToken change replaces local stroked session state',
      (tester) async {
        final firstState = _sessionState();
        final secondState = _sessionState(width: 10, height: 10);
        final sink = FakeCacheInvalidationSink();

        await tester.pumpWidget(
          _app(
            InteractiveBrushCanvasSmokeHost(
              initialSessionState: firstState,
              layerId: layerId,
              frameId: frameId,
              inputSettings: inputSettings,
              cacheInvalidationSink: sink,
              sessionResetToken: 0,
            ),
          ),
        );
        await tapCanvas(tester, const Offset(1.5, 1.5));
        expect(
          _view(tester).sessionState.canvasState.currentSurface.tiles,
          isEmpty,
        );

        await tester.pumpWidget(
          _app(
            InteractiveBrushCanvasSmokeHost(
              initialSessionState: secondState,
              layerId: layerId,
              frameId: frameId,
              inputSettings: inputSettings,
              cacheInvalidationSink: sink,
              sessionResetToken: 1,
            ),
          ),
        );

        expect(identical(_view(tester).sessionState, secondState), isTrue);
        expect(
          _view(tester).sessionState.canvasState.currentSurface.tiles,
          isEmpty,
        );
        expect(
          _view(tester).sessionState.canvasState.currentSurface.canvasSize,
          CanvasSize(width: 10, height: 10),
        );
      },
    );

    testWidgets('does not add GestureDetector outside interactive canvas', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(
          InteractiveBrushCanvasSmokeHost(
            initialSessionState: _sessionState(),
            layerId: layerId,
            frameId: frameId,
            inputSettings: inputSettings,
            cacheInvalidationSink: FakeCacheInvalidationSink(),
          ),
        ),
      );

      final hostFinder = find.byType(InteractiveBrushCanvasSmokeHost);
      expect(
        find.descendant(of: hostFinder, matching: find.byType(GestureDetector)),
        findsNothing,
      );
    });

    test('does not include forbidden state management or app wiring', () {
      final source = File(
        'lib/src/ui/canvas/interactive_brush_canvas_smoke_host.dart',
      ).readAsStringSync();

      expect(source, isNot(contains('Provider')));
      expect(source, isNot(contains('Riverpod')));
      expect(source, isNot(contains('Bloc')));
      expect(source, isNot(contains('ChangeNotifier')));
      expect(
        source,
        isNot(
          contains(
            'commitBrushDabSequenceToBrushEditSessionWithCacheInvalidation',
          ),
        ),
      );
      expect(
        source,
        isNot(contains('brushSurfaceEditForBrushDabSequenceOnBitmapSurface')),
      );
      expect(
        source,
        isNot(contains('applyBrushSurfaceEditToCanvasSurfaceState')),
      );
      expect(source, isNot(contains('undoLatestBrushBitmapMaterialization')));
      expect(source, isNot(contains('redoLatestBrushBitmapMaterialization')));
    });

    testWidgets('does not affect StoryboardPanel or TimelinePanel', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(
          InteractiveBrushCanvasSmokeHost(
            initialSessionState: _sessionState(),
            layerId: layerId,
            frameId: frameId,
            inputSettings: inputSettings,
            cacheInvalidationSink: FakeCacheInvalidationSink(),
          ),
        ),
      );

      expect(find.byType(StoryboardPanel), findsNothing);
      expect(find.byType(TimelinePanel), findsNothing);
    });
  });
}

BrushEditSessionState _sessionState({int width = 8, int height = 8}) {
  return BrushEditSessionState(
    canvasState: CanvasSurfaceState(
      currentSurface: BitmapSurface(
        canvasSize: CanvasSize(width: width, height: height),
        tileSize: 2,
      ),
    ),
    materializationHistoryState: BrushBitmapMaterializationHistoryState(),
  );
}

Widget _app(Widget child) {
  return MaterialApp(
    home: Scaffold(
      body: Align(alignment: Alignment.topLeft, child: child),
    ),
  );
}

InteractiveBrushEditCanvasView _view(WidgetTester tester) {
  return tester.widget<InteractiveBrushEditCanvasView>(
    find.byType(InteractiveBrushEditCanvasView),
  );
}
