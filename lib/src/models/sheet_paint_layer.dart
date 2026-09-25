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

  /// The film's own PICTURES a sheet shows — the conte's panels (with the
  /// camera work written on them) and its cover picture — apart from the
  /// typed values (유저 2026-09-25: 「흰 배경/ 용지서식(칸이나 픽쳐
  /// 텍스트나 이런거)/그림 이런식으로. psd출력할때 이런느낌으로」 · 「그림
  /// 수정하거나 텍스트 바뀌거나 하는데 용지 리빌드하면 너무 비효율적」).
  /// Nothing in it overlaps a value, so the strata stack to the page in
  /// either order.
  picture,

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

/// The strata a sheet is BAKED in, bottom to top — each re-recorded only
/// when what it prints changes (유저 2026-09-25: 「그림 수정하거나 텍스트
/// 바뀌거나 하는데 용지 리빌드하면 너무 비효율적이잖아」 · 「캔버스베이스
/// 패널은 다 통일해줘」). The paper rides with the form: both change only
/// with the sheet's shape. An export that paints a page whole paints it in
/// the same order.
enum SheetStratum {
  form({SheetPaintLayer.paper, SheetPaintLayer.form}),
  content({SheetPaintLayer.content}),
  picture({SheetPaintLayer.picture}),
  ink({SheetPaintLayer.ink});

  const SheetStratum(this.layers);

  /// The layers this stratum prints.
  final Set<SheetPaintLayer> layers;
}
