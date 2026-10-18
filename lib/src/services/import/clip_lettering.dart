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
/// on the canvas — null where the file holds no picture of it.
typedef ClipCelText = ({
  CelTextContent content,
  ClipPictureSource? picture,
  int left,
  int top,
});

/// [layer]'s texts as the app's own — F-370-Q3 (유저 2026-10-17: 「이제
/// 들인다(앱의 글자로)」): what each says, in its faces, sizes, colours and
/// weights, set where it stands — at [alpha], the opacity its cel bakes it
/// at — and what of its setting the app cannot keep said by [name] into
/// [warnings].
///
/// 🎯THE LOOK IS CLIP STUDIO'S OWN. The file keeps a picture of every text
/// ([ClipLayer.textPictures]), and a plate is a text's picture wherever it
/// was baked (`CelText` — 「a plate from another machine is still this
/// text's picture」): a text shows as CLIP STUDIO drew it, in a face this
/// device may not hold, until it is edited and the app sets it again. So
/// what the app cannot set is said as what changes once it is edited.
///
/// The parameters are memory `csp-clip-format-notes` 6-1 §13 — measured on
/// the samples' fifteen texts, with the facts two public readers state
/// (`dobrokot/clip_to_psd` · `wamsoft/clipparse`, both MIT).
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
    final left = layer.offsetX + setting.box.x0;
    final top = layer.offsetY + setting.box.y0;
    said.addAll(setting.unkept(lettering.text, name));
    out.add((
      content: setting.contentOf(
        lettering.text,
        pointPixels: resolution / 72,
        at: (x: left, y: top),
        alpha: alpha,
      ),
      picture: _takePictureOf(setting, pictures),
      left: left,
      top: top,
    ));
  }
  warnings.addAll(said);
  return out;
}

/// The picture of [setting]'s text among [pictures] — CLIP STUDIO keeps it
/// one pixel wider and taller than the text's box (parameter 63; all 15 of
/// the samples' texts) — taken out of [pictures], so two texts of one size
/// each have their own, in the file's order.
ClipPictureSource? _takePictureOf(
  _ClipTextSetting setting,
  List<ClipPictureSource> pictures,
) {
  final size = setting.boxSize;
  if (size == null) {
    return null;
  }
  for (var i = 0; i < pictures.length; i += 1) {
    final int width;
    final int height;
    try {
      final shape = parseClipOffscreenAttribute(pictures[i].attribute);
      (width, height) = (shape.width, shape.height);
    } on ClipFormatException {
      continue;
    }
    if (width == size.width + 1 && height == size.height + 1) {
      return pictures.removeAt(i);
    }
  }
  return null;
}

