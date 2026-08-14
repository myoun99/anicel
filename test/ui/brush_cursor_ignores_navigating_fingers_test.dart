import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/brush/brush_canvas_panel.dart';
import 'package:anicel/src/ui/brush/brush_edit_cache_invalidation_sink.dart';
import 'package:anicel/src/ui/brush/brush_tool_state.dart';
import 'package:anicel/src/ui/input/app_input_settings.dart';

import '../helpers/brush_canvas_fixture.dart';
import 'brush_canvas_test_helpers.dart';

/// 유저 (2026-08-15 #2): 「브러시툴인채로 터치하면 브러시의 커서가
/// 움직이는데, 설마 터치를 브러시로 인식하나? 그림은 안그려지니까 괜찮은데
/// 커서 안움직이도록. 제대로 로직적으로. 1핑거 터치 none으로해도 커서가
/// 움직임」
///
/// The finger was never recognized as a brush — the stroke path refuses it
/// correctly. What took it was the panel's always-mounted pointer CENSUS,
/// which asked no question about the device at all and wrote the tool
/// cursor's position for anything that moved.
///
/// So this is [AppInput.toolAcceptsPointer] again — the door the census was
/// the last input layer never to knock on. 유저 법: 「드로잉모드가 아닌이상은
/// 툴이 작동하면 안되지」, and a cursor is the tool's aim.
void main() {
  Future<void> pumpPanel(WidgetTester tester) async {
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
            brushToolState: BrushToolState.defaults.copyWith(
              tool: CanvasTool.brush,
              size: 40,
            ),
            sampleColorAt: (_) => 0x336699,
            onEyedropperPick: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  final cursor = find.byKey(const ValueKey<String>('brush-cursor-overlay'));

  void useOneFingerSlot(CanvasTouchDragAction action) {
    AppInput.settings.value = AppInput.settings.value.copyWith(
      touchDragOneFinger: action,
    );
    addTearDown(() {
      AppInput.settings.value = AppInputSettings.testCorpusBaseline;
    });
  }

  // ⚠️The corpus baseline pins the one-finger slot to DRAW (touch-as-pen),
  // so every case here has to state its own slot — a test that forgot would
  // pass on the old code.
  for (final action in const [
    CanvasTouchDragAction.none,
    CanvasTouchDragAction.flip,
    CanvasTouchDragAction.navigate,
  ]) {
    testWidgets('a finger does not raise the brush cursor while the '
        'one-finger slot is ${action.name}', (tester) async {
      useOneFingerSlot(action);
      await pumpPanel(tester);

      final finger = await tester.createGesture(kind: PointerDeviceKind.touch);
      await finger.down(canvasGlobalOffset(tester, const Offset(20, 20)));
      await tester.pump();
      await finger.moveTo(canvasGlobalOffset(tester, const Offset(70, 60)));
      await tester.pump();

      expect(
        cursor,
        findsNothing,
        reason: 'the finger is navigating, not aiming — nothing about the '
            'brush should follow it',
      );

      await finger.up();
      await tester.pump();
    });
  }

  testWidgets('a finger never displaces the cursor the pen put down', (
    tester,
  ) async {
    useOneFingerSlot(CanvasTouchDragAction.flip);
    await pumpPanel(tester);

    // The pen hovers: the cursor arms and takes its position.
    final pen = await tester.createGesture(kind: PointerDeviceKind.stylus);
    await pen.addPointer(location: Offset.zero);
    addTearDown(pen.removePointer);
    await pen.moveTo(canvasGlobalOffset(tester, const Offset(24, 24)));
    await tester.pump();
    expect(cursor, findsOneWidget);
    final aimed = tester.getTopLeft(cursor);

    // A finger lands somewhere else entirely. 「커서도 안움직이게」.
    final finger = await tester.createGesture(kind: PointerDeviceKind.touch);
    await finger.down(canvasGlobalOffset(tester, const Offset(160, 140)));
    await tester.pump();
    await finger.moveTo(canvasGlobalOffset(tester, const Offset(180, 150)));
    await tester.pump();

    expect(
      tester.getTopLeft(cursor),
      aimed,
      reason: 'the finger dragged the pen\'s aim across the canvas',
    );

    await finger.up();
    await tester.pump();
  });

  // The other side of the same law: where a finger IS the drawing device,
  // its cursor follows it exactly as the pen's does.
  testWidgets('a finger DOES carry the cursor when the one-finger slot '
      'draws', (tester) async {
    useOneFingerSlot(CanvasTouchDragAction.draw);
    await pumpPanel(tester);

    final finger = await tester.createGesture(kind: PointerDeviceKind.touch);
    await finger.down(canvasGlobalOffset(tester, const Offset(20, 20)));
    await tester.pump();
    expect(cursor, findsOneWidget);
    final start = tester.getTopLeft(cursor);

    await finger.moveTo(canvasGlobalOffset(tester, const Offset(70, 60)));
    await tester.pump();

    expect(
      tester.getTopLeft(cursor),
      isNot(start),
      reason: 'a drawing finger is the aim — the outline has to follow it',
    );

    await finger.up();
    await tester.pump();
  });
}
