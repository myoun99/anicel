import 'package:flutter/foundation.dart';

import '../editor_session_manager.dart';
import 'brush_tool_state.dart';

/// Switches the tool while an input is HELD, and back when it lets go.
///
/// 🗣️I-15 (유저 2026-09-11): 「스포이드는 그대로 해서 누르는동안 툴
/// 바뀌도록. 툴 바껴서 해당툴을 사용한다는 심플한 규칙이 되도록」, and 「법
/// 하나로 통일」. A pen or mouse button mapped to a tool (PEN-7a) and a held
/// key are ONE law, so they are one piece of code: this. The canvas's mapped
/// holds and the shell's held keys both come here.
///
/// The tool it replaced lives on the SESSION
/// ([EditorSessionManager.heldOriginalTool]) rather than here, so a panel
/// that remounts mid-hold still springs back. `??=` keeps the FIRST original
/// when two holds overlap — the later release then has nothing to put back.
final class TemporaryTool {
  const TemporaryTool({
    required this.session,
    required this.current,
    required this.change,
  });

  final EditorSessionManager session;

  /// The tool state in hand now.
  final BrushToolState Function() current;

  /// Where a changed tool state goes; null = nowhere to switch it (a host
  /// without the tool channel).
  final ValueChanged<BrushToolState>? change;

  void hold(CanvasTool tool) {
    session.heldOriginalTool ??= current().tool;
    change?.call(current().copyWith(tool: tool));
  }

  /// [keep] leaves the held tool in hand — a mapping's 「keep」 release.
  void release({required bool keep}) {
    final original = session.heldOriginalTool;
    session.heldOriginalTool = null;
    if (!keep && original != null) {
      change?.call(current().copyWith(tool: original));
    }
  }
}
