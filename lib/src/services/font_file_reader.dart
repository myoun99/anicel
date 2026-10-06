import 'dart:convert';
import 'dart:typed_data';

import '../models/font_face_facts.dart';

/// READS WHAT A FONT FILE SAYS OF ITSELF — or answers null for bytes that
/// are not a font this app reads: something else altogether, a web font
/// (WOFF), a file cut short, a font with no name to call it by.
///
/// 🚨THIS IS THE WALL. The engine takes ANY bytes it is handed as a font
/// and says nothing (measured 2026-10-06: sixty-four sevens registered
/// without an error, and letters asked for in that "face" drew in another)
/// — so whether a picked file is a font is decided here, before anything
/// is written or registered.
///
/// A collection (.ttc) is read as its FIRST face, which is the one the
/// engine draws with when it is handed the file (measured the same day:
/// `msgothic.ttc` set Latin letters at MS Gothic's fixed pitch, the first
/// face of its three).
FontFaceFacts? readFontFaceFacts(Uint8List bytes) {
  try {
    return _SfntFace.of(bytes)?.facts;
  } on RangeError {
    // A table that says it lies outside its own file.
    return null;
  }
}

/// The extension a font file of these [bytes] is kept under — what kind of
/// file they are, read from their first four bytes and not from the name
/// they were picked by.
String fontFileExtensionOf(Uint8List bytes) {
  if (bytes.length < 4) {
    return 'ttf';
  }
  return switch (ByteData.sublistView(bytes).getUint32(0)) {
    _SfntFace._collection => 'ttc',
    _SfntFace._postScriptOutlines => 'otf',
    _ => 'ttf',
  };
}

/// One face of a font file: its table directory, and the three tables this
/// app reads.
class _SfntFace {
  _SfntFace._(this._bytes, this._data, this._tables);

  static const int _collection = 0x74746366; // 'ttcf'
  static const int _postScriptOutlines = 0x4F54544F; // 'OTTO'
  static const int _trueTypeOutlines = 0x00010000;
  static const int _appleTrueType = 0x74727565; // 'true'

  /// What `head` carries at its twelfth byte, in every font there is.
  static const int _headMagic = 0x5F0F3CF5;

  final Uint8List _bytes;
  final ByteData _data;
  final Map<String, ({int offset, int length})> _tables;

  static _SfntFace? of(Uint8List bytes) {
    if (bytes.length < 12) {
      return null;
    }
    final data = ByteData.sublistView(bytes);
    var start = 0;
    if (data.getUint32(0) == _collection) {
      if (data.getUint32(8) == 0) {
        return null;
      }
      start = data.getUint32(12);
    }
    final kind = data.getUint32(start);
    if (kind != _trueTypeOutlines &&
        kind != _postScriptOutlines &&
        kind != _appleTrueType) {
      return null;
    }
    final tables = <String, ({int offset, int length})>{};
    final count = data.getUint16(start + 4);
    for (var index = 0; index < count; index += 1) {
      final record = start + 12 + index * 16;
      final offset = data.getUint32(record + 8);
      final length = data.getUint32(record + 12);
      if (offset + length > bytes.length) {
        return null;
      }
      tables[latin1.decode(bytes.sublist(record, record + 4))] = (
        offset: offset,
        length: length,
      );
    }
    return _SfntFace._(bytes, data, tables);
  }

