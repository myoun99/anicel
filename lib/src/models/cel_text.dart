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

/// How one PARAGRAPH of a cel text is set — its letters from one break to
/// the next: where its lines stand along their way, and how far apart they
/// are.
///
/// 🗣️Q1 (유저 2026-10-17, 「일곱 전부」) ④⑤ of what a CLIP STUDIO text loses
/// once edited: 「줄마다 다른 정렬 · 줄마다 다른 줄 간격」 — a CLIP STUDIO text
/// holds both a paragraph (its parameters 12 and 13).
class CelTextParagraph {
  const CelTextParagraph({
    this.align = TextCelAlign.left,
    this.lineHeight = CelTextContent.defaultLineHeight,
  });

  /// Where its lines stand along their way — in a box, across its width.
  ///
  /// ⚠️Written in columns it keeps its three names and is read along the
  /// letters: left is the head of a column, right its foot.
  final TextCelAlign align;

  /// Its lines' pitch, as a multiple of their letters' size.
  final double lineHeight;

  CelTextParagraph copyWith({TextCelAlign? align, double? lineHeight}) =>
      CelTextParagraph(
        align: align ?? this.align,
        lineHeight: lineHeight ?? this.lineHeight,
      );

  Map<String, dynamic> toJson() => {
    'align': align.jsonValue,
    'lineHeight': lineHeight,
  };

