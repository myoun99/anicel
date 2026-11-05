import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/services/wait_window.dart';

/// 🗣️F-566 (유저 2026-11-05): 「대상이 여러블록일때만 띄우도록. 대상이 한
/// 블록이면 안띄움」 — the one answer every heavy door asks of what it
/// reaches.
void main() {
  test('nothing, or one block however often it is named, is not many', () {
    expect(reachesManyBlocks(const []), isFalse);
    expect(reachesManyBlocks(const ['A1']), isFalse);
    expect(
      reachesManyBlocks(const ['A1', 'A1', 'A1']),
      isFalse,
      reason: 'a hold names its block once a frame',
    );
  });

  test('two blocks are many, wherever the second comes', () {
    expect(reachesManyBlocks(const ['A1', 'B1']), isTrue);
    expect(reachesManyBlocks(const ['A1', 'A1', 'A2']), isTrue);
  });

  test('it stops at the second block: a range\'s cels are not all read', () {
    Iterable<Object> blocks() sync* {
      yield 'A1';
      yield 'A2';
      throw StateError('read past the second block');
    }

    expect(reachesManyBlocks(blocks()), isTrue);
  });
}
