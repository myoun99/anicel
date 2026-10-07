import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_shape_kind.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/services/history_manager.dart';
import 'package:anicel/src/ui/brush/brush_canvas_panel.dart';
import 'package:anicel/src/ui/brush/brush_edit_cache_invalidation_sink.dart';
import 'package:anicel/src/ui/brush/brush_tool_state.dart';
import 'package:anicel/src/ui/brush/canvas_selection_commands.dart';
import 'package:anicel/src/ui/canvas/canvas_selection_layer.dart';
import 'package:anicel/src/ui/canvas/selection_drag.dart';

import '../../helpers/brush_canvas_fixture.dart';
import '../../helpers/device_viewport.dart';

/// I-69 × I-10: 「WHOEVER HEARS THE PRESS ASKS FOR THE CEL, AND ONLY ONE
/// DOES」. The shape tool's drag is the selection layer's, and the layer lies
/// over the drawing view — so on a frame with no cel it is the layer that
/// asks, at the PRESS, as a pen's press and the text tool's do.
///
/// 🚨At the press and not at the release: the cel has to be there when the
/// pen lifts, so that the shape lands inside that event and takes the block
/// made for it into its own step of undo. The host settles a block nobody
/// has claimed when the pointer goes up.
void main() {
  const layerKey = ValueKey<String>('layer');

  Future<({List<DrawnShapePath> drawn, List<String> log})> pumpLayer(
    WidgetTester tester, {
    required bool? celAnswer,
    CanvasSelectionTool tool = CanvasSelectionTool.drawShape,
    Object frameToken = 'frame',
    List<DrawnShapePath>? drawnSoFar,
    List<String>? logSoFar,
  }) async {
    final drawn = drawnSoFar ?? <DrawnShapePath>[];
    final log = logSoFar ?? <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 400,
              height: 300,
              child: CanvasSelectionLayer(
                key: layerKey,
                tool: tool,
                shapeKind: CanvasShapeKind.rect,
                viewport: CanvasViewport(),
                canvasSize: const CanvasSize(width: 400, height: 300),
                frameToken: frameToken,
                onShapeCommitted: (before, after) => log.add('selected'),
                onDrawShape: (path) {
                  drawn.add(path);
                  log.add('drawn');
                },
                onPressNeedsCel: celAnswer == null
                    ? null
                    : () {
                        log.add('asked');
                        return celAnswer;
                      },
              ),
            ),
          ),
        ),
      ),
    );
    return (drawn: drawn, log: log);
  }

  Future<TestGesture> press(WidgetTester tester, Offset at) async {
    final gesture = await tester.startGesture(
      tester.getTopLeft(find.byKey(layerKey)) + at,
      kind: PointerDeviceKind.mouse,
      buttons: kPrimaryButton,
    );
    await tester.pump();
    return gesture;
  }

  Future<void> dragOut(WidgetTester tester, TestGesture gesture) async {
    await gesture.moveBy(const Offset(120, 80));
    await tester.pump();
    await gesture.up();
    await tester.pump();
  }

  testWidgets('the press asks, before anything is traced, and the shape is '
      'handed over at the release', (tester) async {
    final host = await pumpLayer(tester, celAnswer: true);

    final gesture = await press(tester, const Offset(40, 40));
    expect(host.log, ['asked'], reason: 'at the press');

    await dragOut(tester, gesture);
    expect(host.log, ['asked', 'drawn'], reason: 'asked once');
    expect(host.drawn.single.closed, isTrue);
  });

  // 🔬The Windows app, 2026-10-08: the cel the press asked for arrives as
  // another frame under the layer, a frame later — and a frame change
  // drops a drag. The block was made and no shape was drawn.
  testWidgets('🚨the cel that arrives under a shape being traced does not '
      'take it out of the hand', (tester) async {
    final host = await pumpLayer(
      tester,
      celAnswer: true,
      frameToken: 'no cel here',
    );
    final gesture = await press(tester, const Offset(40, 40));
    await gesture.moveBy(const Offset(40, 30));
    await tester.pump();

    // The frame that brings the cel: another frame under the layer, and
    // nothing left to ask.
    await pumpLayer(
      tester,
      celAnswer: null,
      frameToken: 'the cel',
      drawnSoFar: host.drawn,
      logSoFar: host.log,
    );
    await dragOut(tester, gesture);

    expect(host.log, ['asked', 'drawn']);
    expect(
      host.drawn.single.points.first.x,
      closeTo(40, 0.01),
      reason: 'from where the pen went down',
    );
  });

  testWidgets('⛔a selection being dragged out is still dropped when the '
      'frame under it changes', (tester) async {
    // Fixture: left alone, the same drag selects.
    final left = await pumpLayer(
      tester,
      celAnswer: null,
      tool: CanvasSelectionTool.select,
    );
    await dragOut(tester, await press(tester, const Offset(40, 40)));
    expect(left.log, ['selected']);

    await tester.pumpWidget(const SizedBox());
    final host = await pumpLayer(
      tester,
      celAnswer: null,
      tool: CanvasSelectionTool.select,
      frameToken: 'one frame',
    );
    final gesture = await press(tester, const Offset(40, 40));
    await gesture.moveBy(const Offset(40, 30));
    await tester.pump();
    await pumpLayer(
      tester,
      celAnswer: null,
      tool: CanvasSelectionTool.select,
      frameToken: 'another',
      drawnSoFar: host.drawn,
      logSoFar: host.log,
    );
    await dragOut(tester, gesture);

    expect(host.log, isEmpty);
  });

  testWidgets('⛔a press refused a cel traces nothing', (tester) async {
    final host = await pumpLayer(tester, celAnswer: false);

    final gesture = await press(tester, const Offset(40, 40));
    await dragOut(tester, gesture);

    expect(host.log, ['asked'], reason: 'asked once, and nothing is drawn');
  });

  testWidgets('where a cel is there nobody is asked', (tester) async {
    final host = await pumpLayer(tester, celAnswer: null);

    final gesture = await press(tester, const Offset(40, 40));
    await dragOut(tester, gesture);

    expect(host.log, ['drawn']);
  });

  // The panel's half: WHO is handed the question. On a frame with no cel
  // the layer asks in the standing-down view's stead; where a cel is there
  // nobody under the panel asks (the host's own listener speaks for a row
  // that takes no marks).
  group('through the panel', () {
    Future<List<String>> pumpPanel(
      WidgetTester tester, {
      required bool celEditable,
    }) async {
      final asked = <String>[];
      final frameKeys = BrushCanvasFixture.createFrameKeys();
      final brush = ValueNotifier(
        BrushToolState.defaults.copyWith(tool: CanvasTool.shape),
      );
      addTearDown(brush.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BrushCanvasPanel(
              coordinator: BrushCanvasFixture.createCoordinator(
                frameKeys: frameKeys,
                canvasSize: BrushCanvasFixture.canvasSize,
              ),
              canvasSize: BrushCanvasFixture.canvasSize,
              availableFrameKeys: frameKeys,
              cacheInvalidationSink: BrushEditCacheInvalidationSink(),
              historyManager: HistoryManager(),
              brushToolState: brush,
              selectionCommands: CanvasSelectionCommands(),
              viewport: seedFromRender(tester, CanvasViewport()),
              celEditable: celEditable,
              onPressNeedsCel: () {
                asked.add('asked');
                return false;
              },
            ),
          ),
        ),
      );
      await tester.pump();
      return asked;
    }

    Future<TestGesture> pressOnThePanel(WidgetTester tester) async {
      final origin = tester.getTopLeft(
        find.byKey(const ValueKey<String>('canvas-selection-layer')),
      );
      final gesture = await tester.startGesture(
        origin + const Offset(100, 100),
        kind: PointerDeviceKind.mouse,
        buttons: kPrimaryButton,
      );
      await tester.pump();
      return gesture;
    }

    testWidgets('on a frame with no cel the shape tool\'s press is the one '
        'that asks — once', (tester) async {
      final asked = await pumpPanel(tester, celEditable: false);

      final gesture = await pressOnThePanel(tester);
      expect(asked, ['asked'], reason: 'at the press: the layer asked');

      await dragOut(tester, gesture);
      expect(asked, ['asked'], reason: 'and nobody asks again at the release');
    });

    testWidgets('⛔where a cel is there nobody under the panel asks', (
      tester,
    ) async {
      final asked = await pumpPanel(tester, celEditable: true);

      await dragOut(tester, await pressOnThePanel(tester));

      expect(asked, isEmpty);
    });
  });

  testWidgets('⛔only the verb that draws asks: a selection is dragged out '
      'over an empty frame without a cel being made', (tester) async {
    final host = await pumpLayer(
      tester,
      celAnswer: true,
      tool: CanvasSelectionTool.select,
    );

    final gesture = await press(tester, const Offset(40, 40));
    await dragOut(tester, gesture);

    expect(host.log, ['selected'], reason: 'it selected, and asked nobody');
  });
}
