import 'dart:convert';
import 'dart:io' show ZLibDecoder;
import 'dart:typed_data';

import 'clip_container.dart' show ClipFormatException;

/// One node of a 「cmt binc」 document — the tree CLIP STUDIO PAINT keeps a
/// track's animation in (which cel shows from which tick, a sound's place).
final class CmtNode {
  const CmtNode({
    required this.name,
    required this.type,
    required this.value,
    required this.attributes,
    required this.children,
  });

  final String name;

  /// The value's type as the document spells it — `Double[]`, `String` …
  final String type;

  /// A number, a string, a list of those, or null (a `null` node, or a
  /// type this reader does not know in a document that lets it be skipped).
  final Object? value;

  final Map<String, String> attributes;
  final List<CmtNode> children;

  /// The first child called [name], or null.
  CmtNode? child(String name) {
    for (final node in children) {
      if (node.name == name) {
        return node;
      }
    }
    return null;
  }

  /// Every node under this one, this one first, depth first.
  Iterable<CmtNode> get everyNode sync* {
    yield this;
    for (final node in children) {
      yield* node.everyNode;
    }
  }
}

/// A track's external data — u32 LE length, then that many bytes of zlib —
/// as the document it holds.
CmtNode cmtDocumentOfTrackData(Uint8List data) {
  if (data.length < 4) {
    throw const ClipFormatException('a track holds no document');
  }
  final length = ByteData.sublistView(data, 0, 4).getUint32(0, Endian.little);
  if (4 + length > data.length) {
    throw const ClipFormatException('a track document runs past its data');
  }
  final inflated = ZLibDecoder().convert(
    Uint8List.sublistView(data, 4, 4 + length),
  );
  return parseCmtDocument(Uint8List.fromList(inflated));
}

/// A 「cmt binc」 document, read whole.
///
/// ## Format (memory `csp-clip-format-notes` §3; two versions, both seen)
///
/// Little-endian throughout:
///
///   "cmt 0100binc" or "cmt 0110binc" · u32 checksum · u32 string count ·
///   strings (a LEB128 length, then UTF-8 — the first 22 are type names)
///   node := [0110 only: u32 16 · u32 where the attributes start ·
///            u32 where the children start, both from the node's start]
///           u32 name · u32 type · value · u32 attribute count ·
///           (u32 key · u32 text)… · u32 child count · children
///
/// Names and texts are indices into the string table. A 0110 document
/// stores reals as doubles (`Double[]` · `Double2` · `Double3`), a 0100 one
/// as singles (`Single[]` · `Float2` · `Float3`); `Quat` and `Matrix44`
/// follow the version. A 0110 node whose type this reader does not know is
/// stepped over by its attribute offset; in a 0100 one there is no way
/// past it, so the document is refused.
CmtNode parseCmtDocument(Uint8List bytes) {
  if (bytes.length < 20) {
    throw const ClipFormatException('not a cmt document');
  }
  final magic = ascii.decode(bytes.sublist(0, 12), allowInvalid: true);
  final doubles = magic == 'cmt 0110binc';
  if (!doubles && magic != 'cmt 0100binc') {
    throw ClipFormatException('not a cmt document: $magic');
  }
  return _CmtReader(bytes, doubles: doubles).document();
}

final class _CmtReader {
  _CmtReader(this.bytes, {required this.doubles})
    : data = ByteData.sublistView(bytes);

  final Uint8List bytes;
  final ByteData data;

  /// Whether the document is the 0110 version.
  final bool doubles;

  var _at = 16;
  final _strings = <String>[];

  CmtNode document() {
    final count = _u32();
    for (var i = 0; i < count; i += 1) {
      final length = _leb128();
      _need(length);
      _strings.add(
        utf8.decode(bytes.sublist(_at, _at + length), allowMalformed: true),
      );
      _at += length;
    }
    return _node();
  }

  void _need(int count) {
    if (_at + count > bytes.length) {
      throw ClipFormatException('a cmt document ends inside it at $_at');
    }
  }

  int _leb128() {
    var value = 0;
    var shift = 0;
    while (true) {
      _need(1);
      final byte = bytes[_at];
      _at += 1;
      value |= (byte & 0x7f) << shift;
      if (byte & 0x80 == 0) {
        return value;
      }
      shift += 7;
    }
  }

  int _u32() {
    _need(4);
    _at += 4;
    return data.getUint32(_at - 4, Endian.little);
  }

  String _text() {
    final index = _u32();
    if (index >= _strings.length) {
      throw ClipFormatException('a cmt document names string $index');
    }
    return _strings[index];
  }

  double _single() {
    _need(4);
    _at += 4;
    return data.getFloat32(_at - 4, Endian.little);
  }

  double _double() {
    _need(8);
    _at += 8;
    return data.getFloat64(_at - 8, Endian.little);
  }

  double _real() => doubles ? _double() : _single();

  Object? _value(String type) {
    switch (type) {
      case 'null':
        return null;
      case 'Byte':
        _need(1);
        return bytes[_at++];
      case 'SByte':
        _need(1);
        return data.getInt8(_at++);
      case 'UInt16':
        _need(2);
        _at += 2;
        return data.getUint16(_at - 2, Endian.little);
      case 'Int16':
        _need(2);
        _at += 2;
        return data.getInt16(_at - 2, Endian.little);
      case 'UInt32':
        return _u32();
      case 'Int32':
        _need(4);
        _at += 4;
        return data.getInt32(_at - 4, Endian.little);
      case 'Single':
        return _single();
      case 'Double':
        return _double();
      case 'String':
        return _text();
      case 'Double2':
        return [_double(), _double()];
      case 'Double3':
        return [_double(), _double(), _double()];
      case 'Float2':
        return [_single(), _single()];
      case 'Float3':
        return [_single(), _single(), _single()];
      case 'Quat':
        return [for (var i = 0; i < 4; i += 1) _real()];
      case 'Matrix44':
        return [for (var i = 0; i < 16; i += 1) _real()];
    }
    if (type.endsWith('[]')) {
      final element = type.substring(0, type.length - 2);
      final count = _u32();
      return [for (var i = 0; i < count; i += 1) _value(element)];
    }
    throw ClipFormatException('a cmt document holds an unknown type $type');
  }

  CmtNode _node() {
    final start = _at;
    var attributesAt = -1;
    if (doubles) {
      _u32();
      attributesAt = start + _u32();
      _u32();
    }
    final name = _text();
    final type = _text();
    Object? value;
    try {
      value = _value(type);
    } on ClipFormatException {
      if (!doubles) {
        rethrow;
      }
      value = null;
    }
    if (doubles) {
      _at = attributesAt;
    }
    final attributes = <String, String>{};
    final attributeCount = _u32();
    for (var i = 0; i < attributeCount; i += 1) {
      final key = _text();
      attributes[key] = _text();
    }
    final childCount = _u32();
    return CmtNode(
      name: name,
      type: type,
      value: value,
      attributes: attributes,
      children: [for (var i = 0; i < childCount; i += 1) _node()],
    );
  }
}
