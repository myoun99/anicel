import 'dart:ui' show Color, Offset;

/// THE LETTER HALF of the canvas-text vocabulary: what may differ from one
/// letter to the next — the face, its size and weight, the tracking, the
/// colour, the outline and whether its edges are smoothed. Serializable
/// like [MediaReference] — a style is document data, never a hardcoded
/// TextStyle.
///
/// 🗣️유저 2026-10-02 (R9-rest, the text tool): 「선택해서 그 상태에서
/// 도구설정에서 폰트바꾸면 해당 텍스트박스 설정 자동으로 바꿈 … 텍스트를
/// 선택하고 조절하면 일부만 텍스트 조절」. A text on a cel is therefore runs
/// of letters, each run wearing one of these ([CelTextSpan]), and what belongs
/// to the whole box — its alignment, the box behind it — is not in here.
///
/// The SE name tag's [TextCelStyle] IS one of these plus the two values of
/// its one block, which is why the fields are declared here and nowhere
/// else.
class TextLetterStyle {
  const TextLetterStyle({
    this.fontFamily,
    this.fontSize = 48,
    this.bold = false,
    this.letterSpacing = 0,
    this.color = 0xFF000000,
    this.outlineColor,
    this.outlineWidth = 0,
    this.antialias = true,
  });

  /// Registered family name — null writes in the app's bundled face
  /// (`AppTypography.bundledFamily`, which is what the renderer falls back
  /// to; ↩️it was the platform's default font until 2026-09-25).
  final String? fontFamily;

  /// Canvas pixels (the cel bakes at canvas resolution, so this is
  /// document-true, not screen-relative).
  final double fontSize;

  final bool bold;

  /// Fixed em tracking in canvas pixels (the SE "fit" distribution is a
  /// different, extent-driven axis and stays out of the style).
  final double letterSpacing;

  /// ARGB ints — [Color] is a UI type; the model stays dart:ui-light so
  /// JSON stays trivially stable.
  final int color;

  /// Two-pass outline (stroke under fill, the timeline glyph recipe);
  /// null = no outline.
  final int? outlineColor;
  final double outlineWidth;

  /// Whether the letters' edges are SMOOTHED. Off, a letter is drawn HARD:
  /// every pixel it covers by half or more is its colour, whole, and every
  /// other pixel is none of it — the two-value letter a cel's paint asks
  /// for (`CanvasLetterPasses`).
  ///
  /// 🗣️유저 2026-10-06 (R9-rest, asked whether letters need the switch the
  /// shape fill and the selection carry): 「권장대로. 2차에서 스위치로 넣음」.
  final bool antialias;

  Color get colorValue => Color(color);
  Color? get outlineColorValue =>
      outlineColor == null ? null : Color(outlineColor!);

  TextLetterStyle copyWith({
    Object? fontFamily = _sentinel,
    double? fontSize,
    bool? bold,
    double? letterSpacing,
    int? color,
    Object? outlineColor = _sentinel,
    double? outlineWidth,
    bool? antialias,
  }) {
    return TextLetterStyle(
      fontFamily: identical(fontFamily, _sentinel)
          ? this.fontFamily
          : fontFamily as String?,
      fontSize: fontSize ?? this.fontSize,
      bold: bold ?? this.bold,
      letterSpacing: letterSpacing ?? this.letterSpacing,
      color: color ?? this.color,
      outlineColor: identical(outlineColor, _sentinel)
          ? this.outlineColor
          : outlineColor as int?,
      outlineWidth: outlineWidth ?? this.outlineWidth,
      antialias: antialias ?? this.antialias,
    );
  }

  Map<String, dynamic> toJson() => {
    if (fontFamily != null) 'fontFamily': fontFamily,
    'fontSize': fontSize,
    if (bold) 'bold': bold,
    if (letterSpacing != 0) 'letterSpacing': letterSpacing,
    'color': color,
    if (outlineColor != null) 'outlineColor': outlineColor,
    if (outlineWidth != 0) 'outlineWidth': outlineWidth,
    if (!antialias) 'antialias': antialias,
  };

