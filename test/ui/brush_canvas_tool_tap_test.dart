import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/gestures.dart'
    show kMiddleMouseButton, kPrimaryButton, kSecondaryMouseButton;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import '../helpers/device_viewport.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/brush_blend_mode.dart';
import 'package:anicel/src/models/brush_dab.dart';
import 'package:anicel/src/models/brush_stamp_image.dart';
import 'package:anicel/src/models/brush_tip_shape.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/cut_piece.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/services/brush_frame_editing_coordinator.dart';
import 'package:anicel/src/services/canvas_color_sampler.dart';
import 'package:anicel/src/services/canvas_flood_fill.dart';
import 'package:anicel/src/services/canvas_selection_region.dart';
import 'package:anicel/src/services/canvas_selection_shape.dart';
import 'package:anicel/src/services/cut_piece_slot.dart';
import 'package:anicel/src/services/fill_gradient.dart';
import 'package:anicel/src/ui/brush/brush_canvas_panel.dart';
import 'package:anicel/src/ui/brush/brush_edit_cache_invalidation_sink.dart';
import 'package:anicel/src/ui/brush/brush_tool_state.dart';
import 'package:anicel/src/ui/brush/canvas_selection_commands.dart';
import 'package:anicel/src/ui/canvas/active_stroke_overlay.dart';
import 'package:anicel/src/ui/canvas/canvas_view_hold.dart';
import 'package:anicel/src/ui/canvas/interactive_brush_edit_canvas_view.dart';
import 'package:anicel/src/models/app_input_settings.dart';

import '../helpers/brush_canvas_fixture.dart';
import 'brush_canvas_test_helpers.dart';

