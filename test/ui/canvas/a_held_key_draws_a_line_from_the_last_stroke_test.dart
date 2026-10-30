import 'dart:ui' as ui;

import 'package:flutter/gestures.dart'
    show PointerDeviceKind, kSecondaryMouseButton;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart' show SchedulerBinding;
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/brush_dab.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_shape_kind.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/models/drawing_guide.dart';
import 'package:anicel/src/models/shape_tool_options.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/services/brush_frame_editing_coordinator.dart';
import 'package:anicel/src/services/canvas_color_sampler.dart';
import 'package:anicel/src/services/history_manager.dart';
import 'package:anicel/src/ui/brush/brush_canvas_panel.dart';
import 'package:anicel/src/ui/brush/brush_edit_cache_invalidation_sink.dart';
import 'package:anicel/src/ui/brush/brush_tool_state.dart';
import 'package:anicel/src/ui/brush/canvas_selection_commands.dart';
import 'package:anicel/src/ui/canvas/active_stroke_overlay.dart';
import 'package:anicel/src/ui/canvas/canvas_line_hold.dart';
import 'package:anicel/src/ui/canvas/interactive_brush_edit_canvas_view.dart'
    show debugStrokeDabsLaid;
import 'package:anicel/src/ui/canvas/selection_ants_painter.dart';

import '../../helpers/brush_canvas_fixture.dart';
import '../../helpers/device_viewport.dart';

