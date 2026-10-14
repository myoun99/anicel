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
/// 🗣️F-342 (유저 2026-10-12) of the colour: 「색도 그냥 결정되돌림. 생성시
/// 브러시색 따라가도록」 — the tool has NO colour of its own: a new text is
/// set in the brush's colour as it is when the text is made ([letters]).
/// ↩️On 2026-10-06 the tool had one, black (「기본값은 검정이고 텍스트편집툴
/// 프로들 다 이렇게하잖아」), and ↩️F-334-Q1 (2026-10-10, 「자기 색은 두고,
/// 처음만 붓 색」) kept it, only STARTING it as the brush's.
///
/// ⚠️No width here. Whether a text grows or wraps is said by the hand — a
/// click starts one that grows, a drag one as wide as the drag (유저
/// 2026-10-06) — and swapped afterwards on the text itself.
class TextToolOptions {
  const TextToolOptions({
    TextLetterStyle letters = const TextLetterStyle(),
    this.align = TextCelAlign.left,
    this.lineHeight = CelTextContent.defaultLineHeight,
    this.backgroundColor,
    this.vertical = false,
  }) : _letters = letters;

  /// What the tool starts as in a run of the app: the app's face at 48, no
  /// outline.
  static const TextToolOptions defaults = TextToolOptions();

  /// How the letters of the next text are set, until the person says
  /// otherwise. Read through [letters]: their colour is the next text's
  /// only where there is no brush to read.
  final TextLetterStyle _letters;

  final TextCelAlign align;

  /// A line's pitch, as a multiple of its letters' size.
  final double lineHeight;

  /// The box filled behind the next text, ARGB; null for none.
  final int? backgroundColor;

  /// Whether the next text is written in columns
  /// ([CelTextContent.vertical]).
  final bool vertical;

  /// The letters of the next text, in [brushColour]. Null where there is no
  /// brush to read: the colour they were made in.
  TextLetterStyle letters({required int? brushColour}) =>
      brushColour == null ? _letters : _letters.copyWith(color: brushColour);

  /// These with [change] made on the letters.
  TextToolOptions withLetters(
    TextLetterStyle Function(TextLetterStyle letters) change,
  ) => TextToolOptions(
    letters: change(_letters),
    align: align,
    lineHeight: lineHeight,
    backgroundColor: backgroundColor,
    vertical: vertical,
  );

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
        vertical: vertical,
      );

  /// These with the box's values given — the letters are [withLetters]'.
  TextToolOptions copyWith({
    TextCelAlign? align,
    double? lineHeight,
    Object? backgroundColor = _sentinel,
    bool? vertical,
  }) => TextToolOptions(
    letters: _letters,
    align: align ?? this.align,
    lineHeight: lineHeight ?? this.lineHeight,
    backgroundColor: identical(backgroundColor, _sentinel)
        ? this.backgroundColor
        : backgroundColor as int?,
    vertical: vertical ?? this.vertical,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TextToolOptions &&
          other._letters == _letters &&
          other.align == align &&
          other.lineHeight == lineHeight &&
          other.backgroundColor == backgroundColor &&
          other.vertical == vertical;

  @override
  int get hashCode =>
      Object.hash(_letters, align, lineHeight, backgroundColor, vertical);

  static const Object _sentinel = Object();
}
