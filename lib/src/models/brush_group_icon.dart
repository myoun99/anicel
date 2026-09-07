/// The icons a brush group can wear on its rail tab.
///
/// A FIXED catalogue rather than a free codepoint, and that is not a
/// limitation to route around: the face each entry wears is a const `IconData`
/// literal in `ui/brush/brush_group_icon_glyph.dart`, which is what lets
/// Flutter tree-shake the icon font. Storing a number and building
/// `IconData(code)` at runtime would ship the whole font — or, with
/// tree-shaking left on, render nothing at all.
///
/// The enum is data and stays data: it names the choice, and `ui/` decides
/// what that choice looks like.
///
/// The stored form is the enum's [name], so reordering or extending this
/// list never rewrites a saved library.
enum BrushGroupIcon {
  brush,
  pencil,
  pen,
  marker,
  paint,
  palette,
  ink,
  watercolor,
  airbrush,
  texture,
  grain,
  eraser,
  effect,
  shape,
  line,
  star,
  folder;

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
