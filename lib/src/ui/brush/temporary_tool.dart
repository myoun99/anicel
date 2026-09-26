import 'package:flutter/foundation.dart';

import 'brush_tool_state.dart';

/// Switches the tool while an input is HELD, and back when it lets go.
///
/// 🗣️I-15 (유저 2026-09-11): 「스포이드는 그대로 해서 누르는동안 툴
/// 바뀌도록. 툴 바껴서 해당툴을 사용한다는 심플한 규칙이 되도록」, and 「법
/// 하나로 통일」. A pen or mouse button mapped to a tool (PEN-7a) and a held
/// key are ONE law, so they are one piece of code: this. The canvas's mapped
/// holds and the shell's held keys both come here.
///
/// The tool it replaced lives in a [ToolHoldMemory] rather than here, so a
/// panel that remounts mid-hold still springs back. `??=` keeps the FIRST
/// original when two holds overlap — the later release then has nothing to
/// put back.
final class TemporaryTool {
  const TemporaryTool({
    required this.memory,
    required this.current,
    required this.change,
  });

  final ToolHoldMemory memory;

  /// The tool state in hand now.
  final BrushToolState Function() current;

  /// Where a changed tool state goes; null = nowhere to switch it (a host
  /// without the tool channel).
  final ValueChanged<BrushToolState>? change;

  void hold(CanvasTool tool) {
    memory.sprangFrom ??= current().tool;
    change?.call(current().copyWith(tool: tool));
  }

  /// [keep] leaves the held tool in hand — a mapping's 「keep」 release.
  void release({required bool keep}) {
    final original = memory.sprangFrom;
    memory.sprangFrom = null;
    if (!keep && original != null) {
      change?.call(current().copyWith(tool: original));
    }
  }
}

/// The tool a temporary hold sprang FROM; null = no hold live.
///
/// It lives outside the canvas area's State because the PEN TAIL holds for
/// as long as the pen stays flipped — across strokes, panel rebuilds and
/// tab switches — where a barrel hold lasted one press. A State that
/// unmounted mid-hold would lose the tool to spring back to, and leave the
/// user holding an eraser with nothing to undo it. Not a listenable: only
/// the release path reads it.
///
/// 🚨ONE per app, made by the shell beside the tool it remembers (I-7). It
/// sat on the session while a session outlived everything that remounts;
/// with a project per tab the session is what changes under a switch, and
/// the tool — the app's, shared by every project — does not.
final class ToolHoldMemory {
  CanvasTool? sprangFrom;
}
