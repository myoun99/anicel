/// The project's PAPER (R10-⑥, reshaped by R3b's four-plane stage:
/// backdrop → pasteboard → paper → pictures): the sheet under the artwork
/// on the canvas and the bottom covered track's stage in every composed
/// view.
///
/// The color carries its own ALPHA (user 2026-07-29): a thinned paper
/// reveals the pasteboard and the backdrop behind it, on screen and in
/// print alike — the old display-only "transparent" flag collapsed into
/// alpha 0, and the alpha checkerboard moved to the backdrop's
/// alpha-preview toggle where it says what it means (what an alpha export
/// leaves open).
///
/// 🚨F-114 brings an ABSENCE back, and it is not alpha (유저 2026-09-15):
/// 「없음버튼은 표시상? 없애서 체크무늬가 되도록 하는거고, 불투명도는 체크무늬는
/// 안되고 진짜 불투명도를 낮추는행위」. [none] says the plane is not there; the
/// alpha in [argb] says it is there, thinner. Two questions, two fields — the
/// same pair the pasteboard and the backdrop carry on the project.
class ProjectBackground {
  const ProjectBackground.color(this.argb, {this.none = false});

  /// The ARGB the paper paints with — alpha included, everywhere: canvas,
  /// playback, bakes. What you see is what exports. Kept while [none] is
  /// set, so the next pick or slider move brings the same colour back.
  final int argb;

  /// 「없음버튼 누르면 없는상태. 즉 해당 용지부분이 체크무늬되도록」 (유저
  /// 2026-09-15): the paper is absent — a checkerboard on the canvas where
  /// it would be, and nothing painted for it anywhere.
  final bool none;

  /// What the paper actually puts into a picture: its colour, or nothing at
  /// all while it is absent. ONE answer for everything that reads the paper
  /// as pixels — the painter, the eyedropper's paper fallback, the fill's
  /// paper — so an absent paper cannot be skipped by one of them and sampled
  /// as white by another. [argb] stays the kept colour a swatch shows.
  int get paintedArgb => none ? 0x00000000 : argb;

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

  Map<String, dynamic> toJson() => {'argb': argb, if (none) 'none': true};

  factory ProjectBackground.fromJson(Map<String, dynamic> json) =>
      ProjectBackground.color(
        json['argb'] as int? ?? defaultPaperArgb,
        none: json['none'] == true,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ProjectBackground && other.argb == argb && other.none == none;

  @override
  int get hashCode => Object.hash(argb, none);

  @override
  String toString() =>
      'ProjectBackground(argb: 0x${argb.toRadixString(16).toUpperCase()}'
      '${none ? ', none' : ''})';
}
