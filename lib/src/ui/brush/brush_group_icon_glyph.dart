import 'package:flutter/material.dart';

import '../../models/brush_group_icon.dart';

/// The glyph a [BrushGroupIcon] wears on screen.
///
/// THE CATALOGUE IS FIXED AND EVERY ARM BELOW IS A CONST LITERAL, and that is
/// not a limitation to route around: Flutter tree-shakes the icon font using
/// the const `IconData` literals it can see in the source. Storing a number
/// and building `IconData(code)` at runtime would ship the whole font — or,
/// with tree-shaking left on, render nothing at all. The build keeps exactly
/// the glyphs named here and drops the rest.
///
/// It is a switch and not a map so the analyzer fails the day a case is added
/// to the enum without a face.
IconData brushGroupIconGlyph(BrushGroupIcon icon) => switch (icon) {
  BrushGroupIcon.brush => Icons.brush,
  BrushGroupIcon.pencil => Icons.edit,
  BrushGroupIcon.pen => Icons.create,
  BrushGroupIcon.marker => Icons.border_color,
  BrushGroupIcon.paint => Icons.format_paint,
  BrushGroupIcon.palette => Icons.palette,
  BrushGroupIcon.ink => Icons.water_drop,
  BrushGroupIcon.watercolor => Icons.opacity,
  BrushGroupIcon.airbrush => Icons.blur_on,
  BrushGroupIcon.texture => Icons.texture,
  BrushGroupIcon.grain => Icons.grain,
  BrushGroupIcon.eraser => Icons.cleaning_services,
  BrushGroupIcon.effect => Icons.auto_fix_high,
  BrushGroupIcon.shape => Icons.category,
  BrushGroupIcon.line => Icons.gesture,
  BrushGroupIcon.star => Icons.star,
  BrushGroupIcon.folder => Icons.folder_outlined,
};
