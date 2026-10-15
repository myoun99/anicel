import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/brush_dab.dart';
import 'package:anicel/src/models/brush_frame_key.dart';
import 'package:anicel/src/models/brush_tip_shape.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/services/brush_frame_editing_coordinator.dart';
import 'package:anicel/src/services/canvas_color_sampler.dart';
import 'package:anicel/src/ui/brush/brush_canvas_panel.dart';
import 'package:anicel/src/ui/brush/brush_edit_cache_invalidation_sink.dart';
import 'package:anicel/src/ui/brush/brush_tool_state.dart';
import 'package:anicel/src/ui/brush/canvas_selection_commands.dart';

import '../../helpers/brush_canvas_fixture.dart';

/// I-37 — EVERY CEL A FOLDER'S LIFT TOOK UP LANDS, each from the float the
/// layer hands back for it.
///
/// Pinned on a host with NO history, where the session's own landings are
/// the only ones: on a history host the transform's ladder walks the cels
/// underfoot as well and would land a cel the session dropped all over
/// again — through a fresh lift rather than the bytes its preview showed,
/// which is a difference only a warp's last bit can see.
void main() {
  BrushDab dab(double x, double y) => BrushDab(
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

  bool inked(
    BrushFrameEditingCoordinator coordinator,
    BrushFrameKey key,
    int x,
    int y,
  ) => (surfacePixelRgba(coordinator.currentSurfaceOf(key), x, y) ?? 0) != 0;

  testWidgets('a host with no history lands every cel a folder\'s lift took '
      'up', (tester) async {
    final keys = BrushCanvasFixture.createFrameKeys();
    final coordinator = BrushCanvasFixture.createCoordinator(frameKeys: keys);
    // Two cels standing for two rows of a folder, inked apart.
    coordinator.commitSourceStroke(sourceDabs: [dab(30, 30), dab(40, 40)]);
    coordinator.selectFrame(keys[1]);
    coordinator.commitSourceStroke(sourceDabs: [dab(120, 120), dab(130, 130)]);
    coordinator.selectFrame(keys[0]);
    final commands = CanvasSelectionCommands();
    addTearDown(commands.dispose);
    final brush = ValueNotifier(
      BrushToolState.defaults.copyWith(tool: CanvasTool.move),
    );
    addTearDown(brush.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 800,
            height: 600,
            child: BrushCanvasPanel(
              coordinator: coordinator,
              availableFrameKeys: keys,
              cacheInvalidationSink: BrushEditCacheInvalidationSink(),
              brushToolState: brush,
              selectionCommands: commands,
              transformCelsUnderfoot: () => [
                (key: keys[0], live: false),
                (key: keys[1], live: false),
              ],
              // A composite behind the canvas — where a folder's rows show.
              viewportUnderlayBuilder: (context, viewport, painter, floats) =>
                  const SizedBox.expand(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      (inked(coordinator, keys[0], 30, 30), inked(coordinator, keys[1], 120, 120)),
      (true, true),
      reason: '⛔fixture premise: both cels draw where the test reads',
    );

    commands.beginTransform();
    await tester.pump();
    commands.editTransformValues((now) => now.copyWith(tx: 50));
    await tester.pump();
    commands.applyTransform();
    await tester.pump();

    expect(
      (inked(coordinator, keys[0], 30, 30), inked(coordinator, keys[0], 80, 30)),
      (false, true),
      reason: 'the first cel landed where the box put it',
    );
    expect(
      (
        inked(coordinator, keys[1], 120, 120),
        inked(coordinator, keys[1], 170, 120),
      ),
      (false, true),
      reason: 'and so did the second',
    );
  });
}
