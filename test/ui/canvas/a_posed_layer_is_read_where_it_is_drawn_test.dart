import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/app_input_settings.dart';
import 'package:anicel/src/models/brush_frame_key.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/property_track.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/models/transform_track.dart';
import 'package:anicel/src/services/canvas_color_sampler.dart';
import 'package:anicel/src/services/editing/default_cut_helpers.dart';
import 'package:anicel/src/ui/brush/brush_tool_state.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/home_page.dart';

import '../../helpers/panel_finders.dart';

/// 🚨I-36 — 「이 과정에서 법 다른거 통일」: on a TRANSFORMED layer, the tools
/// that read the picture read it where it is drawn.
///
/// The pen on a posed layer is inside the draw-through wrap: its points are
/// in that layer's ARTWORK. A pick held from a mapped button (the right
/// click, by default) was read as if it were the canvas, and the fill laid
/// its raster in the canvas under a seed that was not — so on a transformed
/// layer both read somewhere the pointer was not.
void main() {
  const lineCel = FrameId('pl-line-cel');
  const paintCel = FrameId('pl-paint-cel');
  const line = LayerId('pl-line');
  const paint = LayerId('pl-paint');
  const red = 0xFFFF0000;
  const green = 0xFF00FF00;
  const blue = 0xFF0000FF;
  const opaqueBlue = 0x0000FFFF;

  setUp(() => AppInput.settings.value = const AppInputSettings());
  tearDown(() => AppInput.settings.value = const AppInputSettings());

  Layer cel(LayerId id, FrameId frame, {double? scale}) => Layer(
    id: id,
    name: id.value,
    frames: [
      Frame(id: frame, name: frame.value, duration: 1, strokes: const []),
    ],
    timeline: {0: TimelineExposure.drawing(frame, length: 1)},
    // Twice the size about the canvas centre: the artwork under a pointer
    // away from the centre is somewhere else.
    transformTrack: scale == null
        ? null
        : TransformTrack.empty().copyWith(
            scale: PropertyTrack<double>.empty().withKey(0, scale),
          ),
  );

  Project project() => Project(
    id: const ProjectId('pl-project'),
    name: 'Posed',
    createdAt: DateTime.utc(2026),
    tracks: [
      Track(
        id: const TrackId('pl-track'),
        name: 'Video Track',
        cuts: [
          Cut(
            id: const CutId('pl-cut'),
            name: 'pl-cut',
            duration: defaultCutDuration,
            canvasSize: defaultCutCanvasSize,
            layers: [cel(line, lineCel), cel(paint, paintCel, scale: 2)],
          ),
        ],
      ),
    ],
  );

  EditorWorkspace workspaceOf(WidgetTester tester) =>
      tester.widget<EditorWorkspace>(find.byType(EditorWorkspace));

  EditorSessionManager sessionOf(WidgetTester tester) =>
      workspaceOf(tester).session;

  Future<void> pumpFrames(WidgetTester tester, [int frames = 6]) async {
    for (var i = 0; i < frames; i += 1) {
      await tester.pump(const Duration(milliseconds: 16));
    }
  }

  Future<void> pumpApp(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(home: HomePage(initialProject: project())),
    );
    await tester.pumpAndSettle();
  }

  Future<void> hold(WidgetTester tester, {CanvasTool? tool, int? argb}) async {
    final brush = workspaceOf(tester).brushTool!;
    brush.value = brush.value.copyWith(tool: tool, color: argb);
    await pumpFrames(tester);
  }

  Future<void> standOn(WidgetTester tester, LayerId layer) async {
    sessionOf(tester).selectLayer(layer);
    await pumpFrames(tester);
  }

  /// A red scribble well away from the centre; returns a point on it.
  Future<Offset> scribble(WidgetTester tester) async {
    final at = visibleCanvasPoint(tester, offset: const Offset(120, 70));
    final pen = await tester.startGesture(at, kind: PointerDeviceKind.stylus);
    await tester.pump();
    for (var i = 0; i < 6; i += 1) {
      await pen.moveBy(const Offset(4, 2));
      await tester.pump();
    }
    await pen.up();
    await pumpFrames(tester);
    return at + const Offset(8, 4);
  }

  testWidgets('a right-click pick on a TRANSFORMED layer picks the colour '
      'under the pointer', (tester) async {
    await pumpApp(tester);
    await standOn(tester, paint);
    await hold(tester, argb: red);
    final onTheRed = await scribble(tester);
    await hold(tester, argb: green);

    final mouse = await tester.startGesture(
      onTheRed,
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryMouseButton,
    );
    await tester.pump();
    await mouse.up();
    await pumpFrames(tester);

    expect(
      workspaceOf(tester).brushTool!.value.color,
      red,
      reason: 'the held pick read the red stroke under the pointer — not the '
          'paper at the artwork coordinates taken for canvas ones',
    );
  });

  testWidgets('a fill on a TRANSFORMED layer reads the line art where the '
      'pointer is', (tester) async {
    await pumpApp(tester);
    // The red line on the plain layer; the fill on the one scaled 2×.
    await standOn(tester, line);
    await hold(tester, argb: red);
    final onTheRed = await scribble(tester);
    await standOn(tester, paint);
    await hold(tester, tool: CanvasTool.fill, argb: blue);

    await tester.tapAt(onTheRed, kind: PointerDeviceKind.stylus);
    for (var i = 0; i < 6; i += 1) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 40)),
      );
      await tester.pump(const Duration(milliseconds: 16));
    }

    final surface = sessionOf(tester).pixelEditingCoordinator!
        .currentSurfaceOf(
          const BrushFrameKey(
            projectId: ProjectId('pl-project'),
            trackId: TrackId('pl-track'),
            cutId: CutId('pl-cut'),
            layerId: paint,
            frameId: paintCel,
          ),
        );
    final size = surface.canvasSize;
    var cells = 0;
    var filled = 0;
    for (var y = 0; y < size.height; y += 4) {
      for (var x = 0; x < size.width; x += 4) {
        cells += 1;
        if (surfacePixelRgba(surface, x, y) == opaqueBlue) {
          filled += 1;
        }
      }
    }
    expect(filled, greaterThan(0), reason: '⛔CONTROL: the bucket filled');
    expect(
      filled,
      lessThan(cells ~/ 20),
      reason: 'seeded ON the red line, the fill keeps to the line — read in '
          'the canvas under an artwork seed it landed on paper and flooded '
          'the whole layer',
    );
  });
}
