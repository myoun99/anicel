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

/// Every closed path the pages draw: `x y m`, then `x y l` …, then `h`.
List<List<Offset>> pdfClosedPaths(Uint8List pdf) {
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
          paths.add(path);
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
