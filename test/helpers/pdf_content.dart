import 'dart:convert' show latin1;
import 'dart:io' show ZLibDecoder;
import 'dart:typed_data';
import 'dart:ui' show Offset, Rect;

/// What a PDF's pages draw, read back out of the file — the writer's own
/// operators, in PDF points (y up).
///
/// Every deflated stream is inflated and read as operators; a font program
/// inflates too, and its bytes spell no `m`/`l`/`h`/`Td` with numbers
/// before them.
Iterable<List<String>> _streamTokens(Uint8List pdf) =>
    _streamContents(pdf).map((content) => content.split(RegExp(r'\s+')));

/// Every deflated stream's content, inflated.
Iterable<String> _streamContents(Uint8List pdf) sync* {
  final text = latin1.decode(pdf);
  for (final start in RegExp('(?<!end)stream\r?\n').allMatches(text)) {
    final end = text.indexOf('endstream', start.end);
    if (end < 0) {
      continue;
    }
    final body = text
        .substring(start.end, end)
        .replaceFirst(RegExp('\r?\n\$'), '');
    try {
      yield latin1.decode(ZLibDecoder().convert(latin1.encode(body)));
    } on FormatException {
      continue;
    }
  }
}

/// The pixel size of every image the file embeds — the `/Width` and
/// `/Height` of each image dictionary, wherever the writer put it: in the
/// file's own text or inside a compressed object stream. An image with an
/// alpha mask counts twice, once for its mask.
List<(int, int)> pdfImageSizes(Uint8List pdf) {
  final image = RegExp(r'<<[^<>]*/Subtype\s*/Image\b[^<>]*>>');
  int? number(String dictionary, String key) => int.tryParse(
    RegExp('/$key\\s+(\\d+)').firstMatch(dictionary)?.group(1) ?? '',
  );
  return [
    for (final text in [latin1.decode(pdf), ..._streamContents(pdf)])
      for (final match in image.allMatches(text))
        if ((number(match[0]!, 'Width'), number(match[0]!, 'Height'))
            case (final int width, final int height))
          (width, height),
  ];
}

/// Every closed path the pages draw: `x y m`, then `x y l` …, then `h` —
/// given [then], only those that operator takes right after (`W*`: the
/// paths an even-odd clip cuts by).
List<List<Offset>> pdfClosedPaths(Uint8List pdf, {String? then}) {
  final paths = <List<Offset>>[];
  for (final tokens in _streamTokens(pdf)) {
    List<Offset>? path;
    for (var i = 2; i < tokens.length; i += 1) {
      final x = double.tryParse(tokens[i - 2]);
      final y = double.tryParse(tokens[i - 1]);
      switch (tokens[i]) {
        case 'm' when x != null && y != null:
          path = [Offset(x, y)];
        case 'l' when x != null && y != null && path != null:
          path.add(Offset(x, y));
        case 'h' when path != null:
          final next = i + 1 < tokens.length ? tokens[i + 1] : null;
          if (then == null || next == then) {
            paths.add(path);
          }
          path = null;
      }
    }
  }
  return paths;
}

/// Where each run of text starts: the `x y Td` of every text object.
List<Offset> pdfTextOrigins(Uint8List pdf) => [
  for (final tokens in _streamTokens(pdf))
    for (var i = 2; i < tokens.length; i += 1)
      if (tokens[i] == 'Td')
        if ((double.tryParse(tokens[i - 2]), double.tryParse(tokens[i - 1]))
            case (final double x, final double y))
          Offset(x, y),
];

/// Where each image is laid: the `w 0 0 h x y cm` before every `Do`, as the
/// rect it spans.
List<Rect> pdfImagePlacements(Uint8List pdf) => [
  for (final tokens in _streamTokens(pdf))
    for (var i = 6; i + 2 < tokens.length; i += 1)
      if (tokens[i] == 'cm' && tokens[i + 2] == 'Do')
        if ((
              double.tryParse(tokens[i - 6]),
              double.tryParse(tokens[i - 3]),
              double.tryParse(tokens[i - 2]),
              double.tryParse(tokens[i - 1]),
            )
            case (
              final double w,
              final double h,
              final double x,
              final double y,
            ))
          Rect.fromLTWH(x, y, w, h),
];

