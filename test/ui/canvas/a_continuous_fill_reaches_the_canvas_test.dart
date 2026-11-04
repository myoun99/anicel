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
import 'package:anicel/src/ui/brush/brush_tool_state.dart';
import 'package:anicel/src/ui/canvas/interactive_brush_edit_canvas_view.dart';
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/home_page.dart';

import '../../helpers/boolean_dot_probe.dart';
import '../../helpers/rail_group_button.dart';

/// I-160-Q6 「연속 채우기」: the switch in the fill's settings is what the
/// canvas a press lands on asks — through the real app, so every hand the
/// answer passes through on its way down is in the path.
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

  List<bool> asked(WidgetTester tester) => [
    for (final view in tester.widgetList<InteractiveBrushEditCanvasView>(
      find.byType(InteractiveBrushEditCanvasView),
    ))
      view.fillsContinuously?.call() ?? false,
  ];

  testWidgets('the switch is what the canvas asks', (tester) async {
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
    expect(asked(tester), isNotEmpty, reason: '⛔CONTROL: a canvas stands');
    expect(asked(tester), everyElement(isFalse), reason: 'off at first');

    await pressToolSettingsButton(tester);
    await tester.pumpAndSettle();
    final row = find.byKey(const ValueKey<String>('fill-continuous-switch'));
    await tester.ensureVisible(row);
    await tester.pumpAndSettle();
    await tester.pressRingIn(row);
    await tester.pumpAndSettle();

    expect(asked(tester), everyElement(isTrue));
  });
}
