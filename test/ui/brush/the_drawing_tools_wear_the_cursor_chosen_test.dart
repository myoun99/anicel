import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RendererBinding;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/app_input_settings.dart';
import 'package:anicel/src/ui/brush/brush_canvas_panel.dart';
import 'package:anicel/src/ui/brush/brush_cursor_painter.dart';
import 'package:anicel/src/ui/brush/brush_edit_cache_invalidation_sink.dart';
import 'package:anicel/src/ui/brush/brush_tool_state.dart';
import 'package:anicel/src/ui/brush/drawing_cursor.dart';
import 'package:anicel/src/ui/brush/tool_cursor_sprite.dart';
import 'package:anicel/src/ui/canvas/canvas_view_hold.dart';
import 'package:anicel/src/ui/debug/measurement_mode.dart';
import 'package:anicel/src/ui/debug/repaint_cause.dart';

import '../../helpers/brush_canvas_fixture.dart';
import '../../helpers/settle_async.dart';
import '../brush_canvas_test_helpers.dart';

/// 🗣️I-54 (유저 2026-09-30): 「브러시 커서, 여러 커서 옵션으로 고를수있게. 지금처럼
/// 브러시커서, 펜 커서(크기고정, 펜 모양 아이콘, os커서를 바꿈으로서 앱이랑
/// 관계없이 빠르게), 십자커서(크기고정, 동일하게 os커서 바꿈) 이렇게 세개」.
///
/// What is measured is the cursor the system actually resolved under a real
/// mouse (`MouseTracker`), and the sprites the app actually shows — not the
/// region's declaration.
void main() {
  const outline = ValueKey<String>('brush-cursor-overlay');
  const pen = ValueKey<String>('pen-cursor-overlay');
  const crosshair = ValueKey<String>('crosshair-cursor-overlay');

  void choose(DrawingCursor cursor) => AppInput.settings.value =
      AppInputSettings.testCorpusBaseline.copyWith(drawingCursor: cursor);

  tearDown(
    () => AppInput.settings.value = AppInputSettings.testCorpusBaseline,
  );

  Future<void> pumpPanel(
    WidgetTester tester, {
    CanvasTool tool = CanvasTool.brush,
    Widget Function(BuildContext context, Object viewport)? controls,
    bool rowAcceptsStrokes = true,
    bool toolCursorsEnabled = true,
    bool Function()? onPressNeedsCel,
    VoidCallback? onAutoFrameSettled,
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
            brushToolState: ValueNotifier(
              BrushToolState.defaults.copyWith(tool: tool, size: 40),
            ),
            viewportControlsBuilder: controls,
            rowAcceptsStrokes: rowAcceptsStrokes,
            toolCursorsEnabled: toolCursorsEnabled,
            onPressNeedsCel: onPressNeedsCel,
            onAutoFrameSettled: onAutoFrameSettled,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// A control over the LEFT half of the canvas, as the standing row's box
  /// lies over the tools and takes the presses that are its own.
  Widget Function(BuildContext context, Object viewport) leftHalfControl(
    VoidCallback pressed,
  ) =>
      (context, viewport) => Align(
        alignment: Alignment.centerLeft,
        child: FractionallySizedBox(
          widthFactor: 0.5,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (_) => pressed(),
            child: const SizedBox.expand(),
          ),
        ),
      );

  /// A point on [leftHalfControl], and one on the tool's half beside it.
  ({Offset onTheControl, Offset onTheTool}) halves(WidgetTester tester) {
    final width = tester.getSize(interactiveBrushCanvasFinder()).width;
    return (
      onTheControl: Offset(width / 4, 40),
      onTheTool: Offset(width * 3 / 4, 40),
    );
  }

  Future<TestGesture> hover(WidgetTester tester, Offset local) async {
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(canvasGlobalOffset(tester, local));
    await tester.pump();
    return mouse;
  }

  /// The cursor the system was told to show for the mouse (device 1).
  MouseCursor? shown() =>
      RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(1);

  bool drawn(WidgetTester tester, ValueKey<String> key) =>
      find.byKey(key).evaluate().isNotEmpty &&
      toolCursorShownAt(tester, find.byKey(key)) != null;

  for (final tool in [CanvasTool.brush, CanvasTool.eraser]) {
    testWidgets('🚨the crosshair is the system\'s own under the ${tool.name}: '
        'the system shows it, and the app draws no cursor at all', (
      tester,
    ) async {
      choose(DrawingCursor.crosshair);
      await pumpPanel(tester, tool: tool);
      await hover(tester, const Offset(40, 40));
      expect(shown(), SystemMouseCursors.precise);
      expect(drawn(tester, outline), isFalse);
      expect(drawn(tester, crosshair), isFalse);
      expect(drawn(tester, pen), isFalse);
    });

    testWidgets('the outline is the app\'s under the ${tool.name}: the system '
        'steps aside and the tip\'s outline is drawn', (tester) async {
      choose(DrawingCursor.brush);
      await pumpPanel(tester, tool: tool);
      await hover(tester, const Offset(40, 40));
      expect(shown(), SystemMouseCursors.none);
      expect(drawn(tester, outline), isTrue);
    });
  }

  testWidgets('a choice made while the pointer is on the canvas is worn at '
      'once — no move needed', (tester) async {
    choose(DrawingCursor.brush);
    await pumpPanel(tester);
    await hover(tester, const Offset(40, 40));
    expect(drawn(tester, outline), isTrue, reason: '⛔CONTROL');

    choose(DrawingCursor.crosshair);
    await tester.pump();
    expect(shown(), SystemMouseCursors.precise);
    expect(drawn(tester, outline), isFalse);

    choose(DrawingCursor.brush);
    await tester.pump();
    expect(shown(), SystemMouseCursors.none);
    expect(drawn(tester, outline), isTrue);
  });

  // 🗣️F-285 (유저 2026-10-17): 「카메라 레이어에선 그냥 기본커서로. 이런식으로
  // 도구가 연관이 없는 곳에선 기본커서. 트랜스폼fx든 뭐 그런거 전부」 — and
  // F-377: 「그런 누름 관련, 입구 확실하게 나눠서 근본/구조적으로」.
  testWidgets('🚨a control over the tools takes the pointer before the '
      'tool\'s entrance: the system\'s default shows on it and nothing of '
      'the tool\'s is drawn there', (tester) async {
    choose(DrawingCursor.brush);
    var controlPresses = 0;
    await pumpPanel(tester, controls: leftHalfControl(() => controlPresses++));
    final (:onTheControl, :onTheTool) = halves(tester);

    final mouse = await hover(tester, onTheTool);
    expect(shown(), SystemMouseCursors.none, reason: '⛔CONTROL: the outline');
    expect(drawn(tester, outline), isTrue, reason: '⛔CONTROL');

    await mouse.moveTo(canvasGlobalOffset(tester, onTheControl));
    await tester.pump();
    expect(shown(), SystemMouseCursors.basic);
    expect(drawn(tester, outline), isFalse, reason: 'no aim over a control');

    choose(DrawingCursor.crosshair);
    await tester.pump();
    expect(shown(), SystemMouseCursors.basic, reason: 'whatever the tool asks');

    await mouse.down(canvasGlobalOffset(tester, onTheControl));
    await mouse.up();
    await tester.pump();
    expect(controlPresses, 1, reason: '⛔CONTROL: the control is over them');

    await mouse.moveTo(canvasGlobalOffset(tester, onTheTool));
    await tester.pump();
    expect(shown(), SystemMouseCursors.precise, reason: 'the tool\'s off it');
  });

  testWidgets('🚨a press a control takes asks for no cel and settles none — '
      'the tool\'s entrance never hears it; a press beside the control does', (
    tester,
  ) async {
    var asks = 0;
    var settles = 0;
    var controlPresses = 0;
    await pumpPanel(
      tester,
      // A cel is there and its row takes no strokes — the camera row's
      // borrowed cel, a property lane: no layer under the entrance hears a
      // press, so the entrance asks for the cel itself (I-10 · R26 #35).
      rowAcceptsStrokes: false,
      onPressNeedsCel: () {
        asks++;
        return false;
      },
      // A press's end settles a block no stroke claimed (I-10) — the tool's
      // business, so a control's press settles none.
      onAutoFrameSettled: () => settles++,
      controls: leftHalfControl(() => controlPresses++),
    );
    final (:onTheControl, :onTheTool) = halves(tester);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);

    await mouse.down(canvasGlobalOffset(tester, onTheControl));
    await mouse.up();
    await tester.pump();
    expect(controlPresses, 1, reason: '⛔CONTROL: the control took it');
    expect(asks, 0, reason: 'the camera\'s box, dragged: no 「그릴 수 없음」');
    expect(settles, 0);

    await mouse.down(canvasGlobalOffset(tester, onTheTool));
    await mouse.up();
    await tester.pump();
    expect(asks, 1, reason: 'a paint press on the row is still told why');
    expect(settles, 1, reason: 'and its end settles what it may have made');
  });

  // CLAUDE.md: 「컨트롤 위에서 시작한 제스처는 그 컨트롤의 것이다」 — and a
  // pressed mouse's cursor is asked of whatever lies under it at every move,
  // so a drag that outran its handle wore the tool's there: under the
  // outline, nothing at all.
  testWidgets('🚨a drag that began on a control is the control\'s to its '
      'lift — no tool where it outruns the control, and the tool\'s back '
      'under the resting hand at the lift', (tester) async {
    choose(DrawingCursor.brush);
    await pumpPanel(tester, controls: leftHalfControl(() {}));
    final (:onTheControl, :onTheTool) = halves(tester);
    final mouse = await hover(tester, onTheTool);
    expect(shown(), SystemMouseCursors.none, reason: '⛔CONTROL: the outline');
    expect(drawn(tester, outline), isTrue, reason: '⛔CONTROL');

    await mouse.moveTo(canvasGlobalOffset(tester, onTheControl));
    await tester.pump();
    await mouse.down(canvasGlobalOffset(tester, onTheControl));
    await tester.pump();
    await mouse.moveTo(canvasGlobalOffset(tester, onTheTool));
    await tester.pump();
    expect(shown(), SystemMouseCursors.basic, reason: 'the control\'s drag');
    expect(drawn(tester, outline), isFalse);

    await mouse.up();
    await tester.pump();
    await tester.pump();
    expect(shown(), SystemMouseCursors.none, reason: 'the tool\'s again');
    expect(drawn(tester, outline), isTrue, reason: 'with no move needed');
  });

  testWidgets('a marking tool wears no cursor of its own where the panel '
      'shows none — the system\'s default', (tester) async {
    choose(DrawingCursor.brush);
    // One mouse for both: a second one added while the first is still there
    // is a device added twice.
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    for (final (tool, own, sprite) in [
      (CanvasTool.brush, SystemMouseCursors.none, outline),
      (
        CanvasTool.fill,
        SystemMouseCursors.none,
        const ValueKey<String>('fill-cursor-icon'),
      ),
      // The caret's own cursor, which the system wears.
      (CanvasTool.text, SystemMouseCursors.text, null),
    ]) {
      for (final enabled in [true, false]) {
        await pumpPanel(tester, tool: tool, toolCursorsEnabled: enabled);
        await mouse.moveTo(Offset.zero);
        await mouse.moveTo(canvasGlobalOffset(tester, const Offset(40, 40)));
        await tester.pump();
        final why =
            '${tool.name}, cursors ${enabled ? 'on (⛔CONTROL)' : 'off'}';
        expect(
          shown(),
          enabled ? own : SystemMouseCursors.basic,
          reason: why,
        );
        if (sprite != null) {
          expect(drawn(tester, sprite), enabled, reason: why);
        }
      }
    }
  });

  testWidgets('the view hold\'s hand wins over the tool\'s cursor for as long '
      'as it is held', (tester) async {
    addTearDown(() => CanvasViewHold.held.value = null);
    choose(DrawingCursor.crosshair);
    await pumpPanel(tester);
    await hover(tester, const Offset(40, 40));
    expect(shown(), SystemMouseCursors.precise, reason: '⛔CONTROL');

    CanvasViewHold.held.value = ViewHold.values.first;
    await tester.pump();
    expect(shown(), SystemMouseCursors.grab);

    CanvasViewHold.held.value = null;
    await tester.pump();
    expect(shown(), SystemMouseCursors.precise);
  });

  testWidgets('a cursor the system wears costs the app no frame when the '
      'pointer moves; the outline does', (tester) async {
    choose(DrawingCursor.brush);
    await pumpPanel(tester);
    final mouse = await hover(tester, const Offset(40, 40));
    await mouse.moveTo(canvasGlobalOffset(tester, const Offset(60, 50)));
    expect(
      tester.binding.hasScheduledFrame,
      isTrue,
      reason: '⛔CONTROL: the outline moves in a frame of its own',
    );
    await tester.pump();

    choose(DrawingCursor.crosshair);
    await tester.pump();
    await mouse.moveTo(canvasGlobalOffset(tester, const Offset(80, 70)));
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('and a move under a cursor the system wears is not named as '
      'the cause of the next frame — it causes none', (tester) async {
    MeasurementMode.frameStats.value = true;
    addTearDown(MeasurementMode.reset);
    addTearDown(RepaintCause.reset);
    choose(DrawingCursor.brush);
    await pumpPanel(tester);
    final mouse = await hover(tester, const Offset(40, 40));
    RepaintCause.reset();
    await mouse.moveTo(canvasGlobalOffset(tester, const Offset(60, 50)));
    expect(
      RepaintCause.debugMarkedCause,
      'pointer',
      reason: '⛔CONTROL: the outline\'s move is marked',
    );
    await tester.pump();

    choose(DrawingCursor.crosshair);
    await tester.pump();
    RepaintCause.reset();
    await mouse.moveTo(canvasGlobalOffset(tester, const Offset(80, 70)));
    expect(RepaintCause.debugMarkedCause, isNull);
  });

  group('where the system shows no cursor (iPadOS) the app draws the one '
      'chosen, at one size', () {
    testWidgets('the crosshair', (tester) async {
      choose(DrawingCursor.crosshair);
      await pumpPanel(tester);
      await hover(tester, const Offset(40, 40));
      expect(shown(), SystemMouseCursors.none);
      expect(drawn(tester, crosshair), isTrue);
      expect(drawn(tester, outline), isFalse);
      final look = tester.widget<ToolCursorSprite>(find.byKey(crosshair)).look;
      expect(look.key, crosshairCursorLook().key);
      expect(look.painter, isA<BrushCursorPainter>());
      expect((look.painter as BrushCursorPainter).shape, isNull);
    }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

    testWidgets('the pen, whatever the brush\'s size', (tester) async {
      choose(DrawingCursor.pen);
      final brush = ValueNotifier(
        BrushToolState.defaults.copyWith(tool: CanvasTool.brush, size: 10),
      );
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
              brushToolState: brush,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await hover(tester, const Offset(40, 40));
      expect(shown(), SystemMouseCursors.none);
      expect(drawn(tester, pen), isTrue);
      final before = tester.widget<ToolCursorSprite>(find.byKey(pen)).look;
      expect(before.key, 'pen');

      brush.value = brush.value.copyWith(size: 200);
      await tester.pump();
      final after = tester.widget<ToolCursorSprite>(find.byKey(pen)).look;
      expect(after.extent, before.extent);
      expect(after.hotspot, before.hotspot);
    }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));
  });

  // ⚠️I-54 ⓔ: macOS, Android and Linux take a picture for their cursor only
  // through the runner, which is not built yet — until then the app draws
  // the pen there, as it does on iPadOS.
  testWidgets('where the system takes no picture, the app draws the pen', (
    tester,
  ) async {
    choose(DrawingCursor.pen);
    await pumpPanel(tester);
    await hover(tester, const Offset(40, 40));
    expect(shown(), SystemMouseCursors.none);
    expect(drawn(tester, pen), isTrue);
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  group('on Windows the pen is the system\'s cursor', () {
    late List<MethodCall> calls;

    void listen(WidgetTester tester) {
      calls = [];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.mouseCursor,
        (call) async {
          calls.add(call);
          if (call.method == 'createCustomCursor/windows') {
            return (call.arguments as Map<Object?, Object?>)['name'];
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.mouseCursor,
          null,
        ),
      );
    }

    Iterable<MethodCall> named(String method) =>
        calls.where((call) => call.method == method);

    // The picture is made by `toImage` and `toByteData`, which finish on the
    // real event loop, and what follows them in the fake one: [settleAsync]
    // lends it both clocks.

    testWidgets('🚨its pixels are handed over once a size, and named after '
        'that; the app draws nothing of its own', (tester) async {
      listen(tester);
      choose(DrawingCursor.pen);
      await pumpPanel(tester);
      await hover(tester, const Offset(40, 40));
      expect(shown(), const PenMouseCursor(devicePixelRatio: 3));
      expect(drawn(tester, pen), isFalse);
      expect(drawn(tester, outline), isFalse);

      await settleAsync(
        tester,
        () => named('setCustomCursor/windows').isNotEmpty,
      );
      final made = named('createCustomCursor/windows').single;
      final arguments = made.arguments as Map<Object?, Object?>;
      // 22 logical px at the test view's 3 screen px each.
      expect(arguments['width'], 66);
      expect(arguments['height'], 66);
      expect((arguments['buffer']! as Uint8List).length, 66 * 66 * 4);
      // The point, in the screen's pixels — doubles, as the engine reads.
      expect(arguments['hotX'], 9.0);
      expect(arguments['hotY'], 57.0);
      expect(
        (named('setCustomCursor/windows').single.arguments
            as Map<Object?, Object?>)['name'],
        arguments['name'],
      );

      // Away and back: named again, never made again.
      choose(DrawingCursor.crosshair);
      await tester.pump();
      choose(DrawingCursor.pen);
      await tester.pump();
      await settleAsync(
        tester,
        () => named('setCustomCursor/windows').length > 1,
      );
      expect(named('setCustomCursor/windows'), hasLength(2));
      expect(named('createCustomCursor/windows'), hasLength(1));
    }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

    testWidgets('🚨a cursor that came after the pen while its picture was '
        'being made keeps the system — the pen does not take it back', (
      tester,
    ) async {
      // A size of its own, so the picture is not already made.
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.resetDevicePixelRatio);
      listen(tester);
      choose(DrawingCursor.pen);
      await pumpPanel(tester);
      await hover(tester, const Offset(40, 40));
      expect(shown(), const PenMouseCursor(devicePixelRatio: 2));

      choose(DrawingCursor.crosshair);
      await tester.pump();
      expect(shown(), SystemMouseCursors.precise);

      await settleAsync(
        tester,
        () => named('createCustomCursor/windows').isNotEmpty,
      );
      // Time for a set to follow the making, were one coming.
      await lendBothClocks(tester, rounds: 10);
      expect(
        named('createCustomCursor/windows'),
        hasLength(1),
        reason: '⛔CONTROL: the picture was made',
      );
      expect(named('setCustomCursor/windows'), isEmpty);
      expect(
        (named('activateSystemCursor').last.arguments
            as Map<Object?, Object?>)['kind'],
        'precise',
      );
    }, variant: TargetPlatformVariant.only(TargetPlatform.windows));
  });

  test('the pixels go to Windows blue first, as it reads them', () {
    final rgba = ByteData.sublistView(
      Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8]),
    );
    expect(bgraOf(rgba), [3, 2, 1, 4, 7, 6, 5, 8]);
  });
}
