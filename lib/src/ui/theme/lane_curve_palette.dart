import 'package:flutter/painting.dart' show Color;

/// The colour each number a lane holds is drawn in, in a HEADER GRAPH
/// (I-89 ③) — the colours of the mock the consultation settled on (5판):
/// a point's across and down, Scale, Rotation, Opacity, and an effect's
/// first parameter (its Blur's width).
///
/// ⚠️A layer's Scale DOWN and an effect's later parameters were not in the
/// mock (it drew one Scale and one parameter): their colours are the
/// round's own, put to the user 2026-10-11 — a lighter Scale blue, and a
/// round of hues after the first parameter's.
abstract final class LaneCurvePalette {
  static const Color across = Color(0xFFE2836F);
  static const Color down = Color(0xFF8DCB73);
  static const Color scale = Color(0xFF6BB3F7);
  static const Color scaleDown = Color(0xFFA9D4FF);
  static const Color rotation = Color(0xFFE3C567);
  static const Color opacity = Color(0xFFC792EA);

  static const List<Color> _effect = [
    Color(0xFFE39BCB),
    Color(0xFF5FC9BF),
    Color(0xFFE8A35C),
    Color(0xFF9FA8F5),
  ];

  /// The colour of an effect's parameter, by where it stands among the
  /// effect's parameters.
  static Color effectParameter(int index) => _effect[index % _effect.length];
}
