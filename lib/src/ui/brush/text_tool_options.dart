import '../../models/canvas_point.dart';
import '../../models/cel_text.dart';
import '../../models/text_cel_style.dart';

/// What the NEXT text set with the text tool starts as (R9-rest): the
/// letters' style, and the values of the whole box.
///
/// The app's, like every tool's settings — not the project's and not a
/// text's: a text that is selected shows ITS values in the tool settings
/// and a change there reaches it ([[R9-rest]] 유저 2026-10-02: 「선택해서 그
/// 상태에서 도구설정에서 폰트바꾸면 해당 텍스트박스 설정 자동으로 바꿈」), while
/// these stand for the text nobody has set yet.
///
/// 🗣️유저 2026-10-06 of the colour: 「기본값은 검정이고 텍스트편집툴 프로들 다
/// 이렇게하잖아」 — the tool has a colour of its own, and the brush's is not
/// read.
///
/// ⚠️No width here. Whether a text grows or wraps is said by the hand — a
/// click starts one that grows, a drag one as wide as the drag (유저
/// 2026-10-06) — and swapped afterwards on the text itself.
class TextToolOptions {
  const TextToolOptions({
    this.letters = const TextLetterStyle(),
    this.align = TextCelAlign.left,
    this.lineHeight = CelTextContent.defaultLineHeight,
    this.backgroundColor,
  });

  static const TextToolOptions defaults = TextToolOptions();

  /// How the letters of the next text are set: the app's face at 48, black,
  /// no outline — until the person says otherwise.
  final TextLetterStyle letters;

  final TextCelAlign align;

  /// A line's pitch, as a multiple of its letters' size.
  final double lineHeight;

  /// The box filled behind the next text, ARGB; null for none.
  final int? backgroundColor;

  /// A text with no letters yet, standing at [anchor] — as wide as
  /// [wrapWidth] says, or growing with what is typed.
  CelTextContent newTextAt(CanvasPoint anchor, {double? wrapWidth}) =>
      CelTextContent(
        spans: const [],
        anchor: anchor,
        wrapWidth: wrapWidth,
        align: align,
        lineHeight: lineHeight,
        backgroundColor: backgroundColor,
      );

  TextToolOptions copyWith({
    TextLetterStyle? letters,
    TextCelAlign? align,
    double? lineHeight,
    Object? backgroundColor = _sentinel,
  }) => TextToolOptions(
    letters: letters ?? this.letters,
    align: align ?? this.align,
    lineHeight: lineHeight ?? this.lineHeight,
    backgroundColor: identical(backgroundColor, _sentinel)
        ? this.backgroundColor
        : backgroundColor as int?,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TextToolOptions &&
          other.letters == letters &&
          other.align == align &&
          other.lineHeight == lineHeight &&
          other.backgroundColor == backgroundColor;

  @override
  int get hashCode => Object.hash(letters, align, lineHeight, backgroundColor);

  static const Object _sentinel = Object();
}