/// A stretch of a text's letters — its first, in UTF-16 units of what the
/// text says, and how many — and what is said of it.
typedef _Stretch<T> = ({int start, int length, T value});

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
    required this.underlined,
    required this.struck,
    required this.face,
    required this.points,
    required this.colour,
    required this.box,
    required this.boxSize,
    required this.upright,
    required this.across,
  });

  /// Null for bytes that do not read as the parameters they say they are,
  /// or that set no letters anywhere.
  static _ClipTextSetting? read(Uint8List attributes) {
    try {
      final parameters = _parametersOf(attributes);
      ByteData? at(int id) => parameters[id];
      final size = at(32);
      final points = size == null || size.lengthInBytes < 4
          ? 0.0
          : size.getInt32(0, Endian.little) / 100;
      final box = _boxOf(at(42));
      if (!(points > 0) || box == null) {
        return null;
      }
      int flagAt(ByteData data, int item) => data.getUint8(item + 12);
      return _ClipTextSetting._(
        runs: _runsOf(at(11)),
        aligns: _stretchesOf(at(12), flagAt),
        spacings: _spacingsOf(at(13)),
        underlined: _stretchesOf(at(16), flagAt).any((on) => on.value != 0),
        struck: _stretchesOf(at(20), flagAt).any((on) => on.value != 0),
        face: _utf8Of(at(31)),
        points: points,
        colour: _colourOf(at(34)),
        box: box,
        boxSize: _boxSizeOf(at(63)),
        upright: _uprightOf(at(64)),
        across: _acrossOf(at(26)),
      );
    } on RangeError {
      return null;
    }
  }

  final List<_Run> runs;
  final List<_Stretch<int>> aligns;
  final List<_Stretch<double>> spacings;
  final bool underlined;
  final bool struck;

  /// The face its letters are set in where a run names none.
  final String? face;

  /// Its letters' size in points (parameter 32 — hundredths of a point).
  final double points;

  /// Its letters' colour where a run has none of its own, RGB.
  final int colour;

  /// Where its letters stand in the layer (parameter 42: x0 · y0 · x1 · y1)
  /// — the top-left the picture of it is laid at (wamsoft `clipparse`: 「この
  /// (x0, y0) にオブジェクト Offscreen をそのまま置く」, and so it lies on the
  /// samples' own canvas preview, 10-17).
  final ({int x0, int y0, int x1, int y1}) box;

  /// Parameter 63 — its picture is one pixel more each way.
  final ({int width, int height})? boxSize;

  /// Whether its corners (parameter 64) stand square: not turned, not
  /// slanted. True where it names none.
  final bool upright;

  /// How wide its letters are drawn, in % of their own width (parameter 26).
  final double across;

  /// What [text] says, set as this setting sets it, standing [at] the
  /// canvas — its box's top-left — at [alpha].
  ///
  /// [pointPixels] is how many canvas pixels a point is (the canvas's
  /// resolution ÷ 72).
  CelTextContent contentOf(
    String text, {
    required double pointPixels,
    required ({int x, int y}) at,
    required double alpha,
  }) {
    final align = _alignOf(_mostOf(aligns, text.length) ?? 0);
    final lineHeight =
        (_mostOf(spacings, text.length) ?? defaultSpacing) / 100;
    final size = points * pointPixels;
    return CelTextContent(
      spans: _spansOf(text, size, alpha),
      anchor: CanvasPoint(
        x: at.x + (box.x1 - box.x0) * align.shareBefore,
        // ⚠️The box holds the first line's letters, and a line is set
        // [lineHeight] tall about them: its top stands half the leading
        // above the box, so the letters land where CLIP STUDIO set them.
        y: at.y - (lineHeight - 1) * size / 2,
      ),
      align: align,
      lineHeight: lineHeight,
    );
  }

  /// The line spacing of a text that names none: CLIP STUDIO's own
  /// (parameter 13 — 120 on all 15 of the samples' texts).
  static const double defaultSpacing = 120;

  /// What [text] says, a letter at a time in its style — its run's, the
  /// setting's elsewhere — [size] pixels tall at [alpha]. A CR LF is one
  /// line break, and so is a CR; the content joins what reads alike.
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
        color: _faded(run.colour ?? colour, alpha),
      );
      final end = math.min(text.length, run.start + run.length);
      for (var i = math.max(0, run.start); i < end; i += 1) {
        styles[i] = style;
      }
    }
    return [
      for (var i = 0; i < text.length; i += 1)
        if (!(text.codeUnitAt(i) == _cr &&
            i + 1 < text.length &&
            text.codeUnitAt(i + 1) == _lf))
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
    ImportWarning say(String key, String template, [String? percent]) =>
        ImportWarning(key, template, {'name': name, 'percent': ?percent});
    if (runs.any((run) => run.italic)) {
      yield say(
        'clipTextItalic',
        '{name}: italic letters — shown as CLIP STUDIO drew them, and set '
            'upright once edited.',
      );
    }
    if (underlined) {
      yield say(
        'clipTextUnderline',
        '{name}: underlined letters — shown as CLIP STUDIO drew them, and '
            'set without the line once edited.',
      );
    }
    if (struck) {
      yield say(
        'clipTextStrike',
        '{name}: struck-through letters — shown as CLIP STUDIO drew them, '
            'and set without the line once edited.',
      );
    }
    if (_kindsOf(aligns, text.length) > 1 ||
        aligns.any((align) => align.value > 2)) {
      yield say(
        'clipTextAlign',
        '{name}: lines aligned in a way this app cannot set — shown as CLIP '
            'STUDIO drew them, and aligned alike once edited.',
      );
    }
    if (_kindsOf(spacings, text.length) > 1) {
      yield say(
        'clipTextSpacing',
        '{name}: lines spaced unevenly — shown as CLIP STUDIO drew them, and '
            'spaced evenly once edited.',
      );
    }
    if ((across - 100).abs() > _noise) {
      yield say(
        'clipTextAcross',
        '{name}: letters drawn {percent}% as wide as they are — shown as '
            'CLIP STUDIO drew them, and set at their own width once edited.',
        _percent(across),
      );
    }
    if (!upright) {
      yield say(
        'clipTextTurned',
        '{name}: a turned or slanted text — shown as CLIP STUDIO drew it, '
            'and set upright once edited.',
      );
    }
  }
}

