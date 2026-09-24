import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/brush/brush_canvas_panel.dart';
import 'package:anicel/src/ui/brush/brush_edit_cache_invalidation_sink.dart';
import 'package:anicel/src/ui/brush/brush_tool_state.dart';
import 'package:anicel/src/ui/debug/input_inspector.dart';

import '../helpers/brush_canvas_fixture.dart';
import 'brush_canvas_test_helpers.dart';

/// 🐛The D34 probe's `held=` printed the panel's State object, never the flag
/// (유저 스샷 2026-09-13: `aim census:mouse -> (1372,515)
/// held=_BrushCanvasPanelState…`). An interpolation without braces stops at
/// the first `.`, so `$_state._tap.aimIsHeld` is the State followed by the
/// literal text `._tap.aimIsHeld` — the same slip the T12 `stack paint` line
/// had the same day. The one question this line exists to answer never
/// reached the screen.
void main() {
  tearDown(InputInspector.reset);

  testWidgets('a hovering mouse writes an aim line that says the aim is '
      'held — the flag, not the panel it lives on', (tester) async {
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
            floorCover: EdgeInsets.zero,
            brushToolState: ValueNotifier(BrushToolState.defaults.copyWith(
              tool: CanvasTool.brush,
              size: 40,
            )),
            sampleColorAt: (_) => 0x336699,
            onEyedropperPick: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    InputInspector.visible.value = true;

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(canvasGlobalOffset(tester, const Offset(40, 40)));
    await tester.pump();

    final line = InputInspector.notes['aim'];
    expect(line, isNotNull, reason: 'fixture: the census wrote the aim');
    expect(
      line,
      contains(' held=true '),
      reason: 'a mouse inside the canvas holds the aim: $line',
    );
    expect(
      line,
      isNot(contains('State')),
      reason: 'the line names a flag, not an object: $line',
    );
  });
}
