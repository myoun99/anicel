import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/services/history_manager.dart';
import 'package:anicel/src/ui/brush/brush_canvas_panel.dart';
import 'package:anicel/src/ui/brush/brush_edit_cache_invalidation_sink.dart';
import 'package:anicel/src/ui/brush/brush_tool_state.dart';
import 'package:anicel/src/ui/canvas/interactive_brush_edit_canvas_view.dart';
import 'package:anicel/src/ui/canvas/view_hand.dart';

import '../../helpers/brush_canvas_fixture.dart';
import '../../helpers/device_viewport.dart';

/// 🚨THE PANEL HOLDS UP WHAT A SAVE LANDS FIRST, AND PUTS IT DOWN WHEN IT
/// GOES. A save asks the session's hand (`LiveStrokeLanding.lander`) to
/// land the pen and the text in hand before it snapshots; the main canvas
/// panel is who holds that hand up (`BrushCanvasPanel.strokeLander`).
///
/// ⚠️`the_canvas_publishes_its_stroke_lander_test` pins the view's hand to
/// the panel; this pins the panel's to the session. Without it the panel
/// could leave a gone panel's hand up, or stop landing the stroke the pen
/// is drawing, and every save test would stay green (F-419: both lived as
/// mutants).
void main() {
  const size = CanvasSize(width: 400, height: 300);
  const view = ValueKey<String>('interactive-brush-edit-canvas-view-listener');

  late ViewHand<StrokeLander> lander;
  late HistoryManager history;

  setUp(() {
    lander = ViewHand();
    history = HistoryManager();
  });

  Future<void> pumpPanel(WidgetTester tester) async {
    final keys = BrushCanvasFixture.createFrameKeys();
    final brush = ValueNotifier(BrushToolState.defaults);
    addTearDown(brush.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BrushCanvasPanel(
            coordinator: BrushCanvasFixture.createCoordinator(
              frameKeys: keys,
              canvasSize: size,
            ),
            canvasSize: size,
            availableFrameKeys: keys,
            cacheInvalidationSink: BrushEditCacheInvalidationSink(),
            historyManager: history,
            brushToolState: brush,
            viewport: seedFromRender(tester, CanvasViewport()),
            strokeLander: lander,
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('a mounted panel holds up its save lander, and a gone one '
      'puts it down', (tester) async {
    await pumpPanel(tester);
    expect(lander.now, isNotNull, reason: 'a save could land nothing');

    await tester.pumpWidget(const SizedBox.shrink());
    expect(
      lander.now,
      isNull,
      reason: 'a gone panel\'s hand would land into a canvas already given '
          'back',
    );
  });

  testWidgets('its lander lands the stroke the pen is still drawing — '
      'once', (tester) async {
    await pumpPanel(tester);
    final origin = tester.getTopLeft(find.byKey(view));
    final steps = history.undoCount;

    // A pen that is still DOWN — the state pressing Ctrl+S catches.
    final pen = await tester.createGesture(kind: PointerDeviceKind.stylus);
    await pen.down(origin + const Offset(100, 100));
    await tester.pump();
    await pen.moveTo(origin + const Offset(160, 130));
    await tester.pump();
    expect(
      history.undoCount,
      steps,
      reason: 'fixture premise: nothing has landed while the pen is down',
    );

    expect(lander.now!(), isTrue, reason: 'it had a stroke to land');
    expect(history.undoCount, steps + 1, reason: 'one step back');

    await pen.up();
    await tester.pump();
    await tester.pump();
    expect(
      history.undoCount,
      steps + 1,
      reason: 'the lift finds nothing left to land — two steps would be '
          'two undos for one line',
    );
  });
}
