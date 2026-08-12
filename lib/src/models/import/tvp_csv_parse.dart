/// TVPaint's CSV export, read for ONE thing: which instances the animator
/// actually named.
///
/// The JSON cannot answer that. It writes an auto-ordinal for an unnamed
/// instance and a typed name for a named one into the same field with no
/// flag between them — a clip where nothing was named comes through as
/// `1, 2, 3, …` and is byte-identical to a sheet numbered by hand. Handing
/// those ordinals to a program whose law is "same name in a layer is the
/// same drawing" is how a layer of ten drawings becomes one label repeated
/// ten times.
///
/// The CSV says it plainly. Every cell of its exposure grid is an image
/// file named `[layer][frame] <label>.png`, and the label is the CEL's
/// name — except when the instance has none, where TVPaint falls back to
/// the LAYER's name. So:
///
///   `"[004][00001] 1.png"` on layer `D`   → named `1`
///   `"[001][00001] TAP.png"` on layer `TAP` → no name
///
/// Measured on three real exports: a production clip with nothing named
/// (478 cells, 478 of them the layer's own name), one with names typed
/// throughout, and one where a single layer is unnamed for its first
/// sixteen frames and named after — which is why this is read per CELL and
/// not per layer.
///
/// ⚠️**Names only.** The grid also describes exposure, and it is NOT the
/// authority for it: a held span writes its head's file on every frame it
/// covers, so reading timing from here invents commas the animator never
/// wrote. The JSON stays the source of what is exposed when.
library;

/// What TVPaint called one cell of the exposure grid.
class TvpCsvCell {
  const TvpCsvCell({
    required this.layerNumber,
    required this.frameNumber,
    required this.label,
  });

  /// 1-based, read from the file name's own prefix rather than the cell's
  /// position: a frame row lists only the layers that have something on
  /// it, so column N is not layer N.
  final int layerNumber;

  /// 1-based, as the row writes it.
  final int frameNumber;

  /// The file name's label — the cel's name, or the layer's when the
  /// instance has none.
  final String label;
}

/// A parsed CSV: the clip it describes, and the names it carries.
class TvpCsvNames {
  TvpCsvNames({
    required this.clipName,
    required this.width,
    required this.height,
    required this.frameCount,
    required this.layerCount,
    required List<String> layerNames,
    required List<TvpCsvCell> cells,
  }) : layerNames = List.unmodifiable(layerNames),
       _byCell = {
         for (final cell in cells)
           _key(cell.layerNumber, cell.frameNumber): cell.label,
       };

  final String clipName;
  final int width;
  final int height;
  final int frameCount;

  /// As the CSV counts them — DRAWING layers only. An import adds its own
  /// camera and instruction rows, so compare this against the JSON's layer
  /// list, never against the planned cut's.
  final int layerCount;

  final List<String> layerNames;
  final Map<int, String> _byCell;

  static int _key(int layerNumber, int frameNumber) =>
      layerNumber * 1000000 + frameNumber;

  /// The name TVPaint holds for the instance covering [frameNumber] on
  /// [layerNumber], or null when it has none — which is both "the label
  /// was the layer's own name" and "the CSV says nothing about this cell".
  ///
  /// Both absences mean the same thing to a caller that must not invent a
  /// name, so they are not distinguished.
  String? nameAt({required int layerNumber, required int frameNumber}) {
    final label = _byCell[_key(layerNumber, frameNumber)];
    if (label == null) {
      return null;
    }
    final layerName = layerNumber >= 1 && layerNumber <= layerNames.length
        ? layerNames[layerNumber - 1]
        : null;
    return label == layerName ? null : label;
  }

  /// Whether this CSV and a JSON export describe the same clip in the same
  /// state.
  ///
  /// The two are separate exports, so nothing stops a stale CSV being
  /// paired with a fresh JSON — and a mispaired one would rename cels
  /// after somebody else's drawings. All five values come free in the
  /// header.
  bool describesSameClipAs({
    required String clipName,
    required int width,
    required int height,
    required int frameCount,
    required int layerCount,
  }) =>
      this.clipName == clipName &&
      this.width == width &&
      this.height == height &&
      this.frameCount == frameCount &&
      this.layerCount == layerCount;
}

