import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/gestures.dart' show kMiddleMouseButton;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/brush_blend_mode.dart';
import 'package:anicel/src/models/brush_dab.dart';
import 'package:anicel/src/models/brush_tip_shape.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/services/brush_frame_editing_coordinator.dart';
import 'package:anicel/src/services/canvas_color_sampler.dart';
import 'package:anicel/src/ui/brush/brush_canvas_panel.dart';
import 'package:anicel/src/ui/brush/brush_edit_cache_invalidation_sink.dart';
import 'package:anicel/src/ui/brush/brush_tool_state.dart';
import 'package:anicel/src/ui/canvas/interactive_brush_edit_canvas_view.dart';
import 'package:anicel/src/ui/input/app_input_settings.dart';

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
          fillDab(0xFF000000).copyWith(
            center: CanvasPoint(x: x.toDouble(), y: 4),
          ),
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
          fillDabAt: (_, color) => fillDab(color),
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
          fillDabAt: (_, color) => fillDab(color),
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
    final gesture = await tester.startGesture(centre);
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
          fillDabAt: (point, color) {
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
          fillDabAt: (_, _) => null,
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

  testWidgets('Alt+click picks the color and starts no stroke', (tester) async {
    final frameKeys = BrushCanvasFixture.createFrameKeys();
    final coordinator = BrushCanvasFixture.createCoordinator(
      frameKeys: frameKeys,
    );
    final altPicks = <int>[];

    await tester.pumpWidget(
      app(
        BrushCanvasPanel(
          coordinator: coordinator,
          availableFrameKeys: frameKeys,
          cacheInvalidationSink: BrushEditCacheInvalidationSink(),
          sampleColorAt: (_) => 0xFFAABBCC,
          onAltColorPick: altPicks.add,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tapCanvas(tester, const Offset(30, 30));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    await tester.pumpAndSettle();

    expect(altPicks, [0xFFAABBCC]);
    expect(
      coordinator.frameStore.celHasRenderableContent(frameKeys.first),
      isFalse,
    );
    // Without Alt the same tap draws — the gate is the modifier, not the
    // handler wiring.
    await tapCanvas(tester, const Offset(30, 30));
    await tester.pumpAndSettle();
    expect(
      coordinator.frameStore.celHasRenderableContent(frameKeys.first),
      isTrue,
    );
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

    final swatch = tester.widget<Container>(
      find.byKey(const ValueKey<String>('eyedropper-hover-swatch')),
    );
    expect(
      (swatch.decoration! as BoxDecoration).color,
      const Color(0xFF123456),
    );
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

    Color swatchColor() =>
        (tester
                    .widget<Container>(
                      find.byKey(
                        const ValueKey<String>('eyedropper-hover-swatch'),
                      ),
                    )
                    .decoration!
                as BoxDecoration)
            .color!;

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
      reason: 'R28 #8: the swatch must track a button-held move, not freeze '
          'wherever it was seeded',
    );
    expect(
      samples.last.x,
      greaterThan(samples.first.x),
      reason: 'the sample point followed the pointer',
    );
  });

  testWidgets('holding Alt arms the eyedropper cursor on a painting tool '
      '(R11-②)', (tester) async {
    const trackerKey = ValueKey<String>('eyedropper-hover-tracker');
    final frameKeys = BrushCanvasFixture.createFrameKeys();
    await tester.pumpWidget(
      app(
        BrushCanvasPanel(
          coordinator: BrushCanvasFixture.createCoordinator(
            frameKeys: frameKeys,
          ),
          availableFrameKeys: frameKeys,
          cacheInvalidationSink: BrushEditCacheInvalidationSink(),
          sampleColorAt: (_) => 0xFFAABBCC,
          onAltColorPick: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(trackerKey), findsNothing);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.pump();
    expect(find.byKey(trackerKey), findsOneWidget);

    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    await tester.pump();
    expect(find.byKey(trackerKey), findsNothing);
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
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Tap a known offset INSIDE the interactive canvas: viewport identity
    // maps the local offset straight to canvas coordinates.
    final canvasTopLeft = tester.getTopLeft(
      find.byType(InteractiveBrushEditCanvasView),
    );
    await tester.tapAt(canvasTopLeft + const Offset(25, 35));
    await tester.pump();

    expect(sampledPoints, hasLength(1));
    expect(sampledPoints.single.x, closeTo(25, 0.001));
    expect(sampledPoints.single.y, closeTo(35, 0.001));
  });
}
