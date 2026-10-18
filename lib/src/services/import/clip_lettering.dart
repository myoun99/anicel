import 'dart:convert' show utf8;
import 'dart:math' as math;
import 'dart:typed_data';

import '../../models/canvas_point.dart';
import '../../models/cel_text.dart';
import '../../models/import/import_warning.dart';
import '../../models/text_cel_style.dart';
import 'clip_container.dart' show ClipFormatException;
import 'clip_document.dart';
import 'clip_offscreen.dart' show parseClipOffscreenAttribute;

/// One text of a CLIP STUDIO text layer as the app's own text, and the
/// picture CLIP STUDIO drew of it, whose top-left stands at ([left], [top])
/// on the canvas — null where the file holds no picture of it, or does not
/// say where a turned one stands.
typedef ClipCelText = ({
  CelTextContent content,
  ClipPictureSource? picture,
  int left,
  int top,
});

/// [layer]'s texts as the app's own — F-370-Q3 (유저 2026-10-17: 「이제
/// 들인다(앱의 글자로)」): what each says, in its faces, sizes, colours,
/// weights, leans and lines, its paragraphs aligned and spaced as each is,
/// written across or in columns and turned as it stands — at [alpha], the
/// opacity its cel bakes it at — and what of its setting the app cannot
/// keep said by [name] into [warnings].
///
/// 🎯THE LOOK IS CLIP STUDIO'S OWN. The file keeps a picture of every text
/// ([ClipLayer.textPictures]), and a plate is a text's picture wherever it
/// was baked (`CelText` — 「a plate from another machine is still this
/// text's picture」): a text shows as CLIP STUDIO drew it, in a face this
/// device may not hold, until it is edited and the app sets it again. So
/// what the app cannot set is said as what changes once it is edited.
///
/// The parameters are memory `csp-clip-format-notes` 6-1 §13 — measured on
/// the samples' fifteen texts and on the twelve the person set turned, in
/// columns and aligned to be read (F-370-Q4, 10-18), with the facts two
/// public readers state (`dobrokot/clip_to_psd` · `wamsoft/clipparse`,
/// both MIT).
List<ClipCelText> clipCelTextsOf(
  ClipLayer layer, {
  required double resolution,
  required String name,
  required List<ImportWarning> warnings,
  double alpha = 1,
}) {
  final pictures = [...layer.textPictures];
  // Each thing said once a layer, however many of its texts it is true of.
  final said = <ImportWarning>{};
  final out = <ClipCelText>[];
  for (final lettering in layer.texts) {
    final setting = _ClipTextSetting.read(lettering.attributes);
    if (setting == null) {
      said.add(
        ImportWarning(
          'clipTextUnread',
          '{name}: a text whose setting could not be read — not imported.',
          {'name': name},
        ),
      );
      continue;
    }
    if (lettering.text.isEmpty) {
      continue; // It says nothing: there is nothing of it to show.
    }
    // ⚠️Taken out even where it cannot be laid: left among the rest, it
    // would be the picture of the next text of its size.
    final picture = _takePictureOf(setting, pictures);
    final at = setting.frame.pictureAt;
    said.addAll(setting.unkept(lettering.text, name));
    out.add((
      content: setting.contentOf(
        lettering.text,
        pointPixels: resolution / 72,
        layer: (x: layer.offsetX, y: layer.offsetY),
        alpha: alpha,
      ),
      picture: at == null ? null : picture,
      left: layer.offsetX + (at?.x ?? setting.box.x0),
      top: layer.offsetY + (at?.y ?? setting.box.y0),
    ));
  }
  warnings.addAll(said);
  return out;
}

