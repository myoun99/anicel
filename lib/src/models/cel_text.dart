import '../core/collection_equality.dart';
import 'bitmap_tile.dart';
import 'canvas_point.dart';
import 'text_cel_style.dart';
import 'tile_coord.dart';

/// One run of a cel text's letters, all in one letter style.
class CelTextSpan {
  const CelTextSpan({required this.text, required this.style});

  final String text;
  final TextLetterStyle style;

  Map<String, dynamic> toJson() => {'text': text, 'style': style.toJson()};

  factory CelTextSpan.fromJson(Map<String, dynamic> json) => CelTextSpan(
    text: json['text'] as String? ?? '',
    style: json['style'] is Map<String, dynamic>
        ? TextLetterStyle.fromJson(json['style'] as Map<String, dynamic>)
        : const TextLetterStyle(),
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CelTextSpan && other.text == text && other.style == style;

  @override
  int get hashCode => Object.hash(text, style);

  @override
  String toString() => 'CelTextSpan($text)';
}

/// What a text on a cel SAYS and how it is set — every value the person
/// chose, in canvas pixels, and nothing derived from them.
///
/// 🗣️유저 2026-10-02 (R9-rest): 「클튜나 포토샵이랑 동일하게 텍스트툴로 캔버스에
/// 클릭하면 텍스트 박스가 생김. 거기서 입력 … 텍스트 레이어가 존재하지않음 …
/// 기존 그림 레이어에 텍스트툴로 텍스트 들어가고, 복수 텍스트 들어갈수있음」.
///
/// ⚠️THE NUMBERS ARE ABSOLUTE, as every edit value on a canvas is (the tool
/// law, 유저 2026-09-20: 「편집값은 절대값이야. 그냥 고정이야」): a size is the
/// size on every cut, and nothing here is a share of the page.
class CelTextContent {
  CelTextContent({
    required List<CelTextSpan> spans,
    required this.anchor,
    this.wrapWidth,
    this.rotationDegrees = 0,
    this.align = TextCelAlign.left,
    this.lineHeight = defaultLineHeight,
    this.backgroundColor,
  }) : spans = List.unmodifiable(_settled(spans));

  /// A line's pitch as a multiple of its letters' size — the leading the
  /// canvas text has always been set at (`layoutTextCel`).
  static const double defaultLineHeight = 1.25;

  /// The letters, in reading order: no run is empty and no two neighbours
  /// wear the same style, so two contents that read and look alike ARE
  /// alike ([_settled]).
  final List<CelTextSpan> spans;

  /// Where the text stands. With no [wrapWidth] it is the point its lines
  /// are set about — their left end, their middle or their right end, as
  /// [align] says — at the first line's top. With one it is the box's top
  /// left corner, and [align] places the lines inside the width.
  ///
  /// The text turns about this point ([rotationDegrees]), so letters typed
  /// into a turned text run on along its own line and the ones already
  /// there do not move.
  final CanvasPoint anchor;

  /// The width its lines wrap at — 유저 2026-10-06: a box dragged out has
  /// 「폭이 정해진 상자(자동 줄바꿈)」. Null for a text that grows with what
  /// is typed and breaks only where the person pressed Enter.
  final double? wrapWidth;

  /// Clockwise, in canvas degrees, about [anchor].
  final double rotationDegrees;

  final TextCelAlign align;
  final double lineHeight;

  /// The box filled behind the letters, ARGB; null for none.
  final int? backgroundColor;

  /// Every letter, as one string.
  String get text => spans.map((span) => span.text).join();

  bool get isEmpty => spans.isEmpty;

  /// Runs as a content keeps them: the empty ones dropped, and a run that
  /// wears its neighbour's style joined to it.
  static List<CelTextSpan> _settled(List<CelTextSpan> spans) {
    final settled = <CelTextSpan>[];
    for (final span in spans) {
      if (span.text.isEmpty) {
        continue;
      }
      if (settled.isNotEmpty && settled.last.style == span.style) {
        settled.last = CelTextSpan(
          text: settled.last.text + span.text,
          style: span.style,
        );
        continue;
      }
      settled.add(span);
    }
    return settled;
  }

  CelTextContent copyWith({
    List<CelTextSpan>? spans,
    CanvasPoint? anchor,
    Object? wrapWidth = _sentinel,
    double? rotationDegrees,
    TextCelAlign? align,
    double? lineHeight,
    Object? backgroundColor = _sentinel,
  }) => CelTextContent(
    spans: spans ?? this.spans,
    anchor: anchor ?? this.anchor,
    // ⚠️Through `num`: the parameter is untyped so that null can mean
    // 「take it off」, and a whole number written `200` arrives as an int.
    wrapWidth: identical(wrapWidth, _sentinel)
        ? this.wrapWidth
        : (wrapWidth as num?)?.toDouble(),
    rotationDegrees: rotationDegrees ?? this.rotationDegrees,
    align: align ?? this.align,
    lineHeight: lineHeight ?? this.lineHeight,
    backgroundColor: identical(backgroundColor, _sentinel)
        ? this.backgroundColor
        : backgroundColor as int?,
  );

