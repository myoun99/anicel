import '../cut.dart';

/// The paper an envelope prints on.
///
/// A model, not a UI detail: the export spec chooses one, and a spec is a
/// serializable value that must not reach into `ui/`.
enum CutEnvelopePaperMode {
  /// The real 봉투: the form's own size at the export resolution.
  sheet,

  /// The cut's canvas, so the exported image drops into a working file as
  /// a layer and lines up with the artwork.
  cut;

  String toJson() => name;

  static CutEnvelopePaperMode fromJson(Object? json) =>
      values.asNameMap()[json] ?? CutEnvelopePaperMode.sheet;
}

/// The paper size for [mode], in pixels.
///
/// [sheetWidth] is what the real-envelope mode prints at; the cut mode
/// takes the canvas verbatim so the result is drop-in.
({int width, int height}) cutEnvelopePaperSize({
  required CutEnvelopePaperMode mode,
  required Cut cut,
  required double formAspectRatio,
  int sheetWidth = 2480,
}) {
  switch (mode) {
    case CutEnvelopePaperMode.sheet:
      final width = sheetWidth < 1 ? 1 : sheetWidth;
      return (width: width, height: (width / formAspectRatio).round());
    case CutEnvelopePaperMode.cut:
      return (width: cut.canvasSize.width, height: cut.canvasSize.height);
  }
}
