import 'package:flutter/foundation.dart';

import 'brush_tool_state.dart';

/// The app's active-tool notifier with PER-PAINT-TOOL memory (R11-④):
/// the brush and the eraser each keep their own stroke settings (size,
/// tip, preset payload…) — switching tools stashes the outgoing paint
/// tool's state and restores the incoming one's, CSP-style. COLOR and the
/// stabilizer stay shared across tools (the color panel and the hand-feel
/// setting are global).
///
/// Non-paint tools (eyedropper, fill, selections) carry the current
/// settings through unchanged — they never stroke, and the shared color
/// keeps working for fill/eyedropper.
class PaintToolStateNotifier extends ValueNotifier<BrushToolState> {
  PaintToolStateNotifier(super.value);

  final Map<CanvasTool, BrushToolState> _paintToolBank =
      <CanvasTool, BrushToolState>{};

  /// The tool-switch GUARD (R26 #13): returns a refusal MESSAGE to block
  /// the switch, null to allow it. Installed once by the shell — every
  /// entrance (toolbar, library panel, shortcut, Ctrl+T, mapped pen
  /// button) writes through this one setter, so a refusal cannot be
  /// routed around.
  String? Function(CanvasTool tool)? switchGuard;

  /// Where a refusal is announced (the shared cursor notice).
  void Function(String message)? onSwitchRefused;

  @override
  set value(BrushToolState next) {
    final previous = value;
    if (next.tool != previous.tool) {
      final refusal = switchGuard?.call(next.tool);
      if (refusal != null) {
        onSwitchRefused?.call(refusal);
        // The refusal blocks the TOOL only — settings carried in the
        // same write still apply (a preset landing while blocked).
        final kept = next.copyWith(tool: previous.tool);
        if (kept != previous) {
          super.value = kept;
        }
        return;
      }
    }
    if (next.tool != previous.tool) {
      if (canvasToolPaints(previous.tool)) {
        _paintToolBank[previous.tool] = previous;
      }
      // Restore ONLY on a pure tool switch (the caller changed nothing but
      // the tool) — an assignment that also carries new settings (a preset
      // application landing on the brush) must win over the bank.
      final pureToolSwitch = next.copyWith(tool: previous.tool) == previous;
      final stored = pureToolSwitch && canvasToolPaints(next.tool)
          ? _paintToolBank[next.tool]
          : null;
      if (stored != null) {
        // 🚨★★★ 유저 #14 (2026-08-14): 「선택툴에서 올가미 선택하고 브러시가면
        // 초기화되는거」 — ⛔THE LIST RUNS THE OTHER WAY NOW.
        //
        // This restored `stored` WHOLE and carved out the two shared values
        // (`color`, `stabilizerStrength`). Everything not named was
        // therefore REVERTED — and the state carries other tools' fields:
        // `selectShape` / `cutShape` / `fillShape` (유저: 도형은 동사별로
        // 기억) plus the fill's and the stamp's blends. Pick the lasso, tap
        // the brush, and a snapshot from before the pick put the box back.
        // From the very first frame, because the app starts on the brush.
        //
        // 🚨★★Third time this round a hand-written carry list went stale as
        // fields were added (`withMask` passed three and reset the shapes;
        // `withPresetSettings` dropped them). The DIRECTION is what makes
        // this one safe: build from the LIVE state and pull back only what
        // the bank exists to remember — this paint tool's own brush and its
        // blend. A field added tomorrow is then shared by default, a mild
        // wrong; under the old direction it silently reverted, which is the
        // bug.
        //
        // ⚠️`color` is re-asserted on top because it rides INSIDE the shape
        // — swapping the brush swaps its colour with it, and the colour is
        // shared across tools. That is the order `copyWith` documents: the
        // individual arguments win over the shape laid down beneath them.
        // `stabilizerStrength` needs no such line; it is its own field, so
        // building from `next` already keeps the live one.
        next = next.copyWith(
          shape: stored.shape,
          color: next.color,
          brushBlendMode: stored.brushBlendMode,
        );
      }
    }
    super.value = next;
  }
}
