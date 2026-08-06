/// Which stratum of the envelope a painter draws.
///
/// Four layers, so a PSD export can hand them over separately and whoever
/// opens it can delete the filled-in values without losing the form (user,
/// 2026-08-06: "자동입력된거 지우고싶을때 못지우니까"). The timesheet
/// already splits FORM from CONTENT for the same reason; the envelope is
/// born with the whole set.
///
/// A model, not a painter detail: the export spec chooses among these, and
/// a spec is a serializable value that must not reach into `ui/`.
enum EnvelopePaintLayer {
  /// The sheet itself: kraft for a real 봉투, white for a digital one.
  paper,

  /// Printed rules, box outlines and the words the form itself carries.
  form,

  /// Values bound from the project — the layer that has to be erasable.
  content,

  /// Handwriting. Lives in its own store, never in a cel.
  ink;

  String get jsonValue => name;

  static EnvelopePaintLayer? fromJson(Object? json) {
    for (final layer in EnvelopePaintLayer.values) {
      if (layer.jsonValue == json) {
        return layer;
      }
    }
    return null;
  }
}
