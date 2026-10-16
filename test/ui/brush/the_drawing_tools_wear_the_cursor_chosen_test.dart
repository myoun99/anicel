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

  testWidgets('🚨F-285: a box floating over the tools with no cursor of its '
      'own (the standing row\'s) wears the tool\'s — the system\'s arrow '
      'never shows beside the app\'s', (tester) async {
    var boxPresses = 0;
    await pumpPanel(
      tester,
      // As the camera row's box does: it takes the whole canvas's presses.
      controls: (context, viewport) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => boxPresses++,
        child: const SizedBox.expand(),
      ),
    );
    final mouse = await hover(tester, const Offset(40, 40));
    await mouse.down(canvasGlobalOffset(tester, const Offset(40, 40)));
    await mouse.up();
    await tester.pump();
    expect(boxPresses, 1, reason: '⛔CONTROL: the box is over the tools');

    expect(shown(), SystemMouseCursors.none, reason: 'the outline is up');
    expect(drawn(tester, outline), isTrue);

    choose(DrawingCursor.crosshair);
    await tester.pump();
    expect(shown(), SystemMouseCursors.precise);
  });

  testWidgets('the view hold\'s hand lies deeper than the tool\'s cursor, and '
      'wins for as long as it is held', (tester) async {
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

    /// Lets the picture be made: `toImage` and `toByteData` finish on the
    /// real event loop, and what follows them in the fake one.
    Future<void> settle(
      WidgetTester tester,
      bool Function() done, {
      int rounds = 50,
    }) async {
      for (var i = 0; i < rounds && !done(); i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
      }
    }

    testWidgets('🚨its pixels are handed over once a size, and named after '
        'that; the app draws nothing of its own', (tester) async {
      listen(tester);
      choose(DrawingCursor.pen);
      await pumpPanel(tester);
      await hover(tester, const Offset(40, 40));
      expect(shown(), const PenMouseCursor(devicePixelRatio: 3));
      expect(drawn(tester, pen), isFalse);
      expect(drawn(tester, outline), isFalse);

      await settle(tester, () => named('setCustomCursor/windows').isNotEmpty);
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
      await settle(tester, () => named('setCustomCursor/windows').length > 1);
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

      await settle(
        tester,
        () => named('createCustomCursor/windows').isNotEmpty,
      );
      // Time for a set to follow the making, were one coming.
      await settle(tester, () => false, rounds: 10);
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
