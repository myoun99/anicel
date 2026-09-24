import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/brush/brush_canvas_panel.dart';
import 'package:anicel/src/ui/brush/brush_edit_cache_invalidation_sink.dart';
import 'package:anicel/src/ui/brush/brush_tool_state.dart';
import 'package:anicel/src/ui/brush/tool_cursor_sprite.dart';

import '../helpers/brush_canvas_fixture.dart';
import 'brush_canvas_test_helpers.dart';

/// 🚨★★★F-130 (유저, 2026-09-15): 「앱 커서만 최대한 가볍게 … os커서는
/// 60프레임급으로 렉없이 움직이는데 앱 브러시같은 툴커서만 30프레임정도로
/// 렉걸린다고」.
///
/// Every tool cursor the app draws — the brush ring, the bucket, the
/// dropper and its swatch — is a sprite that moves by LAYER OFFSET: a move
/// rebuilds no widget, lays nothing out, paints nothing and re-records no
/// picture. The frame it asks for is compositing only. The system cursor
/// hides while a tool cursor is up, so the app's is the one that shows.
void main() {
  const outlineKey = ValueKey<String>('brush-cursor-overlay');

  Future<void> pumpPanel(
    WidgetTester tester, {
    CanvasTool tool = CanvasTool.brush,
    int? Function(Object point)? sample,
  }) async {
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
              tool: tool,
              size: 40,
            )),
            sampleColorAt: (point) => sample == null ? 0x336699 : sample(point),
            onEyedropperPick: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<TestGesture> hover(WidgetTester tester, Offset local) async {
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(canvasGlobalOffset(tester, local));
    await tester.pump();
    return mouse;
  }

  testWidgets('the system cursor hides while a tool cursor is up, and the '
      'app draws the ring where the pointer is', (tester) async {
    await pumpPanel(tester);
    expect(
      tester
          .widget<MouseRegion>(
            find.byKey(const ValueKey<String>('brush-cursor-region')),
          )
          .cursor,
      SystemMouseCursors.none,
    );
    await hover(tester, const Offset(40, 40));
    expect(toolCursorShownAt(tester, find.byKey(outlineKey)), isNotNull);
  });

  testWidgets('moving the ring is compositing only: no widget rebuilt, no '
      'render object painted, no picture re-recorded — and it followed', (
    tester,
  ) async {
    await pumpPanel(tester);
    final mouse = await hover(tester, const Offset(40, 40));
    final outline = find.byKey(outlineKey);
    final sprite = tester.renderObject<RenderToolCursorSprite>(outline);
    final before = sprite.debugPosition!;
    // The first move after arming is the sprite's own appearance frame;
    // the measurement starts after it.
    await mouse.moveTo(canvasGlobalOffset(tester, const Offset(44, 40)));
    await tester.pump();

    var rebuilt = 0;
    var painted = 0;
    debugOnRebuildDirtyWidget = (_, _) => rebuilt += 1;
    debugOnProfilePaint = (_) => painted += 1;
    final pictureBefore = _spritePicture(sprite);
    try {
      for (var i = 2; i <= 8; i += 1) {
        await mouse.moveTo(canvasGlobalOffset(tester, Offset(40 + 4.0 * i, 40)));
        expect(
          SchedulerBinding.instance.hasScheduledFrame,
          isTrue,
          reason: 'move $i: the app draws this cursor, so it composites',
        );
        await tester.pump();
      }
    } finally {
      debugOnRebuildDirtyWidget = null;
      debugOnProfilePaint = null;
    }
    expect(rebuilt, 0, reason: 'a move builds nothing');
    expect(painted, 0, reason: 'a move paints nothing');
    expect(
      identical(_spritePicture(sprite), pictureBefore),
      isTrue,
      reason: 'the ring\'s picture was moved, not re-recorded',
    );
    expect(
      sprite.debugPosition!.dx - before.dx,
      closeTo(32, 0.5),
      reason: 'and it followed all eight moves',
    );
  });

  testWidgets('the bucket and the dropper are sprites with the spout and '
      'the tip as hot spots; the swatch is a sprite of its own', (
    tester,
  ) async {
    await pumpPanel(tester, tool: CanvasTool.fill);
    await hover(tester, const Offset(40, 40));
    final bucket = find.byKey(const ValueKey<String>('fill-cursor-icon'));
    expect(toolCursorShownAt(tester, bucket), isNotNull);
    expect(tester.widget<ToolCursorSprite>(bucket).look.hotspot, const Offset(3, 20));

    await pumpPanel(tester, tool: CanvasTool.eyedropper);
    await tester.pump();
    final dropper = find.byKey(const ValueKey<String>('eyedropper-cursor-icon'));
    expect(tester.widget<ToolCursorSprite>(dropper).look.hotspot, const Offset(3, 21));
    expect(
      find.byKey(const ValueKey<String>('eyedropper-hover-swatch')),
      findsOneWidget,
    );
  });

  testWidgets('the eyedropper samples once per FRAME, not per event', (
    tester,
  ) async {
    var samples = 0;
    await pumpPanel(
      tester,
      tool: CanvasTool.eyedropper,
      sample: (_) {
        samples += 1;
        return 0x336699;
      },
    );
    final mouse = await hover(tester, const Offset(40, 40));
    expect(eyedropperSwatchColor(tester), 0x336699);

    samples = 0;
    // Five events, one frame.
    for (var i = 1; i <= 5; i += 1) {
      await mouse.moveTo(canvasGlobalOffset(tester, Offset(40 + 2.0 * i, 40)));
    }
    await tester.pump();
    expect(samples, 1, reason: 'one frame shows one colour');
  });
}

/// The picture the sprite's moving layer holds right now.
Object? _spritePicture(RenderToolCursorSprite sprite) {
  // ignore: invalid_use_of_protected_member
  final boundary = sprite.layer;
  if (boundary is! ContainerLayer) {
    return null;
  }
  final moving = boundary.firstChild;
  if (moving is! ContainerLayer) {
    return null;
  }
  final picture = moving.firstChild;
  return picture is PictureLayer ? picture.picture : null;
}
