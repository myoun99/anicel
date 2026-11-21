import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/services/persistence/anicel_incremental_writer.dart';
import 'package:anicel/src/services/persistence/anicel_project_archive.dart';

import '../../helpers/temp_dir.dart';

/// 🚨Card incremental-save-holds-every-dirty-cel-at-once (2026-11-21): an
/// append wrote its new entries as ONE buffer joined first — a copy of
/// every edited cel's blob at the write (🔬110.4 MiB for 220 edited cels).
/// Each entry goes to the file as it is now, as the whole write's do.
void main() {
  late Directory directory;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('anicel-append-each');
  });

  tearDown(() {
    anicelDebugWriteWatcher = null;
    return deleteTempQuietly(directory);
  });

  test('🚨no write of an append is larger than the largest entry it '
      'carries: the new entries are not joined into one buffer', () {
    final path = '${directory.path}/each.anicel';
    File(path).writeAsBytesSync(
      buildAnicelArchiveBytes(project: createDefaultProject(), cels: []),
    );
    const size = 64 * 1024;
    final entries = {
      for (var i = 0; i < 4; i += 1)
        'cels/e$i.celz': Uint8List(size)..fillRange(0, size, i + 1),
    };
    final heard = _Widest();
    anicelDebugWriteWatcher = heard;

    final layout = appendAnicelEntries(path: path, newEntries: entries);

    expect(heard.writes, greaterThan(0), reason: '⛔premise: it was heard');
    expect(heard.widest, lessThanOrEqualTo(size));
    final file = File(path).readAsBytesSync();
    for (final MapEntry(key: name, value: bytes) in entries.entries) {
      final entry = layout.entryNamed(name)!;
      expect(
        file.sublist(entry.dataOffset, entry.dataOffset + entry.length),
        bytes,
        reason: '$name reads back where the layout says',
      );
    }
  });
}

class _Widest implements AnicelWriteWatcher {
  int writes = 0;
  int widest = 0;

  @override
  void wrote(int at, List<int> bytes) {
    writes += 1;
    if (bytes.length > widest) {
      widest = bytes.length;
    }
  }

  @override
  void cut(int length) {}
}
