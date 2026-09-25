import 'dart:convert' show latin1;
import 'dart:io' show ZLibDecoder;
import 'dart:typed_data';
import 'dart:ui' show Offset;

/// What a PDF's pages draw, read back out of the file — the writer's own
/// operators, in PDF points (y up).
///
/// Every deflated stream is inflated and read as operators; a font program
/// inflates too, and its bytes spell no `m`/`l`/`h`/`Td` with numbers
/// before them.
Iterable<List<String>> _streamTokens(Uint8List pdf) sync* {
  final text = latin1.decode(pdf);
  for (final start in RegExp('(?<!end)stream\r?\n').allMatches(text)) {
    final end = text.indexOf('endstream', start.end);
    if (end < 0) {
      continue;
    }
    final body = text
        .substring(start.end, end)
        .replaceFirst(RegExp('\r?\n\$'), '');
    final String content;
    try {
      content = latin1.decode(ZLibDecoder().convert(latin1.encode(body)));
    } on FormatException {
      continue;
    }
    yield content.split(RegExp(r'\s+'));
  }
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
