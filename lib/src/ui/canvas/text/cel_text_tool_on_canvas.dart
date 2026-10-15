part of 'cel_text_tool.dart';

/// What floats over the hole the text in hand left in its cel
/// ([CelTextOnCanvas.floatingOn]): its pixels as they are drawn, the cel
/// without it and without the texts above it, and those texts.
typedef CelTextFloating = ({
  CelTextPixels pixels,
  BitmapSurface under,
  List<CelText> above,
});

/// The text in hand lifted off a picture: the picture, which text, the
/// picture without it and the texts above it, the picture without it
/// alone — and the texts above it.
typedef _Lift = ({
  BitmapSurface picture,
  CelTextSession session,
  int? id,
  BitmapSurface under,
  BitmapSurface without,
  List<CelText> above,
});

/// WHAT THE CANVAS SHOWS OF WHAT THE HAND HOLDS (F-344): the cel's place
/// while a text is in hand or still owes its landing, what floats over that
/// place, and the boxes the texts nobody holds wear.
///
/// The hand's own collaborator ([CelTextTool.onCanvas]), in its library:
/// every answer here is read off what the hand holds and what it still owes
/// a landing — and the lift made for the text in hand is kept here, for the
/// picture and the text it was made of.
class CelTextOnCanvas {
  CelTextOnCanvas._(this._tool);

  final CelTextTool _tool;

  /// What the canvas draws for [key] in place of [cel] — [key]'s picture
  /// as it stands — or null when that is [cel] itself: the texts let go of
  /// that still owe a landing laid in as they are shown, and the text in
  /// hand LIFTED OFF, with every text above it ([floatingOn] floats them).
  ///
  /// 🚨★★★F-344 — A TEXT IN HAND IS A FLOAT OVER ITS HOLE, as a lifted
  /// selection is (유저 2026-10-12: 「변형로직같은거 참고/재사용하면서 라이브
  /// 빠르게 움직이도록 구조개편」). ↩️It was laid into the cel here instead,
  /// as it was shown, so every move of a hand on its box cut its plate
  /// again, stamped and pictured every tile under it again, and built the
  /// panel again for a painter of the surface that made. The hole is made
  /// when the text is taken, and what the hand does to the text after that
  /// changes only what floats.
  BitmapSurface? shownSurfaceFor(BrushFrameKey key, BitmapSurface cel) =>
      _shownFor(key, cel, (lift) => lift.under);

  /// [shownSurfaceFor] with the texts above the one in hand LAID IN, where
  /// they stand — the picture without the text in hand, and nothing else
  /// taken off it: what a canvas draws that floats, in the text's place,
  /// what the cel will show where it lands, those texts included
  /// (`CelTextLanding`, F-344-Q3).
  BitmapSurface? shownWithoutFor(BrushFrameKey key, BitmapSurface cel) =>
      _shownFor(key, cel, (lift) => lift.without);

  BitmapSurface? _shownFor(
    BrushFrameKey key,
    BitmapSurface cel,
    BitmapSurface Function(_Lift lift) part,
  ) {
    final picture = _withLeaving(key, cel);
    final lift = _liftOff(key, picture);
    final surface = lift == null ? picture : part(lift);
    return identical(surface, cel) ? null : surface;
  }

  /// What floats over the hole [shownSurfaceFor] answers for [key]: the
  /// text in hand as it is shown, and the texts [cel] carries above it, as
  /// they stand — or null with none of [cel]'s texts in hand.
  ///
  /// ⛔THE TEXTS ABOVE FLOAT WITH IT. On the cel they are over it wherever
  /// they meet (유저 2026-10-02: 「그림/텍스트/텍스트」), and a hole holding them
  /// would put the text in hand over them while it is carried.
  CelTextFloating? floatingOn(BrushFrameKey key, BitmapSurface cel) {
    final lift = _liftOff(key, _withLeaving(key, cel));
    return lift == null
        ? null
        : (
            pixels: lift.session.shown.pixels,
            under: lift.under,
            above: lift.above,
          );
  }

  /// [cel] with the texts let go of that still owe a landing laid in as
  /// they are shown.
  BitmapSurface _withLeaving(BrushFrameKey key, BitmapSurface cel) {
    var surface = cel;
    for (final leaving in _tool._wayOut.leaving) {
      if (leaving.session.key == key) {
        surface = leaving.session.shownOver(surface);
      }
    }
    return surface;
  }

  /// The text in hand lifted off [picture], [key]'s — null when the text in
  /// hand is on another cel, or none is, or it is shown as the cel carries
  /// it: then the cel itself is the picture ([CelTextTool._lifts]). A text
  /// new to the cel is over all of them, so nothing is above it and either
  /// hole is the picture itself.
  ///
  /// Made once for a picture and a text, so the painter of the hole is
  /// made once too (`_activeSurfacePainterToken`).
  _Lift? _liftOff(BrushFrameKey key, BitmapSurface picture) {
    final session = _tool._held?.session;
    if (session == null || session.key != key || session.shownAsCarried) {
      return _lift = null;
    }
    final id = session.textId;
    final kept = _lift;
    if (kept != null &&
        identical(kept.picture, picture) &&
        identical(kept.session, session) &&
        kept.id == id) {
      return kept;
    }
    final texts = picture.texts;
    final at = texts.indexWhere((text) => text.id == id);
    return _lift = (
      picture: picture,
      session: session,
      id: id,
      under: at < 0 ? picture : picture.withTexts(texts.sublist(0, at)),
      without: at < 0 ? picture : picture.withTexts([...texts]..removeAt(at)),
      above: at < 0 ? const <CelText>[] : texts.sublist(at + 1),
    );
  }

  _Lift? _lift;

  /// Where the texts of [key]'s cel stand that are in NOBODY'S hand:
  /// [cel]'s own, but for the ones the tool speaks for — and, of those,
  /// the ones let go of that still owe a landing, as they are shown.
  ///
  /// 🗣️유저 2026-10-02: 「텍스트는 텍스트 툴을 선택했을때만 **텍스트별로
  /// 박스가 떠서** 편집가능. 화면에 텍스트박스를 선택해서(선택된지 알수있도록
  /// ui 필요.)」 — every text wears a box while the tool is in hand, and the
  /// one in hand wears its own ([CelTextTool.session]), which says it is
  /// the one.
  List<CelTextBox> restingBoxesOn(BrushFrameKey key, BitmapSurface cel) {
    final leaving = [
      for (final holding in _tool._wayOut.leaving)
        if (holding.session.key == key) holding,
    ];
    final held = _tool._held?.session;
    final spokenFor = {
      for (final holding in leaving) holding.session.textId,
      if (held != null && held.key == key) held.textId,
    };
    return [
      for (final text in celTextsInReach(cel))
        if (!spokenFor.contains(text.id)) celTextBoxOf(text.content),
      for (final _Holding(:session, :becomesDrawing) in leaving)
        // A text with no letters is not there, shown or landed — and one
        // on its way into the drawing is no text of the tool's any more
        // ([CelTextTool.takeableOn]).
        if (!session.shown.content.isEmpty && !becomesDrawing)
          session.shown.layout.onCanvas,
    ];
  }
}