/// The picture of [setting]'s text among [pictures] — taken out of
/// [pictures], so two texts of one size each have their own, in the file's
/// order.
///
/// CLIP STUDIO keeps it one pixel wider and taller than the text's box
/// (parameter 63; all 15 of the samples' upright texts), and a turned
/// text's as wide and as tall as that box turned — to within a pixel, as it
/// rounds a turned picture its own way, so the nearest within
/// [_turnedSlack] is its own.
ClipPictureSource? _takePictureOf(
  _ClipTextSetting setting,
  List<ClipPictureSource> pictures,
) {
  final size = setting.boxSize;
  if (size == null) {
    return null;
  }
  final turn = setting.frame.turn;
  final (along, across) = (math.cos(turn).abs(), math.sin(turn).abs());
  final width = size.width * along + size.height * across + 1;
  final height = size.width * across + size.height * along + 1;
  final slack = turn == 0 ? 0 : _turnedSlack;
  int? nearest;
  var nearestMiss = double.infinity;
  for (var i = 0; i < pictures.length; i += 1) {
    final double miss;
    try {
      final shape = parseClipOffscreenAttribute(pictures[i].attribute);
      miss = math.max(
        (shape.width - width).abs(),
        (shape.height - height).abs(),
      );
    } on ClipFormatException {
      continue;
    }
    if (miss <= slack && miss < nearestMiss) {
      (nearest, nearestMiss) = (i, miss);
    }
  }
  return nearest == null ? null : pictures.removeAt(nearest);
}

/// How far a turned text's picture may be from its box turned, either way:
/// the sample's three were 0.92 px off at most (F-370-Q4 — 0.1 · 0.92,
/// 0.22 · 0.38 and 0.90 · 0.04 across and down), and a picture two pixels
/// off is another text's.
const double _turnedSlack = 1.5;

/// A stretch of a text's letters — its first, in UTF-16 units of what the
/// text says, and how many — and what is said of it.
typedef _Stretch<T> = ({int start, int length, T value});

/// The units of a text from [start] up to [end].
typedef _Range = ({int start, int end});

/// One run of letters in a style of its own (parameter 11).
typedef _Run = ({
  int start,
  int length,
  bool bold,
  bool italic,
  int? colour,
  double? scale,
  String? face,
});

/// A text's setting as its attribute parameters say it: `u32 LE id · u32
/// LE size · bytes`, again and again — a parameter of no size is empty.
final class _ClipTextSetting {
  _ClipTextSetting._({
    required this.runs,
    required this.aligns,
    required this.spacings,
    required this.underlines,
    required this.strikes,
    required this.face,
    required this.points,
    required this.colour,
    required this.box,
    required this.boxSize,
    required this.frame,
    required this.across,
    required this.columns,
    required this.textAlign,
  });

  /// Null for bytes that do not read as the parameters they say they are,
  /// or that set no letters anywhere.
  static _ClipTextSetting? read(Uint8List attributes) {
    try {
      final parameters = _parametersOf(attributes);
      ByteData? at(int id) => parameters[id];
      List<int>? ints(int id, int count) => _intsOf(at(id), count);
      final points = (ints(32, 1)?.single ?? 0) / 100;
      final box = switch (ints(42, 4)) {
        [final x0, final y0, final x1, final y1] => (
          x0: x0,
          y0: y0,
          x1: x1,
          y1: y1,
        ),
        _ => null,
      };
      if (!(points > 0) || box == null) {
        return null;
      }
      int flagAt(ByteData data, int item) => data.getUint8(item + 12);
      return _ClipTextSetting._(
        runs: _runsOf(at(11)),
        aligns: _stretchesOf(at(12), flagAt),
        spacings: _spacingsOf(at(13)),
        underlines: _stretchesOf(at(16), flagAt),
        strikes: _stretchesOf(at(20), flagAt),
        face: _utf8Of(at(31)),
        points: points,
        colour: _colourOf(at(34)),
        box: box,
        boxSize: switch (ints(63, 2)) {
          [final width, final height] => (width: width, height: height),
          _ => null,
        },
        frame: _ClipTextFrame.of(
          box,
          corners: ints(64, 8),
          offset: ints(72, 2),
        ),
        across: _acrossOf(at(26)),
        columns: (ints(33, 1)?.single ?? 0) & _inColumns != 0,
        textAlign: ints(35, 1)?.single ?? 0,
      );
    } on RangeError {
      return null;
    }
  }

  final List<_Run> runs;
  final List<_Stretch<int>> aligns;
  final List<_Stretch<double>> spacings;
  final List<_Stretch<int>> underlines;
  final List<_Stretch<int>> strikes;

  /// The face its letters are set in where a run names none.
  final String? face;

  /// Its letters' size in points (parameter 32 — hundredths of a point).
  final double points;

