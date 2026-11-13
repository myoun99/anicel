import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/brush_dab.dart';
import 'package:anicel/src/models/brush_tip_shape.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/services/canvas_selection_region.dart';
import 'package:anicel/src/services/canvas_selection_shape.dart';
import 'package:anicel/src/services/history_manager.dart';
import 'package:anicel/src/ui/brush/brush_canvas_panel.dart';
import 'package:anicel/src/ui/brush/brush_edit_cache_invalidation_sink.dart';
import 'package:anicel/src/ui/brush/brush_tool_state.dart';
import 'package:anicel/src/ui/brush/canvas_selection_commands.dart';
import 'package:anicel/src/ui/brush/transform_tool_options.dart';
import 'package:anicel/src/ui/canvas/box_chrome.dart';
import 'package:anicel/src/ui/canvas/selection_ants_painter.dart';
import 'package:anicel/src/ui/debug/input_inspector.dart'
    show InputInspectorHost;

import 'brush_canvas_fixture.dart';
import 'device_viewport.dart';

/// The Transform tool in hand on a canvas panel, as its box's own pins
/// stand it: a cel with ink under [transformToolSquare], that square
/// selected or the whole picture in its place, one canvas pixel a screen
/// pixel — so a point of the box is its own place on the layer.

const transformToolLayerKey = ValueKey<String>('canvas-selection-layer');

/// 60×60 and far enough in that the pill under it is on the view whole.
/// Under 메쉬's 3×3 grid its points stand 20 apart, the first one inside
/// ([transformToolFirstInside]) at (320,220).
final transformToolSquare = CanvasSelectionRegion.shape(
  CanvasSelectionShape([
    CanvasPoint(x: 300, y: 200),
    CanvasPoint(x: 360, y: 200),
    CanvasPoint(x: 360, y: 260),
    CanvasPoint(x: 300, y: 260),
  ]),
);
const transformToolFirstInside = 5;

/// What a test holds of the tool it pumped: the channel, and the notifiers
/// the host keeps the tool and its options on.
typedef TransformToolOnCanvas = ({
  CanvasSelectionCommands commands,
  ValueNotifier<TransformToolOptions> options,
  ValueNotifier<BrushToolState> tool,
});

BrushDab _dab(double x, double y) => BrushDab(
  center: CanvasPoint(x: x, y: y),
  color: 0xFFFF0000,
  size: 4,
  opacity: 1,
  flow: 1,
  hardness: 1,
  tipShape: BrushTipShape.square,
  pressure: 1,
  sequence: 0,
);

/// The Transform tool in hand over a cel with ink under
/// [transformToolSquare] — or with none at all — and, when [selected], that
/// square selected.
Future<TransformToolOnCanvas> pumpTransformTool(
  WidgetTester tester, {
  TransformToolOptions options = TransformToolOptions.defaults,
  bool selected = true,
  bool inked = true,
}) async {
  final frameKeys = BrushCanvasFixture.createFrameKeys();
  final coordinator = BrushCanvasFixture.createCoordinator(
    frameKeys: frameKeys,
  );
  if (inked) {
    coordinator.commitSourceStroke(
      sourceDabs: [_dab(310, 210), _dab(330, 230), _dab(350, 250)],
    );
  }
  final commands = CanvasSelectionCommands();
  final transform = ValueNotifier(options);
  final brush = ValueNotifier(
    BrushToolState.defaults.copyWith(tool: CanvasTool.move),
  );
  addTearDown(transform.dispose);
  addTearDown(brush.dispose);
  await tester.pumpWidget(
    MaterialApp(
      home: InputInspectorHost(
        child: Scaffold(
          body: BrushCanvasPanel(
            coordinator: coordinator,
            canvasSize: BrushCanvasFixture.canvasSize,
            availableFrameKeys: frameKeys,
            cacheInvalidationSink: BrushEditCacheInvalidationSink(),
            historyManager: HistoryManager(),
            brushToolState: brush,
            selectionCommands: commands,
            viewport: seedFromRender(tester, CanvasViewport()),
            transformOptions: transform,
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  if (selected) {
    // The channel tells the layer in a microtask: a frame later.
    commands.setRegion(transformToolSquare);
    await tester.pump();
    await tester.pump();
  }
  return (commands: commands, options: transform, tool: brush);
}

SelectionAntsPainter _antsOnScreen(WidgetTester tester) => tester
    .widgetList<CustomPaint>(
      find.descendant(
        of: find.byKey(transformToolLayerKey),
        matching: find.byType(CustomPaint),
      ),
    )
    .map((paint) => paint.painter)
    .whereType<SelectionAntsPainter>()
    .first;

/// The box as the layer draws it.
SelectionTransformChrome? transformChromeOnScreen(WidgetTester tester) =>
    _antsOnScreen(tester).transformChrome;

/// Which of the box's handles the layer draws as in hand, by their place
/// among [transformChromeOnScreen]'s.
List<int> handlesInHandOnScreen(WidgetTester tester) =>
    _antsOnScreen(tester).handlesInHand;

/// A press on the layer at [from], carried to [to] and let go.
Future<void> dragOnTransformLayer(
  WidgetTester tester,
  Offset from,
  Offset to,
) async {
  final gesture = await pressOnTransformLayer(tester, from);
  final origin = tester.getTopLeft(find.byKey(transformToolLayerKey));
  await gesture.moveTo(origin + to);
  await tester.pump();
  await gesture.up();
  await tester.pump();
}

/// A press on the layer at [at], still down — the gesture is the caller's
/// to move and to let go.
Future<TestGesture> pressOnTransformLayer(
  WidgetTester tester,
  Offset at,
) async {
  final origin = tester.getTopLeft(find.byKey(transformToolLayerKey));
  final gesture = await tester.startGesture(origin + at);
  await tester.pump();
  return gesture;
}
