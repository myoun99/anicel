import '../cut.dart';
import '../sheet_paper.dart';

/// The paper an envelope prints on.
///
/// A model, not a UI detail: the export spec chooses one, and a spec is a
/// serializable value that must not reach into `ui/`.
enum CutEnvelopePaperMode {
  /// The real 봉투: the envelope's own paper — the one its panel shows
  /// (`SheetPaper.envelope`), at its own pixels.
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
/// The real-envelope mode prints the envelope's own paper at its own pixels,
/// what its panel shows at 100% (F-294, 유저 2026-10-05: 「1x하더라도
/// 100%크기인채로 출력해야」 · 「컷봉투도 확인한거맞아? 법 통일되있겠지?」);
/// the cut mode takes the canvas verbatim so the result is drop-in.
///
/// ↩️The real envelope was the FORM's own shape at a width in pixels the
/// export named (1240 · 2480 · 3508): a paper with no margin, which the
/// panel never showed, sized by a number of its own — and then that paper a
/// number of times over (a scale row, 1x–4x), until 유저 2026-10-06 took the
/// row out: 「시트 이미지는 배율 없앰. 늘 용지 그대로. 콘티든 컷봉투든
/// 똑같음」.
({int width, int height}) cutEnvelopePaperSize({
  required CutEnvelopePaperMode mode,
  required Cut cut,
}) {
  switch (mode) {
    case CutEnvelopePaperMode.sheet:
      final paper = SheetPaper.envelope.pixelSize;
      return (width: paper.width, height: paper.height);
    case CutEnvelopePaperMode.cut:
      return (width: cut.canvasSize.width, height: cut.canvasSize.height);
  }
}
