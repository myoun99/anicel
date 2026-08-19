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

    expect(
      cursor,
      findsOneWidget,
      reason: 'and it may not DELETE that aim on the way out either — a '
          'pointer the census refuses to write from is a pointer with '
          'nothing here to erase',
    );
    expect(tester.getTopLeft(cursor), aimed);

    // The same on the cancel path, which is how a navigating gesture
    // usually ends once the pan recognizer claims it.
    final second = await tester.createGesture(kind: PointerDeviceKind.touch);
    await second.down(canvasGlobalOffset(tester, const Offset(60, 60)));
    await tester.pump();
    await second.cancel();
    await tester.pump();
    expect(cursor, findsOneWidget);
    expect(tester.getTopLeft(cursor), aimed);
  });

  testWidgets('changing the one-finger slot WHILE a finger is down leaves '
      'the census intact — membership is the record, not a fresh look at '
      'a live setting', (tester) async {
    useOneFingerSlot(CanvasTouchDragAction.draw);
    await pumpPanel(tester);

    // A drawing finger goes down, then the user turns finger-drawing off
    // with the other hand while it is still resting on the glass.
    final finger = await tester.createGesture(kind: PointerDeviceKind.touch);
    await finger.down(canvasGlobalOffset(tester, const Offset(20, 20)));
    await tester.pump();
    expect(cursor, findsOneWidget);

    useOneFingerSlot(CanvasTouchDragAction.flip);
    await tester.pump();
    await finger.up();
    await tester.pump();

    expect(
      cursor,
      findsNothing,
      reason: 'the finger was admitted at DOWN, so its lift still ends its '
          'span — re-asking the live setting here would strand this ring',
    );

    // …and the census is not poisoned: the NEXT finger still clears.
    useOneFingerSlot(CanvasTouchDragAction.draw);
    await tester.pump();
    final next = await tester.createGesture(kind: PointerDeviceKind.touch);
    await next.down(canvasGlobalOffset(tester, const Offset(50, 50)));
    await tester.pump();
    expect(cursor, findsOneWidget);
    await next.up();
    await tester.pump();
    expect(
      cursor,
      findsNothing,
      reason: 'a stranded id would have made this unreachable for the rest '
          'of the session — D34 back, and silently',
    );
  });

  testWidgets('one finger lifting does not blank the ring another finger '
      'is still drawing with', (tester) async {
    useOneFingerSlot(CanvasTouchDragAction.draw);
    await pumpPanel(tester);

    final drawing = await tester.createGesture(kind: PointerDeviceKind.touch);
    await drawing.down(canvasGlobalOffset(tester, const Offset(20, 20)));
    await tester.pump();
    expect(cursor, findsOneWidget);
    final aimed = tester.getTopLeft(cursor);

    final other = await tester.createGesture(kind: PointerDeviceKind.touch);
    await other.down(canvasGlobalOffset(tester, const Offset(120, 100)));
    await tester.pump();
    await other.up();
    await tester.pump();

    expect(
      cursor,
      findsOneWidget,
      reason: 'a press is a SPAN and they overlap — the aim belongs to the '
          'span, so it survives until the LAST holder lifts',
    );

    await drawing.up();
    await tester.pump();
    expect(
      cursor,
      findsNothing,
      reason: 'and it does go when that last one lifts',
    );
    expect(aimed, isNotNull);
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

    expect(
      cursor,
      findsNothing,
      reason: 'and the aim goes with the finger. Flutter delivers a region '
          'exit only for mouse and stylus, so the exit that clears this '
          'never runs for a finger — the ring stayed at the last touched '
          'point for the rest of the session (D34)',
    );
  });

  // ⚠️NOT a touch-only bug, and this half needs no setting at all: the pen
  // TAIL reports as invertedStylus, which every tool accepts, and Flutter
  // delivers no exit for it either.
  testWidgets('the pen TAIL leaves no ring behind either — invertedStylus '
      'and unknown get no exit from Flutter, at product defaults', (
    tester,
  ) async {
    for (final kind in [
      PointerDeviceKind.invertedStylus,
      PointerDeviceKind.unknown,
    ]) {
      await pumpPanel(tester);

      final pointer = await tester.createGesture(kind: kind);
      await pointer.down(canvasGlobalOffset(tester, const Offset(30, 30)));
      await tester.pump();
      await pointer.moveTo(canvasGlobalOffset(tester, const Offset(90, 70)));
      await tester.pump();
      expect(cursor, findsOneWidget, reason: '$kind aims a tool');

      await pointer.up();
      await tester.pump();
      expect(
        cursor,
        findsNothing,
        reason: '$kind: the contact ending IS its exit — nothing else is '
            'ever coming',
      );
    }
  });
}
