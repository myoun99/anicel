import 'dart:ui' show Offset, Size;

import '../core/contain_rect.dart';
import 'canvas_size.dart';

/// A paper format: its sheet standing upright, in millimetres.
enum SheetPaperFormat {
  a4(widthMm: 210, heightMm: 297),
  a3(widthMm: 297, heightMm: 420);

  const SheetPaperFormat({required this.widthMm, required this.heightMm});

  final double widthMm;
  final double heightMm;

  /// What the format is called where a sheet says its paper: `A4`.
  String get label => name.toUpperCase();
}

/// A sheet panel's PAPER: a format at a resolution — and so a size in
/// pixels, which is the canvas the panel shows, the grade its handwriting
/// is kept at, and what its 100% means (a pixel of the paper a pixel of the
/// screen).
///
/// 🗣️유저 2026-10-05 (F-294): 「이런 패널들은 사이즈 생각할때 dpi를 기준으로
/// 생각할거야. 즉 용지 크기 바꾼다면 dpi사이즈 바꾸는느낌으로」 — a sheet is
/// made larger or smaller by its [dpi], never by a pixel count of its own.
///
/// ↩️Each sheet had a size of its own making: the timesheet's paper was
/// its form's own units (1096×1574 on a 24fps sheet), the conte's was A4 in
/// points (595×842) and the envelope's was whatever canvas its cut had —
/// and the handwriting, kept a pixel a unit since 2026-09-26
/// (one-paper-brush-width-Q2), was as coarse as those were small (「지금까지가
/// 잉크가 이상하게 됬던거뿐이야」).
class SheetPaper {
  const SheetPaper(this.format, {required this.dpi, this.landscape = false});

  /// THE TABLE (유저 2026-10-05, F-294: 「타임시트 용지패널 용지크기 너무
  /// 작음 … 1754x2480을 기본으로 할것. 콘티패널이랑 컷봉투패널의 용지는
  /// 300dpi인 2480x3508으로함」 · 「컷봉투 가로a4 수용할게」 · 「사이즈만 아까
  /// 말한대로 되면되 … 이게 무슨 dpi인지는 너가 확인해서 지정해줘」).
  ///
  /// The pixels are the user's; the format and the dpi are what gives
  /// exactly those pixels. 1754×2480 is A3 at 150dpi — on A4 it would take
  /// 212.13dpi, and A4 at a whole 212 comes to 1753×2479.
  static const SheetPaper timesheet = SheetPaper(SheetPaperFormat.a3, dpi: 150);
  static const SheetPaper conte = SheetPaper(SheetPaperFormat.a4, dpi: 300);
  static const SheetPaper envelope = SheetPaper(
    SheetPaperFormat.a4,
    dpi: 300,
    landscape: true,
  );

  final SheetPaperFormat format;

  /// Pixels to the inch.
  final int dpi;

  /// Whether the sheet lies on its side.
  final bool landscape;

  static const double _mmPerInch = 25.4;

  /// The paper in pixels: its millimetres at [dpi], to the whole pixel.
  CanvasSize get pixelSize {
    int pixels(double mm) => (mm / _mmPerInch * dpi).round();
    final across = pixels(format.widthMm);
    final along = pixels(format.heightMm);
    return landscape
        ? CanvasSize(width: along, height: across)
        : CanvasSize(width: across, height: along);
  }

  /// [pixelSize] as a measure — for the geometry laid on it.
  Size get extent {
    final pixels = pixelSize;
    return Size(pixels.width.toDouble(), pixels.height.toDouble());
  }

  /// This paper round a form [form] large (its own units): the form as
  /// large on it as fits, its shape kept, centred ([containFit]).
  SheetPaperFit around(Size form) => SheetPaperFit._on(form, extent);
}

/// A sheet's FORM on its paper, said in the form's own units.
class SheetPaperFit {
  const SheetPaperFit._({
    required this.scale,
    required this.sheet,
    required this.inset,
  });

  factory SheetPaperFit._on(Size form, Size pixels) {
    final (:scale, :fillsWidth) = containFit(form, pixels);
    // The side the form fills is the form's own measure — the paper's
    // divided back by the scale comes back a rounding off it, and a page
    // a hair taller than its form starts the next page a unit lower
    // (`PageStack`).
    final sheet = fillsWidth
        ? Size(form.width, pixels.height / scale)
        : Size(pixels.width / scale, form.height);
    return SheetPaperFit._(
      scale: scale,
      sheet: sheet,
      inset: Offset(
        (sheet.width - form.width) / 2,
        (sheet.height - form.height) / 2,
      ),
    );
  }

  /// The paper's pixels a unit of the form takes.
  final double scale;

  /// The paper as the form's units measure it.
  final Size sheet;

  /// Where the form's corner lies on [sheet] — the margin the paper's shape
  /// leaves it, the same on both sides.
  final Offset inset;
}