  /// Its letters' colour where a run has none of its own, RGB.
  final int colour;

  /// Where its letters stand on the layer before its frame turns
  /// (parameter 42: x0 · y0 · x1 · y1 — a turned text keeps the box it had
  /// upright, F-370-Q4).
  final ({int x0, int y0, int x1, int y1}) box;

  /// Parameter 63 — its picture is one pixel more each way.
  final ({int width, int height})? boxSize;

  /// How its box stands: where the frame it stands in is, and how far that
  /// is turned (parameters 64 · 72).
  final _ClipTextFrame frame;

  /// How wide its letters are drawn, in % of their own width (parameter 26).
  final double across;

  /// Whether it is written in columns (parameter 33).
  final bool columns;

  /// How a paragraph no stretch of [aligns] covers is aligned (parameter
  /// 35 — on the sample's twelve, what its stretches say).
  final int textAlign;

  /// What [text] says, set as this setting sets it on a layer whose
  /// top-left stands at [layer] on the canvas, at [alpha].
  ///
  /// [pointPixels] is how many canvas pixels a point is (the canvas's
  /// resolution ÷ 72).
  CelTextContent contentOf(
    String text, {
    required double pointPixels,
    required ({int x, int y}) layer,
    required double alpha,
  }) {
    final size = points * pointPixels;
    final paragraphs = _paragraphsOf(text);
    // ⚠️The box holds the first line's letters, and a line is set its
    // pitch tall about them: its top stands half the leading above the box
    // — in columns, its right half the leading right of the first column's
    // letters — so the letters land where CLIP STUDIO set them.
    final lead = (paragraphs.first.lineHeight - 1) * size / 2;
    final share = paragraphs.first.align.shareBefore;
    final (width, height) = (box.x1 - box.x0, box.y1 - box.y0);
    final corner = frame.corner;
    final anchor = columns
        ? frame.place(
            corner.x + width - _columnsPast + lead,
            corner.y + height * share,
          )
        : frame.place(corner.x + width * share, corner.y - lead);
    return CelTextContent(
      spans: _spansOf(text, size, alpha),
      anchor: CanvasPoint(x: layer.x + anchor.x, y: layer.y + anchor.y),
      rotationDegrees: frame.turn * 180 / math.pi,
      paragraphs: paragraphs,
      letterWidth: across > 0 && across.isFinite ? across / 100 : 1,
      vertical: columns,
    );
  }

  /// The line spacing of a text that names none: CLIP STUDIO's own
  /// (parameter 13 — 120 on all 15 of the samples' texts).
  static const double defaultSpacing = 120;

  /// How each of [text]'s paragraphs is set — as most of its letters say,
  /// and as the text says where none of them do; a last one with no
  /// letters as the one before it, as a break typed at the end leaves it
  /// (`celTextWithLetters`).
  List<CelTextParagraph> _paragraphsOf(String text) {
    final paragraphs = <CelTextParagraph>[];
    for (final range in _paragraphRangesOf(text)) {
      paragraphs.add(
        range.start == range.end && paragraphs.isNotEmpty
            ? paragraphs.last
            : CelTextParagraph(
                align: _alignOf(_mostOf(aligns, range) ?? textAlign),
                lineHeight:
                    (_mostOf(spacings, range) ?? defaultSpacing) / 100,
              ),
      );
    }
    return paragraphs;
  }

