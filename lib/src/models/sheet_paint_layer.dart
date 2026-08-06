/// Which stratum of a paper SHEET a painter draws.
///
/// One vocabulary for all three sheets — timesheet, conte and cut envelope
/// — so an export can hand the strata over separately and whoever opens
/// them can delete the filled-in values without losing the printed form
/// (user, 2026-08-06: "자동입력된거 지우고싶을때 못지우니까"). The
/// timesheet split FORM from CONTENT first, for exactly this reason; the
/// envelope was born with the whole set; this is the pair said once.
///
/// The split is also a rule about what may be drawn where, and it is what
/// makes the three sheets behave alike:
///
/// **The form layer never reads project data.** A page with nothing on it
/// still prints its whole form — every rule, every box, every frame. What
/// changes with the film is content, always. A form that grew a box when a
/// cut existed would not be a printed sheet; it would be a drawing of one.
enum SheetPaintLayer {
  /// The sheet itself: white paper, or kraft for a real 봉투.
  paper,

  /// Printed rules, box outlines, frames and the words the form carries.
  /// Static per sheet SHAPE — never per content.
  form,

  /// Values read from the project — the layer that has to be erasable.
  content,

  /// Handwriting. Lives in its own store, never in a cel.
  ink;

  String get jsonValue => name;

  static SheetPaintLayer? fromJson(Object? json) {
    for (final layer in SheetPaintLayer.values) {
      if (layer.jsonValue == json) {
        return layer;
      }
    }
    return null;
  }
}
