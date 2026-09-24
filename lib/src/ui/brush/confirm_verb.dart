import 'package:flutter/foundation.dart';

import '../../services/last_stroke_slot.dart';
import 'brush_tool_state.dart';
import 'canvas_selection_commands.dart';
import 'transform_tool_options.dart';

/// 🚨★★★**확정 — ONE verb.** Enter, the rail's ↵ button and the move tool's
/// 적용 are its doors.
///
/// 🗣️유저 2026-09-24 (confirm-button-Q2): 「입구 확실하게 안전하게 해서
/// **일반상태=마지막 스트로크 재입력, 변형도구=변형중이지 않으면 마지막 변형
/// 재실행, 변형중이면 확정**, 이런식으로 입구 확실하게 통일하면서」.
///
/// ↩️Enter committed an open box and nothing else, while 적용 replayed the
/// last transform first — one word, two verbs, which is what 유저 found as
/// 「구현이 안 된 것 같다」 (confirm-button, 09-15 정정).
///
/// ⛔[canConfirm] and [confirm] read ONE function, so a door that is lit
/// always does something and one that is grey never does.
class ConfirmVerb {
  ConfirmVerb({
    required this.selection,
    required this.lastStroke,
    required this.tool,
    required this.transformOptions,
  });

  final CanvasSelectionCommands selection;
  final LastStrokeSlot lastStroke;
  final ValueListenable<BrushToolState> tool;

  /// Not read here: 적용 reads the armed MODE to pick the replay
  /// (`CanvasSelectionCommands.recallFor`), so a door showing [canConfirm]
  /// has to hear it change.
  final ValueListenable<TransformToolOptions> transformOptions;

  /// Everything [canConfirm] depends on.
  Listenable get changes =>
      Listenable.merge([selection, lastStroke, tool, transformOptions]);

  bool get canConfirm => _action() != null;

  void confirm() => _action()?.call();

  VoidCallback? _action() {
    // An open polygon outline is the newest thing a confirm can be closing,
    // and it is what the user is looking at (유저 확정 — 폴리곤 확정은 확정
    // 버튼으로).
    if (selection.hasOpenPolygon) {
      return selection.closePolygon;
    }
    // 변형도구 — or a transform still in play, whichever tool is up: a
    // session is the transform tool's work until it lands.
    if (tool.value.tool == CanvasTool.move ||
        selection.transformActive ||
        selection.movePending) {
      return selection.canApplyTransform ? selection.applyTransform : null;
    }
    return lastStroke.canReinput ? lastStroke.reinput : null;
  }
}