  /// What [text] says, a letter at a time in its style — its run's, the
  /// setting's elsewhere, lined under and through where its stretches say
  /// — [size] pixels tall at [alpha]. Its breaks are read as
  /// [_paragraphRangesOf] reads them; the content joins what reads alike.
  List<CelTextSpan> _spansOf(String text, double size, double alpha) {
    final base = TextLetterStyle(
      fontFamily: face,
      fontSize: size,
      color: _faded(colour, alpha),
    );
    final styles = List<TextLetterStyle>.filled(text.length, base);
    for (final run in runs) {
      final style = TextLetterStyle(
        fontFamily: run.face ?? face,
        fontSize: size * (run.scale ?? 100) / 100,
        bold: run.bold,
        italic: run.italic,
        color: _faded(run.colour ?? colour, alpha),
      );
      for (final i in _lettersOf(run.start, run.length, text.length)) {
        styles[i] = style;
      }
    }
    void line(
      List<_Stretch<int>> stretches,
      TextLetterStyle Function(TextLetterStyle style) lined,
    ) {
      for (final (:start, :length, :value) in stretches) {
        if (value == 0) {
          continue; // A line set to nothing is none.
        }
        for (final i in _lettersOf(start, length, text.length)) {
          styles[i] = lined(styles[i]);
        }
      }
    }

    line(underlines, (style) => style.copyWith(underline: true));
    line(strikes, (style) => style.copyWith(strikethrough: true));
    return [
      for (var i = 0; i < text.length; i += 1)
        if (!_isCrBeforeLf(text, i))
          CelTextSpan(
            text: text.codeUnitAt(i) == _cr ? '\n' : text[i],
            // A letter outside the first plane is two units: the second
            // wears the first's style, so no run boundary can split it.
            style: i > 0 && _isTrail(text.codeUnitAt(i))
                ? styles[i - 1]
                : styles[i],
          ),
    ];
  }

  /// What of this setting the app cannot set, said by [name] of [text].
  Iterable<ImportWarning> unkept(String text, String name) sync* {
    ImportWarning say(String key, String template) =>
        ImportWarning(key, template, {'name': name});
    final paragraphs = _paragraphRangesOf(
      text,
    ).where((range) => range.end > range.start);
    if (paragraphs.any(
      (range) =>
          _kindsOf(aligns, range) > 1 ||
          (_mostOf(aligns, range) ?? textAlign) > 2,
    )) {
      yield say(
        'clipTextAlign',
        '{name}: lines aligned in a way this app cannot set — shown as CLIP '
            'STUDIO drew them, and aligned alike once edited.',
      );
    }
    if (paragraphs.any((range) => _kindsOf(spacings, range) > 1)) {
      yield say(
        'clipTextSpacing',
        '{name}: lines spaced unevenly — shown as CLIP STUDIO drew them, and '
            'spaced evenly once edited.',
      );
    }
    if (frame.distorted) {
      yield say(
        'clipTextDistorted',
        '{name}: a distorted text — shown as CLIP STUDIO drew it, and set '
            'undistorted once edited.',
      );
    }
  }
}

/// Where a text's frame stands on its layer and how it is turned: the
/// text's box stands upright in it, and the frame turns about its origin.
///
/// Parameter 64 is the box's four corners, clockwise from the top-left in
/// hundredths of a pixel, measured from the origin and turned with the
/// frame; parameter 72 is how far the origin stands right of and below the
/// top-left of the picture CLIP STUDIO drew (F-370-Q4 — the sample's
/// turned texts keep their upright box, parameter 42, and their corners
/// alone turn).
final class _ClipTextFrame {
  const _ClipTextFrame._({
    required this.origin,
    required this.turn,
    required this.corner,
    required this.pictureAt,
    required this.distorted,
  });

  /// [box]'s frame as its [corners] (eight hundredths) and its picture's
  /// [offset] (x · y) say it — upright, its origin at the box's top-left,
  /// where it names no corners.
  factory _ClipTextFrame.of(
    ({int x0, int y0, int x1, int y1}) box, {
    required List<int>? corners,
    required List<int>? offset,
  }) {
    final (width, height) = (100 * (box.x1 - box.x0), 100 * (box.y1 - box.y0));
    // The top edge runs from a to b, the left edge from a to d.
    final [ax, ay, bx, by, _, _, dx, dy] = [
      for (final value
          in corners ?? [0, 0, width, 0, width, height, 0, height])
        value / 100,
    ];
    final turn = math.atan2(by - ay, bx - ax);
    final (cos, sin) = (math.cos(turn), math.sin(turn));
    // The box's top-left in the frame, turned back upright.
    final corner = (
      x: (ax * cos + ay * sin).round(),
      y: (ay * cos - ax * sin).round(),
    );
    // Where the origin stood upright, and where turning it takes it.
    final (ux, uy) = (box.x0 - corner.x, box.y0 - corner.y);
    final (px, py) = (
      (box.x0 + box.x1) / 2 + _pivotRight,
      (box.y0 + box.y1) / 2,
    );
    final origin = (
      x: (px + (ux - px) * cos - (uy - py) * sin).round(),
      y: (py + (ux - px) * sin + (uy - py) * cos).round(),
    );
    final picture = switch (offset) {
      [final x, final y] => (x: x, y: y),
      // Upright, its picture stands at its box (wamsoft `clipparse`: 「この
      // (x0, y0) にオブジェクト Offscreen をそのまま置く」, and so it lies on
      // the samples' own canvas preview, 10-17); turned, nobody says where.
      _ when turn == 0 => (x: -corner.x, y: -corner.y),
      _ => null,
    };
    return _ClipTextFrame._(
      origin: origin,
      turn: turn,
      corner: corner,
      pictureAt: picture == null
          ? null
          : (x: origin.x - picture.x, y: origin.y - picture.y),
      distorted: !_isSquare(bx - ax, by - ay, dx - ax, dy - ay),
    );
  }

