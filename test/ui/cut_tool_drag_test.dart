import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/brush_dab.dart';
import 'package:anicel/src/models/brush_tip_shape.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/services/brush_frame_editing_coordinator.dart';
import 'package:anicel/src/services/cut_piece_slot.dart';
import 'package:anicel/src/services/history_manager.dart';
import 'package:anicel/src/ui/brush/brush_canvas_panel.dart';
import 'package:anicel/src/ui/brush/brush_edit_cache_invalidation_sink.dart';
import 'package:anicel/src/ui/brush/brush_tool_state.dart';
import 'package:anicel/src/ui/brush/canvas_selection_commands.dart';
import 'package:anicel/src/ui/canvas/canvas_selection_layer.dart';

import '../helpers/brush_canvas_fixture.dart';

/// The cut tool driven through real pointer input.
///
/// The pure lift is pinned next door in cut_piece_lift_test; what this file
/// is for is the WIRING — that a drag with a cut variant armed reaches the
/// slot at all, and that it leaves the selection alone on the way.
void main() {
  const layerKey = ValueKey<String>('canvas-selection-layer');

  BrushDab dab(double x, double y) => BrushDab(
    center: CanvasPoint(x: x, y: y),
    color: 0xFFFF0000,
    size: 8,
    opacity: 1,
    flow: 1,
    hardness: 1,
    tipShape: BrushTipShape.square,
    pressure: 1,
    sequence: 0,
  );

  Future<
    ({
      BrushFrameEditingCoordinator coordinator,
      CanvasSelectionCommands commands,
      CutPieceSlot slot,
      Future<void> Function(CanvasTool tool) setTool,
    })
  >
  pumpPanel(WidgetTester tester, {required CanvasTool tool}) async {
    final frameKeys = BrushCanvasFixture.createFrameKeys();
    final coordinator = BrushCanvasFixture.createCoordinator(
      frameKeys: frameKeys,
    );
    final history = HistoryManager();
    final commands = CanvasSelectionCommands();
    final slot = CutPieceSlot();

    Future<void> pumpWith(CanvasTool next) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BrushCanvasPanel(
              coordinator: coordinator,
              availableFrameKeys: frameKeys,
              cacheInvalidationSink: BrushEditCacheInvalidationSink(),
              historyManager: history,
              brushToolState: BrushToolState.defaults.copyWith(tool: next),
              selectionCommands: commands,
              cutPieceSlot: slot,
            ),
          ),
        ),
      );
      await tester.pump();
    }

    // Ink to cut: a wide bar across the middle of the canvas.
    coordinator.commitSourceStroke(
      sourceDabs: [for (var x = 10; x <= 90; x += 2) dab(x.toDouble(), 40)],
    );
    await pumpWith(tool);
    return (
      coordinator: coordinator,
      commands: commands,
      slot: slot,
      setTool: pumpWith,
    );
  }

  Future<void> dragOnLayer(
    WidgetTester tester,
    Offset from,
    Offset to,
  ) async {
    final origin = tester.getTopLeft(find.byKey(layerKey));
    final gesture = await tester.startGesture(
      origin + from,
      kind: PointerDeviceKind.mouse,
      buttons: kPrimaryButton,
    );
    await tester.pump();
    await gesture.moveTo(origin + (from + to) / 2);
    await tester.pump();
    await gesture.moveTo(origin + to);
    await tester.pump();
    await gesture.up();
    await tester.pump();
  }

  testWidgets('a cut variant still mounts the selection layer', (tester) async {
    // It rides the same drag surface; that is the whole reason the marquee
    // geometry is not duplicated anywhere.
    await pumpPanel(tester, tool: CanvasTool.cutRect);
    expect(find.byKey(layerKey), findsOneWidget);
  });

  testWidgets('the stamp variant does NOT mount it', (tester) async {
    await pumpPanel(tester, tool: CanvasTool.cutStamp);
    expect(find.byKey(layerKey), findsNothing);
  });

  testWidgets('a rectangle cut fills the slot', (tester) async {
    final env = await pumpPanel(tester, tool: CanvasTool.cutRect);
    expect(env.slot.isEmpty, isTrue);
    await dragOnLayer(tester, const Offset(10, 10), const Offset(90, 70));
    expect(env.slot.isNotEmpty, isTrue);
    expect(env.slot.piece!.image.width, greaterThan(0));
  });

  testWidgets('a lasso cut fills the slot too', (tester) async {
    final env = await pumpPanel(tester, tool: CanvasTool.cutLasso);
    // The path has to BEND: a lasso dragged in a straight line is a
    // zero-area polygon, and enclosing nothing is correctly nothing to cut.
    final origin = tester.getTopLeft(find.byKey(layerKey));
    final gesture = await tester.startGesture(
      origin + const Offset(10, 10),
      kind: PointerDeviceKind.mouse,
      buttons: kPrimaryButton,
    );
    await tester.pump();
    for (final point in const [
      Offset(90, 10),
      Offset(90, 70),
      Offset(10, 70),
    ]) {
      await gesture.moveTo(origin + point);
      await tester.pump();
    }
    await gesture.up();
    await tester.pump();
    expect(env.slot.isNotEmpty, isTrue);
  });

  testWidgets('a lasso dragged in a straight line cuts nothing', (
    tester,
  ) async {
    // It encloses no area, so there is nothing under it — and the slot
    // must not be blanked on the way to finding that out.
    final env = await pumpPanel(tester, tool: CanvasTool.cutLasso);
    await dragOnLayer(tester, const Offset(10, 10), const Offset(90, 70));
    expect(env.slot.isEmpty, isTrue);
  });

  testWidgets('cutting leaves the selection completely alone', (tester) async {
    // 유저 확정: "잘라내기는 잘라내기만이야. 그러니 선택으로 남지 않아."
    final env = await pumpPanel(tester, tool: CanvasTool.cutRect);
    expect(env.commands.region, isNull);
    await dragOnLayer(tester, const Offset(10, 10), const Offset(90, 70));
    expect(env.slot.isNotEmpty, isTrue, reason: 'the cut happened');
    expect(env.commands.region, isNull, reason: 'and made no selection');
  });

  testWidgets('an EXISTING selection survives a cut untouched', (tester) async {
    // A selection made with the select tool still clips painting, so a cut
    // must not quietly redraw or drop it.
    final env = await pumpPanel(tester, tool: CanvasTool.selectRect);
    await dragOnLayer(tester, const Offset(10, 10), const Offset(60, 60));
    final selected = env.commands.region;
    expect(selected, isNotNull);

    await env.setTool(CanvasTool.cutRect);
    await dragOnLayer(tester, const Offset(20, 20), const Offset(90, 70));
    expect(env.slot.isNotEmpty, isTrue);
    expect(env.commands.region, same(selected));
  });

  testWidgets('cutting again replaces the held piece', (tester) async {
    final env = await pumpPanel(tester, tool: CanvasTool.cutRect);
    await dragOnLayer(tester, const Offset(10, 10), const Offset(90, 70));
    final first = env.slot.piece;
    await dragOnLayer(tester, const Offset(20, 20), const Offset(80, 60));
    expect(env.slot.piece, isNot(same(first)));
  });

  testWidgets('the piece survives switching tools and back', (tester) async {
    // The slot outlives the tool — the whole point is cutting here and
    // stamping somewhere else later.
    final env = await pumpPanel(tester, tool: CanvasTool.cutRect);
    await dragOnLayer(tester, const Offset(10, 10), const Offset(90, 70));
    final piece = env.slot.piece;
    expect(piece, isNotNull);

    await env.setTool(CanvasTool.brush);
    await env.setTool(CanvasTool.cutStamp);
    expect(env.slot.piece, same(piece));
  });

  testWidgets('a cut over blank cel leaves the held piece alone', (
    tester,
  ) async {
    // The slot is a long-term holder; one stray scrape must not empty it.
    final env = await pumpPanel(tester, tool: CanvasTool.cutRect);
    await dragOnLayer(tester, const Offset(10, 10), const Offset(90, 70));
    final piece = env.slot.piece;
    expect(piece, isNotNull);

    // Far below the painted bar.
    await dragOnLayer(tester, const Offset(10, 200), const Offset(60, 250));
    expect(env.slot.piece, same(piece));
  });
}
