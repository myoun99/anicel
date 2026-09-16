import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/gestures.dart'
    show kMiddleMouseButton, kPrimaryButton, kSecondaryMouseButton;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import '../helpers/device_viewport.dart';
import 'package:anicel/src/models/brush_blend_mode.dart';
import 'package:anicel/src/models/brush_dab.dart';
import 'package:anicel/src/models/brush_stamp_image.dart';
import 'package:anicel/src/models/brush_tip_shape.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/models/cut_piece.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/services/brush_frame_editing_coordinator.dart';
import 'package:anicel/src/services/canvas_color_sampler.dart';
import 'package:anicel/src/services/cut_piece_slot.dart';
import 'package:anicel/src/ui/brush/brush_canvas_panel.dart';
import 'package:anicel/src/ui/brush/brush_edit_cache_invalidation_sink.dart';
import 'package:anicel/src/ui/brush/brush_tool_state.dart';
import 'package:anicel/src/ui/canvas/brush_edit_canvas_view.dart';
import 'package:anicel/src/ui/canvas/canvas_pan_hold.dart';
import 'package:anicel/src/ui/canvas/interactive_brush_edit_canvas_view.dart';
import 'package:anicel/src/models/app_input_settings.dart';

import '../helpers/brush_canvas_fixture.dart';
import 'brush_canvas_test_helpers.dart';

