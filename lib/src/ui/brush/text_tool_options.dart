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
/// 이렇게하잖아」 — the tool has a colour of its own. ↩️Where it STARTS moved
/// on 2026-10-10 ([takesTheBrushColour]): the brush's, not black.
///
/// ⚠️No width here. Whether a text grows or wraps is said by the hand — a
/// click starts one that grows, a drag one as wide as the drag (유저
/// 2026-10-06) — and swapped afterwards on the text itself.
class TextToolOptions {
  const TextToolOptions({
    TextLetterStyle letters = const TextLetterStyle(),
    this.takesTheBrushColour = false,
    this.align = TextCelAlign.left,
    this.lineHeight = CelTextContent.defaultLineHeight,
    this.backgroundColor,
    this.vertical = false,
  }) : _letters = letters;

  /// What the tool starts as in a run of the app: the app's face at 48, no
  /// outline — in the brush's colour until a text is set.
  static const TextToolOptions defaults = TextToolOptions(
    takesTheBrushColour: true,
  );

  /// How the letters of the next text are set, until the person says
  /// otherwise. Read through [letters]: their colour is not the next text's
  /// while [takesTheBrushColour].
  final TextLetterStyle _letters;

  /// Whether the next text's letters wear the BRUSH's colour — the tool has
  /// none of its own yet.
  ///
  /// 🗣️F-334-Q1 (유저 2026-10-10, 「자기 색은 두고, 처음만 붓 색」): 「처음
  /// 생성될떄만 기본값을 붓색. 이후로 편집도중 브러시 색 바꾼다고 텍스트색
  /// 안바뀜. 진짜 초기값만 브러시색으로 해두는것」. True until the FIRST text
  /// is set — it is set in the brush's colour, and the tool keeps that colour
  /// as its own ([seeded]) — or a colour is picked in the tool settings
  /// first ([withColour]). After either, the brush's colour reaches no text.
  final bool takesTheBrushColour;

  final TextCelAlign align;

  /// A line's pitch, as a multiple of its letters' size.
  final double lineHeight;

  /// The box filled behind the next text, ARGB; null for none.
  final int? backgroundColor;

  /// Whether the next text is written in columns
  /// ([CelTextContent.vertical]).
  final bool vertical;

  /// The letters of the next text — in [brushColour] while the tool takes
  /// the brush's. Null where there is no brush to read: the colour they
  /// were made in.
  TextLetterStyle letters({required int? brushColour}) =>
      seeded(brushColour: brushColour)._letters;

  /// These once a text is set with them: the brush's colour, while they
  /// take it, the tool's own from here — whatever the brush's does after.
  /// As they are where there is no brush to read, and once the tool has a
  /// colour of its own.
  TextToolOptions seeded({required int? brushColour}) =>
      takesTheBrushColour && brushColour != null
      ? withColour(brushColour)
      : this;

  /// These with [color] the letters' colour, the tool's OWN — a colour
  /// picked in the tool settings, the brush's own colour picked through
  /// 「현재 색 반영」 too.
  TextToolOptions withColour(int color) => TextToolOptions(
    letters: _letters.copyWith(color: color),
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

  /// ⚠️[letters] gives the letters, not whose colour they wear: a colour in
  /// them is the next text's only once the tool has its own — [withColour]
  /// is what gives it one.
  TextToolOptions copyWith({
    TextLetterStyle? letters,
    TextCelAlign? align,
    double? lineHeight,
    Object? backgroundColor = _sentinel,
    bool? vertical,
  }) => TextToolOptions(
    letters: letters ?? _letters,
    takesTheBrushColour: takesTheBrushColour,
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
          other.takesTheBrushColour == takesTheBrushColour &&
          other.align == align &&
          other.lineHeight == lineHeight &&
          other.backgroundColor == backgroundColor &&
          other.vertical == vertical;

  @override
  int get hashCode => Object.hash(
    _letters,
    takesTheBrushColour,
    align,
    lineHeight,
    backgroundColor,
    vertical,
  );

  static const Object _sentinel = Object();
}