/// Thrown when [parseTvpCsv] is handed something that is not one.
class TvpCsvParseException implements Exception {
  const TvpCsvParseException(this.message);

  final String message;

  @override
  String toString() => 'TvpCsvParseException: $message';
}

/// Reads a TVPaint CSV export.
///
/// Shape, from the real files:
/// ```
/// UTF-8, TVPaint, "CSV 1.1"
/// Project Name, Width, Height, Frame Count, Layer Count, …
/// "343", 2340, 1654, 54, 12, 24.000000, 1.000000, Progressive
///
/// #Layers,"format","D","D","C",…
/// #Folder,…   #Density,…   #Blending,…   #Visible,…
/// #00001, "[001][00001] format.png", "[002][00001] 1.png", …
/// ```
TvpCsvNames parseTvpCsv(String contents) {
  final lines = contents.split(RegExp(r'\r?\n'));
  if (lines.isEmpty || !lines.first.contains('TVPaint')) {
    throw const TvpCsvParseException(
      'not a TVPaint CSV — the first line does not name TVPaint',
    );
  }

  List<String>? summary;
  List<String>? layerNames;
  final cells = <TvpCsvCell>[];

  for (var index = 1; index < lines.length; index += 1) {
    final line = lines[index].trim();
    if (line.isEmpty) {
      continue;
    }
    if (line.startsWith('#Layers')) {
      layerNames = _fields(line).skip(1).toList();
      continue;
    }
    if (line.startsWith('#')) {
      final row = RegExp(r'^#(\d+)').firstMatch(line);
      if (row == null) {
        continue; // #Folder, #Density, #Blending, #Visible.
      }
      for (final cell in _cellPattern.allMatches(line)) {
        cells.add(
          TvpCsvCell(
            layerNumber: int.parse(cell.group(1)!),
            frameNumber: int.parse(cell.group(2)!),
            label: cell.group(3)!,
          ),
        );
      }
      continue;
    }
    // The first non-# line after the header is the clip summary; the
    // column-title line above it starts with a letter too, so the summary
    // is recognised by its quoted name rather than by position.
    summary ??= line.startsWith('"') ? _fields(line) : null;
  }

  if (summary == null || summary.length < 5 || layerNames == null) {
    throw const TvpCsvParseException(
      'missing the clip summary row or the #Layers row',
    );
  }

  final clip = summary;
  int number(int at, String what) {
    final value = int.tryParse(clip[at]);
    if (value == null) {
      throw TvpCsvParseException('$what is not a number: ${clip[at]}');
    }
    return value;
  }

  return TvpCsvNames(
    clipName: summary[0],
    width: number(1, 'width'),
    height: number(2, 'height'),
    frameCount: number(3, 'frame count'),
    layerCount: number(4, 'layer count'),
    layerNames: layerNames,
    cells: cells,
  );
}

/// `[layer][frame] label.png`, with the label allowed everything but a
/// quote — cel names carry commas (`arisu,おはよ`) and dots (`1.5`), so
/// neither can be a delimiter here.
final RegExp _cellPattern = RegExp(r'"\[(\d+)\]\[(\d+)\]\s*([^"]*)\.png"');

/// Splits a CSV line, honouring quotes: a cel name may contain a comma.
List<String> _fields(String line) {
  final fields = <String>[];
  final buffer = StringBuffer();
  var quoted = false;
  for (final rune in line.runes) {
    final character = String.fromCharCode(rune);
    if (character == '"') {
      quoted = !quoted;
      continue;
    }
    if (character == ',' && !quoted) {
      fields.add(buffer.toString().trim());
      buffer.clear();
      continue;
    }
    buffer.write(character);
  }
  fields.add(buffer.toString().trim());
  return fields;
}