/// The sub colour a gradient runs to (I-160-Q3), and as a pixel reads it.
const _sub = 0xFF00FF00;
const _subRgba = 0x00FF00FF;

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

  /// What a fill flooded: [width]×[height] at ([left], [top]), hard and
  /// closed — where [fillDab] lands, by default.
  FillRange rangeOf({
    int left = 0,
    int top = 0,
    int width = 8,
    int height = 8,
  }) => FillRange.over(
    FloodFillRegion(
      left: left,
      top: top,
      width: width,
      height: height,
      mask: Uint8List(width * height)..fillRange(0, width * height, 255),
    ),
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
            brushToolState: ValueNotifier(BrushToolState.defaults.copyWith(
              tool: CanvasTool.fill,
            )),
            fillRangeAt: (_, _) => rangeOf(),
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

    testWidgets('a PEN press retires a resting finger\'s held fill — one '
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
            brushToolState: ValueNotifier(BrushToolState.defaults.copyWith(
              tool: CanvasTool.fill,
            )),
            // 🚨Each fill lands somewhere ELSE, so a second one cannot hide
            // under the first. ⛔Not the seed point — the canvas is 2340px
            // wide inside a small viewport, so a local offset is nowhere
            // near the canvas coordinate of the same name.
            fillRangeAt: (_, _) => rangeOf(left: 20 * fills++),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // A finger resting on the glass holds a fill of its own on touchdown
      // — the range at 0.
      final resting = await tester.startGesture(
        canvasAt(tester, const Offset(4, 4)),
        kind: PointerDeviceKind.touch,
      );
      await tester.pump();
      // The pen fills somewhere else while it rests — the range at 20.
      await tester.tapAt(
        canvasAt(tester, const Offset(20, 4)),
        kind: PointerDeviceKind.stylus,
      );
      await tester.pumpAndSettle();
      expect(inkAt(coordinator, 24, 4), isNonZero, reason: 'the pen filled');

      // ⛔And the rest lifting must not fill a second time.
      await resting.up();
      await tester.pumpAndSettle();
      expect(
        inkAt(coordinator, 4, 4),
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

  /// 🚨★★★I-160-Q2 a (유저 2026-11-04 「바꾼다 — 누르는 동안 미리보기, 떼면
  /// 채움」): a fill is HELD — the press marks the range it covers, the mark
  /// follows the press from region to region, and the lift lands where it
  /// showed. Every pointer, one law.
  group('I-160: a fill held marks its range and lands at the lift', () {
    Future<
      ({
        BrushFrameEditingCoordinator coordinator,
        ActiveStrokeOverlayModel overlay,
        List<CanvasPoint> floods,
      })
    >
    pumpHeld(
      WidgetTester tester, {
      CanvasSelectionRegion? selection,
      bool continuous = false,
      FillGradientOptions? gradient,
      ValueNotifier<BrushToolState>? brush,
    }) async {
      final frameKeys = BrushCanvasFixture.createFrameKeys();
      final coordinator = BrushCanvasFixture.createCoordinator(
        frameKeys: frameKeys,
      );
      final overlay = ActiveStrokeOverlayModel();
      addTearDown(overlay.dispose);
      final floods = <CanvasPoint>[];
      await tester.pumpWidget(
        app(
          BrushCanvasPanel(
            coordinator: coordinator,
            availableFrameKeys: frameKeys,
            cacheInvalidationSink: BrushEditCacheInvalidationSink(),
            brushToolState:
                brush ??
                ValueNotifier(
                  BrushToolState.defaults.copyWith(tool: CanvasTool.fill),
                ),
            activeStrokeOverlayModel: overlay,
            // One canvas pixel to a logical one, from the view's corner.
            viewport: seedFromRender(tester, CanvasViewport()),
            selectionCommands: selection == null
                ? null
                : (CanvasSelectionCommands()..setRegion(selection)),
            // A region sixteen wide around wherever it is flooded from.
            fillRangeAt: (point, _) {
              floods.add(point);
              return rangeOf(
                left: point.x.floor() - 8,
                top: point.y.floor() - 8,
                width: 16,
                height: 16,
              );
            },
            fillsContinuously: () => continuous,
            fillGradient: gradient == null
                ? null
                : () => (options: gradient, sub: _sub),
          ),
        ),
      );
      // ⛔Not settled: a selection's ants march for as long as it stands.
      await tester.pump();
      await tester.pump();
      return (coordinator: coordinator, overlay: overlay, floods: floods);
    }

    int inkWhere(BrushFrameEditingCoordinator coordinator, CanvasPoint at) =>
        inkAt(coordinator, at.x.floor(), at.y.floor());

    group('🚨I-160 the gradient: a press picks the range, the next drags '
        'its gradient', () {
      const gradient = FillGradientOptions(enabled: true);

      /// A red fill's range picked at the centre and held: where it was
      /// flooded from, and the view's corner.
      Future<({CanvasPoint at, Offset origin})> pick(
        WidgetTester tester,
        List<CanvasPoint> floods,
      ) async {
        final view = find.byKey(const ValueKey<String>('brush-canvas-view'));
        final pen = await tester.startGesture(
          tester.getCenter(view),
          kind: PointerDeviceKind.stylus,
        );
        await tester.pump();
        await pen.up();
        await tester.pumpAndSettle();
        return (at: floods.single, origin: tester.getTopLeft(view));
      }

      /// A press dragged along the range's middle row, from the centre of
      /// its first column to the centre of its last.
      Future<TestGesture> dragAcross(
        WidgetTester tester,
        ({CanvasPoint at, Offset origin}) picked,
      ) async {
        final left = picked.at.x.floor() - 8;
        final row = picked.at.y.floor() + 0.5;
        final pen = await tester.startGesture(
          picked.origin + Offset(left + 0.5, row),
          kind: PointerDeviceKind.stylus,
        );
        await tester.pump();
        await pen.moveBy(const Offset(15, 0));
        await tester.pump();
        return pen;
      }

      testWidgets('lifted, the range is held marked and nothing lands — the '
          'next press\'s lift lands the gradient across it, start to end', (
        tester,
      ) async {
        final brush = ValueNotifier(
          BrushToolState.defaults.copyWith(
            tool: CanvasTool.fill,
            color: 0xFFFF0000,
          ),
        );
        final (:coordinator, :overlay, :floods) = await pumpHeld(
          tester,
          gradient: gradient,
          brush: brush,
        );
        final picked = await pick(tester, floods);
        expect(overlay.fillRange, isNotNull, reason: 'held, marked');
        expect(inkWhere(coordinator, picked.at), 0, reason: '⛔not laid');

        final pen = await dragAcross(tester, picked);
        expect(floods, hasLength(1), reason: 'the drag floods nothing');
        await pen.up();
        await tester.pumpAndSettle();
        final left = picked.at.x.floor() - 8;
        final y = picked.at.y.floor();
        expect(inkAt(coordinator, left, y), 0xFF0000FF, reason: 'main');
        expect(inkAt(coordinator, left + 15, y), _subRgba, reason: 'sub');
        final middle = inkAt(coordinator, left + 7, y);
        expect(middle >> 24, inExclusiveRange(0, 0xFF), reason: 'between');
        expect(overlay.fillRange, isNull, reason: 'the result took its place');

        // Laid and let go: the next press picks anew.
        final again = await tester.startGesture(
          picked.origin + Offset(picked.at.x + 60, picked.at.y),
          kind: PointerDeviceKind.stylus,
        );
        await tester.pump();
        expect(floods, hasLength(2));
        await again.up();
        await tester.pumpAndSettle();
      });

      testWidgets('a drag given up gives up the drag, not the range — the '
          'next press drags it again', (tester) async {
        final (:coordinator, :overlay, :floods) = await pumpHeld(
          tester,
          gradient: gradient,
        );
        final picked = await pick(tester, floods);
        final pen = await dragAcross(tester, picked);
        await pen.cancel();
        await tester.pumpAndSettle();
        expect(inkWhere(coordinator, picked.at), 0, reason: 'nothing laid');
        expect(overlay.fillRange, isNotNull, reason: 'the range, marked');

        final again = await dragAcross(tester, picked);
        expect(floods, hasLength(1), reason: 'still the range picked');
        await again.up();
        await tester.pumpAndSettle();
        expect(inkWhere(coordinator, picked.at), isNonZero);
      });

      testWidgets('the fill put down lets the held range go', (tester) async {
        final brush = ValueNotifier(
          BrushToolState.defaults.copyWith(tool: CanvasTool.fill),
        );
        final (:coordinator, :overlay, :floods) = await pumpHeld(
          tester,
          gradient: gradient,
          brush: brush,
        );
        final picked = await pick(tester, floods);
        brush.value = brush.value.copyWith(tool: CanvasTool.brush);
        await tester.pumpAndSettle();
        expect(overlay.fillRange, isNull, reason: 'the mark goes with it');
        brush.value = brush.value.copyWith(tool: CanvasTool.fill);
        await tester.pumpAndSettle();

        final pen = await tester.startGesture(
          picked.origin + Offset(picked.at.x, picked.at.y),
          kind: PointerDeviceKind.stylus,
        );
        await tester.pump();
        expect(floods, hasLength(2), reason: 'a press picks anew');
        await pen.up();
        await tester.pumpAndSettle();
        expect(inkWhere(coordinator, picked.at), 0, reason: 'held, not laid');
      });

      testWidgets('its cel gone, the held range goes with it', (tester) async {
        final (:coordinator, :overlay, :floods) = await pumpHeld(
          tester,
          gradient: gradient,
        );
        final picked = await pick(tester, floods);
        final frameKeys = BrushCanvasFixture.createFrameKeys();
        coordinator.selectFrame(frameKeys[1]);
        // The host builds the panel again on the other cel, as a flip does.
        tester.element(find.byType(BrushCanvasPanel)).markNeedsBuild();
        await tester.pumpAndSettle();
        expect(overlay.fillRange, isNull);

        final pen = await tester.startGesture(
          picked.origin + Offset(picked.at.x, picked.at.y),
          kind: PointerDeviceKind.stylus,
        );
        await tester.pump();
        expect(floods, hasLength(2), reason: 'a press picks anew');
        await pen.up();
        await tester.pumpAndSettle();
      });

      testWidgets('the gradient is cut by the selection, as the fill is', (
        tester,
      ) async {
        final (:coordinator, :overlay, :floods) = await pumpHeld(
          tester,
          gradient: gradient,
          selection: CanvasSelectionRegion.shape(
            CanvasSelectionShape.rect(left: 0, top: 0, right: 200, bottom: 400),
          ),
        );
        final origin = tester.getTopLeft(
          find.byKey(const ValueKey<String>('brush-canvas-view')),
        );
        final press = await tester.startGesture(
          origin + const Offset(200, 100),
          kind: PointerDeviceKind.stylus,
        );
        await tester.pump();
        await press.up();
        await tester.pump();
        final pen = await dragAcross(tester, (
          at: floods.single,
          origin: origin,
        ));
        await pen.up();
        await tester.pump();
        await tester.pump();
        final left = floods.single.x.floor() - 8;
        final y = floods.single.y.floor();
        expect(inkAt(coordinator, left + 3, y), isNonZero, reason: 'inside');
        expect(inkAt(coordinator, left + 12, y), 0, reason: 'past it');
      });

      testWidgets('the gradient lays under the fill\'s blend — erase takes '
          'ink away as far as the gradient reaches', (tester) async {
        final brush = ValueNotifier(
          BrushToolState.defaults.copyWith(
            tool: CanvasTool.fill,
            fillBlendMode: BrushBlendMode.erase,
          ),
        );
        final (:coordinator, :overlay, :floods) = await pumpHeld(
          tester,
          gradient: const FillGradientOptions(
            enabled: true,
            end: FillGradientEnd.transparent,
          ),
          brush: brush,
        );
        coordinator.commitSourceStroke(
          sourceDabs: [
            for (var x = 8; x <= 40; x += 4)
              fillDab(
                0xFF000000,
              ).copyWith(center: CanvasPoint(x: x.toDouble(), y: 16)),
          ],
        );
        final origin = tester.getTopLeft(
          find.byKey(const ValueKey<String>('brush-canvas-view')),
        );
        final press = await tester.startGesture(
          origin + const Offset(24, 16),
          kind: PointerDeviceKind.stylus,
        );
        await tester.pump();
        await press.up();
        await tester.pumpAndSettle();
        final left = floods.single.x.floor() - 8;
        expect(inkAt(coordinator, left, 16), isNonZero, reason: 'ink there');
        final pen = await dragAcross(tester, (
          at: floods.single,
          origin: origin,
        ));
        await pen.up();
        await tester.pumpAndSettle();
        expect(inkAt(coordinator, left, 16), 0, reason: 'the start erases');
        expect(
          inkAt(coordinator, left + 15, 16),
          isNonZero,
          reason: 'its clear end leaves the ink',
        );
      });

      testWidgets('an open range is laid as ever — it says so at the lift '
          'and holds nothing for a gradient', (tester) async {
        var said = 0;
        var floods = 0;
        const size = CanvasSize(width: 16, height: 16);
        final frameKeys = BrushCanvasFixture.createFrameKeys();
        await tester.pumpWidget(
          app(
            BrushCanvasPanel(
              coordinator: BrushCanvasFixture.createCoordinator(
                frameKeys: frameKeys,
              ),
              availableFrameKeys: frameKeys,
              cacheInvalidationSink: BrushEditCacheInvalidationSink(),
              brushToolState: ValueNotifier(
                BrushToolState.defaults.copyWith(tool: CanvasTool.fill),
              ),
              viewport: seedFromRender(tester, CanvasViewport()),
              // Nothing drawn and the fill let out past the canvas: the
              // flood reaches the apron's wall wherever it starts.
              fillRangeAt: (_, _) {
                floods += 1;
                return fillRangeAt(
                  cut: Cut(
                    id: const CutId('open'),
                    name: 'Open',
                    duration: 24,
                    canvasSize: size,
                    layers: [
                      Layer(
                        id: const LayerId('ink'),
                        name: 'Ink',
                        frames: [
                          Frame(
                            id: const FrameId('ink-frame'),
                            duration: 1,
                            strokes: const [],
                          ),
                        ],
                        timeline: {
                          0: const TimelineExposure.drawing(
                            FrameId('ink-frame'),
                            length: 1,
                          ),
                        },
                      ),
                    ],
                  ),
                  frameIndex: 0,
                  surfaceResolver: (_, _) =>
                      BitmapSurface(canvasSize: size, tileSize: 4),
                  point: CanvasPoint(x: 3, y: 3),
                  options: const FloodFillOptions(
                    expandPx: 0,
                    antiAlias: false,
                    extendBeyondCanvas: true,
                  ),
                  onOpenRegion: () => said += 1,
                );
              },
              fillGradient: () => (options: gradient, sub: _sub),
            ),
          ),
        );
        await tester.pump();
        final view = find.byKey(const ValueKey<String>('brush-canvas-view'));
        for (var press = 1; press <= 2; press += 1) {
          final pen = await tester.startGesture(
            tester.getCenter(view),
            kind: PointerDeviceKind.stylus,
          );
          await tester.pump();
          await pen.up();
          await tester.pumpAndSettle();
          expect(said, press, reason: 'said at each lift');
          expect(floods, press, reason: 'each press picks');
        }
      });

      testWidgets('switched off while a range is held: the next press picks '
          'anew and lands at its lift', (tester) async {
        var options = gradient;
        final frameKeys = BrushCanvasFixture.createFrameKeys();
        final coordinator = BrushCanvasFixture.createCoordinator(
          frameKeys: frameKeys,
        );
        final floods = <CanvasPoint>[];
        await tester.pumpWidget(
          app(
            BrushCanvasPanel(
              coordinator: coordinator,
              availableFrameKeys: frameKeys,
              cacheInvalidationSink: BrushEditCacheInvalidationSink(),
              brushToolState: ValueNotifier(
                BrushToolState.defaults.copyWith(tool: CanvasTool.fill),
              ),
              viewport: seedFromRender(tester, CanvasViewport()),
              fillRangeAt: (point, _) {
                floods.add(point);
                return rangeOf(
                  left: point.x.floor() - 8,
                  top: point.y.floor() - 8,
                  width: 16,
                  height: 16,
                );
              },
              fillGradient: () => (options: options, sub: _sub),
            ),
          ),
        );
        await tester.pump();
        final picked = await pick(tester, floods);
        options = const FillGradientOptions();
        final pen = await tester.startGesture(
          picked.origin + Offset(picked.at.x, picked.at.y),
          kind: PointerDeviceKind.stylus,
        );
        await tester.pump();
        expect(floods, hasLength(2));
        await pen.up();
        await tester.pumpAndSettle();
        expect(inkWhere(coordinator, picked.at), isNonZero);

        // The range picked before is let go, not left waiting.
        options = gradient;
        final again = await tester.startGesture(
          picked.origin + Offset(picked.at.x + 60, picked.at.y),
          kind: PointerDeviceKind.stylus,
        );
        await tester.pump();
        expect(floods, hasLength(3), reason: 'a press picks anew');
        await again.up();
        await tester.pumpAndSettle();
      });
    });

    testWidgets('🚨held: marked, not filled — moved within its region, '
        'flooded once — moved past it, marked anew — lifted, filled there', (
      tester,
    ) async {
      final (:coordinator, :overlay, :floods) = await pumpHeld(tester);
      final centre = tester.getCenter(
        find.byKey(const ValueKey<String>('brush-canvas-view')),
      );
      final pen = await tester.startGesture(
        centre,
        kind: PointerDeviceKind.stylus,
      );
      await tester.pump();
      expect(floods, hasLength(1), reason: 'the press floods its range');
      final first = overlay.fillRange;
      expect(first, isNotNull, reason: 'and marks it');
      expect(
        inkWhere(coordinator, floods.single),
        0,
        reason: '⛔nothing lands while the fill is held',
      );

      await pen.moveBy(const Offset(1, 0));
      await tester.pump();
      expect(floods, hasLength(1), reason: 'inside its range: no new flood');
      expect(identical(overlay.fillRange, first), isTrue);

      await pen.moveBy(const Offset(120, 0));
      await tester.pump();
      expect(floods, hasLength(2), reason: 'past it: the flood from there');
      expect(overlay.fillRange, isNotNull);
      expect(identical(overlay.fillRange, first), isFalse);

      await pen.up();
      await tester.pumpAndSettle();
      expect(
        inkWhere(coordinator, floods.last),
        isNonZero,
        reason: 'the lift lands the range it showed',
      );
      expect(
        inkWhere(coordinator, floods.first),
        0,
        reason: 'and only that one',
      );
      expect(overlay.fillRange, isNull, reason: 'the result takes its place');
    });

    testWidgets('🚨I-160-Q6 「연속 채우기」: every region the press passed over '
        'is marked and held — passed again, not flooded again — lifted, all '
        'filled', (tester) async {
      final (:coordinator, :overlay, :floods) = await pumpHeld(
        tester,
        continuous: true,
      );
      final centre = tester.getCenter(
        find.byKey(const ValueKey<String>('brush-canvas-view')),
      );
      final pen = await tester.startGesture(
        centre,
        kind: PointerDeviceKind.stylus,
      );
      await tester.pump();
      await pen.moveBy(const Offset(120, 0));
      await tester.pump();
      expect(floods, hasLength(2), reason: 'past the first: the next flood');
      final mark = overlay.fillRange!.outline;
      for (final at in floods) {
        expect(
          mark.contains(Offset(at.x.floor() + 0.5, at.y.floor() + 0.5)),
          isTrue,
          reason: 'both regions marked: $at',
        );
      }

      await pen.moveBy(const Offset(-120, 0));
      await tester.pump();
      expect(floods, hasLength(2), reason: 'back over the first: held already');
      expect(inkWhere(coordinator, floods.first), 0, reason: 'still held');

      await pen.up();
      await tester.pumpAndSettle();
      for (final at in floods) {
        expect(inkWhere(coordinator, at), isNonZero, reason: 'filled: $at');
      }
      expect(overlay.fillRange, isNull);
    });

    testWidgets('⛔a palm landing while the pen holds the fill takes '
        'nothing — the first press holds it', (tester) async {
      final saved = AppInput.settings.value;
      addTearDown(() => AppInput.settings.value = saved);
      AppInput.settings.value = saved.copyWith(
        touchDragOneFinger: CanvasTouchDragAction.draw,
      );
      final (:coordinator, :overlay, :floods) = await pumpHeld(tester);
      final origin = tester.getTopLeft(
        find.byKey(const ValueKey<String>('brush-canvas-view')),
      );
      final pen = await tester.startGesture(
        origin + const Offset(200, 100),
        kind: PointerDeviceKind.stylus,
      );
      await tester.pump();
      final palm = await tester.startGesture(
        origin + const Offset(400, 100),
        kind: PointerDeviceKind.touch,
      );
      await tester.pump();
      expect(floods, hasLength(1), reason: 'the palm floods nothing');
      await palm.up();
      await tester.pumpAndSettle();
      expect(inkWhere(coordinator, floods.single), 0, reason: 'still held');
      await pen.up();
      await tester.pumpAndSettle();
      expect(
        inkWhere(coordinator, floods.single),
        isNonZero,
        reason: 'the pen\'s fill lands',
      );
      expect(inkAt(coordinator, 400, 100), 0, reason: 'the palm\'s does not');
    });

    testWidgets('the mark is cut by the selection, as the fill is', (
      tester,
    ) async {
      final (:coordinator, :overlay, :floods) = await pumpHeld(
        tester,
        selection: CanvasSelectionRegion.shape(
          CanvasSelectionShape.rect(left: 0, top: 0, right: 200, bottom: 400),
        ),
      );
      final origin = tester.getTopLeft(
        find.byKey(const ValueKey<String>('brush-canvas-view')),
      );
      final pen = await tester.startGesture(
        origin + const Offset(200, 100),
        kind: PointerDeviceKind.stylus,
      );
      await tester.pump();
      final at = floods.single;
      final mark = overlay.fillRange!.outline;
      final row = at.y.floor() + 0.5;
      expect(mark.contains(Offset(at.x.floor() - 3.5, row)), isTrue);
      expect(
        mark.contains(Offset(at.x.floor() + 4.5, row)),
        isFalse,
        reason: 'past the selection nothing fills, so nothing is marked',
      );
      await pen.up();
      await tester.pump();
    });

    testWidgets('a second finger takes the mark away with the fill', (
      tester,
    ) async {
      final saved = AppInput.settings.value;
      addTearDown(() => AppInput.settings.value = saved);
      AppInput.settings.value = saved.copyWith(
        touchDragOneFinger: CanvasTouchDragAction.draw,
      );
      final (:coordinator, :overlay, :floods) = await pumpHeld(tester);
      final centre = tester.getCenter(
        find.byKey(const ValueKey<String>('brush-canvas-view')),
      );
      final first = await tester.startGesture(
        centre,
        kind: PointerDeviceKind.touch,
      );
      await tester.pump();
      expect(overlay.fillRange, isNotNull, reason: 'premise: held');
      final second = await tester.startGesture(
        centre + const Offset(40, 0),
        kind: PointerDeviceKind.touch,
      );
      await tester.pump();
      expect(overlay.fillRange, isNull, reason: 'a pinch, not a fill');
      await first.up();
      await second.up();
      await tester.pumpAndSettle();
      expect(inkWhere(coordinator, floods.first), 0);
    });
  });

  testWidgets('the bucket on the erase blend REMOVES ink', (tester) async {
    // The other half of 유저 확정 ③ (erase is in the blend list), and the
    // half that is easy to leave behind: this path builds its commit in
    // the interactive VIEW while the shape fill builds its own in the
    // panel. Erase rides a flag on the DAB, so passing only the blend mode
    // would paint the flooded region instead of clearing it — asserted on
    // the raster, because a flag can be set and still not erase.
    // ⚠️A REAL fill's pieces: a plain dab erases on the blend mode alone,
    // so it never takes the stamp's road, where erase is the dab's flag.
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
          brushToolState: ValueNotifier(BrushToolState.defaults.copyWith(
            tool: CanvasTool.fill,
            fillBlendMode: BrushBlendMode.erase,
          )),
          fillRangeAt: (_, _) => rangeOf(width: 16),
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
          fillRangeAt: (_, _) => rangeOf(),
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
          brushToolState: ValueNotifier(BrushToolState.defaults.copyWith(
            tool: CanvasTool.eyedropper,
          )),
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
          brushToolState: ValueNotifier(BrushToolState.defaults.copyWith(
            tool: CanvasTool.eyedropper,
          )),
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
          brushToolState: ValueNotifier(BrushToolState.defaults.copyWith(
            tool: CanvasTool.eyedropper,
          )),
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
          brushToolState: ValueNotifier(BrushToolState.defaults.copyWith(
            tool: CanvasTool.eyedropper,
          )),
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
          brushToolState: ValueNotifier(BrushToolState.defaults.copyWith(
            tool: CanvasTool.eyedropper,
          )),
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
    var floods = 0;

    await tester.pumpWidget(
      app(
        BrushCanvasPanel(
          coordinator: coordinator,
          availableFrameKeys: frameKeys,
          cacheInvalidationSink: BrushEditCacheInvalidationSink(),
          brushToolState: ValueNotifier(BrushToolState.defaults.copyWith(
            tool: CanvasTool.fill,
            color: 0xFF3366CC,
          )),
          fillRangeAt: (_, _) {
            floods += 1;
            return rangeOf();
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
    expect(floods, 1);
    expect(inkAt(coordinator, 4, 4), 0x3366CCFF);
    expect(
      coordinator.frameStore.celHasRenderableContent(frameKeys.first),
      isTrue,
    );

    // Middle-button regression pin (R22-B): a wheel-click pan attempt
    // must NEVER fill (it used to deposit stray entries — the
    // "two undos to remove one fill" bug).
    final before = floods;
    final gesture = await tester.createGesture(buttons: kMiddleMouseButton);
    await gesture.down(
      tester.getTopLeft(
            find.byKey(const ValueKey<String>('brush-canvas-view')),
          ) +
          const Offset(12, 12),
    );
    await gesture.up();
    await tester.pump();
    expect(floods, before, reason: 'middle click never fills');
  });

  testWidgets('a fill that spills off the canvas shows and lands its '
      'pasteboard tiles too — a fill is a stroke of one dab', (
    tester,
  ) async {
    final frameKeys = BrushCanvasFixture.createFrameKeys();
    final coordinator = BrushCanvasFixture.createCoordinator(
      frameKeys: frameKeys,
    );
    // A 64×64 range centred on the canvas ORIGIN lands at (-32, -32)..
    // (32, 32): three of its four tiles are pasteboard tiles.
    await tester.pumpWidget(
      app(
        BrushCanvasPanel(
          coordinator: coordinator,
          availableFrameKeys: frameKeys,
          cacheInvalidationSink: BrushEditCacheInvalidationSink(),
          brushToolState: ValueNotifier(BrushToolState.defaults.copyWith(
            tool: CanvasTool.fill,
          )),
          fillRangeAt: (_, _) =>
              rangeOf(left: -32, top: -32, width: 64, height: 64),
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
          brushToolState: ValueNotifier(BrushToolState.defaults.copyWith(
            tool: CanvasTool.fill,
          )),
          fillRangeAt: (_, _) => null,
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
    addTearDown(() => CanvasViewHold.held.value = null);
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

    CanvasViewHold.held.value = ViewHold.pan;
    await tester.pump();
    expect(hand, findsOneWidget, reason: 'the hand says what a press does');
    await mouseDrag();
    expect(viewports, isNotEmpty, reason: 'the drag moved the view');
    expect(drawn(), isFalse, reason: 'the brush stood down for the pan');

    CanvasViewHold.held.value = null;
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
    // The icon, mounted with the tool it is the cursor of (F-130).
    const trackerKey = ValueKey<String>('eyedropper-cursor-icon');
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
            brushToolState: ValueNotifier(
              BrushToolState.defaults.copyWith(tool: tool),
            ),
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
          brushToolState: ValueNotifier(BrushToolState.defaults.copyWith(
            tool: CanvasTool.eyedropper,
          )),
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
          brushToolState: ValueNotifier(BrushToolState.defaults.copyWith(
            tool: CanvasTool.eyedropper,
          )),
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
          brushToolState: ValueNotifier(BrushToolState.defaults.copyWith(
            tool: CanvasTool.eyedropper,
          )),
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
            brushToolState: ValueNotifier(BrushToolState.defaults.copyWith(
              tool: CanvasTool.cutStamp,
            )),
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
            brushToolState: ValueNotifier(BrushToolState.defaults.copyWith(
              tool: CanvasTool.eyedropper,
            )),
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