/// Where each image lands on its page, through every `cm` in force at its
/// `Do` (`q` saves the matrix, `Q` restores it): the corners its unit
/// square is carried to — the image's first row is that square's top — so
/// an image turned or flipped by the matrices above it reads as well as
/// one laid square.
List<({Offset topLeft, Offset topRight, Offset bottomLeft})> pdfImageCorners(
  Uint8List pdf,
) {
  const identity = [1.0, 0.0, 0.0, 1.0, 0.0, 0.0];
  final corners = <({Offset topLeft, Offset topRight, Offset bottomLeft})>[];
  for (final tokens in _streamTokens(pdf)) {
    var matrix = identity;
    final saved = <List<double>>[];
    for (var i = 0; i < tokens.length; i += 1) {
      switch (tokens[i]) {
        case 'q':
          saved.add(matrix);
        case 'Q':
          matrix = saved.isEmpty ? identity : saved.removeLast();
        case 'cm' when i >= 6:
          if ([for (var j = i - 6; j < i; j += 1) double.tryParse(tokens[j])]
              case final numbers when !numbers.contains(null)) {
            matrix = _concat([for (final n in numbers) n!], matrix);
          }
        case 'Do' when i >= 1 && tokens[i - 1].startsWith('/'):
          final m = matrix;
          Offset at(double x, double y) =>
              Offset(m[0] * x + m[2] * y + m[4], m[1] * x + m[3] * y + m[5]);
          corners.add((
            topLeft: at(0, 1),
            topRight: at(1, 1),
            bottomLeft: at(0, 0),
          ));
      }
    }
  }
  return corners;
}

/// [inner] (`a b c d e f`) set by a `cm` under [outer]: a point goes
/// through [inner] first.
List<double> _concat(List<double> inner, List<double> outer) => [
  outer[0] * inner[0] + outer[2] * inner[1],
  outer[1] * inner[0] + outer[3] * inner[1],
  outer[0] * inner[2] + outer[2] * inner[3],
  outer[1] * inner[2] + outer[3] * inner[3],
  outer[0] * inner[4] + outer[2] * inner[5] + outer[4],
  outer[1] * inner[4] + outer[3] * inner[5] + outer[5],
];

/// Every stroked path the pages draw: `x y m`, then `x y l` …, then `S` —
/// or `s`, which closes it first — and the graphics state it is stroked
/// under: the name of the last `/Name gs` still in force (`q` saves it,
/// `Q` restores it), null where none was set.
List<({List<Offset> points, bool closed, String? state})> pdfStrokes(
  Uint8List pdf,
) {
  final strokes = <({List<Offset> points, bool closed, String? state})>[];
  for (final tokens in _streamTokens(pdf)) {
    List<Offset>? path;
    String? state;
    final saved = <String?>[];
    for (var i = 0; i < tokens.length; i += 1) {
      final x = i >= 2 ? double.tryParse(tokens[i - 2]) : null;
      final y = i >= 1 ? double.tryParse(tokens[i - 1]) : null;
      switch (tokens[i]) {
        case 'q':
          saved.add(state);
        case 'Q':
          state = saved.isEmpty ? null : saved.removeLast();
        case 'gs' when i >= 1:
          state = tokens[i - 1];
        case 'm' when x != null && y != null:
          path = [Offset(x, y)];
        case 'l' when x != null && y != null && path != null:
          path.add(Offset(x, y));
        case 'S' || 's' when path != null:
          strokes.add((points: path, closed: tokens[i] == 's', state: state));
          path = null;
        case 'f' || 'f*' || 'n' || 'W' || 'W*' || 'h':
          path = null;
      }
    }
  }
  return strokes;
}

/// Every stroke opacity the file's graphics states carry — their `/CA`,
/// wherever the writer put the dictionary.
List<double> pdfStrokeOpacities(Uint8List pdf) => [
  for (final text in [latin1.decode(pdf), ..._streamContents(pdf)])
    for (final match in RegExp(r'/CA\s+([0-9.]+)').allMatches(text))
      ?double.tryParse(match[1]!),
];

/// Every `a b c d e f cm` the pages set that places no image — a turn, a
/// move — as its six numbers.
List<List<double>> pdfTransforms(Uint8List pdf) => [
  for (final tokens in _streamTokens(pdf))
    for (var i = 6; i < tokens.length; i += 1)
      if (tokens[i] == 'cm' &&
          (i + 2 >= tokens.length || tokens[i + 2] != 'Do'))
        if ([
              for (var j = i - 6; j < i; j += 1) double.tryParse(tokens[j]),
            ]
            case final numbers when !numbers.contains(null))
          [for (final number in numbers) number!],
];
