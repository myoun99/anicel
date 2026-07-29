/// The project's PAPER (R10-⑥, reshaped by R3b's four-plane stage:
/// backdrop → pasteboard → paper → pictures): the sheet under the artwork
/// on the canvas and the bottom covered track's stage in every composed
/// view.
///
/// The color carries its own ALPHA now (user 2026-07-29): a thinned paper
/// reveals the pasteboard and the backdrop behind it, on screen and in
/// print alike — the old display-only "transparent" flag collapsed into
/// alpha 0, and the alpha checkerboard moved to the backdrop's
/// alpha-preview toggle where it says what it means (what an alpha export
/// leaves open).
class ProjectBackground {
  const ProjectBackground.color(this.argb);

  const ProjectBackground.transparent() : argb = 0x00FFFFFF;

  /// Fully see-through paper (alpha 0) — the old boolean's meaning, kept
  /// as a getter so the sentence "is the paper transparent" still reads.
  bool get transparent => argb >>> 24 == 0;

  /// The ARGB the paper paints with — alpha included, everywhere: canvas,
  /// playback, bakes. What you see is what exports.
  final int argb;

  /// The default paper — R28 #9: PURE white.
  ///
  /// It used to be 0xFFEDEDED, the "near white" the user spotted ("캔버스
  /// 색이 애초에 흰색일텐데 완전흰색이아니네?"), and the same literal was
  /// spelled out in four other places. This constant is the single source
  /// now; the canvas painter, the eyedropper's paper fallback and the
  /// playback painter all read it.
  static const int defaultPaperArgb = 0xFFFFFFFF;

  static const ProjectBackground defaultBackground = ProjectBackground.color(
    defaultPaperArgb,
  );

  static const ProjectBackground white = ProjectBackground.color(0xFFFFFFFF);
  static const ProjectBackground black = ProjectBackground.color(0xFF000000);

  Map<String, dynamic> toJson() => {'argb': argb};

  factory ProjectBackground.fromJson(Map<String, dynamic> json) {
    // Legacy shape: the display-only transparent flag → alpha-0 paper.
    if (json['transparent'] == true) {
      return const ProjectBackground.transparent();
    }
    return ProjectBackground.color(json['argb'] as int? ?? defaultPaperArgb);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ProjectBackground && other.argb == argb;

  @override
  int get hashCode => argb.hashCode;

  @override
  String toString() =>
      'ProjectBackground(argb: 0x${argb.toRadixString(16).toUpperCase()})';
}
