import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/app_input_settings.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
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
import 'package:anicel/src/services/fill_gradient.dart';
import 'package:anicel/src/ui/brush/brush_tool_state.dart';
import 'package:anicel/src/ui/brush/tool_settings_section.dart';
import 'package:anicel/src/ui/canvas/interactive_brush_edit_canvas_view.dart';
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/home_page.dart';

import '../../helpers/boolean_dot_probe.dart';
import '../../helpers/rail_group_button.dart';

/// I-160: the fill's knobs — 「연속 채우기」 (Q6) and the gradient (Q3 · Q4)
/// with the sub colour it runs to — are what the canvas a press lands on
/// asks, through the real app, so every hand the answer passes through on
/// its way down is in the path.
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
}