  factory TextLetterStyle.fromJson(Map<String, dynamic> json) {
    return TextLetterStyle(
      fontFamily: json['fontFamily'] as String?,
      fontSize: (json['fontSize'] as num?)?.toDouble() ?? 48,
      bold: json['bold'] as bool? ?? false,
      letterSpacing: (json['letterSpacing'] as num?)?.toDouble() ?? 0,
      color: json['color'] as int? ?? 0xFF000000,
      outlineColor: json['outlineColor'] as int?,
      outlineWidth: (json['outlineWidth'] as num?)?.toDouble() ?? 0,
      antialias: json['antialias'] as bool? ?? true,
    );
  }

  /// Whether [other] writes its letters as this one does — the fields of
  /// this class, whatever else a subclass adds.
  bool sameLettersAs(TextLetterStyle other) =>
      other.fontFamily == fontFamily &&
      other.fontSize == fontSize &&
      other.bold == bold &&
      other.letterSpacing == letterSpacing &&
      other.color == color &&
      other.outlineColor == outlineColor &&
      other.outlineWidth == outlineWidth &&
      other.antialias == antialias;

  /// ⚠️The same TYPE too: a [TextCelStyle] is a letter style with more to
  /// say, and one that happened to match letter for letter is still not
  /// this.
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TextLetterStyle &&
          other.runtimeType == runtimeType &&
          sameLettersAs(other);

  @override
  int get hashCode => Object.hash(
    fontFamily,
    fontSize,
    bold,
    letterSpacing,
    color,
    outlineColor,
    outlineWidth,
    antialias,
  );

  static const Object _sentinel = Object();
}

/// The SE name tag's styling (R5, ⓣ): one block written in one letter style
/// ([TextLetterStyle]) — plus the two values of the block itself, where its
/// lines stand around the anchor and the box behind them.
///
/// The font roster is deliberately the BUNDLED faces: whatever this style
/// can name must also exist for the PDF embedding path, and only OFL faces
/// ship (IP rule).
class TextCelStyle extends TextLetterStyle {
  const TextCelStyle({
    super.fontFamily,
    super.fontSize,
    super.bold,
    super.letterSpacing,
    this.align = TextCelAlign.center,
    super.color = 0xFF202020,
    super.outlineColor,
    super.outlineWidth,
    super.antialias,
    this.backgroundColor,
  });

  final TextCelAlign align;

  /// Filled box behind the text (the アフレコ red box wears danger red);
  /// null = bare text.
  final int? backgroundColor;

  Color? get backgroundColorValue =>
      backgroundColor == null ? null : Color(backgroundColor!);

  @override
  TextCelStyle copyWith({
    Object? fontFamily = TextLetterStyle._sentinel,
    double? fontSize,
    bool? bold,
    double? letterSpacing,
    TextCelAlign? align,
    int? color,
    Object? outlineColor = TextLetterStyle._sentinel,
    double? outlineWidth,
    bool? antialias,
    Object? backgroundColor = TextLetterStyle._sentinel,
  }) {
    return TextCelStyle(
      fontFamily: identical(fontFamily, TextLetterStyle._sentinel)
          ? this.fontFamily
          : fontFamily as String?,
      fontSize: fontSize ?? this.fontSize,
      bold: bold ?? this.bold,
      letterSpacing: letterSpacing ?? this.letterSpacing,
      align: align ?? this.align,
      color: color ?? this.color,
      outlineColor: identical(outlineColor, TextLetterStyle._sentinel)
          ? this.outlineColor
          : outlineColor as int?,
      outlineWidth: outlineWidth ?? this.outlineWidth,
      antialias: antialias ?? this.antialias,
      backgroundColor: identical(backgroundColor, TextLetterStyle._sentinel)
          ? this.backgroundColor
          : backgroundColor as int?,
    );
  }