  /// Where the frame's origin stands on the layer.
  final ({int x, int y}) origin;

  /// How far the frame is turned, clockwise in radians.
  final double turn;

  /// The box's top-left in the frame, upright: where its letters begin.
  final ({int x, int y}) corner;

  /// Where the picture's top-left stands on the layer — null where the file
  /// does not say.
  final ({int x, int y})? pictureAt;

  /// Whether its corners stand other than square: slanted, or flipped.
  final bool distorted;

  /// The point ([x], [y]) of the frame, on the layer.
  ({double x, double y}) place(double x, double y) {
    final (cos, sin) = (math.cos(turn), math.sin(turn));
    return (x: origin.x + x * cos - y * sin, y: origin.y + x * sin + y * cos);
  }
}

/// 🔬A FIT, NOT A READING (F-370-Q4 — the person's sample, 10-18): CLIP
/// STUDIO turns a frame about a point of its own, and where a turned origin
/// stands the file keeps nowhere we could find (every table, as ints,
/// floats, doubles, hundredths, 16.16 and offsets from the box). Turned
/// about the box's middle, none of the sample's three turned texts lands on
/// its picture; about a point [_pivotRight] px right of it, rounded to the
/// pixel, all three do — as they do about any from 1.0 to 1.48 px right,
/// whose middle this is (fourteen rules of this shape fit, and none turns
/// about the middle itself). ⚠️A turned text of another file may stand a
/// pixel off: board `a-turned-clip-text-may-stand-a-pixel-off`.
const double _pivotRight = 1.25;

/// 🔬How far a text's box runs past its first column's letters, written in
/// columns (F-370-Q4: on the sample's four columned texts the first
/// column's ink stands 8 px inside either side of a column whose right is
/// the box's less a pixel).
const int _columnsPast = 1;

/// How far from a right angle a frame's corners may stand and still be
/// square, in radians: the hundredths they are kept in turn a 10 px edge
/// by 0.002 at most.
const double _squareTurn = 0.01;

/// Whether a frame whose top edge runs ([topX], [topY]) and whose left edge
/// runs ([sideX], [sideY]) is square: its left edge its top one turned a
/// right angle clockwise, to within [_squareTurn].
bool _isSquare(double topX, double topY, double sideX, double sideY) {
  final lengths =
      math.sqrt(topX * topX + topY * topY) *
      math.sqrt(sideX * sideX + sideY * sideY);
  return lengths > 0 &&
      (topX * sideY - topY * sideX) / lengths >= math.cos(_squareTurn);
}

/// Parameter 33's bit for a text written in columns (F-370-Q4: set on all
/// four of the sample's columned texts and on none of its eight others, nor
/// on the earlier samples' fifteen); 1 and 2 there are bold and italic, as
/// in a run's style.
const int _inColumns = 16;

const int _cr = 0x0D;
const int _lf = 0x0A;

/// What two of a file's values that say the same thing may differ by: the
/// last bits of a float's (a spacing of 119.99999999999993 is 120).
const double _noise = 1e-6;

bool _isTrail(int unit) => unit >= 0xDC00 && unit <= 0xDFFF;

/// Whether the unit at [i] of [text] is the CR of a CR LF: one break, read
/// at its LF.
bool _isCrBeforeLf(String text, int i) =>
    text.codeUnitAt(i) == _cr &&
    i + 1 < text.length &&
    text.codeUnitAt(i + 1) == _lf;

