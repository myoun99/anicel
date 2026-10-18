import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/app_input_settings.dart';
import 'package:anicel/src/ui/brush/brush_tool_state.dart';
import 'package:anicel/src/ui/editor_canvas_area.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/panels/tool_size_preset_panel.dart';

import '../../helpers/touch_batches.dart';

/// 🗣️F-391 (유저 2026-10-17): 「브러시 크기 스냅은 해당 쓰던 로직있으면 툴
/// 사이즈 패널을 바탕으로 사용하도록 변경하고, 설정의 브러시크기스냅은
/// 필요없어지니 잔재 삭제」 — the canvas's three-finger size drag, held by a
/// late finger, catches on the tool size panel's rack: the sizes the size
/// bar's ± step through (F-325).
void main() {
  tearDown(() {
    AppInput.settings.value = AppInputSettings.testCorpusBaseline;
  });

  testWidgets('a size drag the late finger holds lands on the rack', (
    tester,
  ) async {
    // The engine stands down while one finger draws — the corpus baseline.
    AppInput.settings.value = AppInputSettings.testCorpusBaseline.copyWith(
      touchDragOneFinger: CanvasTouchDragAction.flip,
    );
    final session = EditorSessionManager(
      initialProject: createDefaultProject(),
    );
    addTearDown(session.dispose);
    final brushTool = ValueNotifier<BrushToolState>(
      BrushToolState.defaults.withActiveSize(10),
    );
    final cameraView = ValueNotifier<bool>(false);
    final cameraDim = ValueNotifier<double>(0.5);
    addTearDown(brushTool.dispose);
    addTearDown(cameraView.dispose);
    addTearDown(cameraDim.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EditorCanvasArea(
            session: session,
            brushToolState: brushTool,
            onBrushToolStateChanged: (next) => brushTool.value = next,
            cameraViewEnabled: cameraView,
            cameraDimOpacity: cameraDim,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final fingers = await fingersDown(tester, const [
      Offset(300, 300),
      Offset(360, 300),
      Offset(420, 300),
    ]);
    // The lock batch: the drag starts here.
    await batch(tester, moveAll(fingers, const Offset(0, -30)));
    final late = TestPointer(9, PointerDeviceKind.touch);
    await tester.sendEventToBinding(late.down(const Offset(600, 450)));
    await tester.pump();
    await batch(tester, moveAll(fingers, const Offset(0, -30)));

    // 10 × 2^(30/120) ≈ 11.9, which the rack holds as 12 — not the 11.9 the
    // drag made, and not the 8 of the ladder the settings kept.
    expect(ToolSizePresetPanel.presets, contains(12));
    expect(brushTool.value.activeSize, 12);

    await tester.sendEventToBinding(late.up());
    await liftAll(tester, fingers);
  });
}