  factory CelTextParagraph.fromJson(Map<String, dynamic> json) =>
      CelTextParagraph(
        align: TextCelAlign.fromJson(json['align'] as String?),
        lineHeight:
            (json['lineHeight'] as num?)?.toDouble() ??
            CelTextContent.defaultLineHeight,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CelTextParagraph &&
          other.align == align &&
          other.lineHeight == lineHeight;

  @override
  int get hashCode => Object.hash(align, lineHeight);

  @override
  String toString() => 'CelTextParagraph(${align.name}, $lineHeight)';
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
    this.minHeight,
    this.rotationDegrees = 0,
    List<CelTextParagraph>? paragraphs,
    TextCelAlign? align,
    double? lineHeight,
    this.letterWidth = 1,
    this.backgroundColor,
    this.vertical = false,
  }) : spans = List.unmodifiable(_settled(spans)),
       paragraphs = List.unmodifiable(
         paragraphs ??
             List.filled(
               _paragraphCountOf(spans),
               CelTextParagraph(
                 align: align ?? TextCelAlign.left,
                 lineHeight: lineHeight ?? defaultLineHeight,
               ),
             ),
       ) {
    if (paragraphs != null && (align != null || lineHeight != null)) {
      throw ArgumentError(
        'A text is set paragraph by paragraph, or all alike — not both.',
      );
    }
    if (this.paragraphs.length != _paragraphCountOf(spans)) {
      throw ArgumentError.value(
        this.paragraphs.length,
        'paragraphs',
        'A text is set a paragraph at a time: one for each.',
      );
    }
    // ⚠️Refused HERE, where a content is made, and not where one is set:
    // the engine lays a box of no width out as one letter a line and a
    // pitch of nothing as no lines at all, and a plate baked from either
    // is a picture nobody asked for that the cel then keeps.
    _requireLength(wrapWidth, 'wrapWidth');
    _requireLength(minHeight, 'minHeight');
    for (final paragraph in this.paragraphs) {
      _requireLength(paragraph.lineHeight, 'lineHeight');
    }
    _requireLength(letterWidth, 'letterWidth');
    if (minHeight != null && wrapWidth == null) {
      throw ArgumentError.value(
        minHeight,
        'minHeight',
        'A text that grows has no box to be tall.',
      );
    }
    if (!rotationDegrees.isFinite) {
      throw ArgumentError.value(
        rotationDegrees,
        'rotationDegrees',
        'A text turns by a finite angle.',
      );
    }
  }

  /// How many paragraphs [spans] hold: one more than their breaks.
  static int _paragraphCountOf(List<CelTextSpan> spans) =>
      1 +
      spans.fold(
        0,
        (breaks, span) => breaks + '\n'.allMatches(span.text).length,
      );

  static void _requireLength(double? value, String name) {
    if (value != null && !(value > 0 && value.isFinite)) {
      throw ArgumentError.value(
        value,
        name,
        'A text\'s $name is a length: finite and above zero.',
      );
    }
  }

  /// A line's pitch as a multiple of its letters' size — the leading the
  /// canvas text has always been set at (`layoutTextCel`).
  static const double defaultLineHeight = 1.25;

  /// The letters, in reading order: no run is empty and no two neighbours
  /// wear the same style, so two contents that read and look alike ARE
  /// alike ([_settled]).
  final List<CelTextSpan> spans;

  /// Where the text stands. With no [wrapWidth] it is the point its lines
  /// are set about — their left end, their middle or their right end, as
  /// [standsBy] says — at the first line's top. With one it is the box's
  /// top left corner, and each paragraph's alignment places its lines
  /// inside the width.
  ///
  /// Written in columns ([vertical]) it is the same point read the other
  /// way: the point the columns are set about — their top, their middle or
  /// their bottom — at the first column's right, or the box's top RIGHT
  /// corner.
  ///
  /// The text turns about this point ([rotationDegrees]), so letters typed
  /// into a turned text run on along its own line and the ones already
  /// there do not move.
  final CanvasPoint anchor;

  /// The width its lines wrap at — 유저 2026-10-06: a box dragged out has
  /// 「폭이 정해진 상자(자동 줄바꿈)」. Null for a text that grows with what
  /// is typed and breaks only where the person pressed Enter.
  ///
  /// Written in columns ([vertical]) it is how LONG a column runs before
  /// the next one begins: the same room, along the way the letters go.
  final double? wrapWidth;

  /// How tall a box is AT LEAST — dragged out with it, or set by its top
  /// and bottom edges: its lines go in from the top, and a box with more of
  /// them than that grows down to hold them all. Null for a box as tall as
  /// its lines, and for a text that grows, which has no box.
  ///
  /// 🗣️F-317 (유저 2026-10-08): 「위아래 크기지정도 처음에 사각형 만들때
  /// 살린다던가 그런식으로 로직통일하면서」 — and F-317-Q1 · Q2 (10-14):
  /// 「상자가 글자를 따라 늘어난다 — 끈 높이는 최소치」, kept over Premiere's
  /// and Clip Studio's fixed box that hides what runs over.
  ///
  /// Written in columns it is how WIDE the box is at least: the same room,
  /// the way the columns stack.
  final double? minHeight;

  /// Clockwise, in canvas degrees, about [anchor].
  final double rotationDegrees;

  /// How each PARAGRAPH is set, in reading order: one from the first letter
  /// to the first break, one from each break to the next, one from the last
  /// break to the end — so a text with no break, or no letters, has one.
  ///
  /// [align] and [lineHeight], given to make a content, set every paragraph
  /// alike — a text set as one; [paragraphs] sets each its own. A break
  /// typed in splits a paragraph into two set as it was, and one taken out
  /// joins two as the first was set (`celTextWithLetters`).
  final List<CelTextParagraph> paragraphs;

  /// Which paragraph a caret at [offset] stands in: how many breaks come
  /// before it.
  int paragraphAt(int offset) =>
      '\n'.allMatches(text.substring(0, offset)).length;

  /// How a text that GROWS stands about its [anchor] — the left end of its
  /// lines there, their middle or their right end: as its FIRST paragraph
  /// is aligned, which every paragraph of a text set as one is. Its
  /// paragraphs stand inside the box it is set in each as its own says
  /// (`celTextBoxLengthPast`).
  ///
  /// 🗣️유저 2026-10-18 (text-letters-lean-and-underline-Q5): 「글 덩어리
  /// 하나가 첫 문단의 정렬로 기준점에 선다」 — ONE block, and not each
  /// paragraph about the anchor by its own (a point text's way): made a
  /// box, it moves no letter.
  TextCelAlign get standsBy => paragraphs.first.align;

  /// How wide the letters are drawn, as a share of their own width (장평):
  /// 1 for as their face draws them. Only their width changes — not how
  /// tall they are, nor how far apart their lines are.
  ///
  /// ⏳Written in columns ([vertical]), whether the columns close up with
  /// the letters is text-letters-lean-and-underline-Q3's to say.
  ///
  /// 🗣️Q1 (유저 2026-10-17, 「일곱 전부」) of what a CLIP STUDIO text loses
  /// once edited: ⑥ 「글자 폭(%) — 클튜처럼 글 전체에 하나(상자의 값)」.
  final double letterWidth;

  /// The box filled behind the letters, ARGB; null for none.
  final int? backgroundColor;

  /// Whether the text is written in COLUMNS (縦書き): its letters top to
  /// bottom, its columns from the right to the left — set by the app's one
  /// vertical table (`vertical_writing.dart`).
  ///
  /// 🗣️유저 2026-10-06: 「세로쓰기: 1차는 가로만」 → 「어차피 타임시트나
  /// x시트에서 가로쓰기/세로표기같은거 한거 많으니 그거 통합하면서
  /// 진행해도될듯」.
  ///
  /// ⚠️A paragraph's alignment keeps its three names and is read along the
  /// letters ([CelTextParagraph.align]).
  final bool vertical;

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
    Object? minHeight = _sentinel,
    double? rotationDegrees,
    List<CelTextParagraph>? paragraphs,
    double? letterWidth,
    Object? backgroundColor = _sentinel,
    bool? vertical,
  }) => CelTextContent(
    spans: spans ?? this.spans,
    anchor: anchor ?? this.anchor,
    // ⚠️Through `num`: the parameter is untyped so that null can mean
    // 「take it off」, and a whole number written `200` arrives as an int.
    wrapWidth: identical(wrapWidth, _sentinel)
        ? this.wrapWidth
        : (wrapWidth as num?)?.toDouble(),
    minHeight: identical(minHeight, _sentinel)
        ? this.minHeight
        : (minHeight as num?)?.toDouble(),
    rotationDegrees: rotationDegrees ?? this.rotationDegrees,
    paragraphs: paragraphs ?? this.paragraphs,
    letterWidth: letterWidth ?? this.letterWidth,
    backgroundColor: identical(backgroundColor, _sentinel)
        ? this.backgroundColor
        : backgroundColor as int?,
    vertical: vertical ?? this.vertical,
  );

  /// ⚠️A text whose paragraphs are all set alike writes them as it always
  /// wrote its one setting — two words of its own ([CelTextParagraph.toJson])
  /// — and only one set paragraph by paragraph writes a list. So a file
  /// written before paragraphs were set apart reads as it was written.
  Map<String, dynamic> toJson() {
    final first = paragraphs.first;
    return {
      'spans': [for (final span in spans) span.toJson()],
      'anchor': anchor.toJson(),
      if (wrapWidth != null) 'wrapWidth': wrapWidth,
      if (minHeight != null) 'minHeight': minHeight,
      if (rotationDegrees != 0) 'rotationDegrees': rotationDegrees,
      if (paragraphs.every((paragraph) => paragraph == first))
        ...first.toJson()
      else
        'paragraphs': [for (final paragraph in paragraphs) paragraph.toJson()],
      if (letterWidth != 1) 'letterWidth': letterWidth,
      if (backgroundColor != null) 'backgroundColor': backgroundColor,
      if (vertical) 'vertical': vertical,
    };
  }

  factory CelTextContent.fromJson(Map<String, dynamic> json) {
    final spans = [
      for (final span in json['spans'] as List? ?? const [])
        CelTextSpan.fromJson(span as Map<String, dynamic>),
    ];
    final each = json['paragraphs'] as List?;
    return CelTextContent(
      spans: spans,
      anchor: CanvasPoint.fromJson(json['anchor'] as Map<String, dynamic>),
      wrapWidth: (json['wrapWidth'] as num?)?.toDouble(),
      minHeight: (json['minHeight'] as num?)?.toDouble(),
      rotationDegrees: (json['rotationDegrees'] as num?)?.toDouble() ?? 0,
      paragraphs: each == null
          ? List.filled(
              _paragraphCountOf(spans),
              CelTextParagraph.fromJson(json),
            )
          : [
              for (final paragraph in each)
                CelTextParagraph.fromJson(paragraph as Map<String, dynamic>),
            ],
      letterWidth: (json['letterWidth'] as num?)?.toDouble() ?? 1,
      backgroundColor: json['backgroundColor'] as int?,
      vertical: json['vertical'] as bool? ?? false,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CelTextContent &&
          listEquals(other.spans, spans) &&
          other.anchor == anchor &&
          other.wrapWidth == wrapWidth &&
          other.minHeight == minHeight &&
          other.rotationDegrees == rotationDegrees &&
          listEquals(other.paragraphs, paragraphs) &&
          other.letterWidth == letterWidth &&
          other.backgroundColor == backgroundColor &&
          other.vertical == vertical;

  @override
  int get hashCode => Object.hash(
    Object.hashAll(spans),
    anchor,
    wrapWidth,
    minHeight,
    rotationDegrees,
    Object.hashAll(paragraphs),
    letterWidth,
    backgroundColor,
    vertical,
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

/// A text's pixels as they are drawn: [plate] moved ([dx], [dy]) whole
/// pixels — the plate itself while a hand carries the text (F-344).
typedef CelTextPixels = ({Map<TileCoord, BitmapTile> plate, int dx, int dy});

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