/// Where each paragraph of [text] runs, its break with it and the last one
/// to the end: a CR LF is one break, and so is a CR or an LF alone.
List<_Range> _paragraphRangesOf(String text) {
  final ranges = <_Range>[];
  var start = 0;
  for (var i = 0; i < text.length; i += 1) {
    final unit = text.codeUnitAt(i);
    if ((unit == _cr || unit == _lf) && !_isCrBeforeLf(text, i)) {
      ranges.add((start: start, end: i + 1));
      start = i + 1;
    }
  }
  return [...ranges, (start: start, end: text.length)];
}

/// The units of a [count]-unit text that a stretch from [start], [length]
/// units long, covers.
Iterable<int> _lettersOf(int start, int length, int count) sync* {
  final end = math.min(count, start + length);
  for (var i = math.max(0, start); i < end; i += 1) {
    yield i;
  }
}

/// [rgb] at [alpha].
int _faded(int rgb, double alpha) =>
    ((0xFF * alpha).round().clamp(0, 0xFF) << 24) | (rgb & 0xFFFFFF);

/// Parameters 12 · 35's alignment as the app's: 0 left, 1 right, 2 centred
/// (F-370-Q4: the sample's right-aligned and centred texts, as clip_to_psd
/// reads them) — in columns the head, the foot and the middle; anything
/// else left.
TextCelAlign _alignOf(int value) => switch (value) {
  1 => TextCelAlign.right,
  2 => TextCelAlign.center,
  _ => TextCelAlign.left,
};

/// The value most of [range]'s letters are given by [stretches] — of two
/// given to as many, the smaller; null where no stretch covers a letter of
/// it.
T? _mostOf<T extends num>(List<_Stretch<T>> stretches, _Range range) {
  final counts = _countsOf(stretches, range);
  if (counts.isEmpty) {
    return null;
  }
  final values = counts.keys.toList()..sort();
  return values.reduce((a, b) => counts[b]! > counts[a]! ? b : a);
}

/// How many different values [stretches] give [range]'s letters.
int _kindsOf<T extends num>(List<_Stretch<T>> stretches, _Range range) =>
    _countsOf(stretches, range).length;

/// How many of [range]'s letters each value covers — values within
/// [_noise] of one another counted as one.
Map<T, int> _countsOf<T extends num>(
  List<_Stretch<T>> stretches,
  _Range range,
) {
  final counts = <T, int>{};
  for (final stretch in stretches) {
    final covered =
        math.min<int>(range.end, stretch.start + stretch.length) -
        math.max<int>(range.start, stretch.start);
    if (covered <= 0) {
      continue;
    }
    final key =
        counts.keys
            .where((value) => (value - stretch.value).abs() <= _noise)
            .firstOrNull ??
        stretch.value;
    counts[key] = (counts[key] ?? 0) + covered;
  }
  return counts;
}

/// The parameters [attributes] holds, each the first of its id.
Map<int, ByteData> _parametersOf(Uint8List attributes) {
  final data = ByteData.sublistView(attributes);
  final out = <int, ByteData>{};
  var at = 0;
  while (at + 8 <= attributes.length) {
    final id = data.getUint32(at, Endian.little);
    final size = data.getUint32(at + 4, Endian.little);
    at += 8;
    if (at + size > attributes.length) {
      throw RangeError('parameter $id runs past the attributes');
    }
    out.putIfAbsent(id, () => ByteData.sublistView(attributes, at, at + size));
    at += size;
  }
  return out;
}

/// The first [count] `i32 LE` of [data] — null where it holds fewer:
/// parameters 32 (size) · 33 (flags) · 35 (alignment) · 42 (box) · 63 (box
/// size) · 64 (corners) · 72 (the picture's offset).
List<int>? _intsOf(ByteData? data, int count) =>
    data == null || data.lengthInBytes < 4 * count
    ? null
    : [for (var k = 0; k < count; k += 1) data.getInt32(4 * k, Endian.little)];

