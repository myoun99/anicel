import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/camera_instruction.dart';
import 'package:anicel/src/models/project_background.dart';
import 'package:anicel/src/ui/brush/brush_tool_state.dart';
import 'package:anicel/src/ui/editor_canvas_area.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';

/// 🗣️F-192 (유저 2026-09-27): 「컷의 f.i은 빈공간에서가 생기는게 아니라,
/// 컷의 페이드인은 애초에 쌩 검은화면에서 바뀐단거였음. 화이트인은 쌩
/// 흰화면에서 바뀌는거고 … 백그라운드색을 바꾸는거말고 구조적으로」.
///
/// The PIXELS of the editing canvas standing inside a fade — the surface the
/// user reported from. The paper is a green sentinel and the backdrop red:
/// the old law thinned the cut down to the backdrop, so a closed F.O showed
/// red here (and a backdrop of NONE showed empty space — the report).
void main() {
  const paperArgb = 0xFF00FF00;

  bool isPaper(int r, int g, int b) => g > 200 && r < 80 && b < 80;
  bool isBlack(int r, int g, int b) => r < 16 && g < 16 && b < 16;
  bool isWhite(int r, int g, int b) => r > 240 && g > 240 && b > 240;
  bool isBackdrop(int r, int g, int b) => r > 200 && g < 80 && b < 80;

  /// The default project on green paper and a red backdrop, a fade [term]
  /// over the cut's first five frames, standing on its frame [frame].
  EditorSessionManager standingInAFade(String term, int frame) {
    final s = EditorSessionManager(initialProject: createDefaultProject());
    s.projectSettings.setProjectBackground(
      const ProjectBackground.color(paperArgb),
    );
    s.projectSettings.setProjectBackdrop(0xFFFF0000);
    s.transitions.updateTransitionInstructions({
      0: InstructionEvent(instructionId: term, length: 5),
    });
    s.selectFrameIndex(frame);
    return s;
  }

  Future<void> pumpArea(WidgetTester tester, EditorSessionManager s) async {
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
    await tester.pumpAndSettle();
  }

  /// How many pixels of the canvas area are each of [kinds].
  Future<List<int>> count(
    WidgetTester tester,
    List<bool Function(int r, int g, int b)> kinds,
  ) async {
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find
          .descendant(
            of: find.byType(EditorCanvasArea),
            matching: find.byType(RepaintBoundary),
          )
          .first,
    );
    final image = (await tester.runAsync(boundary.toImage))!;
    final bytes = (await tester.runAsync(
      () => image.toByteData(format: ui.ImageByteFormat.rawRgba),
    ))!;
    image.dispose();
    final counts = List<int>.filled(kinds.length, 0);
    for (var offset = 0; offset < bytes.lengthInBytes; offset += 4) {
      final r = bytes.getUint8(offset);
      final g = bytes.getUint8(offset + 1);
      final b = bytes.getUint8(offset + 2);
      for (var i = 0; i < kinds.length; i += 1) {
        if (kinds[i](r, g, b)) {
          counts[i] += 1;
        }
      }
    }
    return counts;
  }

  Future<void> drainWarming(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
  }

  testWidgets('standing where an F.O has closed, the canvas is BLACK — not '
      'the backdrop behind it', (tester) async {
    final s = standingInAFade('fo', 4);
    addTearDown(s.dispose);
    await pumpArea(tester, s);
    final [paper, black, backdrop] = await count(tester, [
      isPaper,
      isBlack,
      isBackdrop,
    ]);
    expect(paper, 0, reason: 'the screen covers the paper');
    expect(black, greaterThan(1000), reason: 'and it is black');
    expect(backdrop, 0, reason: 'nothing behind the cut shows through');
    await drainWarming(tester);
  });

  testWidgets('standing where a W.I begins, the canvas is WHITE', (
    tester,
  ) async {
    final s = standingInAFade('wi', 0);
    addTearDown(s.dispose);
    await pumpArea(tester, s);
    final [paper, white] = await count(tester, [isPaper, isWhite]);
    expect(paper, 0);
    expect(white, greaterThan(1000));
    await drainWarming(tester);
  });

  testWidgets('CONTROL: past the fade the paper shows', (tester) async {
    final s = standingInAFade('fo', 6);
    addTearDown(s.dispose);
    await pumpArea(tester, s);
    final [paper] = await count(tester, [isPaper]);
    expect(paper, greaterThan(1000));
    await drainWarming(tester);
  });
}
