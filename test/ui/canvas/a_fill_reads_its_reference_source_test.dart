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
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/canvas_color_sampler.dart';
import 'package:anicel/src/services/canvas_read_source.dart';
import 'package:anicel/src/services/editing/default_cut_helpers.dart';
import 'package:anicel/src/ui/brush/brush_tool_state.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/text/app_strings.dart';
import 'package:anicel/src/ui/widgets/app_icon_button.dart';
import 'package:anicel/src/ui/widgets/fill_reference_button.dart';

import '../../helpers/panel_finders.dart';

/// 🚨I-36 (유저 2026-09-24): 「범위를 보여주고, 활성 레이어의 참조 버튼을
/// 둔다」 + 「모드 세개. 참조(보이는거 전부), 참조(참조 설정한 레이어만, 없으면
/// 현재), 현재레이어」 — through the real app: the mode is picked on the fill's
/// own settings, the line under it names what the fill reads, the bucket
/// beside it flags the active layer with the rail's verb, and a tap on the
/// canvas reads exactly that.
///
/// The rig: a LINE layer under a COLOR layer, one red stroke on each, and a
/// blue fill tapped in the empty space between them. What the fill read is
/// what it went around — the stroke of a layer it read is a wall the blue
/// stops at; the stroke of a layer it did not read is floor it paints over.
void main() {
  const lineFrame = FrameId('fr-line-cel');
  const colorFrame = FrameId('fr-color-cel');
  const line = LayerId('fr-line');
  const color = LayerId('fr-color');
  const cutId = CutId('fr-cut');
  const red = 0xFFFF0000;
  const blue = 0xFF0000FF;
  const opaqueBlue = 0x0000FFFF;

  setUp(() => AppInput.settings.value = const AppInputSettings());
  tearDown(() => AppInput.settings.value = const AppInputSettings());

  Layer cel(LayerId id, FrameId frame) => Layer(
    id: id,
    name: id.value,
    frames: [
      Frame(id: frame, name: frame.value, duration: 1, strokes: const []),
    ],
    timeline: {0: TimelineExposure.drawing(frame, length: 1)},
  );

  Project project() => Project(
    id: const ProjectId('fr-project'),
    name: 'Fill reads',
    createdAt: DateTime.utc(2026),
    tracks: [
      Track(
        id: const TrackId('fr-track'),
        name: 'Video Track',
        cuts: [
          Cut(
            id: cutId,
            name: cutId.value,
            duration: defaultCutDuration,
            canvasSize: defaultCutCanvasSize,
            layers: [
              cel(line, lineFrame),
              cel(color, colorFrame),
              // A row the flag does not belong on, to stand on at the end.
              Layer(
                id: const LayerId('fr-photo'),
                name: 'fr-photo',
                frames: const [],
                kind: LayerKind.image,
              ),
            ],
          ),
        ],
      ),
    ],
  );

  EditorWorkspace workspaceOf(WidgetTester tester) =>
      tester.widget<EditorWorkspace>(find.byType(EditorWorkspace));

  EditorSessionManager sessionOf(WidgetTester tester) =>
      workspaceOf(tester).session;

  List<int> pixelsOf(WidgetTester tester, LayerId layer, FrameId frame) {
    final coordinator = sessionOf(tester).pixelEditingCoordinator!;
    final surface = coordinator.currentSurfaceOf(
      BrushFrameKey(
        projectId: const ProjectId('fr-project'),
        trackId: const TrackId('fr-track'),
        cutId: cutId,
        layerId: layer,
        frameId: frame,
      ),
    );
    final size = surface.canvasSize;
    return [
      for (var y = 0; y < size.height; y += 4)
        for (var x = 0; x < size.width; x += 4)
          surfacePixelRgba(surface, x, y) ?? 0,
    ];
  }

  Future<void> pumpFrames(WidgetTester tester, [int frames = 6]) async {
    for (var i = 0; i < frames; i += 1) {
      await tester.pump(const Duration(milliseconds: 16));
    }
  }

  Future<void> hold(WidgetTester tester, {CanvasTool? tool, int? argb}) async {
    final brush = workspaceOf(tester).brushTool!;
    brush.value = brush.value.copyWith(tool: tool, color: argb);
    await pumpFrames(tester);
  }

  Future<void> strokeAt(WidgetTester tester, Offset offset) async {
    final gesture = await tester.startGesture(
      visibleCanvasPoint(tester, offset: offset),
      kind: PointerDeviceKind.stylus,
    );
    await tester.pump();
    await gesture.moveBy(const Offset(24, 12));
    await tester.pump();
    await gesture.moveBy(const Offset(24, 12));
    await tester.pump();
    await gesture.up();
    await pumpFrames(tester);
  }

  Future<void> standOn(WidgetTester tester, LayerId layer) async {
    sessionOf(tester).selectLayer(layer);
    await pumpFrames(tester);
  }

  Finder segment(String label) => find.descendant(
    of: find.byKey(const ValueKey<String>('fill-source-segments')),
    matching: find.text(label),
  );

  String readout(WidgetTester tester) => tester
      .widget<Text>(find.byKey(const ValueKey<String>('fill-reads')))
      .data!;

  /// A window wide enough for the canvas beside the settings.
  Future<void> pumpApp(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(home: HomePage(initialProject: project())),
    );
    await tester.pumpAndSettle();
  }

  /// A press on something in the tool settings — which scroll, so it is
  /// brought into view first.
  Future<void> press(WidgetTester tester, Finder target) async {
    await tester.ensureVisible(target);
    await tester.pumpAndSettle();
    await tester.tap(target);
    await pumpFrames(tester);
  }

  /// The tool settings ship closed, behind the second button of the left
  /// sub-strip; a second press closes them again, off the canvas.
  Future<void> toggleToolSettings(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey<String>('rail-group-rail-L2')));
    await tester.pumpAndSettle();
  }

  /// Opens the settings, picks [label] from the fill's reference segments,
  /// reads the line under them, and closes the settings again.
  Future<String> pickSource(WidgetTester tester, String? label) async {
    await toggleToolSettings(tester);
    if (label != null) {
      await press(tester, segment(label));
    }
    final reads = readout(tester);
    await toggleToolSettings(tester);
    return reads;
  }

  /// The two strokes, then the bucket in hand — standing on the COLOR layer.
  Future<void> pumpRig(WidgetTester tester) async {
    await pumpApp(tester);
    await hold(tester, argb: red);
    await standOn(tester, line);
    await strokeAt(tester, const Offset(-120, -60));
    await standOn(tester, color);
    await strokeAt(tester, const Offset(60, 40));
    await hold(tester, tool: CanvasTool.fill, argb: blue);
  }

  /// Taps the blue in, well away from both strokes, and reports which of
  /// them it went around: the line stroke's cells on the COLOR layer, and
  /// the color stroke's own cells.
  Future<({bool paintedOverLine, bool paintedOverColor})> fill(
    WidgetTester tester,
  ) async {
    final lineStroke = [
      for (final (i, pixel) in pixelsOf(tester, line, lineFrame).indexed)
        if (pixel != 0) i,
    ];
    final colorStroke = [
      for (final (i, pixel) in pixelsOf(tester, color, colorFrame).indexed)
        if (pixel != 0) i,
    ];
    expect(lineStroke, isNotEmpty, reason: '⛔CONTROL: the line was drawn');
    expect(colorStroke, isNotEmpty, reason: '⛔CONTROL: the color was drawn');
    expect(
      lineStroke.toSet().intersection(colorStroke.toSet()),
      isEmpty,
      reason: '⛔CONTROL: the two strokes lie apart',
    );

    await tester.tapAt(
      visibleCanvasPoint(tester, offset: const Offset(-150, 80)),
      kind: PointerDeviceKind.stylus,
    );
    for (var i = 0; i < 6; i += 1) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 40)),
      );
      await tester.pump(const Duration(milliseconds: 16));
    }
    final after = pixelsOf(tester, color, colorFrame);
    expect(
      after.where((pixel) => pixel == opaqueBlue),
      isNotEmpty,
      reason: '⛔CONTROL: the bucket filled',
    );
    return (
      paintedOverLine: lineStroke.every((i) => after[i] == opaqueBlue),
      paintedOverColor: colorStroke.every((i) => after[i] == opaqueBlue),
    );
  }

  testWidgets('「보이는거 전부」 — both strokes are walls', (tester) async {
    await pumpRig(tester);
    expect(
      await pickSource(tester, null),
      AppText.strings.toolReadsEveryVisibleLayer,
      reason: 'the first mode is where the fill starts',
    );

    final went = await fill(tester);
    expect(went.paintedOverLine, isFalse);
    expect(went.paintedOverColor, isFalse);
  });

  testWidgets('「현재레이어」 — only the current layer\'s stroke is a wall', (
    tester,
  ) async {
    await pumpRig(tester);
    expect(await pickSource(tester, AppText.strings.tlLayer), color.value);

    final went = await fill(tester);
    expect(went.paintedOverLine, isTrue, reason: 'the line is not read');
    expect(went.paintedOverColor, isFalse);
  });

  testWidgets('「참조 설정한 레이어만」 — the flagged line is the wall, and the '
      'current layer\'s own stroke is not', (tester) async {
    await pumpRig(tester);
    sessionOf(tester).layerSwitches.toggleLayerFillReference(line);
    await pumpFrames(tester);
    expect(
      await pickSource(tester, AppText.strings.toolReadReferences),
      line.value,
    );

    final went = await fill(tester);
    expect(went.paintedOverLine, isFalse);
    expect(went.paintedOverColor, isTrue, reason: 'the color is not read');
  });

  testWidgets('「없으면 현재」 — nothing flagged reads the current layer', (
    tester,
  ) async {
    await pumpRig(tester);
    expect(
      await pickSource(tester, AppText.strings.toolReadReferences),
      color.value,
    );

    final went = await fill(tester);
    expect(went.paintedOverLine, isTrue);
    expect(went.paintedOverColor, isFalse);
  });

  testWidgets('the bucket beside the line flags the ACTIVE layer with the '
      'rail\'s verb — one undo — and is dead on a row that cannot carry it', (
    tester,
  ) async {
    await pumpApp(tester);
    await standOn(tester, color);
    await hold(tester, tool: CanvasTool.fill);
    await toggleToolSettings(tester);
    await press(tester, segment(AppText.strings.toolReadReferences));
    final session = sessionOf(tester);
    final bucket = find.byKey(
      const ValueKey<String>('fill-active-layer-reference'),
    );
    final before = session.historyManager.undoCount;

    FillReferenceButton face() => tester.widget<FillReferenceButton>(
      find.ancestor(of: bucket, matching: find.byType(FillReferenceButton)),
    );
    expect(face().isOn, isFalse);

    await press(tester, bucket);
    await pumpFrames(tester);
    expect(
      session.layers.firstWhere((layer) => layer.id == color).isFillReference,
      isTrue,
    );
    expect(face().isOn, isTrue, reason: 'the bucket wears the flag');
    expect(session.historyManager.undoCount, before + 1);
    expect(readout(tester), color.value, reason: 'the flagged layer is read');

    session.layerSwitches.toggleLayerFillReference(line);
    await pumpFrames(tester);
    expect(readout(tester), '${line.value} · ${color.value}');

    session.undo();
    session.undo();
    await pumpFrames(tester);
    expect(
      session.layers.any((layer) => layer.isFillReference),
      isFalse,
      reason: 'each press was its own undo step',
    );

    final photo = session.layers.firstWhere(
      (layer) => !layer.kind.carriesFillReference,
    );
    await standOn(tester, photo.id);
    expect(
      tester.widget<AppIconButtonFace>(bucket).onPressed,
      isNull,
      reason: 'only a drawing row carries the flag — the bucket stays, dead',
    );
  });

  testWidgets('the eyedropper offers its two, and a readout instead of a '
      'caption', (tester) async {
    await pumpApp(tester);
    await standOn(tester, color);
    await hold(tester, tool: CanvasTool.eyedropper);
    await toggleToolSettings(tester);
    final segments = find.byKey(
      const ValueKey<String>('eyedropper-source-segments'),
    );
    expect(
      tester
          .widget<SegmentedButton<CanvasReadSource>>(segments)
          .segments
          .map((segment) => segment.value),
      [CanvasReadSource.display, CanvasReadSource.layer],
    );
    final reads = find.byKey(const ValueKey<String>('eyedropper-reads'));
    expect(
      tester.widget<Text>(reads).data,
      AppText.strings.toolReadsEveryVisibleLayer,
    );
    await press(
      tester,
      find.descendant(
        of: segments,
        matching: find.text(AppText.strings.tlLayer),
      ),
    );
    expect(tester.widget<Text>(reads).data, color.value);
  });
}
