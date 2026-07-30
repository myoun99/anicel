import 'dart:ui' show Color, Offset;

/// The shared canvas-text styling vocabulary (R5, ⓣ): the TEXT LAYER's
/// cels and the SE name tags speak the same style so neither reinvents
/// fonts, spacing, outlines or the red-box background. Serializable like
/// [MediaReference] — a style is document data, never a hardcoded
/// TextStyle.
///
/// The font roster is deliberately the BUNDLED faces plus the platform
/// default: whatever this style can name must also exist for the PDF
/// embedding path, and only OFL faces ship (IP rule).
class TextCelStyle {
  const TextCelStyle({
    this.fontFamily,
    this.fontSize = 48,
    this.bold = false,
    this.letterSpacing = 0,
    this.align = TextCelAlign.center,
    this.color = 0xFF202020,
    this.outlineColor,
    this.outlineWidth = 0,
    this.backgroundColor,
  });

  /// Registered family name (the conte faces) — null uses the platform
  /// default font.
  final String? fontFamily;

  /// Canvas pixels (the cel bakes at canvas resolution, so this is
  /// document-true, not screen-relative).
  final double fontSize;

  final bool bold;

  /// Fixed em tracking in canvas pixels (the SE "fit" distribution is a
  /// different, extent-driven axis and stays out of the style).
  final double letterSpacing;

  final TextCelAlign align;

  /// ARGB ints — [Color] is a UI type; the model stays dart:ui-light so
  /// JSON stays trivially stable.
  final int color;

  /// Two-pass outline (stroke under fill, the timeline glyph recipe);
  /// null = no outline.
  final int? outlineColor;
  final double outlineWidth;

  /// Filled box behind the text (the アフレコ red box wears danger red);
  /// null = bare text.
  final int? backgroundColor;

  Color get colorValue => Color(color);
  Color? get outlineColorValue =>
      outlineColor == null ? null : Color(outlineColor!);
  Color? get backgroundColorValue =>
      backgroundColor == null ? null : Color(backgroundColor!);

  TextCelStyle copyWith({
    Object? fontFamily = _sentinel,
    double? fontSize,
    bool? bold,
    double? letterSpacing,
    TextCelAlign? align,
    int? color,
    Object? outlineColor = _sentinel,
    double? outlineWidth,
    Object? backgroundColor = _sentinel,
  }) {
    return TextCelStyle(
      fontFamily: identical(fontFamily, _sentinel)
          ? this.fontFamily
          : fontFamily as String?,
      fontSize: fontSize ?? this.fontSize,
      bold: bold ?? this.bold,
      letterSpacing: letterSpacing ?? this.letterSpacing,
      align: align ?? this.align,
      color: color ?? this.color,
      outlineColor: identical(outlineColor, _sentinel)
          ? this.outlineColor
          : outlineColor as int?,
      outlineWidth: outlineWidth ?? this.outlineWidth,
      backgroundColor: identical(backgroundColor, _sentinel)
          ? this.backgroundColor
          : backgroundColor as int?,
    );
  }

  Map<String, dynamic> toJson() => {
    if (fontFamily != null) 'fontFamily': fontFamily,
    'fontSize': fontSize,
    if (bold) 'bold': bold,
    if (letterSpacing != 0) 'letterSpacing': letterSpacing,
    'align': align.jsonValue,
    'color': color,
    if (outlineColor != null) 'outlineColor': outlineColor,
    if (outlineWidth != 0) 'outlineWidth': outlineWidth,
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
      backgroundColor: json['backgroundColor'] as int?,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TextCelStyle &&
          other.fontFamily == fontFamily &&
          other.fontSize == fontSize &&
          other.bold == bold &&
          other.letterSpacing == letterSpacing &&
          other.align == align &&
          other.color == color &&
          other.outlineColor == outlineColor &&
          other.outlineWidth == outlineWidth &&
          other.backgroundColor == backgroundColor;

  @override
  int get hashCode => Object.hash(
    fontFamily,
    fontSize,
    bold,
    letterSpacing,
    align,
    color,
    outlineColor,
    outlineWidth,
    backgroundColor,
  );

  static const Object _sentinel = Object();
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
