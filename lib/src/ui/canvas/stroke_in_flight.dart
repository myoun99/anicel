import '../../models/brush_edit_canvas_input_settings.dart';

/// The stroke a canvas has in flight, as it tells its host
/// (`InteractiveBrushEditCanvasView.onActiveStrokeChanged`): none, one that
/// can put pixels on the cel it draws, or one that can only take them off.
///
/// 🗣️F-482 (유저 2026-10-27): 「없던 블록에서 지우는 동작은 블록 채우지
/// 않도록 근본/구조적으로」. A cel counts as drawn from pen-down
/// (`LayerStack.liveStrokeDraws`), and that asked only whether a stroke was
/// in flight — so an eraser on an empty block turned it white until the pen
/// lifted. Whether a stroke is in flight and whether it can draw are two
/// questions; this answers both from the stroke's own settings.
enum StrokeInFlight {
  none,
  paints,
  erases;

  /// The stroke laid in [settings] — the ones it took at its press, a
  /// mapped-erase press's among them, not the tool's.
  ///
  /// ⚠️Only the erase can add nothing to an empty cel: every other blend,
  /// `BrushBlendMode.behind` too, lands its paint where the cel is empty.
  static StrokeInFlight of(BrushEditCanvasInputSettings settings) =>
      settings.erase ? erases : paints;
}
