// Dumps the descriptor structure of an ABR file (keys, types, values) so
// dynamics mappings are built from ground truth instead of guesses.
//
// Usage: dart run tool/abr_inspect.dart <file.abr> [maxBrushes]
import 'dart:io';
import 'dart:typed_data';

import 'package:anicel/src/services/photoshop/photoshop_byte_reader.dart';
import 'package:anicel/src/services/abr/photoshop_descriptor.dart';

void main(List<String> args) {
  final bytes = File(args[0]).readAsBytesSync();
  final maxBrushes = args.length > 1 ? int.parse(args[1]) : 2;
  final reader = PhotoshopByteReader(bytes);
  stdout.writeln('version=${reader.readInt16()} sub=${reader.readInt16()}');

  while (reader.remaining >= 12) {
    final start = reader.offset;
    final signature = reader.readAscii(4);
    if (signature != '8BIM') {
      reader.offset = start + 1;
      continue;
    }
    final tag = reader.readAscii(4);
    final length = reader.readInt32();
    final end = reader.offset + length;
    if (tag == 'desc') {
      final descriptor = readVersionedDescriptor(
        PhotoshopByteReader(reader.readBytes(length)),
      );
      final brushes = descriptor['Brsh'];
      if (brushes is List) {
        stdout.writeln('brush count: ${brushes.length}');
        for (final entry in brushes.take(maxBrushes)) {
          if (entry is PsDescriptor) {
            _print(entry, 1);
            stdout.writeln('-' * 50);
          }
        }
      }
    }
    reader.offset = end;
  }
}

void _print(PsDescriptor descriptor, int depth) {
  final pad = '  ' * depth;
  stdout.writeln('$pad<${descriptor.classId}>');
  descriptor.items.forEach((key, value) {
    if (value is PsDescriptor) {
      stdout.writeln('$pad"$key":');
      _print(value, depth + 1);
    } else if (value is List) {
      stdout.writeln('$pad"$key": list(${value.length})');
      for (final item in value.take(2)) {
        if (item is PsDescriptor) {
          _print(item, depth + 1);
        } else {
          stdout.writeln('$pad  $item');
        }
      }
    } else if (value is PsUnitFloat) {
      stdout.writeln('$pad"$key": ${value.value}${value.unit}');
    } else if (value is PsEnum) {
      stdout.writeln('$pad"$key": enum ${value.type}.${value.value}');
    } else if (value is Uint8List) {
      stdout.writeln('$pad"$key": blob(${value.length})');
    } else {
      stdout.writeln('$pad"$key": $value');
    }
  });
}