/// 🗣️I-119 (유저 2026-10-21): 「브러시 도구(브러시,지우개) 전용기능, …
/// 누르고있으면 저번에 찍은 마지막 dab? 점 부터 현재 호버중인 커서까지
/// 라이브로 직선 보여주고(도형도구의 직선이랑 최대한 동일하게 로직 재사용.
/// 법 통일) 거기서 찍으면 직선 그림. 물론 쉬프트누르면 스냅 작동」 —
/// I-119-Q1: 「호버 중에도 실제 브러시 획까지」 · I-119-Q2: 「도중에 … 키를
/// 떼면 취소임. 호버하면서 위치 정하고, 클릭해야 직선 착지」.
///
/// The key is the shell's (`EditorKeyHolds`, pinned beside the pan's); the
/// canvas reads the hold it writes ([CanvasLineHold]). Everything here is
/// a real mouse: it hovers, presses and lets go over the panel.
void main() {
  const antsKey = ValueKey<String>('line-from-the-last-stroke-ants');
  const size = CanvasSize(width: 400, height: 300);

  tearDown(() => CanvasLineHold.held.value = false);

  Future<
    ({
      BrushFrameEditingCoordinator coordinator,
      HistoryManager history,
      ActiveStrokeOverlayModel overlay,
      ValueNotifier<BrushToolState> brush,
    })
  >
  pumpPanel(
    WidgetTester tester, {
    CutGuides? guides,
    ValueNotifier<bool>? rowTakesStrokes,
  }) async {
    final keys = BrushCanvasFixture.createFrameKeys();
    final coordinator = BrushCanvasFixture.createCoordinator(
      frameKeys: keys,
      canvasSize: size,
    );
    final history = HistoryManager();
    final overlay = ActiveStrokeOverlayModel();
    addTearDown(overlay.dispose);
    final brush = ValueNotifier(
      BrushToolState.defaults.copyWith(
        tool: CanvasTool.brush,
        // The shape tool set to its own plain line: the line from the last
        // stroke is a stroke of the tool in hand whatever that tool says.
        shapeOptions: const ShapeToolOptions(type: ShapeLineType.plain),
      ),
    );
    final viewport = seedFromRender(tester, CanvasViewport());
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ValueListenableBuilder<bool>(
            valueListenable: rowTakesStrokes ?? ValueNotifier(true),
            builder: (context, takes, _) => BrushCanvasPanel(
              coordinator: coordinator,
              canvasSize: size,
              availableFrameKeys: keys,
              cacheInvalidationSink: BrushEditCacheInvalidationSink(),
              historyManager: history,
              brushToolState: brush,
              selectionCommands: CanvasSelectionCommands(),
              guides: guides,
              viewport: viewport,
              rowAcceptsStrokes: takes,
              activeStrokeOverlayModel: overlay,
              viewportUnderlayBuilder: (context, viewport, painter, float) =>
                  painter == null
                  ? const SizedBox.shrink()
                  : CustomPaint(
                      painter: painter,
                      size: Size(
                        size.width.toDouble(),
                        size.height.toDouble(),
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    // The panel goes before its overlay does: the view resets the host's
    // overlay on its way out.
    addTearDown(() => tester.pumpWidget(const SizedBox()));
    return (
      coordinator: coordinator,
      history: history,
      overlay: overlay,
      brush: brush,
    );
  }

  Offset on(WidgetTester tester, Offset at) =>
      tester.getTopLeft(find.byKey(antsKey)) + at;

  Future<TestGesture> mouseAt(WidgetTester tester, Offset at) async {
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: on(tester, at));
    addTearDown(mouse.removePointer);
    await tester.pump();
    return mouse;
  }

  Future<void> hover(WidgetTester tester, TestGesture mouse, Offset at) async {
    await mouse.moveTo(on(tester, at));
    await tester.pump();
  }

  /// A stroke of the tool in hand from [from] to [to], let go there.
  Future<void> stroke(
    WidgetTester tester,
    TestGesture mouse,
    Offset from,
    Offset to,
  ) async {
    await mouse.moveTo(on(tester, from));
    await mouse.down(on(tester, from));
    await tester.pump();
    await mouse.moveTo(on(tester, to));
    await tester.pump();
    await mouse.up();
    await tester.pump();
  }

  /// A stroke of a pen held at [pressure] the whole way from [from] to
  /// [to], let go there.
  Future<void> penStroke(
    WidgetTester tester,
    Offset from,
    Offset to, {
    required double pressure,
  }) async {
    const pen = 77;
    var time = const Duration(seconds: 1);
    PointerEvent sample(Offset at, {required bool down}) {
      time += const Duration(milliseconds: 8);
      return down
          ? PointerDownEvent(
              pointer: pen,
              kind: PointerDeviceKind.stylus,
              position: on(tester, at),
              timeStamp: time,
              pressure: pressure,
              pressureMin: 0,
              pressureMax: 1,
            )
          : PointerMoveEvent(
              pointer: pen,
              kind: PointerDeviceKind.stylus,
              position: on(tester, at),
              timeStamp: time,
              pressure: pressure,
              pressureMin: 0,
              pressureMax: 1,
            );
    }

    tester.binding.handlePointerEvent(sample(from, down: true));
    await tester.pump();
    for (var step = 1; step <= 4; step += 1) {
      tester.binding.handlePointerEvent(
        sample(Offset.lerp(from, to, step / 4)!, down: false),
      );
      await tester.pump();
    }
    tester.binding.handlePointerEvent(
      PointerUpEvent(
        pointer: pen,
        kind: PointerDeviceKind.stylus,
        position: on(tester, to),
        timeStamp: time + const Duration(milliseconds: 8),
      ),
    );
    await tester.pump();
  }

  /// A tap of a pen pressed at [pressure], at [at].
  Future<void> penTap(
    WidgetTester tester,
    Offset at, {
    required double pressure,
  }) async {
    const pen = 78;
    tester.binding.handlePointerEvent(
      PointerDownEvent(
        pointer: pen,
        kind: PointerDeviceKind.stylus,
        position: on(tester, at),
        pressure: pressure,
        pressureMin: 0,
        pressureMax: 1,
      ),
    );
    await tester.pump();
    tester.binding.handlePointerEvent(
      PointerUpEvent(
        pointer: pen,
        kind: PointerDeviceKind.stylus,
        position: on(tester, at),
      ),
    );
    await tester.pump();
  }

  /// A click where the mouse is.
  Future<void> click(WidgetTester tester, TestGesture mouse, Offset at) async {
    await mouse.moveTo(on(tester, at));
    await mouse.down(on(tester, at));
    await tester.pump();
    await mouse.up();
    await tester.pump();
  }

  Future<void> holdTheKey(WidgetTester tester, bool held) async {
    CanvasLineHold.held.value = held;
    await tester.pump();
  }

  Future<void> untilShown(
    WidgetTester tester,
    ActiveStrokeOverlayModel overlay,
  ) async {
    for (var frame = 0; frame < 400 && !overlay.hasStrokeContent; frame++) {
      await tester.pump();
    }
  }

  /// What the ants draw: the line and every copy of it.
  List<List<CanvasPoint>> antsOf(WidgetTester tester) {
    final paint = tester.widget<CustomPaint>(
      find
          .descendant(of: find.byKey(antsKey), matching: find.byType(CustomPaint))
          .first,
    );
    return (paint.painter! as SelectionAntsPainter).openTrails;
  }

  List<CanvasPoint> line(Offset from, Offset to) => [
    CanvasPoint(x: from.dx, y: from.dy),
    CanvasPoint(x: to.dx, y: to.dy),
  ];

  BitmapSurface celOf(BrushFrameEditingCoordinator coordinator) =>
      coordinator.currentSurfaceOf(coordinator.activeFrameKey);

  int alphaAt(BrushFrameEditingCoordinator coordinator, int x, int y) =>
      (surfacePixelRgba(celOf(coordinator), x, y) ?? 0) & 0xFF;

  /// The alpha [overlay] SHOWS over each tile it pictures, off its pictures.
  Future<Map<TileCoord, List<int>>> shownAlphas(
    WidgetTester tester,
    ActiveStrokeOverlayModel overlay,
  ) async {
    final shown = <TileCoord, List<int>>{};
    for (final MapEntry(key: coord, value: picture)
        in overlay.tileImages.entries) {
      final data = await tester.runAsync(
        () => picture.toByteData(format: ui.ImageByteFormat.rawRgba),
      );
      final bytes = data!.buffer.asUint8List();
      shown[coord] = [for (var i = 3; i < bytes.length; i += 4) bytes[i]];
    }
    return shown;
  }

  /// Where the cel's alpha parts from [shown] — a tile and a pixel — or null.
  String? whereTheCelParts(
    BrushFrameEditingCoordinator coordinator,
    Map<TileCoord, List<int>> shown,
  ) {
    final cel = celOf(coordinator);
    for (final MapEntry(key: coord, value: alphas) in shown.entries) {
      final pixels = cel.tileAt(coord)?.pixels;
      for (var i = 0; i < alphas.length; i += 1) {
        final landed = pixels == null ? 0 : pixels[i * 4 + 3];
        if (landed != alphas[i]) {
          return '$coord pixel $i: shown ${alphas[i]}, landed $landed';
        }
      }
    }
    return null;
  }

  /// The first tile where [a] and [b] part, or null.
  TileCoord? firstDifference(BitmapSurface a, BitmapSurface b) {
    for (final coord in {...a.tiles.keys, ...b.tiles.keys}) {
      final ta = a.tileAt(coord)?.pixels;
      final tb = b.tileAt(coord)?.pixels;
      if (ta == null || tb == null) {
        if ((ta ?? tb)!.any((byte) => byte != 0)) {
          return coord;
        }
        continue;
      }
      for (var i = 0; i < ta.length; i += 1) {
        if (ta[i] != tb[i]) {
          return coord;
        }
      }
    }
    return null;
  }

  const strokeFrom = Offset(50, 50);
  const strokeEnd = Offset(120, 60);
  const hand = Offset(300, 200);

  testWidgets('held, the line runs from where the last stroke ended to the '
      'hovering hand — the ants over the stroke itself — and nothing lands '
      'until a click', (tester) async {
    final env = await pumpPanel(tester);
    final mouse = await mouseAt(tester, const Offset(10, 10));
    await stroke(tester, mouse, strokeFrom, strokeEnd);
    final steps = env.history.undoCount;
    final before = celOf(env.coordinator);
    expect(alphaAt(env.coordinator, 50, 50), isNonZero, reason: 'fixture');

    await holdTheKey(tester, true);
    await hover(tester, mouse, hand);
    await untilShown(tester, env.overlay);

    expect(antsOf(tester), [line(strokeEnd, hand)]);
    expect(env.overlay.hasStrokeContent, isTrue, reason: 'the stroke shows');
    expect(
      SchedulerBinding.instance.transientCallbackCount,
      isPositive,
      reason: 'the ants march, as the shape tool\'s do',
    );
    expect(env.history.undoCount, steps, reason: 'nothing landed');
    expect(firstDifference(celOf(env.coordinator), before), isNull);
  });

  testWidgets('a click lands it — one step back, the very bytes the shape '
      'tool\'s line of the brush lays from that end to that point', (
    tester,
  ) async {
    final env = await pumpPanel(tester);
    final mouse = await mouseAt(tester, const Offset(10, 10));
    await stroke(tester, mouse, strokeFrom, strokeEnd);
    final steps = env.history.undoCount;

    await holdTheKey(tester, true);
    await hover(tester, mouse, hand);
    await untilShown(tester, env.overlay);
    final shown = await shownAlphas(tester, env.overlay);
    await click(tester, mouse, hand);

    expect(env.overlay.hasStrokeContent, isFalse, reason: 'it has landed');
    // The shape tool here lays its own plain line, and the show is still
    // the stroke the click lands — not the tool's (I-69-Q4ⓒ: shown as it
    // will land).
    expect(shown, isNotEmpty, reason: '⛔premise: the line showed');
    expect(whereTheCelParts(env.coordinator, shown), isNull);
    expect(env.history.undoCount, steps + 1, reason: 'one step back');
    expect(antsOf(tester), isEmpty, reason: 'the hand rests on its end');
    expect(alphaAt(env.coordinator, 210, 130), isNonZero, reason: 'midway');
    final landed = celOf(env.coordinator);

    // The same stroke, then the shape tool's line of the brush dragged from
    // that end to that point — on a panel of its own, by the same mouse.
    await holdTheKey(tester, false);
    await tester.pumpWidget(const SizedBox());
    final twin = await pumpPanel(tester);
    await stroke(tester, mouse, strokeFrom, strokeEnd);
    twin.brush.value = twin.brush.value.copyWith(
      tool: CanvasTool.shape,
      drawShape: CanvasShapeKind.line,
      shapeOptions: const ShapeToolOptions(type: ShapeLineType.brush),
    );
    await tester.pump();
    await stroke(tester, mouse, strokeEnd, hand);

    expect(firstDifference(celOf(twin.coordinator), landed), isNull);
  });

  testWidgets('the line landed is the last stroke: the next one runs from '
      'its end', (tester) async {
    await pumpPanel(tester);
    final mouse = await mouseAt(tester, const Offset(10, 10));
    await stroke(tester, mouse, strokeFrom, strokeEnd);
    await holdTheKey(tester, true);
    await click(tester, mouse, hand);

    const next = Offset(300, 280);
    await hover(tester, mouse, next);
    expect(antsOf(tester), [line(hand, next)]);
  });

  // 🗣️F-483 (유저 2026-10-27): 「마지막 찍은 필압 기준으로 직선 그리도록」.
  testWidgets('🚨the line is laid at the pressure the last stroke\'s last dab '
      'was laid at — shown and landed alike', (tester) async {
    final env = await pumpPanel(tester);
    final mouse = await mouseAt(tester, const Offset(10, 10));
    final laid = debugStrokeDabsLaid = <BrushDab>[];
    addTearDown(() => debugStrokeDabsLaid = null);
    await penStroke(tester, strokeFrom, strokeEnd, pressure: 0.3);
    final pressed = laid.last.pressure;
    expect(pressed, lessThan(0.9), reason: '⛔premise: the pen pressed light');

    laid.clear();
    await holdTheKey(tester, true);
    await hover(tester, mouse, hand);
    await untilShown(tester, env.overlay);
    expect(laid, isNotEmpty, reason: '⛔premise: the line showed');
    expect({for (final dab in laid) dab.pressure}, {pressed}, reason: 'shown');

    laid.clear();
    await click(tester, mouse, hand);
    expect(env.overlay.hasStrokeContent, isFalse, reason: 'it has landed');
    expect(laid, isEmpty, reason: 'it lands what was shown, laid as it was');
  });

  // 🗣️F-513 (유저 2026-10-30): 「z로 찍는건 그 기준에 안들어가서 … z로 찍다가
  // 중간에 마우스로 찍고 다시z누르면 진해져있어야하는데」.
  testWidgets('🚨the click that lands a line is the next line\'s press: a '
      'mouse\'s, after a light pen, lays the next one at full', (
    tester,
  ) async {
    final env = await pumpPanel(tester);
    final mouse = await mouseAt(tester, const Offset(10, 10));
    final laid = debugStrokeDabsLaid = <BrushDab>[];
    addTearDown(() => debugStrokeDabsLaid = null);
    await penStroke(tester, strokeFrom, strokeEnd, pressure: 0.3);
    final pressed = laid.last.pressure;
    expect(pressed, lessThan(0.9), reason: '⛔premise: the pen pressed light');

    await holdTheKey(tester, true);
    await hover(tester, mouse, hand);
    await untilShown(tester, env.overlay);
    laid.clear();
    await click(tester, mouse, hand);
    expect(env.overlay.hasStrokeContent, isFalse, reason: '⛔premise: landed');

    await hover(tester, mouse, const Offset(300, 280));
    await untilShown(tester, env.overlay);
    expect({for (final dab in laid) dab.pressure}, {1.0});
  });

  testWidgets('a run of lines landed by a pen: each is laid at the tap that '
      'landed the one before', (tester) async {
    final env = await pumpPanel(tester);
    final mouse = await mouseAt(tester, const Offset(10, 10));
    final laid = debugStrokeDabsLaid = <BrushDab>[];
    addTearDown(() => debugStrokeDabsLaid = null);
    await penStroke(tester, strokeFrom, strokeEnd, pressure: 0.3);
    await holdTheKey(tester, true);

    Future<Set<double>> nextLineAt(Offset at) async {
      laid.clear();
      await hover(tester, mouse, at);
      await untilShown(tester, env.overlay);
      return {for (final dab in laid) dab.pressure};
    }

    expect(await nextLineAt(hand), {0.3}, reason: '⛔premise: the stroke\'s');
    await penTap(tester, hand, pressure: 0.6);
    expect(await nextLineAt(const Offset(300, 280)), {0.6});
    await penTap(tester, const Offset(300, 280), pressure: 0.9);
    expect(await nextLineAt(const Offset(200, 250)), {0.9});
  });

  testWidgets('a click that lands nothing is no start: the next stroke is '
      'laid at its own pen', (tester) async {
    final takes = ValueNotifier(true);
    addTearDown(takes.dispose);
    final env = await pumpPanel(tester, rowTakesStrokes: takes);
    final mouse = await mouseAt(tester, const Offset(10, 10));
    final laid = debugStrokeDabsLaid = <BrushDab>[];
    addTearDown(() => debugStrokeDabsLaid = null);
    await penStroke(tester, strokeFrom, strokeEnd, pressure: 0.3);
    final steps = env.history.undoCount;

    takes.value = false;
    await holdTheKey(tester, true);
    await hover(tester, mouse, hand);
    expect(antsOf(tester), isNotEmpty, reason: '⛔premise: the line is up');
    await click(tester, mouse, hand);
    expect(antsOf(tester), isEmpty, reason: '⛔premise: the line\'s press');
    expect(env.history.undoCount, steps, reason: '⛔premise: nothing landed');

    takes.value = true;
    await holdTheKey(tester, false);
    await penStroke(
      tester,
      const Offset(60, 200),
      const Offset(150, 220),
      pressure: 0.5,
    );
    await holdTheKey(tester, true);
    laid.clear();
    await hover(tester, mouse, const Offset(300, 280));
    await untilShown(tester, env.overlay);
    expect({for (final dab in laid) dab.pressure}, {0.5});
  });

  testWidgets('the key let go takes it back, and nothing lands', (
    tester,
  ) async {
    final env = await pumpPanel(tester);
    final mouse = await mouseAt(tester, const Offset(10, 10));
    await stroke(tester, mouse, strokeFrom, strokeEnd);
    final steps = env.history.undoCount;
    final before = celOf(env.coordinator);
    await holdTheKey(tester, true);
    await hover(tester, mouse, hand);
    await untilShown(tester, env.overlay);
    expect(env.overlay.hasStrokeContent, isTrue, reason: '⛔premise');

    await holdTheKey(tester, false);
    expect(antsOf(tester), isEmpty);
    expect(
      SchedulerBinding.instance.transientCallbackCount,
      0,
      reason: 'and the ants stop with them',
    );
    expect(env.overlay.hasStrokeContent, isFalse);
    expect(env.history.undoCount, steps);
    expect(firstDifference(celOf(env.coordinator), before), isNull);
  });

  testWidgets('let go of the key mid-click, the click lands nothing — and the '
      'press was the line\'s, so it draws nothing either', (tester) async {
    final env = await pumpPanel(tester);
    final mouse = await mouseAt(tester, const Offset(10, 10));
    await stroke(tester, mouse, strokeFrom, strokeEnd);
    final steps = env.history.undoCount;
    await holdTheKey(tester, true);
    await hover(tester, mouse, hand);

    await mouse.down(on(tester, hand));
    await tester.pump();
    await holdTheKey(tester, false);
    await mouse.up();
    await tester.pump();

    expect(env.history.undoCount, steps);
    expect(alphaAt(env.coordinator, 210, 130), 0);
    expect(alphaAt(env.coordinator, 300, 200), 0);
  });

  testWidgets('a click of another button lands no line', (tester) async {
    final env = await pumpPanel(tester);
    // One mouse at a time: the left one draws the stroke and goes.
    final left = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await left.addPointer(location: on(tester, const Offset(10, 10)));
    await stroke(tester, left, strokeFrom, strokeEnd);
    await left.removePointer();
    final steps = env.history.undoCount;
    await holdTheKey(tester, true);

    final right = await tester.createGesture(
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryMouseButton,
    );
    await right.addPointer(location: on(tester, const Offset(10, 10)));
    addTearDown(right.removePointer);
    await hover(tester, right, hand);
    expect(antsOf(tester), [line(strokeEnd, hand)], reason: '⛔premise');
    await right.down(on(tester, hand));
    await tester.pump();
    await right.up();
    await tester.pump();

    expect(env.history.undoCount, steps);
    expect(alphaAt(env.coordinator, 210, 130), 0);
  });

  testWidgets('「물론 쉬프트누르면 스냅 작동」: with Shift the line keeps to the '
      'shape tool\'s eight ways, and lands so', (tester) async {
    final env = await pumpPanel(tester);
    final mouse = await mouseAt(tester, const Offset(10, 10));
    await stroke(tester, mouse, strokeFrom, strokeEnd);
    await holdTheKey(tester, true);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await hover(tester, mouse, const Offset(300, 75));
    expect(antsOf(tester), [line(strokeEnd, const Offset(300, 60))]);
    await click(tester, mouse, const Offset(300, 75));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);

    expect(alphaAt(env.coordinator, 250, 60), isNonZero, reason: 'level');
    expect(alphaAt(env.coordinator, 299, 75), 0, reason: 'not to the hand');
  });

  testWidgets('the eraser runs the same line, and erases along it', (
    tester,
  ) async {
    final env = await pumpPanel(tester);
    final mouse = await mouseAt(tester, const Offset(10, 10));
    await stroke(tester, mouse, const Offset(50, 100), const Offset(300, 100));
    final inked = alphaAt(env.coordinator, 175, 100);
    expect(inked, isNonZero, reason: 'fixture');

    env.brush.value = env.brush.value.copyWith(tool: CanvasTool.eraser);
    await tester.pump();
    await holdTheKey(tester, true);
    await hover(tester, mouse, const Offset(50, 100));
    expect(antsOf(tester), [
      line(const Offset(300, 100), const Offset(50, 100)),
    ]);
    await click(tester, mouse, const Offset(50, 100));

    expect(alphaAt(env.coordinator, 175, 100), lessThan(inked));
  });

  testWidgets('a tool that does not paint has no line: switched to one, the '
      'line goes; switched back, it comes back where the hand is', (
    tester,
  ) async {
    final env = await pumpPanel(tester);
    final mouse = await mouseAt(tester, const Offset(10, 10));
    await stroke(tester, mouse, strokeFrom, strokeEnd);
    await holdTheKey(tester, true);
    await hover(tester, mouse, hand);
    await untilShown(tester, env.overlay);

    env.brush.value = env.brush.value.copyWith(tool: CanvasTool.eyedropper);
    await tester.pump();
    expect(antsOf(tester), isEmpty);
    expect(env.overlay.hasStrokeContent, isFalse);

    env.brush.value = env.brush.value.copyWith(tool: CanvasTool.brush);
    await tester.pump();
    expect(antsOf(tester), [line(strokeEnd, hand)]);
  });

  testWidgets('with no stroke yet there is no line to show: held, a click '
      'draws as it always does — and that stroke starts the next line', (
    tester,
  ) async {
    final env = await pumpPanel(tester);
    final mouse = await mouseAt(tester, const Offset(10, 10));
    await holdTheKey(tester, true);
    await hover(tester, mouse, const Offset(80, 80));
    expect(antsOf(tester), isEmpty);

    await click(tester, mouse, const Offset(80, 80));
    expect(alphaAt(env.coordinator, 80, 80), isNonZero, reason: 'a dot');

    await hover(tester, mouse, const Offset(200, 80));
    expect(antsOf(tester), [line(const Offset(80, 80), const Offset(200, 80))]);
  });

  testWidgets('a key that goes down under a pen already drawing shows no '
      'line until that stroke is down — and runs from where it ended', (
    tester,
  ) async {
    final env = await pumpPanel(tester);
    final mouse = await mouseAt(tester, const Offset(10, 10));
    await stroke(tester, mouse, strokeFrom, strokeEnd);

    await mouse.moveTo(on(tester, const Offset(50, 150)));
    await mouse.down(on(tester, const Offset(50, 150)));
    await tester.pump();
    await mouse.moveTo(on(tester, const Offset(100, 150)));
    await tester.pump();
    await holdTheKey(tester, true);
    await mouse.moveTo(on(tester, const Offset(150, 150)));
    await tester.pump();
    expect(antsOf(tester), isEmpty, reason: 'the pen is drawing');
    await mouse.up();
    await tester.pump();
    expect(alphaAt(env.coordinator, 125, 150), isNonZero, reason: 'drawn');

    await hover(tester, mouse, const Offset(150, 250));
    expect(antsOf(tester), [
      line(const Offset(150, 150), const Offset(150, 250)),
    ]);
  });

  testWidgets('with a mirror the line starts where the HAND\'s stroke ended '
      '— not its copy\'s, whose dabs come last — and the ants show every '
      'copy, as the shape tool\'s do', (tester) async {
    // A vertical mirror down the middle of the canvas: x → 400 − x.
    final guide = DrawingGuide(
      id: const GuideId('mirror'),
      name: 'Mirror',
      shape: SymmetryShape(
        axis: GuideAxis(origin: CanvasPoint(x: 200, y: 150), angleDegrees: 90),
        lineCount: 2,
      ),
    );
    await pumpPanel(
      tester,
      guides: CutGuides(guides: [guide], activeSymmetryId: guide.id),
    );
    final mouse = await mouseAt(tester, const Offset(10, 10));
    await stroke(tester, mouse, strokeFrom, strokeEnd);
    await holdTheKey(tester, true);
    await hover(tester, mouse, hand);

    // The mirror's carry rounds in the last bit; the hand's own is exact.
    final ants = antsOf(tester);
    expect(ants.first, line(strokeEnd, hand));
    expect(
      [
        for (final trail in ants)
          [
            for (final point in trail)
              Offset(point.x.roundToDouble(), point.y.roundToDouble()),
          ],
      ],
      [
        [strokeEnd, hand],
        [const Offset(280, 60), const Offset(100, 200)],
      ],
    );
  });

  testWidgets('a stroke that lands by the buffer — its overlay gone under '
      'it — still says where it ended', (tester) async {
    final env = await pumpPanel(tester);
    final mouse = await mouseAt(tester, const Offset(10, 10));
    await mouse.moveTo(on(tester, strokeFrom));
    await mouse.down(on(tester, strokeFrom));
    await tester.pump();
    await mouse.moveTo(on(tester, strokeEnd));
    await tester.pump();
    // The overlay's base goes, so the pen-up cannot install promoted tiles
    // and commits the stroke's buffer instead.
    env.overlay.reset();
    await mouse.up();
    await tester.pump();
    expect(alphaAt(env.coordinator, 50, 50), isNonZero, reason: 'fixture');

    await holdTheKey(tester, true);
    await hover(tester, mouse, hand);
    expect(antsOf(tester), [line(strokeEnd, hand)]);
  });
}
