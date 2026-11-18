import 'dart:math';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/app_input_settings.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/drawing_guide.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/editing/default_cut_helpers.dart';
import 'package:anicel/src/services/canvas_flood_fill.dart';
import 'package:anicel/src/services/canvas_selection_region.dart';
import 'package:anicel/src/services/canvas_selection_shape.dart';
import 'package:anicel/src/services/fill_gradient.dart';
import 'package:anicel/src/ui/brush/brush_canvas_panel.dart';
import 'package:anicel/src/ui/brush/brush_tool_state.dart';
import 'package:anicel/src/ui/brush/tool_settings_section.dart';
import 'package:anicel/src/ui/canvas/interactive_brush_edit_canvas_view.dart';
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/home_page.dart';

import '../../helpers/a_canvas_standing_on_a_frame.dart';
import '../../helpers/boolean_dot_probe.dart';
import '../../helpers/panel_finders.dart';
import '../../helpers/rail_group_button.dart';

/// I-160: the fill's knobs — 「연속 채우기」 (Q6) and the gradient (Q3 · Q4)
/// with the sub colour it runs to — are what the canvas a press lands on
/// asks, through the real app, so every hand the answer passes through on
/// its way down is in the path. And the fill it is asked for is laid at the
/// fill's own opacity, from every copy the guide makes of the press.
void main() {
  setUp(() => AppInput.settings.value = const AppInputSettings());
  tearDown(() => AppInput.settings.value = const AppInputSettings());

  Project project() => Project(
    id: const ProjectId('cf-project'),
    name: 'Continuous fill',
    createdAt: DateTime.utc(2026),
    tracks: [
      Track(
        id: const TrackId('cf-track'),
        name: 'Video Track',
        cuts: [
          Cut(
            id: const CutId('cf-cut'),
            name: 'cf-cut',
            duration: defaultCutDuration,
            canvasSize: defaultCutCanvasSize,
            layers: [
              Layer(
                id: const LayerId('cf-layer'),
                name: 'cf-layer',
                frames: [
                  Frame(
                    id: const FrameId('cf-cel'),
                    name: 'cf-cel',
                    duration: 1,
                    strokes: const [],
                  ),
                ],
                timeline: {
                  0: const TimelineExposure.drawing(
                    FrameId('cf-cel'),
                    length: 1,
                  ),
                },
              ),
            ],
          ),
        ],
      ),
    ],
  );

  /// What every drawing canvas asks of [knob].
  List<T> asked<T>(
    WidgetTester tester,
    T Function(InteractiveBrushEditCanvasView view) knob,
  ) => [
    for (final view in tester.widgetList<InteractiveBrushEditCanvasView>(
      find.byType(InteractiveBrushEditCanvasView),
    ))
      knob(view),
  ];

  /// The app with the fill in hand and its settings open.
  Future<void> pumpFill(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(home: HomePage(initialProject: project())),
    );
    await tester.pumpAndSettle();
    final brush = tester
        .widget<EditorWorkspace>(find.byType(EditorWorkspace))
        .brushTool!;
    brush.value = brush.value.copyWith(tool: CanvasTool.fill);
    await tester.pumpAndSettle();
    await pressToolSettingsButton(tester);
    await tester.pumpAndSettle();
  }

  /// A press on the settings' [key] — which scroll, and build only what
  /// they show, so they are taken to their end first. ⛔Not dragged there:
  /// a drag landing on a slider is the slider's.
  Future<void> press(WidgetTester tester, String key, {bool ring = false}) async {
    final settings = tester.state<ScrollableState>(
      find
          .descendant(
            of: find.byKey(ToolSettingsSection.keyFor('fill')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    settings.position.jumpTo(settings.position.maxScrollExtent);
    await tester.pumpAndSettle();
    final target = find.byKey(ValueKey<String>(key));
    await tester.ensureVisible(target);
    await tester.pumpAndSettle();
    if (ring) {
      await tester.pressRingIn(target);
    } else {
      await tester.tap(target);
    }
    await tester.pumpAndSettle();
  }

  testWidgets('「연속 채우기」: the switch is what the canvas asks', (
    tester,
  ) async {
    await pumpFill(tester);
    bool continuous(InteractiveBrushEditCanvasView view) =>
        view.fillsContinuously?.call() ?? false;
    expect(asked(tester, continuous), isNotEmpty, reason: '⛔CONTROL');
    expect(asked(tester, continuous), everyElement(isFalse));

    await press(tester, 'fill-continuous-switch', ring: true);
    expect(asked(tester, continuous), everyElement(isTrue));
  });

  testWidgets('the gradient: its knobs, and the rail swatch\'s back slot as '
      'the sub colour, are what the canvas asks', (tester) async {
    await pumpFill(tester);
    FillGradientInHand? inHand(InteractiveBrushEditCanvasView view) =>
        view.fillGradient?.call();
    expect(asked(tester, inHand), isNotEmpty, reason: '⛔CONTROL');
    expect(
      asked(tester, inHand).map((hand) => hand?.options),
      everyElement(const FillGradientOptions()),
      reason: 'off at first',
    );

    await press(tester, 'fill-gradient-switch', ring: true);
    await press(tester, 'fill-gradient-end-transparent');
    await press(tester, 'fill-gradient-reverse-switch', ring: true);
    await press(tester, 'fill-gradient-shape-radial');
    tester
            .widget<EditorWorkspace>(find.byType(EditorWorkspace))
            .colorBackground!
            .value =
        0xFF123456;
    expect(
      asked(tester, inHand),
      everyElement((
        options: const FillGradientOptions(
          enabled: true,
          end: FillGradientEnd.transparent,
          reversed: true,
          shape: FillGradientShape.radial,
        ),
        sub: 0xFF123456,
      )),
    );
  });

  // What a press asks the canvas for a fill by, beside the fill's options:
  // the fill's own opacity (TP1 — the strip's bar writes the fill's field,
  // not the brush's) and the guide the view read — a symmetry floods from
  // every copy it makes of the press (mutants GI3 · GI4 lived, 2026-11-12).
  group('a fill the canvas is asked for', () {
    // It reads the frame's picture on the engine.
    opensTheEnginesScreens();

    testWidgets('is laid at the fill\'s own opacity, and floods from every '
        'copy a symmetry makes of the press', (tester) async {
      tester.view.physicalSize = const Size(1600, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(home: HomePage(initialProject: project())),
      );
      await tester.pumpAndSettle();
      final workspace = tester.widget<EditorWorkspace>(
        find.byType(EditorWorkspace),
      );
      final session = workspace.session;
      const layer = LayerId('cf-layer');
      session.selectLayer(layer);
      await tester.pumpAndSettle();

      // A closed loop, right of the canvas's middle.
      final pen = await tester.startGesture(
        visibleCanvasPoint(tester, offset: const Offset(60, -30)),
        kind: PointerDeviceKind.stylus,
      );
      await tester.pump();
      for (final side in const [
        Offset(10, 0),
        Offset(0, 10),
        Offset(-10, 0),
        Offset(0, -10),
      ]) {
        for (var step = 0; step < 6; step += 1) {
          await pen.moveBy(side);
          await tester.pump();
        }
      }
      await pen.up();
      await tester.pumpAndSettle();

      // What the loop encloses: the middle of its ink's box.
      final surface = session.pixelEditing.coordinator!.currentSurfaceOf(
        session.brushFrameKeyForCut(
          session.requireActiveCut,
          layer,
          const FrameId('cf-cel'),
        ),
      );
      var (left, top, right, bottom) = (1 << 30, 1 << 30, -1, -1);
      for (final MapEntry(key: at, value: tile) in surface.tiles.entries) {
        final ink = tile.inkBounds;
        if (ink == null || ink.rightExclusive <= ink.left) {
          continue;
        }
        final (x, y) = (at.x * surface.tileSize, at.y * surface.tileSize);
        left = min(left, x + ink.left);
        top = min(top, y + ink.top);
        right = max(right, x + ink.rightExclusive);
        bottom = max(bottom, y + ink.bottomExclusive);
      }
      expect(right, greaterThan(left), reason: '⛔CONTROL: the loop is drawn');
      final inside = CanvasPoint(x: (left + right) / 2, y: (top + bottom) / 2);

      final brush = workspace.brushTool!;
      brush.value = brush.value.copyWith(
        tool: CanvasTool.fill,
        fillOpacity: 0.5,
      );
      await tester.pumpAndSettle();

      // Where a half turn about the canvas's middle brings the loop's
      // inside from: the open canvas, left of the middle.
      const size = defaultCutCanvasSize;
      final press = CanvasPoint(
        x: size.width - inside.x,
        y: size.height - inside.y,
      );
      final halfTurn = SymmetryShape(
        axis: GuideAxis(
          origin: CanvasPoint(x: size.width / 2, y: size.height / 2),
          angleDegrees: 90,
        ),
        lineSymmetry: false,
      );
      final fills = asked<FillRangeAt?>(
        tester,
        (view) => view.fillRangeAt,
      ).nonNulls.toList();
      expect(fills, isNotEmpty, reason: '⛔CONTROL');
      for (final fillRangeAt in fills) {
        final alone = fillRangeAt(press, null)!;
        expect(
          alone.covers(inside),
          isFalse,
          reason: '⛔premise: the loop walls its inside off',
        );
        expect(alone.dabsIn(0xFF3366CC).first.opacity, 0.5);
        expect(fillRangeAt(press, halfTurn)!.covers(inside), isTrue);
      }
    });
  });

  testWidgets('the shape fill: what its outline covers is a range the '
      'canvas can hold for its gradient', (tester) async {
    await pumpFill(tester);
    final outline = CanvasSelectionRegion.shape(
      CanvasSelectionShape.rect(left: 10, top: 10, right: 30, bottom: 20),
    );
    // Every canvas the shape fill lays on can hold what it covers.
    final ranges = [
      for (final panel in tester.widgetList<BrushCanvasPanel>(
        find.byType(BrushCanvasPanel),
      ))
        if (panel.shapeFillDabsFor != null)
          panel.shapeFillRangeFor?.call(outline),
    ];
    expect(ranges, isNotEmpty, reason: '⛔CONTROL');
    for (final range in ranges) {
      expect(range?.covers(CanvasPoint(x: 20, y: 15)), isTrue);
      expect(range?.covers(CanvasPoint(x: 40, y: 15)), isFalse);
    }
  });
}