/// Parameters 11 · 13: `u32 n`, then each item — `i32 start · u32 length
/// · u32 size` and bytes of its own — read by [read] at its offset; the
/// next stands [sizeFrom] bytes past this one's start, and its size more.
/// An item [read] makes nothing of is left out.
List<T> _sizedItemsOf<T extends Object>(
  ByteData? data, {
  required int sizeFrom,
  required T? Function(ByteData data, int at, int size) read,
}) {
  if (data == null || data.lengthInBytes < 4) {
    return <T>[];
  }
  final items = <T>[];
  var at = 4;
  for (var k = data.getUint32(0, Endian.little); k > 0; k -= 1) {
    final size = data.getUint32(at + 8, Endian.little);
    if (read(data, at, size) case final item?) {
      items.add(item);
    }
    at += sizeFrom + size;
  }
  return items;
}

/// Parameter 11: each run's size counts from its length on, and after the
/// header come `u8 style` (1 bold · 2 italic) `· u8 own` (1 its colour · 2
/// its scale) `· u16 × 3 colour · f64 scale % · u16 count + UTF-16LE face`.
List<_Run> _runsOf(ByteData? data) => _sizedItemsOf(
  data,
  sizeFrom: 4,
  read: (data, at, _) {
    final style = data.getUint8(at + 12);
    final own = data.getUint8(at + 13);
    final scale = data.getFloat64(at + 20, Endian.little);
    final letters = data.getUint16(at + 28, Endian.little);
    return (
      start: data.getInt32(at, Endian.little),
      length: data.getUint32(at + 4, Endian.little),
      bold: style & 1 != 0,
      italic: style & 2 != 0,
      colour: own & 1 == 0
          ? null
          : _rgbOf([
              for (var c = 0; c < 3; c += 1)
                (data.getUint16(at + 14 + 2 * c, Endian.little) / 257).round(),
            ]),
      scale: own & 2 != 0 && scale > 0 ? scale : null,
      face: letters == 0
          ? null
          : String.fromCharCodes([
              for (var c = 0; c < letters; c += 1)
                data.getUint16(at + 30 + 2 * c, Endian.little),
            ]),
    );
  },
);

/// Parameters 12 · 16 · 20: `u32 n`, then each stretch — `i32 start · u32
/// length · u32 · u8 value · u8` — its value read by [valueAt].
List<_Stretch<T>> _stretchesOf<T>(
  ByteData? data,
  T Function(ByteData data, int item) valueAt,
) {
  if (data == null || data.lengthInBytes < 4) {
    return const [];
  }
  return [
    for (var k = 0; k < data.getUint32(0, Endian.little); k += 1)
      (
        start: data.getInt32(4 + 14 * k, Endian.little),
        length: data.getUint32(8 + 14 * k, Endian.little),
        value: valueAt(data, 4 + 14 * k),
      ),
  ];
}

/// Parameter 13: each stretch's size counts from past its header, and its
/// bytes end in its spacing, an f64 in %.
List<_Stretch<double>> _spacingsOf(ByteData? data) => _sizedItemsOf(
  data,
  sizeFrom: 12,
  read: (data, at, size) {
    final spacing = data.getFloat64(at + 12 + size - 8, Endian.little);
    return spacing > 0
        ? (
            start: data.getInt32(at, Endian.little),
            length: data.getUint32(at + 4, Endian.little),
            value: spacing,
          )
        : null;
  },
);

String? _utf8Of(ByteData? data) => data == null || data.lengthInBytes == 0
    ? null
    : utf8.decode(Uint8List.sublistView(data), allowMalformed: true);

/// Parameter 34: `u32 × 3`, a channel each — read by its top byte, as the
/// paper's colour is (`ClipLayer.mainColour`). Black where it is not.
int _colourOf(ByteData? data) {
  if (data == null || data.lengthInBytes < 12) {
    return 0;
  }
  return _rgbOf([
    for (var c = 0; c < 3; c += 1) data.getUint32(4 * c, Endian.little) >> 24,
  ]);
}

int _rgbOf(List<int> rgb) => (rgb[0] << 16) | (rgb[1] << 8) | rgb[2];

/// Parameter 26: 16 bytes, then the letters' width in % as an f64 — 100
/// where it is not.
double _acrossOf(ByteData? data) {
  if (data == null || data.lengthInBytes < 24) {
    return 100;
  }
  return data.getFloat64(16, Endian.little);
}
