// 🚨ONE CRC (card crc32-is-a-dart-table-loop, 저장 2026-11-14): the app's
// CRC-32 — every entry a save writes, every PNG chunk, an import's file —
// is the engine's `crc32fast`, folded a slice at a time. ↩️It was a Dart
// table loop a byte at a time beside it.
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:gpu_engine/gpu_engine.dart' show fingerprintBytes;

import 'package:anicel/src/services/persistence/anicel_incremental_writer.dart';

import '../../helpers/dart_sources.dart';

/// [length] bytes no two neighbouring runs of which repeat.
Uint8List _pattern(int length) => Uint8List.fromList([
  for (var i = 0; i < length; i += 1) (i * 131 + (i >> 9)) & 0xFF,
]);

const _slice = 1 << 20;

void main() {
  test('the check string\'s published CRC', () {
    expect(anicelCrc32(ascii.encode('123456789')), 0xCBF43926);
  });

  test('bytes past one leaf call\'s slice fold to the CRC the engine takes '
      'of them whole', () {
    final bytes = _pattern(3 * _slice + 7);
    expect(anicelCrc32(bytes), fingerprintBytes(bytes));
  });

  test('folded in pieces of any size, across a slice\'s edge, it is the '
      'same CRC', () {
    final bytes = _pattern(2 * _slice + 5);
    var running = anicelCrc32Start;
    var at = 0;
    for (final size in [1, _slice - 1, 3, _slice + 1, 0, 1]) {
      running = anicelCrc32Update(
        running,
        Uint8List.sublistView(bytes, at, at + size),
      );
      at += size;
    }
    expect(at, bytes.length, reason: '⛔fixture: every byte folded once');
    expect(anicelCrc32Finish(running), anicelCrc32(bytes));
  });

  test('only the first [length] bytes of a reused buffer count', () {
    final buffer = Uint8List.fromList([
      ...ascii.encode('123456789'),
      0xAA,
      0xBB,
    ]);
    expect(
      anicelCrc32Finish(anicelCrc32Update(anicelCrc32Start, buffer, 9)),
      0xCBF43926,
    );
  });

  test('a length past the bytes is refused, never read past', () {
    expect(
      () => anicelCrc32Update(anicelCrc32Start, Uint8List(4), 5),
      throwsRangeError,
    );
  });

  test('⛔no CRC table of the app\'s own in its Dart', () {
    final tables = [
      for (final file in [
        ...dartFilesUnder('lib'),
        ...dartFilesUnder('packages/gpu_engine/lib'),
      ])
        if (file.readAsStringSync().toLowerCase().contains('0xedb88320'))
          file.path,
    ];
    expect(tables, isEmpty);
  });
}
