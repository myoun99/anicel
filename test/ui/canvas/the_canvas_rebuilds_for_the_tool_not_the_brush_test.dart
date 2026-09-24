import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/ui/brush/brush_canvas_panel.dart';
import 'package:anicel/src/ui/brush/brush_tool_state.dart';
import 'package:anicel/src/ui/brush/main_canvas_brush_host.dart';
import 'package:anicel/src/ui/editor_canvas_area.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';

import '../../helpers/frame_census.dart';

/// 🚨H40 ② (2026-09-24): the brush changes by the frame — a preset pick,
/// every frame of a settings slider drag, a colour notch — and the editing
/// canvas's host heard all of it, so each change rebuilt the host, the
/// canvas panel under it and the panel's shell, which relaid out and
/// repainted for numbers it does not show. The host is built from the tool
/// and its shape ([BrushCanvasPanel.structureOf]) and nothing else of the
/// brush; the verbs read the rest when they run.
void main() {
  testWidgets('a size, a flow and a colour rebuild neither the canvas host '
      'nor its panel — a tool does', (tester) async {
    final s = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(s.dispose);
    final brushTool = ValueNotifier<BrushToolState>(BrushToolState.defaults);
    final cameraView = ValueNotifier<bool>(false);
    final cameraDim = ValueNotifier<double>(0.5);
    addTearDown(brushTool.dispose);
    addTearDown(cameraView.dispose);
    addTearDown(cameraDim.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EditorCanvasArea(
            session: s,
            brushToolState: brushTool,
            cameraViewEnabled: cameraView,
            cameraDimOpacity: cameraDim,
          ),
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(find.byType(BrushCanvasPanel), findsOneWidget);

    final quiet = await frameCensus(
      tester,
      () => brushTool.value = brushTool.value.copyWith(
        size: 40,
        flow: 0.3,
        color: 0xFF336699,
      ),
    );
    expect(quiet.rebuilt, isNot(contains(MainCanvasBrushHost)));
    expect(quiet.rebuilt, isNot(contains(BrushCanvasPanel)));

    // CONTROL — the census sees a rebuild when there is one.
    final loud = await frameCensus(
      tester,
      () => brushTool.value = brushTool.value.copyWith(tool: CanvasTool.eraser),
    );
    expect(loud.rebuilt, contains(MainCanvasBrushHost));
    expect(loud.rebuilt, contains(BrushCanvasPanel));

    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
  });
}
