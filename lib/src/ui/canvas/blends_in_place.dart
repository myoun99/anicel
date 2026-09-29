import 'dart:ui' as ui;

/// Whether [mode] is one the engines blend pixel by pixel wherever it is
/// drawn — `srcOver` and `plus` — rather than through the area drawn.
///
/// 🚨★★★F-243 (유저 2026-09-30, 실기): **THROUGH THE AREA DRAWN REACHES PAST
/// IT.** 🔬Measured on the Windows app (Impeller GLES): an image drawn in
/// multiply, screen, overlay, darken or difference is blended over
/// EVERYTHING the pass can reach — up to the current clip, or across a
/// `saveLayer`'s content — with its border pixels stretched outward. One
/// 16×16 tile of a (180,208,247) stroke turned the white page that colour;
/// ten of them turned it (8,33,185), the colour to the tenth power, which is
/// what the row being drawn on did when it laid its tiles down in multiply.
/// Tiles with clear borders changed nothing, and a clip to the image's own
/// rect held every blend (0 pixels outside). Skia and Impeller Vulkan stay
/// inside the rect, which is why the test VM never showed it.
/// ⇒ A draw in any other blend is ONE image of what is blended — the whole
/// layer, the whole group — never pieces of it laid down one by one, and
/// that one image is held to its own rect ([drawHeldToItsRect]).
///
/// ⛔ONLY THESE TWO, AND A MODE LEFT OUT COSTS TIME, NEVER A PIXEL. A crop to
/// the ink and a tile never drawn both leave clear pixels out, so a mode
/// belongs here only if a CLEAR source pixel also leaves the destination as
/// it was — `src` works in place and still wipes where it is clear. A mode
/// left out gets a buffer or a clip.
bool blendsInPlace(ui.BlendMode mode) =>
    mode == ui.BlendMode.srcOver || mode == ui.BlendMode.plus;

/// Runs [draw] — ONE image laid on [rect] with [paint] — held to [rect]
/// wherever [paint]'s blend does not act in place ([blendsInPlace], which
/// has the measurement): a layer whose ink reaches the edge of its image
/// would otherwise stretch that edge across the pasteboard, and a stamp
/// ghost its border across the row it hovers over.
///
/// ⛔NOT when [paint] carries an image filter. A blur paints past [rect] on
/// purpose, and a clip there cut it — the NO CLIP decision on the sub-tree
/// blit (`_blitSubtreeRaster`), measured. What such a paint stretches is the
/// faded border of its own spread; that combination is not measured.
///
/// `doAntiAlias: false`: the clip is the image's own footprint, and must not
/// soften that image's edge a second time.
void drawHeldToItsRect(
  ui.Canvas canvas,
  ui.Rect rect,
  ui.Paint paint,
  void Function() draw,
) {
  if (blendsInPlace(paint.blendMode) || paint.imageFilter != null) {
    draw();
    return;
  }
  canvas
    ..save()
    ..clipRect(rect, doAntiAlias: false);
  draw();
  canvas.restore();
}