  /// The facts, or null for a face that lacks what every usable font has: a
  /// `head` that is one, a map from letters to glyphs, and a family name.
  FontFaceFacts? get facts {
    final head = _tables['head'];
    if (head == null ||
        head.length < 54 ||
        _data.getUint32(head.offset + 12) != _headMagic ||
        !_tables.containsKey('cmap')) {
      return null;
    }
    final family = _familyName();
    if (family == null) {
      return null;
    }
    final macStyle = _data.getUint16(head.offset + 44);
    final os2 = _tables['OS/2'];
    if (os2 == null || os2.length < 10) {
      // No OS/2 table: the face's weight and slant as `head` gives them,
      // and no word on embedding at all.
      return FontFaceFacts(
        family: family,
        weight: macStyle & 0x1 != 0 ? 700 : 400,
        italic: macStyle & 0x2 != 0,
        fsType: null,
      );
    }
    final weight = _data.getUint16(os2.offset + 4);
    return FontFaceFacts(
      family: family,
      weight: weight == 0 ? 400 : weight.clamp(1, 1000),
      // fsSelection: bit 0 is ITALIC, bit 9 OBLIQUE. A table too short to
      // carry it leaves the slant to `head`.
      italic: os2.length >= 64
          ? _data.getUint16(os2.offset + 62) & 0x0201 != 0
          : macStyle & 0x2 != 0,
      fsType: _data.getUint16(os2.offset + 8),
    );
  }

  /// The family's name (name id 1): the one written for Windows in English
  /// where the file has it — the name the same file gives on every machine —
  /// then whatever else it has, in the order a reader is likeliest to be
  /// able to read it.
  ///
  /// ⚠️Name id 1 and not 16 (the "typographic" family that gathers every
  /// weight under one name): the text tool sets a face regular or bold, and
  /// under id 1 a family is exactly the faces that switch reaches — a Light
  /// or a Black is a family of its own, picked by its own name.
  String? _familyName() {
    final table = _tables['name'];
    if (table == null || table.length < 6) {
      return null;
    }
    final count = _data.getUint16(table.offset + 2);
    final strings = table.offset + _data.getUint16(table.offset + 4);
    String? best;
    var bestRank = _unreadable;
    for (var index = 0; index < count; index += 1) {
      final record = table.offset + 6 + index * 12;
      if (_data.getUint16(record + 6) != 1) {
        continue;
      }
      final rank = _rankOf(
        platform: _data.getUint16(record),
        encoding: _data.getUint16(record + 2),
        language: _data.getUint16(record + 4),
      );
      if (rank >= bestRank) {
        continue;
      }
      final start = strings + _data.getUint16(record + 10);
      final end = start + _data.getUint16(record + 8);
      if (end > table.offset + table.length) {
        continue;
      }
      final name = _decoded(_bytes.sublist(start, end), wide: rank < _macRoman);
      if (name.isNotEmpty && name.length <= _longestName) {
        best = name;
        bestRank = rank;
      }
    }
    return best;
  }

  /// The longest family name taken from a file. A name is what a letter's
  /// style is written with and what a list shows on one line; the format
  /// lets a record run to 65,535 bytes, and no family is called that.
  static const int _longestName = 128;

  static const int _windowsEnglish = 0;
  static const int _windowsOther = 1;
  static const int _unicode = 2;
  static const int _macRoman = 3;
  static const int _unreadable = 4;

  /// How good a name record is to read a family's name from — the lower,
  /// the better; [_unreadable] for one in an encoding this does not read.
  static int _rankOf({
    required int platform,
    required int encoding,
    required int language,
  }) => switch (platform) {
    // Windows: Unicode BMP (1) or full repertoire (10), both UTF-16BE.
    3 when encoding == 1 || encoding == 10 =>
      language == 0x0409 ? _windowsEnglish : _windowsOther,
    0 => _unicode,
    // Macintosh, Roman — a byte a letter, in whatever language.
    1 when encoding == 0 => _macRoman,
    _ => _unreadable,
  };

  /// A name's bytes as text: UTF-16BE when [wide], else one byte a letter.
  static String _decoded(Uint8List bytes, {required bool wide}) {
    final String text;
    if (wide) {
      final data = ByteData.sublistView(bytes);
      text = String.fromCharCodes([
        for (var at = 0; at + 1 < bytes.length; at += 2) data.getUint16(at),
      ]);
    } else {
      text = latin1.decode(bytes);
    }
    // A name is one line a list can show: no control characters in it.
    return text.replaceAll(RegExp(r'[\u0000-\u001F\u007F]'), '').trim();
  }
}