  @override
  Map<String, dynamic> toJson() => {
    if (fontFamily != null) 'fontFamily': fontFamily,
    'fontSize': fontSize,
    if (bold) 'bold': bold,
    if (letterSpacing != 0) 'letterSpacing': letterSpacing,
    'align': align.jsonValue,
    'color': color,
    if (outlineColor != null) 'outlineColor': outlineColor,
    if (outlineWidth != 0) 'outlineWidth': outlineWidth,
    if (!antialias) 'antialias': antialias,
    if (backgroundColor != null) 'backgroundColor': backgroundColor,
  };

  factory TextCelStyle.fromJson(Map<String, dynamic> json) {
    return TextCelStyle(
      fontFamily: json['fontFamily'] as String?,
      fontSize: (json['fontSize'] as num?)?.toDouble() ?? 48,
      bold: json['bold'] as bool? ?? false,
      letterSpacing: (json['letterSpacing'] as num?)?.toDouble() ?? 0,
      align: TextCelAlign.fromJson(json['align'] as String?),
      color: json['color'] as int? ?? 0xFF202020,
      outlineColor: json['outlineColor'] as int?,
      outlineWidth: (json['outlineWidth'] as num?)?.toDouble() ?? 0,
      antialias: json['antialias'] as bool? ?? true,
      backgroundColor: json['backgroundColor'] as int?,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TextCelStyle &&
          sameLettersAs(other) &&
          other.align == align &&
          other.backgroundColor == backgroundColor;

  @override
  int get hashCode => Object.hash(super.hashCode, align, backgroundColor);
}

/// Horizontal alignment around the content's anchor position.
enum TextCelAlign {
  left('left'),
  center('center'),
  right('right');

  const TextCelAlign(this.jsonValue);

  final String jsonValue;

  static TextCelAlign fromJson(String? value) => switch (value) {
    'left' => TextCelAlign.left,
    'right' => TextCelAlign.right,
    _ => TextCelAlign.center,
  };
}

/// One text cel's truth (R5, §6-s): the PICTURE of a text-layer frame is
/// these parameters — the baked raster in the brush store is a derived
/// projection, re-baked on every edit (the import-cel grammar: pixels
/// only ever come from the store; the params are provenance that stays
/// editable).
class TextCelContent {
  const TextCelContent({
    required this.text,
    this.style = const TextCelStyle(),
    this.position,
  });

  /// The literal text; hard newlines break lines (no auto-wrap in v1).
  final String text;

  final TextCelStyle style;

  /// Anchor in CANVAS coordinates ([TextCelStyle.align] spreads the text
  /// around it horizontally; vertically the first line's top sits here).
  /// Null centers on the canvas.
  final Offset? position;

  TextCelContent copyWith({
    String? text,
    TextCelStyle? style,
    Object? position = _sentinel,
  }) {
    return TextCelContent(
      text: text ?? this.text,
      style: style ?? this.style,
      position: identical(position, _sentinel)
          ? this.position
          : position as Offset?,
    );
  }

  Map<String, dynamic> toJson() => {
    'text': text,
    'style': style.toJson(),
    if (position != null) 'position': [position!.dx, position!.dy],
  };

  factory TextCelContent.fromJson(Map<String, dynamic> json) {
    final position = json['position'] as List<dynamic>?;
    return TextCelContent(
      text: json['text'] as String? ?? '',
      style: json['style'] is Map<String, dynamic>
          ? TextCelStyle.fromJson(json['style'] as Map<String, dynamic>)
          : const TextCelStyle(),
      position: position == null
          ? null
          : Offset(
              (position[0] as num).toDouble(),
              (position[1] as num).toDouble(),
            ),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TextCelContent &&
          other.text == text &&
          other.style == style &&
          other.position == position;

  @override
  int get hashCode => Object.hash(text, style, position);

  static const Object _sentinel = Object();
}
