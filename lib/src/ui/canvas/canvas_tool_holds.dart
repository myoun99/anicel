import 'package:flutter/gestures.dart' show PointerEvent;

import '../../models/app_input_settings.dart';
import '../../services/input/pen_sidecars.dart';
import '../brush/brush_tool_state.dart' show CanvasTool;

/// WHO HOLDS THE TOOL ON A CANVAS RIGHT NOW, besides the hand on the keys.
///
/// A pen's tail and a mapped button each switch the tool for as long as
/// they last, through the one hold the shell keeps (`TemporaryTool`), and
/// whichever engaged first keeps it: a barrel press that took the tool
/// mid-flip would leave the tail with nothing to spring back to when the
/// pen is turned upright, and a flip under a held button would do the same
/// to the button.
///
/// They are read in two places. A press that ERASES is the DRAWING VIEW's
/// — the stroke starts with that press and carries the erase in its own
/// settings. A button held for a pick draws nothing, so the canvas panel
/// reads it where every press on the canvas passes: under every tool, with
/// or without a cel (F-299, 유저 2026-10-05: 「어떤 도구 들고있던 규칙
/// 만들지말고 법 통일해서 작동하도록」). This is what each of the two tells
/// the other.
///
/// 🚨And the panel is where an erasing press comes in under the tools whose
/// own layer lies over the drawing view — the selection, the transform, the
/// cut, the shape fill, the stamp, the eyedropper (measured 2026-10-07: the
/// eraser's four roads answered under the brush, the eraser, the bucket and
/// the guide, and under none of those six). The view cannot hear a press
/// that landed on another layer, so the panel reads the tail in the air
/// ([syncPenTail]) and hands the view the press ([handOver]). The stroke is
/// still the view's own, start to finish.
///
/// A panel hands its own to the view it builds; a view nobody handed one —
/// a sheet's ink — keeps its own, and no button ever holds a pick there.
final class CanvasToolHolds {
  /// The pen is turned over and its tail's mapping holds the tool. Written
  /// by [syncPenTail], at every hover and contact either reader hears.
  bool penTail = false;

  /// A mapped button holds the tool for a pick — pressed while the pen
  /// hovers, or in contact. Written by the panel's reader of mapped
  /// buttons.
  bool pick = false;

  /// A mapped button holds the tool for the ERASER: its press is a stroke.
  /// Written by the drawing view, whose stroke it is.
  bool erase = false;

  /// A BUTTON holds the tool. Whoever engaged first keeps it: the pen's
  /// tail does not take the tool from under one, and a second mapped press
  /// waits its turn.
  bool get buttonHoldsTheTool => pick || erase;

  /// Whether a stroke starting NOW is a tail erase — the tool switch is
  /// asynchronous, so the stroke's own settings snapshot has to carry
  /// the substitution exactly as the barrel-eraser path does. And so
  /// whether a tail's contact is a press that erases, for the panel to
  /// hand over.
  bool get penTailErases =>
      penTail &&
      AppInput.settings.value.canvasPenTail.action ==
          CanvasPointerAction.eraser;

  /// The presses the drawing view is hearing ITSELF — each from its down
  /// to its lift. The panel hands over only a press that is not here: one
  /// the view heard is the view's whole business, whatever it made of it
  /// (a press it refused is refused once, not once more through the door).
  final Set<int> heardByTheView = <int>{};

  /// THE DRAWING VIEW'S DOOR for a press it could not hear — one that
  /// erases, landed on another tool's layer. The panel knocks with each
  /// event of that pointer's life, as the panel's listener hears it; the
  /// view takes them as its own. Null while no view stands behind it.
  void Function(PointerEvent event)? handOver;

  /// Engages or releases the tail mapping from the HID observer's view of
  /// which end of the pen is down.
  ///
  /// FLIP-scoped by design, not contact-scoped: the switch happens when
  /// the pen is turned OVER, so one flip covers a whole erasing pass and
  /// the eraser's own size and settings are on screen before the first
  /// stroke — rather than the tool panel blinking brush⇄eraser once per
  /// stroke. A device whose driver reports no hover degrades to
  /// per-contact switching for free: its first report IS the contact.
  ///
  /// A null reading (no observer, non-Windows, or the report aged out)
  /// HOLDS the current state rather than releasing — losing sight of the
  /// pen is not the same as the pen being turned back over.
  ///
  /// ↩️It was the drawing view's alone (`_BrushEditOverlay`), so the pen
  /// was turned over to no effect wherever that view hears no hover. The
  /// view and the panel both call it now, and the second call of a sample
  /// finds the state already as the first left it.
  void syncPenTail({
    required void Function(CanvasTool tool)? hold,
    required void Function({required bool keep})? release,
  }) {
    final inverted = PenSidecars.freshInverted();
    if (inverted == null || inverted == penTail) {
      return;
    }
    final mapping = AppInput.settings.value.canvasPenTail;
    if (inverted) {
      // A button hold that is already running owns the tool.
      if (buttonHoldsTheTool) {
        return;
      }
      final tool = switch (mapping.action) {
        CanvasPointerAction.eraser => CanvasTool.eraser,
        CanvasPointerAction.eyedropper => CanvasTool.eyedropper,
        // pan/undo/redo/none have no tail meaning: those are momentary
        // verbs, and the tail is a state that can last minutes.
        _ => null,
      };
      if (tool == null) {
        return;
      }
      penTail = true;
      hold?.call(tool);
      return;
    }
    penTail = false;
    release?.call(keep: mapping.release == CanvasPointerRelease.keep);
  }
}
