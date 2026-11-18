// Inspection harness for Clip Studio .sut brush files (SQLite databases).
// Read-only: never modifies the input files.
//
// Usage: dart tool/sut_inspect.dart <file.sut> [more files...]
import 'dart:io';
import 'dart:typed_data';

import 'package:sqlite3/sqlite3.dart';

void main(List<String> args) {
  for (final path in args) {
    stdout.writeln('=' * 70);
    stdout.writeln('FILE: $path (${File(path).lengthSync()} bytes)');
    final database = sqlite3.open(path, mode: OpenMode.readOnly);
    try {
      _dump(database);
    } finally {
      database.close();
    }
  }
}

void _dump(Database database) {
  final tables = database
      .select("SELECT name FROM sqlite_master WHERE type='table'")
      .map((row) => row['name'] as String)
      .toList();
  stdout.writeln('TABLES: $tables');

  for (final table in tables) {
    if (table == 'sqlite_sequence') {
      continue;
    }
    final rows = database.select('SELECT * FROM "$table"');
    stdout.writeln('--- $table: ${rows.length} rows');
    var printed = 0;
    for (final row in rows) {
      if (printed >= 6) {
        stdout.writeln('  ... (${rows.length - printed} more rows)');
        break;
      }
      printed += 1;
      final summary = StringBuffer('  row ');
      for (final column in rows.columnNames) {
        final value = row[column];
        if (value == null) {
          continue; // skip nulls to keep output readable
        }
        if (value is Uint8List) {
          summary.write('$column=<blob ${value.length}B ');
          summary.write(_preview(value));
          summary.write('> ');
        } else {
          summary.write('$column=$value ');
        }
      }
      stdout.writeln(summary);
    }
  }
}

String _preview(Uint8List bytes) {
  final head = bytes.take(24).map(
    (b) => b.toRadixString(16).padLeft(2, '0'),
  );
  var text = head.join(' ');
  // Report every embedded PNG with its dimensions and pixel format.
  for (var i = 0; i + 24 < bytes.length; i += 1) {
    if (bytes[i] == 0x89 &&
        bytes[i + 1] == 0x50 &&
        bytes[i + 2] == 0x4E &&
        bytes[i + 3] == 0x47) {
      final data = ByteData.sublistView(bytes, i);
      final width = data.getUint32(16);
      final height = data.getUint32(20);
      final bitDepth = data.getUint8(24);
      final colorType = data.getUint8(25);
      text += ' [PNG@$i ${width}x$height depth=$bitDepth color=$colorType]';
    }
  }
  // Extract readable UTF-16BE runs (catalog path references).
  final chars = StringBuffer();
  for (var i = 0; i + 1 < bytes.length; i += 2) {
    final unit = (bytes[i] << 8) | bytes[i + 1];
    if (unit >= 0x20 && unit < 0x7F) {
      chars.writeCharCode(unit);
    }
  }
  final readable = chars.toString();
  if (readable.length > 6) {
    text += ' utf16be="$readable"';
  }
  return text;
}
