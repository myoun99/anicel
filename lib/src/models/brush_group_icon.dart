import 'package:flutter/material.dart';

/// The icons a brush group can wear on its rail tab.
///
/// A FIXED catalogue rather than a free codepoint, and that is not a
/// limitation to route around: Flutter tree-shakes the icon font using the
/// const `IconData` literals it can see in the source. Storing a number and
/// building `IconData(code)` at runtime would ship the whole font — or, with
/// tree-shaking left on, render nothing at all. Every entry below is a const
/// literal, so the build keeps exactly these and drops the rest.
///
/// The stored form is the enum's [name], so reordering or extending this
/// list never rewrites a saved library.
enum BrushGroupIcon {
  brush(Icons.brush),
  pencil(Icons.edit),
  pen(Icons.create),
  marker(Icons.border_color),
  paint(Icons.format_paint),
  palette(Icons.palette),
  ink(Icons.water_drop),
  watercolor(Icons.opacity),
  airbrush(Icons.blur_on),
  texture(Icons.texture),
  grain(Icons.grain),
  eraser(Icons.cleaning_services),
  effect(Icons.auto_fix_high),
  shape(Icons.category),
  line(Icons.gesture),
  star(Icons.star),
  folder(Icons.folder_outlined);

  const BrushGroupIcon(this.data);

  /// The const icon literal — see the class doc on why this must be const.
  final IconData data;

  /// The icon stored under [name], or null when absent or unrecognised. An
  /// unknown name degrades to "no icon chosen" rather than failing a load.
  static BrushGroupIcon? byName(String? name) {
    if (name == null) {
      return null;
    }
    for (final icon in values) {
      if (icon.name == name) {
        return icon;
      }
    }
    return null;
  }
}