  Map<String, dynamic> toJson() => {
    'spans': [for (final span in spans) span.toJson()],
    'anchor': anchor.toJson(),
    if (wrapWidth != null) 'wrapWidth': wrapWidth,
    if (rotationDegrees != 0) 'rotationDegrees': rotationDegrees,
    'align': align.jsonValue,
    'lineHeight': lineHeight,
    if (backgroundColor != null) 'backgroundColor': backgroundColor,
  };

  factory CelTextContent.fromJson(Map<String, dynamic> json) => CelTextContent(
    spans: [
      for (final span in json['spans'] as List? ?? const [])
        CelTextSpan.fromJson(span as Map<String, dynamic>),
    ],
    anchor: CanvasPoint.fromJson(json['anchor'] as Map<String, dynamic>),
    wrapWidth: (json['wrapWidth'] as num?)?.toDouble(),
    rotationDegrees: (json['rotationDegrees'] as num?)?.toDouble() ?? 0,
    align: TextCelAlign.fromJson(json['align'] as String?),
    lineHeight: (json['lineHeight'] as num?)?.toDouble() ?? defaultLineHeight,
    backgroundColor: json['backgroundColor'] as int?,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CelTextContent &&
          listEquals(other.spans, spans) &&
          other.anchor == anchor &&
          other.wrapWidth == wrapWidth &&
          other.rotationDegrees == rotationDegrees &&
          other.align == align &&
          other.lineHeight == lineHeight &&
          other.backgroundColor == backgroundColor;

  @override
  int get hashCode => Object.hash(
    Object.hashAll(spans),
    anchor,
    wrapWidth,
    rotationDegrees,
    align,
    lineHeight,
    backgroundColor,
  );

  @override
  String toString() => 'CelTextContent($text)';

  static const Object _sentinel = Object();
}

/// One text a cel's picture carries above its pixels: what the person set
/// ([content]) and that setting as pixels ([plate]).
///
/// 🚨★★★THE PLATE IS PART OF THE VALUE, so a text can be SHOWN without
/// being set again. Only the engine can set type — shape the letters, read
/// the font — and it answers a frame or more later, which a picture may not
/// wait for (유저 절대규칙 2026-09-17: 「보이는 중이랑 결과랑 절대로 다르면 안
/// 되」). So whoever changes [content] bakes the plate FIRST and installs
/// the pair; nothing that draws a cel ever sees a text without its pixels.
///
/// It also means a cel reads the same on a machine that does not have the
/// font: the plate was saved with it, and the letters are set again only
/// when someone edits them there.
///
/// ⚠️[plate] is what [content] baked to WHERE IT WAS BAKED — not checked
/// against it again. Two engines set the same letters a hair apart, and a
/// plate from another machine is still this text's picture.
class CelText {
  CelText({
    required this.id,
    required this.content,
    Map<TileCoord, BitmapTile> plate = const {},
  }) : plate = Map<TileCoord, BitmapTile>.unmodifiable(plate);

  /// Which text of its cel this is. A text keeps it through every edit, so
  /// the tool's selection and the settings' list name the same one before
  /// and after — and through a copy of the cel, whose texts are then
  /// another cel's.
  final int id;

  final CelTextContent content;

  /// [content] at canvas resolution: straight RGBA tiles on the cel's own
  /// tile grid, holding the letters, their outline and the box behind them.
  /// Empty for a text that draws nothing.
  final Map<TileCoord, BitmapTile> plate;

  CelText copyWith({
    CelTextContent? content,
    Map<TileCoord, BitmapTile>? plate,
  }) => CelText(
    id: id,
    content: content ?? this.content,
    plate: plate ?? this.plate,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'content': content.toJson(),
    'plate': [
      for (final entry in plate.entries)
        {'coord': entry.key.toJson(), 'tile': entry.value.toJson()},
    ],
  };

  factory CelText.fromJson(Map<String, dynamic> json) => CelText(
    id: json['id'] as int,
    content: CelTextContent.fromJson(json['content'] as Map<String, dynamic>),
    plate: {
      for (final record in json['plate'] as List? ?? const [])
        TileCoord.fromJson(
          (record as Map<String, dynamic>)['coord'] as Map<String, dynamic>,
        ): BitmapTile.fromJson(
          record['tile'] as Map<String, dynamic>,
        ),
    },
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CelText &&
          other.id == id &&
          other.content == content &&
          mapEquals(other.plate, plate);

  @override
  int get hashCode => Object.hash(id, content, plate.length);

  @override
  String toString() => 'CelText($id, ${content.text})';
}

/// The id a text added to [texts] takes: one past the largest there.
int nextCelTextId(Iterable<CelText> texts) {
  var largest = 0;
  for (final text in texts) {
    if (text.id > largest) {
      largest = text.id;
    }
  }
  return largest + 1;
}
