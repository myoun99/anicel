part of '../timesheet_document_painter.dart';

/// THE COMPANY LOGO AN XDTS SHEET PRINTS (I-162-Q5, 유저 2026-11-05:
/// 「회사 로고를 찍는다」) — the work's ([TimesheetDocument.logoAssetPath]),
/// in the viewer's logo place as the viewer prints its own: as large as
/// fits, its shape kept, from the place's top-left corner, in the line
/// colour alone, as opaque as the logo is dark. A work with no logo leaves
/// the place blank. ↩️The title stood there (I-162-Q2) until this answer
/// took it off XDTS sheets.
class _XdtsLogoPass {
  _XdtsLogoPass(this._page);

  final _XdtsPage _page;

  /// A logo's pixel as the viewer keeps it: the line colour, its alpha the
  /// pixel's brightness inverted.
  ///
  /// ⚠️Mine: the brightness is our luminance ([luminanceR]), not Qt's grey
  /// — the two agree on black, white and the greys between.
  // dart format off
  static final ColorFilter _darkness = ColorFilter.matrix(<double>[
    0, 0, 0, 0, _XdtsPage.line.r * 255,
    0, 0, 0, 0, _XdtsPage.line.g * 255,
    0, 0, 0, 0, _XdtsPage.line.b * 255,
    -luminanceR, -luminanceG, -luminanceB, 0, 255,
  ]);
  // dart format on

  /// Page [pageIndex]'s logo, once its picture is read.
  void paintPage(Canvas canvas, int pageIndex) {
    final painter = _page._painter;
    final path = painter.document.logoAssetPath;
    final image = path == null ? null : painter.imageFor?.call(path);
    if (image == null) {
      return;
    }
    final place = _page.form.logo;
    final logo = Size(image.width.toDouble(), image.height.toDouble());
    final slot = Size(place.width.toDouble(), place.height.toDouble());
    final (:scale, :fillsWidth) = containFit(logo, slot);
    final into = Rect.fromLTWH(
      place.left.toDouble(),
      place.top.toDouble(),
      fillsWidth ? slot.width : logo.width * scale,
      fillsWidth ? logo.height * scale : slot.height,
    );
    // ⚠️Mine: what is clear in the logo stays clear — the alpha the darkness
    // gives is cut to the logo's own ([BlendMode.dstIn]), so a logo on a
    // clear ground prints its mark, not a block of the line colour.
    _page.on(canvas, pageIndex, () {
      canvas.saveLayer(into, Paint());
      _logoThrough(canvas, image, into, Paint()..colorFilter = _darkness);
      _logoThrough(canvas, image, into, Paint()..blendMode = BlendMode.dstIn);
      canvas.restore();
    });
  }

  /// [image] in [into], the way every sheet prints a media image
  /// ([paintSheetImageIn]), laid on what is under it through [layer].
  static void _logoThrough(
    Canvas canvas,
    ui.Image image,
    Rect into,
    Paint layer,
  ) {
    canvas.saveLayer(into, layer);
    paintSheetImageIn(canvas, image, into, FilterQuality.high);
    canvas.restore();
  }
}