/// P5/P6 tool routing: the non-painting tools mount ONE tap layer above
/// the canvas (no stroke may start), the eyedropper reports through the
/// pick handlers and the fill commits its dab through the stroke funnel.
void main() {
  const tapLayerKey = ValueKey<String>('canvas-tool-tap-layer');

  BrushDab fillDab(int color) => BrushDab(
    center: CanvasPoint(x: 4, y: 4),
    color: color,
    size: 8,
    opacity: 1,
    flow: 1,
    hardness: 1,
    tipShape: BrushTipShape.square,
    pressure: 1,
    sequence: 0,
  );

  Widget app(Widget panel) => MaterialApp(home: Scaffold(body: panel));

  int inkAt(BrushFrameEditingCoordinator coordinator, int x, int y) =>
      surfacePixelRgba(
        coordinator.currentSurfaceOf(coordinator.activeFrameKey),
        x,
        y,
      ) ??
      0;

  /// H29 — 유저 2026-08-27, iPhone: 「필 툴인 채로 3손가락 핑거로 redo는 잘
  /// 작동하는데 undo가 작동안함. 브러시툴에서는 잘 작동함. 1핑거 플립모드로
  /// 전환하면 또 잘 작동함」(뒤에 정정: 「언두는 2핑거였어」).
  ///
  /// The two-finger undo tap put its FIRST finger down, the fill committed a
  /// history entry nobody asked for, and the undo spent itself on that.
  ///
  /// The law was already in the view for STROKES — a second finger discards a
  /// touch stroke that has not passed slop, "the first finger turned out to
  /// be the start of a pinch" — which is exactly why the brush tool worked
  /// and the fill did not. These pin the fill obeying the same law.
  group('H29: a fill tap that turns out to be a pinch never happens', () {
    // 🚨SAVE and restore, ⛔never assign a fresh default back. `AppInput` is
    // a global: writing `const AppInputSettings()` in the teardown does not
    // undo this group, it overwrites whatever the suite had set up, and the
    // tests after it in this very file went red for reasons that had
    // nothing to do with them.
    late AppInputSettings savedInput;
    setUp(() {
      savedInput = AppInput.settings.value;
      AppInput.settings.value = savedInput.copyWith(
        touchDragOneFinger: CanvasTouchDragAction.draw,
      );
    });
    tearDown(() {
      AppInput.settings.value = savedInput;
    });

    Future<BrushFrameEditingCoordinator> pumpFill(WidgetTester tester) async {
      final frameKeys = BrushCanvasFixture.createFrameKeys();
      final coordinator = BrushCanvasFixture.createCoordinator(
        frameKeys: frameKeys,
      );
      await tester.pumpWidget(
        app(
          BrushCanvasPanel(
            coordinator: coordinator,
            availableFrameKeys: frameKeys,
            cacheInvalidationSink: BrushEditCacheInvalidationSink(),
            brushToolState: BrushToolState.defaults.copyWith(
              tool: CanvasTool.fill,
            ),
            fillDabAt: (_, color, _) => fillDab(color),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(AppInput.touchDraws, isTrue, reason: '터치 묘화 on — 유저 상태');
      return coordinator;
    }

    Offset canvasAt(WidgetTester tester, Offset local) =>
        tester.getTopLeft(
          find.byKey(const ValueKey<String>('brush-canvas-view')),
        ) +
        local;

    testWidgets('ONE finger, down and up: the fill lands', (tester) async {
      final coordinator = await pumpFill(tester);
      final finger = await tester.startGesture(
        canvasAt(tester, const Offset(4, 4)),
        kind: PointerDeviceKind.touch,
      );
      await tester.pump();
      await finger.up();
      await tester.pumpAndSettle();

      expect(
        inkAt(coordinator, 4, 4),
        isNonZero,
        reason: 'a lone tap is the fill\'s own gesture — it fills',
      );
    });

    testWidgets('a PEN fill retires a resting finger\'s armed tap — one '
        'intent, one fill', (tester) async {
      final frameKeys = BrushCanvasFixture.createFrameKeys();
      final coordinator = BrushCanvasFixture.createCoordinator(
        frameKeys: frameKeys,
      );
      var fills = 0;
      await tester.pumpWidget(
        app(
          BrushCanvasPanel(
            coordinator: coordinator,
            availableFrameKeys: frameKeys,
            cacheInvalidationSink: BrushEditCacheInvalidationSink(),
            brushToolState: BrushToolState.defaults.copyWith(
              tool: CanvasTool.fill,
            ),
            // 🚨Each fill lands somewhere ELSE, so a second one cannot hide
            // under the first. ⛔Not the seed point — the canvas is 2340px
            // wide inside a small viewport, so a local offset is nowhere
            // near the canvas coordinate of the same name.
            fillDabAt: (_, color, _) => fillDab(color).copyWith(
              center: CanvasPoint(x: 4 + 20.0 * fills++, y: 4),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // A finger resting on the glass arms a tap of its own on touchdown.
      final resting = await tester.startGesture(
        canvasAt(tester, const Offset(4, 4)),
        kind: PointerDeviceKind.touch,
      );
      await tester.pump();
      // The pen fills somewhere else while it rests.
      await tester.tapAt(
        canvasAt(tester, const Offset(20, 4)),
        kind: PointerDeviceKind.stylus,
      );
      await tester.pumpAndSettle();
      expect(inkAt(coordinator, 4, 4), isNonZero, reason: 'the pen filled');

      // ⛔And the rest lifting must not fill a second time.
      await resting.up();
      await tester.pumpAndSettle();
      expect(
        inkAt(coordinator, 24, 4),
        0,
        reason: 'a palm rest is not a second fill',
      );
    });

    testWidgets('a SECOND finger joins before the lift: nothing is filled '
        'and nothing enters history', (tester) async {
      final coordinator = await pumpFill(tester);
      // Exactly the shape of a two-finger undo: one finger lands, the other
      // follows, both lift.
      final first = await tester.startGesture(
        canvasAt(tester, const Offset(4, 4)),
        kind: PointerDeviceKind.touch,
      );
      await tester.pump();
      final second = await tester.startGesture(
        canvasAt(tester, const Offset(12, 4)),
        kind: PointerDeviceKind.touch,
      );
      await tester.pump();
      await first.up();
      await second.up();
      await tester.pumpAndSettle();

      // 🚨The raster, not a flag. The bug was a REAL commit — an undo entry
      // the user never asked for, which their next undo then spent itself
      // on. ⛔And 「filled, then reverted」 would fail here too, which is the
      // point: nothing may be drawn at any moment of this gesture.
      expect(
        inkAt(coordinator, 4, 4),
        0,
        reason: '유저의 2핑거 언두가 자기 필을 되돌리느라 소모됐다 — 애초에 '
            '칠하지 않는 것이 답이다',
      );
    });
  });

  testWidgets('the bucket on the erase blend REMOVES ink', (tester) async {
    // The other half of 유저 확정 ③ (erase is in the blend list), and the
    // half that is easy to leave behind: this path builds its commit in
    // the interactive VIEW while the shape fill builds its own in the
    // panel. Erase rides a flag on the DAB, so passing only the blend mode
    // would paint the flooded region instead of clearing it — asserted on
    // the raster, because a flag can be set and still not erase.
    final frameKeys = BrushCanvasFixture.createFrameKeys();
    final coordinator = BrushCanvasFixture.createCoordinator(
      frameKeys: frameKeys,
    );
    coordinator.commitSourceStroke(
      sourceDabs: [
        for (var x = 0; x <= 12; x += 2)
          fillDab(
            0xFF000000,
          ).copyWith(center: CanvasPoint(x: x.toDouble(), y: 4)),
      ],
    );
    expect(inkAt(coordinator, 4, 4), isNonZero, reason: 'ink to erase');

    await tester.pumpWidget(
      app(
        BrushCanvasPanel(
          coordinator: coordinator,
          availableFrameKeys: frameKeys,
          cacheInvalidationSink: BrushEditCacheInvalidationSink(),
          brushToolState: BrushToolState.defaults.copyWith(
            tool: CanvasTool.fill,
            fillBlendMode: BrushBlendMode.erase,
          ),
          fillDabAt: (_, color, _) => fillDab(color),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tapAt(
      tester.getTopLeft(
            find.byKey(const ValueKey<String>('brush-canvas-view')),
          ) +
          const Offset(4, 4),
    );
    await tester.pumpAndSettle();

    expect(inkAt(coordinator, 4, 4), 0, reason: 'the ink is gone');
  });

  testWidgets('painting tools mount no tap layer', (tester) async {
    final frameKeys = BrushCanvasFixture.createFrameKeys();
    await tester.pumpWidget(
      app(
        BrushCanvasPanel(
          coordinator: BrushCanvasFixture.createCoordinator(
            frameKeys: frameKeys,
          ),
          availableFrameKeys: frameKeys,
          cacheInvalidationSink: BrushEditCacheInvalidationSink(),
          sampleColorAt: (_) => 0xFF123456,
          onEyedropperPick: (_) {},
          fillDabAt: (_, color, _) => fillDab(color),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(tapLayerKey), findsNothing);
  });

  testWidgets('the eyedropper without handlers mounts no tap layer', (
    tester,
  ) async {
    final frameKeys = BrushCanvasFixture.createFrameKeys();
    await tester.pumpWidget(
      app(
        BrushCanvasPanel(
          coordinator: BrushCanvasFixture.createCoordinator(
            frameKeys: frameKeys,
          ),
          availableFrameKeys: frameKeys,
          cacheInvalidationSink: BrushEditCacheInvalidationSink(),
          brushToolState: BrushToolState.defaults.copyWith(
            tool: CanvasTool.eyedropper,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(tapLayerKey), findsNothing);
  });

  testWidgets('an eyedropper tap picks the sampled color, no stroke', (
    tester,
  ) async {
    final frameKeys = BrushCanvasFixture.createFrameKeys();
    final coordinator = BrushCanvasFixture.createCoordinator(
      frameKeys: frameKeys,
    );
    final sampledPoints = <CanvasPoint>[];
    final picks = <int>[];

    await tester.pumpWidget(
      app(
        BrushCanvasPanel(
          coordinator: coordinator,
          availableFrameKeys: frameKeys,
          cacheInvalidationSink: BrushEditCacheInvalidationSink(),
          brushToolState: BrushToolState.defaults.copyWith(
            tool: CanvasTool.eyedropper,
          ),
          sampleColorAt: (point) {
            sampledPoints.add(point);
            return 0xFF123456;
          },
          onEyedropperPick: picks.add,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(tapLayerKey));
    await tester.pump();

    expect(picks, [0xFF123456]);
    expect(sampledPoints, hasLength(1));
    expect(
      coordinator.frameStore.celHasRenderableContent(frameKeys.first),
      isFalse,
    );
  });

  // TS7 (유저: 지금 클릭해야 색 바뀌고 클릭한채로 드래그하는 도중에는
  // 안바뀌는데, 규칙 간단하게해서 클릭중이면 색 바뀌도록).
  testWidgets('the eyedropper keeps sampling while the button is held', (
    tester,
  ) async {
    final frameKeys = BrushCanvasFixture.createFrameKeys();
    final sampled = <CanvasPoint>[];
    final picks = <int>[];
    var next = 0xFF000001;

    await tester.pumpWidget(
      app(
        BrushCanvasPanel(
          coordinator: BrushCanvasFixture.createCoordinator(
            frameKeys: frameKeys,
          ),
          availableFrameKeys: frameKeys,
          cacheInvalidationSink: BrushEditCacheInvalidationSink(),
          brushToolState: BrushToolState.defaults.copyWith(
            tool: CanvasTool.eyedropper,
          ),
          sampleColorAt: (point) {
            sampled.add(point);
            return next += 1;
          },
          onEyedropperPick: picks.add,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final centre = tester.getCenter(find.byKey(tapLayerKey));
    // 🚨A MOUSE, said out loud. 「클릭중이면 색 바뀌도록」 is click language
    // and this test has always been about the held BUTTON; it just took the
    // harness default, which is a finger. A finger now waits for the gesture
    // to declare itself (see the touch group below), so leaving the default
    // here would quietly turn a mouse contract into a touch one.
    final gesture = await tester.startGesture(
      centre,
      kind: PointerDeviceKind.mouse,
      buttons: kPrimaryButton,
    );
    await tester.pump();
    expect(picks, hasLength(1), reason: 'the press still picks');

    await gesture.moveTo(centre + const Offset(12, 0));
    await tester.pump();
    await gesture.moveTo(centre + const Offset(24, 0));
    await tester.pump();
    await gesture.up();
    await tester.pump();

    expect(
      picks,
      hasLength(3),
      reason: 'a MOVE is the press verb continuing, not a second gesture',
    );
    expect(
      sampled.map((point) => point.x).toSet(),
      hasLength(3),
      reason: 'and it samples where the pointer actually is',
    );
  });

  testWidgets('a null sample (off-canvas) does not pick', (tester) async {
    final frameKeys = BrushCanvasFixture.createFrameKeys();
    final picks = <int>[];

    await tester.pumpWidget(
      app(
        BrushCanvasPanel(
          coordinator: BrushCanvasFixture.createCoordinator(
            frameKeys: frameKeys,
          ),
          availableFrameKeys: frameKeys,
          cacheInvalidationSink: BrushEditCacheInvalidationSink(),
          brushToolState: BrushToolState.defaults.copyWith(
            tool: CanvasTool.eyedropper,
          ),
          sampleColorAt: (_) => null,
          onEyedropperPick: picks.add,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(tapLayerKey));
    await tester.pump();

    expect(picks, isEmpty);
  });

  // TS9 (유저: 1핑거가 플립모드인데도 선택툴고르고 터치하면 선택이 작동함.
  // 드로잉모드가 아닌이상은 툴이 작동하면 안되지). The eyedropper is on this
  // layer with the stamp, so it was taking fingers in flip mode too — the
  // selection layer's own half is pinned in brush_canvas_selection_test.
  testWidgets('a FINGER does not pick unless the one-finger slot draws', (
    tester,
  ) async {
    AppInput.settings.value = AppInput.settings.value.copyWith(
      touchDragOneFinger: CanvasTouchDragAction.flip,
    );
    addTearDown(() {
      AppInput.settings.value = AppInputSettings.testCorpusBaseline;
    });
    final frameKeys = BrushCanvasFixture.createFrameKeys();
    final picks = <int>[];

    await tester.pumpWidget(
      app(
        BrushCanvasPanel(
          coordinator: BrushCanvasFixture.createCoordinator(
            frameKeys: frameKeys,
          ),
          availableFrameKeys: frameKeys,
          cacheInvalidationSink: BrushEditCacheInvalidationSink(),
          brushToolState: BrushToolState.defaults.copyWith(
            tool: CanvasTool.eyedropper,
          ),
          sampleColorAt: (_) => 0xFF123456,
          onEyedropperPick: picks.add,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final centre = tester.getCenter(find.byKey(tapLayerKey));
    final finger = await tester.startGesture(
      centre,
      kind: PointerDeviceKind.touch,
    );
    await tester.pump();
    await finger.moveTo(centre + const Offset(10, 0));
    await tester.pump();
    await finger.up();
    await tester.pump();
    expect(picks, isEmpty, reason: 'that finger was navigating');

    // The pen is unaffected — the slot is about fingers.
    final pen = await tester.startGesture(
      centre,
      kind: PointerDeviceKind.stylus,
    );
    await tester.pump();
    await pen.up();
    await tester.pump();
    expect(picks, hasLength(1));
  });

  testWidgets('a fill tap commits the dab through the stroke funnel', (
    tester,
  ) async {
    final frameKeys = BrushCanvasFixture.createFrameKeys();
    final coordinator = BrushCanvasFixture.createCoordinator(
      frameKeys: frameKeys,
    );
    final fillColors = <int>[];

    await tester.pumpWidget(
      app(
        BrushCanvasPanel(
          coordinator: coordinator,
          availableFrameKeys: frameKeys,
          cacheInvalidationSink: BrushEditCacheInvalidationSink(),
          brushToolState: BrushToolState.defaults.copyWith(
            tool: CanvasTool.fill,
            color: 0xFF3366CC,
          ),
          fillDabAt: (point, color, _) {
            fillColors.add(color);
            return fillDab(color);
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    // R22-A: fill taps land on the interactive VIEW (the stroke
    // pipeline), not a panel tap layer — instant overlay + settling.
    expect(find.byKey(tapLayerKey), findsNothing);
    await tester.tapAt(
      tester.getTopLeft(
            find.byKey(const ValueKey<String>('brush-canvas-view')),
          ) +
          const Offset(10, 10),
    );
    await tester.pump();

    // The active tool color reached the fill and the dab landed through
    // the ordinary stroke funnel — the pixels are the record (R19 P3b).
    expect(fillColors, [0xFF3366CC]);
    expect(
      coordinator.frameStore.celHasRenderableContent(frameKeys.first),
      isTrue,
    );

    // Middle-button regression pin (R22-B): a wheel-click pan attempt
    // must NEVER fill (it used to deposit stray entries — the
    // "two undos to remove one fill" bug).
    final before = fillColors.length;
    final gesture = await tester.createGesture(buttons: kMiddleMouseButton);
    await gesture.down(
      tester.getTopLeft(
            find.byKey(const ValueKey<String>('brush-canvas-view')),
          ) +
          const Offset(12, 12),
    );
    await gesture.up();
    await tester.pump();
    expect(fillColors.length, before, reason: 'middle click never fills');
  });

  testWidgets('a fill that spills off the canvas shows and lands its '
      'pasteboard tiles too — a fill is a stroke of one dab', (
    tester,
  ) async {
    final frameKeys = BrushCanvasFixture.createFrameKeys();
    final coordinator = BrushCanvasFixture.createCoordinator(
      frameKeys: frameKeys,
    );
    // A 64×64 stamp centred on the canvas ORIGIN lands at (-32, -32)..
    // (32, 32): three of its four tiles are pasteboard tiles.
    final stamp = BrushStampImage(
      id: 'spill',
      width: 64,
      height: 64,
      rgba: Uint8List(64 * 64 * 4)..fillRange(0, 64 * 64 * 4, 0xFF),
    );
    await tester.pumpWidget(
      app(
        BrushCanvasPanel(
          coordinator: coordinator,
          availableFrameKeys: frameKeys,
          cacheInvalidationSink: BrushEditCacheInvalidationSink(),
          brushToolState: BrushToolState.defaults.copyWith(
            tool: CanvasTool.fill,
          ),
          fillDabAt: (_, color, _) => fillDab(color).copyWith(
            center: CanvasPoint(x: 0, y: 0),
            size: 64,
            stamp: stamp,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tapAt(
      tester.getTopLeft(
            find.byKey(const ValueKey<String>('brush-canvas-view')),
          ) +
          const Offset(10, 10),
    );
    // The tap frame shows the result tiles (uploaded off the frame on the
    // test runner's engine), the post-frame commit lands the same objects.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump();
    await tester.pump();

    final landed = coordinator.currentSurfaceOf(frameKeys.first).tiles.keys;
    expect(
      landed.toSet(),
      {
        TileCoord(x: -1, y: -1),
        TileCoord(x: 0, y: -1),
        TileCoord(x: -1, y: 0),
        TileCoord(x: 0, y: 0),
      },
      reason: 'the stamp lands on the pasteboard as it lands on the canvas',
    );
    final overlay = tester
        .widget<BrushEditCanvasView>(find.byType(BrushEditCanvasView))
        .overlayModel!;
    expect(
      overlay.settleHoldTiles,
      isNull,
      reason: 'a fill pins nothing: its result tiles ARE what it shows',
    );
  });

  testWidgets('a null fill region commits nothing', (tester) async {
    final frameKeys = BrushCanvasFixture.createFrameKeys();
    final coordinator = BrushCanvasFixture.createCoordinator(
      frameKeys: frameKeys,
    );

    await tester.pumpWidget(
      app(
        BrushCanvasPanel(
          coordinator: coordinator,
          availableFrameKeys: frameKeys,
          cacheInvalidationSink: BrushEditCacheInvalidationSink(),
          brushToolState: BrushToolState.defaults.copyWith(
            tool: CanvasTool.fill,
          ),
          fillDabAt: (_, _, _) => null,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tapAt(
      tester.getTopLeft(
            find.byKey(const ValueKey<String>('brush-canvas-view')),
          ) +
          const Offset(10, 10),
    );
    await tester.pump();

    expect(
      coordinator.frameStore.celHasRenderableContent(frameKeys.first),
      isFalse,
    );
  });

  testWidgets('🗣️I-15: while the 「이동」 key is held a primary drag PANS '
      'and every tool stands down; let go and the same drag draws', (
    tester,
  ) async {
    addTearDown(() => CanvasPanHold.held.value = false);
    final frameKeys = BrushCanvasFixture.createFrameKeys();
    final coordinator = BrushCanvasFixture.createCoordinator(
      frameKeys: frameKeys,
    );
    final viewports = <CanvasViewport>[];
    await tester.pumpWidget(
      app(
        BrushCanvasPanel(
          coordinator: coordinator,
          availableFrameKeys: frameKeys,
          cacheInvalidationSink: BrushEditCacheInvalidationSink(),
          onViewportChanged: viewports.add,
        ),
      ),
    );
    await tester.pumpAndSettle();
    final hand = find.byWidgetPredicate(
      (widget) =>
          widget is MouseRegion && widget.cursor == SystemMouseCursors.grab,
    );
    bool drawn() =>
        coordinator.frameStore.celHasRenderableContent(frameKeys.first);
    Future<void> mouseDrag() async {
      final mouse = await tester.startGesture(
        canvasGlobalOffset(tester, const Offset(30, 30)),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump();
      await mouse.moveTo(canvasGlobalOffset(tester, const Offset(42, 36)));
      await tester.pump();
      await mouse.up();
      await tester.pumpAndSettle();
    }

    CanvasPanHold.held.value = true;
    await tester.pump();
    expect(hand, findsOneWidget, reason: 'the hand says what a press does');
    await mouseDrag();
    expect(viewports, isNotEmpty, reason: 'the drag moved the view');
    expect(drawn(), isFalse, reason: 'the brush stood down for the pan');

    CanvasPanHold.held.value = false;
    await tester.pump();
    expect(hand, findsNothing);
    viewports.clear();
    await mouseDrag();
    expect(viewports, isEmpty);
    expect(drawn(), isTrue, reason: 'let go, and the drag is the brush again');
  });

  testWidgets('🗣️I-15: a held RIGHT button picks through the ONE eyedropper '
      'pick — live along the drag, and no stroke', (tester) async {
    final frameKeys = BrushCanvasFixture.createFrameKeys();
    final coordinator = BrushCanvasFixture.createCoordinator(
      frameKeys: frameKeys,
    );
    final picks = <int>[];
    await tester.pumpWidget(
      app(
        BrushCanvasPanel(
          coordinator: coordinator,
          availableFrameKeys: frameKeys,
          cacheInvalidationSink: BrushEditCacheInvalidationSink(),
          sampleColorAt: (point) => 0xFF000000 | point.x.round(),
          onEyedropperPick: picks.add,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final right = await tester.startGesture(
      canvasGlobalOffset(tester, const Offset(10, 10)),
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryMouseButton,
    );
    await tester.pump();
    await right.moveTo(canvasGlobalOffset(tester, const Offset(40, 10)));
    await tester.pump();
    await right.up();
    await tester.pumpAndSettle();

    expect(picks.length, greaterThanOrEqualTo(2), reason: 'press AND drag');
    expect(picks.last, isNot(picks.first), reason: 'it followed the pointer');
    expect(
      coordinator.frameStore.celHasRenderableContent(frameKeys.first),
      isFalse,
    );
  });

  testWidgets('the eyedropper cursor is the TOOL alone — a painting tool '
      'with the pick wired never arms it (I-15: Alt switches the tool)', (
    tester,
  ) async {
    const trackerKey = ValueKey<String>('eyedropper-hover-tracker');
    final frameKeys = BrushCanvasFixture.createFrameKeys();
    final coordinator = BrushCanvasFixture.createCoordinator(
      frameKeys: frameKeys,
    );
    Future<void> pumpWith(CanvasTool tool) async {
      await tester.pumpWidget(
        app(
          BrushCanvasPanel(
            coordinator: coordinator,
            availableFrameKeys: frameKeys,
            cacheInvalidationSink: BrushEditCacheInvalidationSink(),
            brushToolState: BrushToolState.defaults.copyWith(tool: tool),
            sampleColorAt: (_) => 0xFFAABBCC,
            onEyedropperPick: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    await pumpWith(CanvasTool.brush);
    expect(find.byKey(trackerKey), findsNothing);
    await pumpWith(CanvasTool.eyedropper);
    expect(find.byKey(trackerKey), findsOneWidget);
  });

  testWidgets('the eyedropper shows a hover swatch of the color under the '
      'pointer (R11-②)', (tester) async {
    final frameKeys = BrushCanvasFixture.createFrameKeys();
    await tester.pumpWidget(
      app(
        BrushCanvasPanel(
          coordinator: BrushCanvasFixture.createCoordinator(
            frameKeys: frameKeys,
          ),
          availableFrameKeys: frameKeys,
          cacheInvalidationSink: BrushEditCacheInvalidationSink(),
          brushToolState: BrushToolState.defaults.copyWith(
            tool: CanvasTool.eyedropper,
          ),
          sampleColorAt: (_) => 0xFF123456,
          onEyedropperPick: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);
    await tester.pump();
    await gesture.moveTo(tester.getCenter(find.byKey(tapLayerKey)));
    await tester.pump();

    expect(eyedropperSwatchColor(tester), 0xFF123456);
  });

  testWidgets('R28 #8: the eyedropper cursor follows a BUTTON-HELD move — '
      'the mapped-hold case (pen barrel / right-click)', (tester) async {
    final frameKeys = BrushCanvasFixture.createFrameKeys();
    final samples = <CanvasPoint>[];
    // A gradient stand-in: the color depends on where the pointer is, so a
    // frozen cursor and a following one are distinguishable.
    await tester.pumpWidget(
      app(
        BrushCanvasPanel(
          coordinator: BrushCanvasFixture.createCoordinator(
            frameKeys: frameKeys,
          ),
          availableFrameKeys: frameKeys,
          cacheInvalidationSink: BrushEditCacheInvalidationSink(),
          brushToolState: BrushToolState.defaults.copyWith(
            tool: CanvasTool.eyedropper,
          ),
          sampleColorAt: (point) {
            samples.add(point);
            return 0xFF000000 | (point.x.round() & 0xFF);
          },
          onEyedropperPick: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    int swatchColor() => eyedropperSwatchColor(tester)!;

    final center = tester.getCenter(find.byKey(tapLayerKey));
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);
    await gesture.moveTo(center);
    await tester.pump();
    final restingColor = swatchColor();

    // Press and DRAG with the button held. Under a real mapped hold the
    // cursor's own tracker mounts mid-press and is outside the pointer's
    // route, so only the panel's always-mounted census can report these.
    await gesture.down(center);
    await tester.pump();
    await gesture.moveTo(center + const Offset(60, 0));
    await tester.pump();

    expect(
      swatchColor(),
      isNot(restingColor),
      reason:
          'R28 #8: the swatch must track a button-held move, not freeze '
          'wherever it was seeded',
    );
    expect(
      samples.last.x,
      greaterThan(samples.first.x),
      reason: 'the sample point followed the pointer',
    );
  });

  testWidgets('tool taps convert through the live viewport', (tester) async {
    final frameKeys = BrushCanvasFixture.createFrameKeys();
    final sampledPoints = <CanvasPoint>[];

    await tester.pumpWidget(
      app(
        BrushCanvasPanel(
          coordinator: BrushCanvasFixture.createCoordinator(
            frameKeys: frameKeys,
          ),
          availableFrameKeys: frameKeys,
          cacheInvalidationSink: BrushEditCacheInvalidationSink(),
          brushToolState: BrushToolState.defaults.copyWith(
            tool: CanvasTool.eyedropper,
          ),
          sampleColorAt: (point) {
            sampledPoints.add(point);
            return null;
          },
          onEyedropperPick: (_) {},
          // ⚠️An EXPLICIT render 1.0. This case maps a screen offset
          // straight to canvas coordinates, and an uncontrolled panel now
          // opens at the IDENTITY (one artwork px per DEVICE px), which is
          // a render zoom of 1/3 on the 3x test view.
          viewport: seedFromRender(tester, CanvasViewport()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Tap a known offset INSIDE the interactive canvas: at a render zoom of
    // 1 the local offset IS the canvas coordinate.
    final canvasTopLeft = tester.getTopLeft(
      find.byType(InteractiveBrushEditCanvasView),
    );
    await tester.tapAt(canvasTopLeft + const Offset(25, 35));
    await tester.pump();

    expect(sampledPoints, hasLength(1));
    expect(sampledPoints.single.x, closeTo(25, 0.001));
    expect(sampledPoints.single.y, closeTo(35, 0.001));
  });

  /// 유저 2026-08-27: 「1핑거 드로잉모드일때 **다른 툴도 비슷한 문제
  /// 있을거같은데** 어떻지? … 손가락이 동시에 착지하는게 불가능하니까. …
  /// 그런 비슷한 방식으로 **통일**하는게 근본통일같은데」.
  ///
  /// The user was right and named the cure in the same breath. The fill was
  /// fixed alone (H29, the group above); the STAMP and the EYEDROPPER sit on
  /// the tap layer and fired on the press, so the first finger of every
  /// two-finger undo dropped a piece or repainted the colour.
  ///
  /// One rule covers both, and it is the app's own: a gesture declares
  /// itself by MOVING. Until it has, nothing happens — a tap that stays put
  /// resolves when the finger leaves, and one that crosses the slop resolves
  /// there and carries on.
  group('the tap tools wait for the gesture to say what it is', () {
    // 🚨SAVE and restore — `AppInput` is a global (see the H29 group).
    late AppInputSettings savedInput;
    setUp(() {
      savedInput = AppInput.settings.value;
      AppInput.settings.value = savedInput.copyWith(
        touchDragOneFinger: CanvasTouchDragAction.draw,
      );
    });
    tearDown(() {
      AppInput.settings.value = savedInput;
    });

    /// A 2×2 opaque piece, so a landed stamp is readable in the raster
    /// rather than through a flag.
    CutPiece piece() {
      final rgba = Uint8List(2 * 2 * 4);
      for (var index = 0; index < 4; index += 1) {
        rgba[index * 4] = 0xFF;
        rgba[index * 4 + 3] = 0xFF;
      }
      return CutPiece(
        image: BrushStampImage(id: 'piece', width: 2, height: 2, rgba: rgba),
        originLeft: 0,
        originTop: 0,
      );
    }

    Future<BrushFrameEditingCoordinator> pumpStamp(WidgetTester tester) async {
      final frameKeys = BrushCanvasFixture.createFrameKeys();
      final coordinator = BrushCanvasFixture.createCoordinator(
        frameKeys: frameKeys,
      );
      final slot = CutPieceSlot()..hold(piece());
      addTearDown(slot.dispose);
      await tester.pumpWidget(
        app(
          BrushCanvasPanel(
            coordinator: coordinator,
            availableFrameKeys: frameKeys,
            cacheInvalidationSink: BrushEditCacheInvalidationSink(),
            brushToolState: BrushToolState.defaults.copyWith(
              tool: CanvasTool.cutStamp,
            ),
            cutPieceSlot: slot,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(AppInput.touchDraws, isTrue, reason: '터치 묘화 on — 유저 상태');
      expect(
        find.byKey(tapLayerKey),
        findsOneWidget,
        reason: '🚨the stamp has to be ON the tap layer, or this group is '
            'driving a surface that is not the one under test',
      );
      return coordinator;
    }

    /// Whether the cel has ANY ink. The stamp lands where the pointer is,
    /// which a widget test cannot name in canvas coordinates, so the
    /// question asked is the one that matters: did a piece land at all.
    bool stamped(BrushFrameEditingCoordinator coordinator) => coordinator
        .frameStore
        .celHasRenderableContent(coordinator.activeFrameKey);

    testWidgets('STAMP — one finger down and up: the piece lands', (
      tester,
    ) async {
      final coordinator = await pumpStamp(tester);
      final centre = tester.getCenter(find.byKey(tapLayerKey));
      final finger = await tester.startGesture(
        centre,
        kind: PointerDeviceKind.touch,
      );
      await tester.pump();
      expect(
        stamped(coordinator),
        isFalse,
        reason: '⛔and NOT on the touch — the press cannot yet know whether a '
            'second finger is on its way',
      );

      await finger.up();
      await tester.pumpAndSettle();
      expect(
        stamped(coordinator),
        isTrue,
        reason: 'a lone tap is the stamp\'s own gesture — 「Click = drop the '
            'held piece」 still holds, it just resolves on the lift',
      );
    });

    testWidgets('STAMP — a SECOND finger joins before the lift: nothing '
        'lands', (tester) async {
      final coordinator = await pumpStamp(tester);
      final centre = tester.getCenter(find.byKey(tapLayerKey));
      // The shape of a two-finger undo.
      final first = await tester.startGesture(
        centre,
        kind: PointerDeviceKind.touch,
      );
      await tester.pump();
      final second = await tester.startGesture(
        centre + const Offset(40, 0),
        kind: PointerDeviceKind.touch,
      );
      await tester.pump();
      await first.up();
      await second.up();
      await tester.pumpAndSettle();

      expect(
        stamped(coordinator),
        isFalse,
        reason: '🚨THE RASTER, not a flag: the bug was a real commit, and a '
            'stamp the user never asked for is what ate their undo',
      );
    });

    testWidgets('STAMP — a THIRD finger does not get a fresh turn', (
      tester,
    ) async {
      final coordinator = await pumpStamp(tester);
      final centre = tester.getCenter(find.byKey(tapLayerKey));
      // 🚨THE CASE A MUTATION FOUND. With 「is a tap already waiting」 as the
      // only guard, the second finger cleared the pending tap and the third
      // armed a NEW one — so a three-finger redo stamped a piece on its way
      // past. The guard has to be a count of live fingers, not a flag.
      final fingers = <TestGesture>[];
      for (var index = 0; index < 3; index += 1) {
        fingers.add(
          await tester.startGesture(
            centre + Offset(30.0 * index, 0),
            kind: PointerDeviceKind.touch,
          ),
        );
        await tester.pump();
      }
      // ⚠️LAST DOWN, FIRST UP. Order matters and the first version of this
      // test got it wrong: lifting front-to-back, the third finger's stale
      // turn is cleared by the FIRST finger's release before it can be
      // spent, so the bug hides and the mutation survives. Hands do not
      // promise an order.
      for (final finger in fingers.reversed) {
        await finger.up();
        await tester.pump();
      }
      await tester.pumpAndSettle();

      expect(
        stamped(coordinator),
        isFalse,
        reason: 'three fingers are a shortcut, not three chances to stamp',
      );
    });

    testWidgets('STAMP — a finger that DRAGS past the slop stamps, without '
        'waiting for the lift', (tester) async {
      final coordinator = await pumpStamp(tester);
      final centre = tester.getCenter(find.byKey(tapLayerKey));
      final finger = await tester.startGesture(
        centre,
        kind: PointerDeviceKind.touch,
      );
      await tester.pump();
      // Sub-slop first: a wobble is not yet a drag.
      await finger.moveTo(centre + const Offset(6, 0));
      await tester.pump();
      expect(
        stamped(coordinator),
        isFalse,
        reason: 'six pixels is a wobble, and the slop is '
            '${InteractiveBrushEditCanvasView.kTouchStrokeCommitSlop}',
      );

      await finger.moveTo(centre + const Offset(60, 0));
      await tester.pump();
      expect(
        stamped(coordinator),
        isTrue,
        reason: 'crossing the slop IS the gesture declaring itself — it does '
            'not have to wait for the lift as well',
      );
      await finger.up();
      await tester.pumpAndSettle();
    });

    Future<void> pumpDropper(
      WidgetTester tester, {
      required List<int> picks,
    }) async {
      final frameKeys = BrushCanvasFixture.createFrameKeys();
      await tester.pumpWidget(
        app(
          BrushCanvasPanel(
            coordinator: BrushCanvasFixture.createCoordinator(
              frameKeys: frameKeys,
            ),
            availableFrameKeys: frameKeys,
            cacheInvalidationSink: BrushEditCacheInvalidationSink(),
            brushToolState: BrushToolState.defaults.copyWith(
              tool: CanvasTool.eyedropper,
            ),
            sampleColorAt: (_) => 0xFF123456,
            onEyedropperPick: picks.add,
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('DROPPER — one finger down and up: it picks, on the lift', (
      tester,
    ) async {
      final picks = <int>[];
      await pumpDropper(tester, picks: picks);
      final centre = tester.getCenter(find.byKey(tapLayerKey));
      final finger = await tester.startGesture(
        centre,
        kind: PointerDeviceKind.touch,
      );
      await tester.pump();
      expect(picks, isEmpty, reason: '⛔not on the touch');

      await finger.up();
      await tester.pumpAndSettle();
      expect(
        picks,
        [0xFF123456],
        reason: 'tap-to-pick is the dropper\'s commonest verb and it keeps '
            'working — it just resolves where the answer is known',
      );
    });

    testWidgets('DROPPER — a SECOND finger joins before the lift: no pick', (
      tester,
    ) async {
      final picks = <int>[];
      await pumpDropper(tester, picks: picks);
      final centre = tester.getCenter(find.byKey(tapLayerKey));
      final first = await tester.startGesture(
        centre,
        kind: PointerDeviceKind.touch,
      );
      await tester.pump();
      final second = await tester.startGesture(
        centre + const Offset(40, 0),
        kind: PointerDeviceKind.touch,
      );
      await tester.pump();
      await first.up();
      await second.up();
      await tester.pumpAndSettle();

      expect(
        picks,
        isEmpty,
        reason: '유저: 「선택툴도 선택이 일어나면서 언두 된다거나 그런거 '
            '있을거아니야」 — the colour is not silently rewritten by a '
            'gesture that was never about colour',
      );
    });

    testWidgets('DROPPER — a DRAG still samples all along it (TS7 survives '
        'the wait)', (tester) async {
      final picks = <int>[];
      await pumpDropper(tester, picks: picks);
      final centre = tester.getCenter(find.byKey(tapLayerKey));
      final finger = await tester.startGesture(
        centre,
        kind: PointerDeviceKind.touch,
      );
      await tester.pump();
      await finger.moveTo(centre + const Offset(40, 0));
      await tester.pump();
      await finger.moveTo(centre + const Offset(80, 0));
      await tester.pump();
      await finger.up();
      await tester.pumpAndSettle();

      expect(
        picks.length,
        greaterThan(1),
        reason: '유저 확정 TS7: 「클릭중이면 색 바뀌도록 … 드래그중 계속샘플」 '
            '— deferring the FIRST sample must not cost the rest of them',
      );
    });
  });
}