const int _cr = 0x0D;
const int _lf = 0x0A;

/// What two of a file's values that say the same thing may differ by: the
/// last bits of a float's (a spacing of 119.99999999999993 is 120).
const double _noise = 1e-6;

bool _isTrail(int unit) => unit >= 0xDC00 && unit <= 0xDFFF;

/// [value] to two places, its trailing zeros dropped (`99.48`, `100.5`).
String _percent(double value) =>
    value.toStringAsFixed(2).replaceFirst(RegExp(r'\.?0+$'), '');

/// [rgb] at [alpha].
int _faded(int rgb, double alpha) =>
    ((0xFF * alpha).round().clamp(0, 0xFF) << 24) | (rgb & 0xFFFFFF);

/// Parameter 12's alignment as the app's: 0 left, 1 right, 2 centred (the
/// samples are all 0; clip_to_psd reads 1 and 2 so) — anything else left.
TextCelAlign _alignOf(int value) => switch (value) {
  1 => TextCelAlign.right,
  2 => TextCelAlign.center,
  _ => TextCelAlign.left,
};

/// The value most of a [length]-unit text's letters are given by
/// [stretches] — of two given to as many, the smaller; null where no
/// stretch covers a letter.
T? _mostOf<T extends num>(List<_Stretch<T>> stretches, int length) {
  final counts = _countsOf(stretches, length);
  if (counts.isEmpty) {
    return null;
  }
  final values = counts.keys.toList()..sort();
  return values.reduce((a, b) => counts[b]! > counts[a]! ? b : a);
}

/// How many different values [stretches] give a [length]-unit text.
int _kindsOf<T extends num>(List<_Stretch<T>> stretches, int length) =>
    _countsOf(stretches, length).length;

/// How many of a [length]-unit text's letters each value covers — values
/// within [_noise] of one another counted as one.
Map<T, int> _countsOf<T extends num>(
  List<_Stretch<T>> stretches,
  int length,
) {
  final counts = <T, int>{};
  for (final stretch in stretches) {
    final covered =
        math.min<int>(length, stretch.start + stretch.length) -
        math.max<int>(0, stretch.start);
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

({int x0, int y0, int x1, int y1})? _boxOf(ByteData? data) {
  if (data == null || data.lengthInBytes < 16) {
    return null;
  }
  int at(int k) => data.getInt32(4 * k, Endian.little);
  return (x0: at(0), y0: at(1), x1: at(2), y1: at(3));
}

({int width, int height})? _boxSizeOf(ByteData? data) {
  if (data == null || data.lengthInBytes < 8) {
    return null;
  }
  return (
    width: data.getInt32(0, Endian.little),
    height: data.getInt32(4, Endian.little),
  );
}

/// Parameter 64: the four corners, `i32 × 8` in hundredths of a pixel,
/// clockwise from the top-left — square when its top edge runs straight
/// across and its left edge straight down.
bool _uprightOf(ByteData? data) {
  if (data == null || data.lengthInBytes < 32) {
    return true;
  }
  int at(int k) => data.getInt32(4 * k, Endian.little);
  final (topX, topY) = (at(2) - at(0), at(3) - at(1));
  final (sideX, sideY) = (at(6) - at(0), at(7) - at(1));
  return topY == 0 && sideX == 0 && topX > 0 && sideY > 0;
}

/// Parameter 26: 16 bytes, then the letters' width in % as an f64 — 100
/// where it is not.
double _acrossOf(ByteData? data) {
  if (data == null || data.lengthInBytes < 24) {
    return 100;
  }
  return data.getFloat64(16, Endian.little);
}
