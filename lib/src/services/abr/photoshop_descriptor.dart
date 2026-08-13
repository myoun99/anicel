import 'dart:typed_data';

import '../photoshop/photoshop_byte_reader.dart';

/// Minimal parser for Photoshop's serialized ActionDescriptor structure —
/// the format of the ABR `desc` section (and PSD descriptors generally).
///
/// Supports the value types brush descriptors actually use; an unknown type
/// has no self-describing length, so parsing fails with a [FormatException]
/// and the caller falls back to importing tip bitmaps without metadata.
class PsDescriptor {
  const PsDescriptor({
    required this.name,
    required this.classId,
    required this.items,
  });

  /// Unicode class name (usually empty).
  final String name;

  /// Four-char or long class identifier (e.g. `null`, `Brsh`).
  final String classId;

  /// Item values by key. Values are [double], [int], [bool], [String]
  /// (TEXT), [PsUnitFloat], [PsEnum], [List] (VlLs), [PsDescriptor] (Objc),
  /// or [Uint8List] (tdta).
  final Map<String, Object?> items;

  Object? operator [](String key) => items[key];

  /// The value under [key] if it is a [PsDescriptor].
  PsDescriptor? childDescriptor(String key) {
    final value = items[key];
    return value is PsDescriptor ? value : null;
  }

  /// Numeric value under [key] ([double], [int], or [PsUnitFloat]).
  double? numberValue(String key) {
    final value = items[key];
    if (value is double) {
      return value;
    }
    if (value is int) {
      return value.toDouble();
    }
    if (value is PsUnitFloat) {
      return value.value;
    }
    return null;
  }

  String? textValue(String key) {
    final value = items[key];
    return value is String ? value : null;
  }
}

/// A `UntF` unit float: a value tagged with a unit code (`#Pxl`, `#Prc`,
/// `#Ang`, ...).
class PsUnitFloat {
  const PsUnitFloat({required this.unit, required this.value});

  final String unit;
  final double value;
}

/// An `enum` value: enum type and selected value codes.
class PsEnum {
  const PsEnum({required this.type, required this.value});

  final String type;
  final String value;
}

/// Reads a versioned descriptor (the `desc` section payload starts with a
/// 32-bit descriptor version, expected to be 16).
PsDescriptor readVersionedDescriptor(PhotoshopByteReader reader) {
  final version = reader.readInt32();
  if (version != 16) {
    throw FormatException('Unsupported descriptor version $version.');
  }
  return readDescriptor(reader);
}

PsDescriptor readDescriptor(PhotoshopByteReader reader) {
  final name = reader.readUnicodeString();
  final classId = reader.readKeyString();
  final count = reader.readInt32();
  final items = <String, Object?>{};
  for (var index = 0; index < count; index += 1) {
    final key = reader.readKeyString();
    items[key] = _readTypedValue(reader);
  }
  return PsDescriptor(name: name, classId: classId, items: items);
}

Object? _readTypedValue(PhotoshopByteReader reader) {
  final type = reader.readAscii(4);
  switch (type) {
    case 'Objc':
    case 'GlbO':
      return readDescriptor(reader);
    case 'VlLs':
      final count = reader.readInt32();
      return [
        for (var index = 0; index < count; index += 1) _readTypedValue(reader),
      ];
    case 'doub':
      return reader.readFloat64();
    case 'UntF':
      return PsUnitFloat(
        unit: reader.readAscii(4),
        value: reader.readFloat64(),
      );
    case 'TEXT':
      return reader.readUnicodeString();
    case 'enum':
      return PsEnum(
        type: reader.readKeyString(),
        value: reader.readKeyString(),
      );
    case 'long':
      return reader.readInt32();
    case 'comp':
      // 64-bit integer (large computations); rare but self-describing.
      final high = reader.readInt32();
      final low = reader.readInt32();
      return (high << 32) | (low & 0xFFFFFFFF);
    case 'bool':
      return reader.readUint8() != 0;
    case 'type':
    case 'GlbC':
      // Class reference: unicode name + classID, no payload value.
      reader.readUnicodeString();
      return reader.readKeyString();
    case 'alis':
    case 'tdta':
      final length = reader.readInt32();
      return Uint8List.fromList(reader.readBytes(length));
    default:
      throw FormatException('Unsupported descriptor value type "$type".');
  }
}
